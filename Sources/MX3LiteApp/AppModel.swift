import AppKit
import Combine
import Foundation
import MX3AppSupport

enum AppWorkerState: Equatable {
    case loading
    case running(Int32?)
    case stopped
    case unavailable(String)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .loading: return "Checking"
        case .running(let pid): return pid.map { "Running (PID \($0))" } ?? "Running"
        case .stopped: return "Stopped"
        case .unavailable: return "Needs attention"
        }
    }
}

struct AppAlertMessage: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published var settings = AppSettings.default
    @Published private(set) var savedSettings = AppSettings.default
    @Published private(set) var workerState: AppWorkerState = .loading
    @Published private(set) var isBusy = false
    @Published private(set) var restartRequired = false
    @Published private(set) var doctorOutput = "Run diagnostics to check permissions, the helper, config, and connected mouse."
    @Published var alert: AppAlertMessage?

    let helperURL: URL
    let configURL: URL

    private let helper: HelperClient
    private let settingsStore: AppSettingsStore
    private var hasLoaded = false

    init(helperURL: URL, settingsStore: AppSettingsStore = AppSettingsStore()) {
        self.helperURL = helperURL
        self.settingsStore = settingsStore
        self.configURL = settingsStore.configURL
        self.helper = HelperClient(executableURL: helperURL)
    }

    var hasUnsavedChanges: Bool { settings != savedSettings }
    var validationWarnings: [String] { settings.validationWarnings }

    func refresh(forceConfigReload: Bool = false) {
        guard !isBusy else { return }
        isBusy = true
        Task {
            let statusResult = await helper.run(["status"])
            applyStatus(statusResult)

            if !hasLoaded || forceConfigReload {
                do {
                    let loaded = try settingsStore.loadOrCreate()
                    settings = loaded.settings
                    savedSettings = loaded.settings
                    restartRequired = false
                    hasLoaded = true
                } catch {
                    alert = AppAlertMessage(title: "Config could not be loaded", message: error.localizedDescription)
                }
            }
            isBusy = false
        }
    }

    func toggleWorker() {
        guard !isBusy else { return }
        isBusy = true
        let command = workerState.isRunning ? "off" : "on"
        Task {
            let result = await helper.run([command])
            if result.exitCode != 0 {
                alert = AppAlertMessage(title: "Worker command failed", message: result.combinedOutput)
            }
            applyStatus(await helper.run(["status"]))
            if command == "on", workerState.isRunning {
                restartRequired = false
            }
            isBusy = false
        }
    }

    func save() {
        guard !isBusy else { return }
        do {
            let wasRunning = workerState.isRunning
            let normalized = settings.normalized
            try settingsStore.save(normalized)
            settings = normalized
            savedSettings = normalized
            restartRequired = wasRunning
        } catch {
            alert = AppAlertMessage(title: "Config could not be saved", message: error.localizedDescription)
        }
    }

    func discardChanges() {
        settings = savedSettings
    }

    func restartWorker() {
        guard workerState.isRunning, !isBusy else { return }
        isBusy = true
        Task {
            let stopResult = await helper.run(["off"])
            guard stopResult.exitCode == 0 else {
                alert = AppAlertMessage(title: "Worker could not stop", message: stopResult.combinedOutput)
                applyStatus(await helper.run(["status"]))
                isBusy = false
                return
            }

            let startResult = await helper.run(["on"])
            if startResult.exitCode != 0 {
                alert = AppAlertMessage(title: "Worker could not restart", message: startResult.combinedOutput)
            }
            applyStatus(await helper.run(["status"]))
            restartRequired = !workerState.isRunning
            isBusy = false
        }
    }

    func runDoctor() {
        guard !isBusy else { return }
        isBusy = true
        doctorOutput = "Running diagnostics..."
        Task {
            let result = await helper.run(["doctor", "--verbose"])
            doctorOutput = result.combinedOutput.isEmpty ? "Doctor returned no output." : result.combinedOutput
            isBusy = false
        }
    }

    func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([configURL])
    }

    func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openPrivacyPane("Privacy_ListenEvent")
    }

    private func applyStatus(_ result: HelperCommandResult) {
        switch WorkerStatusParser.parse(result) {
        case .running(let pid): workerState = .running(pid)
        case .stopped: workerState = .stopped
        case .unknown(let message): workerState = .unavailable(message)
        }
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

enum HelperLocator {
    static func locate(bundle: Bundle = .main) -> URL {
        let bundled = bundle.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("mx3-lite")
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        if let executable = bundle.executableURL {
            return executable.deletingLastPathComponent().appendingPathComponent("mx3-lite")
        }
        return URL(fileURLWithPath: "mx3-lite")
    }
}
