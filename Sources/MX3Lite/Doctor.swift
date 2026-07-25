import CoreGraphics
import Foundation
import IOKit

enum DoctorSeverity: Int, Equatable {
    case info
    case ok
    case warning
    case blocker

    var label: String {
        switch self {
        case .info:
            return "info"
        case .ok:
            return "ok"
        case .warning:
            return "warning"
        case .blocker:
            return "blocker"
        }
    }
}

struct DoctorCheck: Equatable {
    let name: String
    let severity: DoctorSeverity
    let summary: String
    let details: [String]

    init(name: String, severity: DoctorSeverity, summary: String, details: [String] = []) {
        self.name = name
        self.severity = severity
        self.summary = summary
        self.details = details
    }
}

struct DoctorReport: Equatable {
    let checks: [DoctorCheck]

    var blockerCount: Int {
        checks.filter { $0.severity == .blocker }.count
    }

    var warningCount: Int {
        checks.filter { $0.severity == .warning }.count
    }

    var exitCode: Int {
        blockerCount == 0 ? 0 : 1
    }

    func rendered(verbose: Bool) -> String {
        var lines = ["mx3-lite doctor"]
        for check in checks {
            lines.append("[\(check.severity.label)] \(check.name): \(check.summary)")
            if verbose || check.severity == .warning || check.severity == .blocker {
                lines.append(contentsOf: check.details.map { "  \($0)" })
            }
        }

        if blockerCount > 0 {
            lines.append("result: blocked (\(blockerCount) blocker(s), \(warningCount) warning(s))")
        } else if warningCount > 0 {
            lines.append("result: ready with warnings (\(warningCount))")
        } else {
            lines.append("result: ready")
        }
        return lines.joined(separator: "\n")
    }
}

enum WrapperInspection: Equatable {
    case valid(target: String)
    case missing
    case unreadable
    case targetMissing
    case targetNotExecutable(String)
    case targetMismatch(actual: String, expected: String)
}

enum WrapperInspector {
    static func inspect(wrapperURL: URL, expectedExecutableURL: URL) -> WrapperInspection {
        guard FileManager.default.fileExists(atPath: wrapperURL.path) else {
            return .missing
        }
        guard let contents = try? String(contentsOf: wrapperURL, encoding: .utf8) else {
            return .unreadable
        }
        guard let target = targetPath(in: contents) else {
            return .targetMissing
        }

        let targetURL = URL(fileURLWithPath: target).resolvingSymlinksInPath().standardizedFileURL
        guard FileManager.default.isExecutableFile(atPath: targetURL.path) else {
            return .targetNotExecutable(targetURL.path)
        }

        let expectedURL = expectedExecutableURL.resolvingSymlinksInPath().standardizedFileURL
        guard targetURL.path == expectedURL.path else {
            return .targetMismatch(actual: targetURL.path, expected: expectedURL.path)
        }
        return .valid(target: targetURL.path)
    }

    static func targetPath(in wrapper: String) -> String? {
        for line in wrapper.split(whereSeparator: { $0.isNewline }) {
            let value = String(line)
            guard value.hasPrefix("MX3_LITE=\"") && value.hasSuffix("\"") else {
                continue
            }
            return String(value.dropFirst("MX3_LITE=\"".count).dropLast())
        }
        return nil
    }
}

struct DoctorRunner {
    let paths: AppPaths
    let lifecycle: WorkerLifecycle
    let wrapperURL: URL
    let executableURL: URL

    init(
        paths: AppPaths,
        wrapperURL: URL = URL(fileURLWithPath: "/usr/local/bin/mxmaster"),
        executableURL: URL? = Bundle.main.executableURL
    ) throws {
        guard let executableURL else {
            throw CLIError("could not resolve executable path for doctor")
        }
        self.paths = paths
        self.lifecycle = WorkerLifecycle(paths: paths)
        self.wrapperURL = wrapperURL
        self.executableURL = executableURL
    }

