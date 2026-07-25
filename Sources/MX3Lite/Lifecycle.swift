import Darwin
import Foundation

@_silgen_name("flock")
private func systemFlock(_ descriptor: Int32, _ operation: Int32) -> Int32

struct WorkerProcessIdentity: Codable, Equatable {
    let pid: Int32
    let executablePath: String
    let startTimeSeconds: UInt64
    let startTimeMicroseconds: UInt64
}

enum WorkerMetadataRecord: Equatable {
    case current(WorkerProcessIdentity)
    case legacyPID(Int32)
    case invalid

    static func parse(_ data: Data) -> WorkerMetadataRecord {
        if let metadata = try? JSONDecoder().decode(WorkerProcessIdentity.self, from: data) {
            return .current(metadata)
        }

        let rawPID = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = Int32(rawPID), pid > 0 else {
            return .invalid
        }
        return .legacyPID(pid)
    }
}

enum WorkerLifecycleDiagnosis: Equatable {
    case stopped
    case running(WorkerProcessIdentity, legacyMetadata: Bool)
    case stale(String)
    case malformedMetadata
}

struct WorkerLifecycle {
    let paths: AppPaths

    func withExclusiveLock<T>(_ operation: () throws -> T) throws -> T {
        let descriptor = paths.lifecycleLockFile.path.withCString {
            Darwin.open($0, O_CREAT | O_RDWR | O_CLOEXEC, mode_t(S_IRUSR | S_IWUSR))
        }
        guard descriptor >= 0 else {
            throw CLIError("could not open lifecycle lock: \(String(cString: strerror(errno)))")
        }
        defer {
            _ = Darwin.close(descriptor)
        }

        while systemFlock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else {
                throw CLIError("could not acquire lifecycle lock: \(String(cString: strerror(errno)))")
            }
        }
        defer {
            _ = systemFlock(descriptor, LOCK_UN)
        }

