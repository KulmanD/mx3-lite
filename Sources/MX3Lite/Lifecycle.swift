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

        if let decoded = try? JSONDecoder().decode(WorkerProcessIdentity.self, from: originalData) {
            metadata = decoded
            wasLegacyPID = false
        } else {
            let rawPID = String(decoding: originalData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let legacyPID = Int32(rawPID), let inspected = inspectProcess(pid: legacyPID) else {
                removeMetadataIfUnchanged(originalData)
                return nil
            }
            metadata = inspected
            wasLegacyPID = true
        }

        guard
            !expectedExecutablePath.isEmpty,
            metadata.executablePath == expectedExecutablePath,
            inspectProcess(pid: metadata.pid) == metadata
        else {
            removeMetadataIfUnchanged(originalData)
            return nil
        }

        if wasLegacyPID {
            try writeMetadata(metadata)
        }

        return metadata
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
