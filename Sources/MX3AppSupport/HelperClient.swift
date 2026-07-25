import Foundation

public struct HelperCommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var combinedOutput: String {
        [standardOutput, standardError]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum ParsedWorkerState: Equatable, Sendable {
    case running(pid: Int32?)
    case stopped
    case unknown(String)
}

public enum WorkerStatusParser {
    public static func parse(_ result: HelperCommandResult) -> ParsedWorkerState {
        let output = result.combinedOutput
        if output.contains("is stopped") {
            return .stopped
        }
        if output.contains("is running") {
            let expression = try? NSRegularExpression(pattern: #"pid\s+(\d+)"#)
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            if let match = expression?.firstMatch(in: output, range: range),
               let pidRange = Range(match.range(at: 1), in: output) {
                return .running(pid: Int32(output[pidRange]))
            }
            return .running(pid: nil)
        }
        return .unknown(output.isEmpty ? "No status returned by helper." : output)
    }
}

public struct HelperClient: Sendable {
    public let executableURL: URL

    public init(executableURL: URL) {
        self.executableURL = executableURL
    }

    public func run(_ arguments: [String]) async -> HelperCommandResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runSynchronously(arguments))
            }
        }
    }

    private func runSynchronously(_ arguments: [String]) -> HelperCommandResult {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            return HelperCommandResult(
                exitCode: 127,
                standardOutput: "",
                standardError: "mx3-lite helper is missing or not executable at \(executableURL.path)"
            )
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            return HelperCommandResult(
                exitCode: process.terminationStatus,
                standardOutput: String(decoding: outputPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                standardError: String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            )
        } catch {
            return HelperCommandResult(exitCode: 126, standardOutput: "", standardError: error.localizedDescription)
        }
    }
}