    func report() -> DoctorReport {
        var checks: [DoctorCheck] = []
        checks.append(executableCheck())
        checks.append(wrapperCheck())

        let loadedConfig: LoadedConfig?
        do {
            loadedConfig = try ConfigStore(paths: paths).loadExistingWithSources()
            checks.append(configCheck(loadedConfig))
        } catch {
            loadedConfig = nil
            checks.append(DoctorCheck(
                name: "config",
                severity: .blocker,
                summary: "could not parse config.json",
                details: [paths.configFile.path, String(describing: error)]
            ))
        }

        let config = loadedConfig?.config ?? AppConfig.default
        checks.append(buttonCheck(config: config, configExists: loadedConfig != nil))
        checks.append(behaviorCheck(config: config))
        checks.append(lifecycleCheck())
        checks.append(accessibilityCheck())
        checks.append(inputMonitoringCheck(config: config))
        checks.append(deviceCheck())
        checks.append(DoctorCheck(
            name: "safety",
            severity: .ok,
            summary: "read-only checks completed",
            details: ["no worker control, config writes, permission prompts, synthetic input, or network access"]
        ))
        return DoctorReport(checks: checks)
    }

    private func executableCheck() -> DoctorCheck {
        let path = executableURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return DoctorCheck(name: "executable", severity: .blocker, summary: "binary is not executable", details: [path])
        }
        return DoctorCheck(name: "executable", severity: .ok, summary: path)
    }

    private func wrapperCheck() -> DoctorCheck {
        switch WrapperInspector.inspect(wrapperURL: wrapperURL, expectedExecutableURL: executableURL) {
        case .valid(let target):
            return DoctorCheck(name: "wrapper", severity: .ok, summary: target, details: [wrapperURL.path])
        case .missing:
            return DoctorCheck(
                name: "wrapper",
                severity: .blocker,
                summary: "mxmaster wrapper is missing",
                details: ["run bash scripts/install.sh", wrapperURL.path]
            )
        case .unreadable:
            return DoctorCheck(name: "wrapper", severity: .blocker, summary: "wrapper is unreadable", details: [wrapperURL.path])
        case .targetMissing:
            return DoctorCheck(name: "wrapper", severity: .blocker, summary: "wrapper target could not be parsed", details: [wrapperURL.path])
        case .targetNotExecutable(let target):
            return DoctorCheck(
                name: "wrapper",
                severity: .blocker,
                summary: "wrapper target is missing or not executable",
                details: [target, "run bash scripts/install.sh after moving or rebuilding the project"]
            )
        case .targetMismatch(let actual, let expected):
            if WorkerLifecycle.isRecognizedWorkerPath(actual, expectedExecutablePath: expected) {
                return DoctorCheck(
                    name: "wrapper",
                    severity: .warning,
                    summary: "wrapper uses another compatible mx3-lite helper",
                    details: [
                        "wrapper target: \(actual)",
                        "current binary: \(expected)",
                        "run the relevant installer to align both paths"
                    ]
                )
            }
            return DoctorCheck(
                name: "wrapper",
                severity: .blocker,
                summary: "wrapper points to a different mx3-lite binary",
                details: ["wrapper target: \(actual)", "current binary: \(expected)", "run bash scripts/install.sh"]
            )
        }
    }

    private func configCheck(_ loadedConfig: LoadedConfig?) -> DoctorCheck {
        guard let loadedConfig else {
            return DoctorCheck(
                name: "config",
                severity: .warning,
                summary: "config.json does not exist; defaults shown below",
                details: [paths.configFile.path, "doctor did not create the file; run mxmaster config or mx3-lite init-config"]
            )
        }

        var details = [paths.configFile.path]
        details.append(contentsOf: loadedConfig.warnings.map { "warning: \($0)" })
        details.append("sources: threshold=\(loadedConfig.sources.threshold), buttons.gesture=\(loadedConfig.sources.gestureButton), buttons.back=\(loadedConfig.sources.backButton), buttons.forward=\(loadedConfig.sources.forwardButton)")
        details.append("sources: actionBackend=\(loadedConfig.sources.actionBackend), scrollTransformMode=\(loadedConfig.sources.scrollTransformMode), smoothScrollMode=\(loadedConfig.sources.smoothScrollMode)")
        return DoctorCheck(
            name: "config",
            severity: loadedConfig.warnings.isEmpty ? .ok : .warning,
            summary: loadedConfig.warnings.isEmpty ? "parsed successfully" : "parsed with \(loadedConfig.warnings.count) warning(s)",
            details: details
        )
    }

    private func buttonCheck(config: AppConfig, configExists: Bool) -> DoctorCheck {
        let mappings = [
            ("gesture", config.buttons.gesture),
            ("back", config.buttons.back),
            ("forward", config.buttons.forward)
        ]
        let missing = mappings.compactMap { name, value in value == nil ? name : nil }
        let values = mappings.map { name, value in "\(name)=\(value.map(String.init) ?? "disabled")" }.joined(separator: ", ")
        guard missing.isEmpty else {
            return DoctorCheck(
                name: "buttons",
                severity: .warning,
                summary: values,
                details: ["missing IDs stay disabled: \(missing.joined(separator: ", "))"]
            )
        }
        return DoctorCheck(name: "buttons", severity: .ok, summary: values, details: configExists ? [] : ["using defaults because config.json is missing"])
    }

    private func behaviorCheck(config: AppConfig) -> DoctorCheck {
        DoctorCheck(
            name: "behavior",
            severity: .info,
            summary: "actionBackend=\(config.actionBackend.rawValue), scrollTransformMode=\(config.scrollTransformMode.rawValue)",
            details: ["smoothScroll=\(config.smoothScroll), smoothScrollMode=\(config.smoothScrollMode.rawValue), threshold=\(String(format: "%.1f", config.threshold))"]
        )
    }

    private func lifecycleCheck() -> DoctorCheck {
        do {
            switch try lifecycle.diagnoseWorkerReadOnly() {
            case .stopped:
                return DoctorCheck(name: "worker", severity: .ok, summary: "stopped; no PID metadata")
            case .running(let identity, let legacyMetadata):
                return DoctorCheck(
                    name: "worker",
                    severity: legacyMetadata ? .warning : .ok,
                    summary: "running pid \(identity.pid)",
                    details: legacyMetadata ? ["legacy numeric PID metadata is still present; lifecycle commands can migrate it safely"] : [identity.executablePath]
                )
            case .stale(let reason):
                return DoctorCheck(name: "worker", severity: .warning, summary: "stale PID metadata", details: [reason, "doctor left the PID file unchanged"])
            case .malformedMetadata:
                return DoctorCheck(name: "worker", severity: .warning, summary: "malformed PID metadata", details: [paths.pidFile.path, "doctor left the PID file unchanged"])
            }
        } catch {
            return DoctorCheck(name: "worker", severity: .blocker, summary: "could not read lifecycle state", details: [String(describing: error)])
        }
    }

    private func accessibilityCheck() -> DoctorCheck {
        guard CGPreflightPostEventAccess() else {
            return DoctorCheck(
                name: "Accessibility",
                severity: .blocker,
                summary: "not granted",
                details: ["allow Terminal and/or mx3-lite in System Settings > Privacy & Security > Accessibility"]
            )
        }
        return DoctorCheck(name: "Accessibility", severity: .ok, summary: "granted")
    }

    private func inputMonitoringCheck(config: AppConfig) -> DoctorCheck {
        guard CGPreflightListenEventAccess() else {
            let relevance = config.scrollTransformMode == .mxMasterOnly
                ? "needed for reliable MX Master HID classification"
                : "may be needed for HID inspection"
            return DoctorCheck(
                name: "Input Monitoring",
                severity: .warning,
                summary: "not granted",
                details: [relevance, "allow Terminal and/or mx3-lite in System Settings > Privacy & Security > Input Monitoring"]
            )
        }
        return DoctorCheck(name: "Input Monitoring", severity: .ok, summary: "granted")
    }

    private func deviceCheck() -> DoctorCheck {
        let snapshot = MXMasterDeviceRegistry.connectedDeviceSnapshot()
        guard !snapshot.devices.isEmpty else {
            var details = ["connect an MX Master 3 or 3S, then run mxmaster doctor again"]
            if snapshot.openResult != kIOReturnSuccess {
                details.append("IOHIDManagerOpen result: \(snapshot.openResult)")
            }
            return DoctorCheck(name: "MX Master", severity: .warning, summary: "no matching Logitech device detected", details: details)
        }
        return DoctorCheck(
            name: "MX Master",
            severity: .ok,
            summary: "detected \(snapshot.devices.count) device(s)",
            details: snapshot.devices.map(\.description) + ["IOHIDManagerOpen result: \(snapshot.openResult)"]
        )
    }
}