        return try operation()
    }

    var expectedExecutablePath: String {
        guard let executableURL = Bundle.main.executableURL else {
            return ""
        }
        return canonicalPath(executableURL.path)
    }

    func currentProcessIdentity() throws -> WorkerProcessIdentity {
        guard let identity = inspectProcess(pid: getpid()) else {
            throw CLIError("could not inspect current mx3-lite process identity")
        }
        return identity
    }

    func inspectProcess(pid: pid_t) -> WorkerProcessIdentity? {
        guard pid > 0 else {
            return nil
        }

        var processInfo = proc_bsdinfo()
        let expectedInfoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        let infoSize = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &processInfo, expectedInfoSize)
        guard infoSize == expectedInfoSize else {
            return nil
        }

        var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let pathLength = pathBuffer.withUnsafeMutableBytes { bytes in
            proc_pidpath(pid, bytes.baseAddress, UInt32(bytes.count))
        }
        guard pathLength > 0, let baseAddress = pathBuffer.withUnsafeBufferPointer({ $0.baseAddress }) else {
            return nil
        }

        return WorkerProcessIdentity(
            pid: Int32(pid),
            executablePath: canonicalPath(String(cString: baseAddress)),
            startTimeSeconds: UInt64(processInfo.pbi_start_tvsec),
            startTimeMicroseconds: UInt64(processInfo.pbi_start_tvusec)
        )
    }

    func liveWorker() throws -> WorkerProcessIdentity? {
        guard FileManager.default.fileExists(atPath: paths.pidFile.path) else {
            return nil
        }

        let originalData = try Data(contentsOf: paths.pidFile)
        let metadata: WorkerProcessIdentity
        let wasLegacyPID: Bool

        switch WorkerMetadataRecord.parse(originalData) {
        case .current(let decoded):
            metadata = decoded
            wasLegacyPID = false
        case .legacyPID(let legacyPID):
            guard let inspected = inspectProcess(pid: legacyPID) else {
                removeMetadataIfUnchanged(originalData)
                return nil
            }
            metadata = inspected
            wasLegacyPID = true
        case .invalid:
            removeMetadataIfUnchanged(originalData)
            return nil
        }

        guard WorkerLifecycle.matchesWorkerIdentity(
            metadata,
            expectedExecutablePath: expectedExecutablePath,
            inspectedIdentity: inspectProcess(pid: metadata.pid)
        ) else {
            removeMetadataIfUnchanged(originalData)
            return nil
        }

        if wasLegacyPID {
            try writeMetadata(metadata)
        }

        return metadata
    }

    func diagnoseWorkerReadOnly() throws -> WorkerLifecycleDiagnosis {
        guard FileManager.default.fileExists(atPath: paths.pidFile.path) else {
            return .stopped
        }

        let data = try Data(contentsOf: paths.pidFile)
        let record = WorkerMetadataRecord.parse(data)
        let inspectedIdentity: WorkerProcessIdentity?
        switch record {
        case .current(let metadata):
            inspectedIdentity = inspectProcess(pid: metadata.pid)
        case .legacyPID(let pid):
            inspectedIdentity = inspectProcess(pid: pid)
        case .invalid:
            inspectedIdentity = nil
        }

        return WorkerLifecycle.diagnose(
            record,
            expectedExecutablePath: expectedExecutablePath,
            inspectedIdentity: inspectedIdentity
        )
    }

    func writeMetadata(_ identity: WorkerProcessIdentity) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(identity)
        try data.write(to: paths.pidFile, options: .atomic)
    }

    func removeMetadata(ifOwnedBy identity: WorkerProcessIdentity) {
        guard let data = try? Data(contentsOf: paths.pidFile) else {
            return
        }

        if let current = try? JSONDecoder().decode(WorkerProcessIdentity.self, from: data) {
            guard current == identity else {
                return
            }
        } else {
            let rawPID = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard Int32(rawPID) == identity.pid else {
                return
            }
        }

        try? FileManager.default.removeItem(at: paths.pidFile)
    }

    func isAlive(_ identity: WorkerProcessIdentity) -> Bool {
        guard identity.executablePath == expectedExecutablePath else {
            return false
        }
        return inspectProcess(pid: identity.pid) == identity
    }

    func send(signal: Int32, to identity: WorkerProcessIdentity) throws {
        guard isAlive(identity) else {
            throw CLIError("worker identity changed; refusing to signal pid \(identity.pid)")
        }

        if Darwin.kill(identity.pid, signal) != 0, errno != ESRCH {
            throw CLIError("failed to signal pid \(identity.pid): \(String(cString: strerror(errno)))")
        }
    }

    static func matchesWorkerIdentity(
        _ metadata: WorkerProcessIdentity,
        expectedExecutablePath: String,
        inspectedIdentity: WorkerProcessIdentity?
    ) -> Bool {
        !expectedExecutablePath.isEmpty
            && metadata.executablePath == expectedExecutablePath
            && inspectedIdentity == metadata
    }

    static func diagnose(
        _ record: WorkerMetadataRecord,
        expectedExecutablePath: String,
        inspectedIdentity: WorkerProcessIdentity?
    ) -> WorkerLifecycleDiagnosis {
        switch record {
        case .invalid:
            return .malformedMetadata
        case .current(let metadata):
            guard let inspectedIdentity else {
                return .stale("recorded process is not running")
            }
            guard metadata.executablePath == expectedExecutablePath else {
                return .stale("recorded executable does not match this mx3-lite binary")
            }
            guard inspectedIdentity == metadata else {
                return .stale("recorded process identity no longer matches the live process")
            }
            return .running(metadata, legacyMetadata: false)
        case .legacyPID(let pid):
            guard let inspectedIdentity else {
                return .stale("legacy pid \(pid) is not running")
            }
            guard inspectedIdentity.executablePath == expectedExecutablePath else {
                return .stale("legacy pid \(pid) belongs to a different executable")
            }
            return .running(inspectedIdentity, legacyMetadata: true)
        }
    }

    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    private func removeMetadataIfUnchanged(_ expectedData: Data) {
        guard let currentData = try? Data(contentsOf: paths.pidFile), currentData == expectedData else {
            return
        }
        try? FileManager.default.removeItem(at: paths.pidFile)
    }
}
