import CoreGraphics
import Foundation
import IOKit.hid

@main
struct MX3Lite {
    static func main() {
        do {
            try CLI().run()
        } catch let error as CLIError {
            FileHandle.standardError.writeLine("mx3-lite: \(error.message)")
            exit(Int32(error.exitCode))
        } catch {
            FileHandle.standardError.writeLine("mx3-lite: \(error)")
            exit(1)
        }
    }
}

struct CLI {
    private let paths = AppPaths()

    func run() throws {
        var args = Array(CommandLine.arguments.dropFirst())
        let executableName = URL(fileURLWithPath: CommandLine.arguments.first ?? "mx3-lite").lastPathComponent

        if executableName == "mx3-on" {
            try start(debug: args.removeFlag("--debug"))
            return
        }

        if executableName == "mx3-off" {
            try stop()
            return
        }

        if executableName == "mx3-toggle" {
            try toggle(debug: args.removeFlag("--debug"))
            return
        }

        if executableName == "mx3-status" {
            try status()
            return
        }

        if args.isEmpty {
            try printHelp()
            return
        }

        let debug = args.removeFlag("--debug")
        let command = args.removeFirst()

        switch command {
        case "--inspect", "inspect":
            try inspect()
        case "--run-foreground", "run-foreground":
            try runForeground(debug: debug)
        case "--debug-scroll", "debug-scroll":
            try debugScroll()
        case "--test-left", "test-left":
            try testAction(.left)
        case "--test-right", "test-right":
            try testAction(.right)
        case "--test-up", "test-up":
            try testAction(.up)
        case "--print-config", "print-config":
            try printConfig()
        case "on":
            try start(debug: debug)
        case "off":
            try stop()
        case "toggle":
            try toggle(debug: debug)
        case "status":
            try status()
        case "init-config":
            try initConfig()
        case "run":
            try runWorker(debug: debug)
        case "config-path":
            print(paths.configFile.path)
        case "--help", "-h", "help":
            try printHelp()
        default:
            throw CLIError("unknown command: \(command)", exitCode: 64)
        }
    }

    private func printHelp() throws {
        print("""
        mx3-lite

        Usage:
          mx3-lite --inspect        Print mouse button, movement, and scroll events
          mx3-lite --run-foreground --debug
                                  Run gesture mapping in the foreground with live event logs
          mx3-lite --debug-scroll  Run foreground scroll transform debugger
          mx3-lite --test-left     Directly post Ctrl+Left using actionBackend
          mx3-lite --test-right    Directly post Ctrl+Right using actionBackend
          mx3-lite --test-up       Directly post Ctrl+Up using actionBackend
          mx3-lite --print-config  Print parsed config values and sources
          mx3-lite on [--debug]     Start the gesture worker
          mx3-lite off              Stop the gesture worker
          mx3-lite toggle [--debug] Toggle the gesture worker
          mx3-lite status           Print worker status
          mx3-lite init-config      Create config.json if missing
          mx3-lite config-path      Print config.json path

        Symlink helpers are supported:
          mx3-on, mx3-off, mx3-toggle, mx3-status
        """)
    }

    private func inspect() throws {
        try paths.ensureDirectories()
        print("mx3-lite inspect mode")
        print("Move the mouse, scroll, and press MX Master 3 buttons. Press Ctrl-C to exit.")
        print("Use the CGEvent button numbers from this output in \(paths.configFile.path).")

        let eventTap = try MouseEventTap(mode: .inspect)
        let hidInspector = HIDInspector()
        hidInspector.start()

        let signalController = SignalController()
        signalController.start {
            print("inspect stopped")
            eventTap.stop()
            hidInspector.stop()
            CFRunLoopStop(CFRunLoopGetMain())
        }

        eventTap.start()
        CFRunLoopRun()
    }

    private func start(debug: Bool) throws {
        try paths.ensureDirectories()

        if let pid = try currentLivePID() {
            print("mx3-lite is already running (pid \(pid))")
            return
        }

        try removeStalePIDFile()

        guard let executableURL = Bundle.main.executableURL else {
            throw CLIError("could not resolve executable path")
        }

        let process = Process()
        process.executableURL = executableURL.resolvingSymlinksInPath()
        process.arguments = debug ? ["run", "--debug"] : ["run"]
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")

        if debug {
            try paths.ensureLogDirectory()
            FileManager.default.createFile(atPath: paths.logFile.path, contents: nil)
            guard let logHandle = try? FileHandle(forWritingTo: paths.logFile) else {
                throw CLIError("could not open debug log at \(paths.logFile.path)")
            }
            try logHandle.seekToEnd()
            process.standardOutput = logHandle
            process.standardError = logHandle
        } else {
            process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
            process.standardError = FileHandle(forWritingAtPath: "/dev/null")
        }

        try process.run()
        try "\(process.processIdentifier)\n".write(to: paths.pidFile, atomically: true, encoding: .utf8)

        usleep(150_000)
        if !processExists(process.processIdentifier) {
            try removeStalePIDFile()
            throw CLIError("worker exited immediately. Check macOS permissions or run mx3-lite run --debug.")
        }

        print("mx3-lite started (pid \(process.processIdentifier))")
        if debug {
            print("debug log: \(paths.logFile.path)")
        }
    }

    private func stop() throws {
        guard let pid = try readPID() else {
            try removeStalePIDFile()
            print("mx3-lite is stopped")
            return
        }

        if !processExists(pid) {
            try removeStalePIDFile()
            print("mx3-lite is stopped")
            return
        }

        if Darwin.kill(pid, SIGTERM) != 0 {
            throw CLIError("failed to stop pid \(pid): \(String(cString: strerror(errno)))")
        }

        let deadline = Date().addingTimeInterval(2.0)
        while processExists(pid), Date() < deadline {
            usleep(50_000)
        }

        if processExists(pid) {
            _ = Darwin.kill(pid, SIGKILL)
        }

        try removeStalePIDFile()
        print("mx3-lite stopped")
    }

    private func toggle(debug: Bool) throws {
        if let _ = try currentLivePID() {
            try stop()
        } else {
            try start(debug: debug)
        }
    }

    private func status() throws {
        if let pid = try currentLivePID() {
            print("mx3-lite is running (pid \(pid))")
        } else {
            try removeStalePIDFile()
            print("mx3-lite is stopped")
        }
    }

    private func initConfig() throws {
        try paths.ensureDirectories()
        _ = try ConfigStore(paths: paths).loadOrCreate()
        print(paths.configFile.path)
    }

    private func testAction(_ direction: ArrowDirection) throws {
        try paths.ensureDirectories()
        let loadedConfig = try ConfigStore(paths: paths).loadOrCreateWithSources()
        let logger = DebugLogger(enabled: true)

        print("configPath: \(paths.configFile.path)")
        print("actionBackend: \(loadedConfig.config.actionBackend.rawValue) source=\(loadedConfig.sources.actionBackend)")
        print("posting test-\(direction.label)")
        KeySender.sendControlArrow(
            direction,
            backend: loadedConfig.config.actionBackend,
            logger: logger,
            waitForSystemEvents: true
        )
    }

    private func printConfig() throws {
        try paths.ensureDirectories()
        let loadedConfig = try ConfigStore(paths: paths).loadOrCreateWithSources()
        ConfigPrinter.printLoadedConfig(loadedConfig, path: paths.configFile)
    }

    private func debugScroll() throws {
        try paths.ensureDirectories()

        if let existingPID = try currentLivePID(), existingPID != getpid() {
            throw CLIError("mx3-lite is already running (pid \(existingPID)); stop it before scroll debugging")
        }

        let loadedConfig = try ConfigStore(paths: paths).loadOrCreateWithSources()
        let logger = DebugLogger(enabled: true)

        print("mx3-lite scroll debug mode")
        print("config: \(paths.configFile.path)")
        print("Press Ctrl-C to exit.")

        let mxMasterRegistry = MXMasterDeviceRegistry(logger: logger, debug: true)
        mxMasterRegistry.start()

        let debugger = ScrollDebugger(config: loadedConfig.config, logger: logger, mxMasterRegistry: mxMasterRegistry)
        let eventTap = try MouseEventTap(mode: .debugScroll(debugger), logger: logger)

        let signalController = SignalController()
        signalController.start {
            logger.log("scroll debugger stopping")
            eventTap.stop()
            mxMasterRegistry.stop()
            CFRunLoopStop(CFRunLoopGetMain())
        }

        eventTap.start()
        CFRunLoopRun()
    }

    private func runForeground(debug: Bool) throws {
        try paths.ensureDirectories()

        if let existingPID = try currentLivePID(), existingPID != getpid() {
            throw CLIError("mx3-lite is already running (pid \(existingPID)); stop it before foreground debugging")
        }

        let configStore = ConfigStore(paths: paths)
        let config = try configStore.loadOrCreate()
        let logger = DebugLogger(enabled: debug)

        print("mx3-lite foreground mode")
        print("config: \(paths.configFile.path)")
        print("debug events: \(debug ? "enabled" : "disabled")")
        print("Press Ctrl-C to exit.")

        let mxMasterRegistry = MXMasterDeviceRegistry(logger: logger, debug: debug)
        if config.needsMXMasterRegistry || debug {
            mxMasterRegistry.start()
        }

        let mapper = GestureMapper(config: config, logger: logger, liveEventDebug: debug, mxMasterRegistry: mxMasterRegistry)
        let eventTap = try MouseEventTap(mode: .map(mapper), logger: logger)

        let signalController = SignalController()
        signalController.start {
            logger.log("foreground worker stopping")
            eventTap.stop()
            mxMasterRegistry.stop()
            CFRunLoopStop(CFRunLoopGetMain())
        }

        eventTap.start()
        CFRunLoopRun()
    }

    private func runWorker(debug: Bool) throws {
        try paths.ensureDirectories()

        if let existingPID = try currentLivePID(), existingPID != getpid() {
            throw CLIError("mx3-lite is already running (pid \(existingPID))")
        }

        let configStore = ConfigStore(paths: paths)
        let config = try configStore.loadOrCreate()
        try "\(getpid())\n".write(to: paths.pidFile, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: paths.pidFile)
        }

        let logger = DebugLogger(enabled: debug)
        logger.log("worker started pid=\(getpid()) config=\(paths.configFile.path)")

        if config.buttons.gesture == nil && config.buttons.back == nil && config.buttons.forward == nil {
            logger.log("no buttons configured; run mx3-lite --inspect, then edit config.json")
        }

        let mxMasterRegistry = MXMasterDeviceRegistry(logger: logger, debug: debug)
        if config.needsMXMasterRegistry || debug {
            mxMasterRegistry.start()
        }

        let mapper = GestureMapper(config: config, logger: logger, liveEventDebug: false, mxMasterRegistry: mxMasterRegistry)
        let eventTap = try MouseEventTap(mode: .map(mapper), logger: logger)

        let signalController = SignalController()
        signalController.start {
            logger.log("worker stopping")
            eventTap.stop()
            mxMasterRegistry.stop()
            try? FileManager.default.removeItem(at: paths.pidFile)
            CFRunLoopStop(CFRunLoopGetMain())
        }

        eventTap.start()
        CFRunLoopRun()
    }

    private func currentLivePID() throws -> pid_t? {
        guard let pid = try readPID() else {
            return nil
        }
        return processExists(pid) ? pid : nil
    }

    private func readPID() throws -> pid_t? {
        guard FileManager.default.fileExists(atPath: paths.pidFile.path) else {
            return nil
        }

        let raw = try String(contentsOf: paths.pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = pid_t(raw), pid > 0 else {
            return nil
        }
        return pid
    }

    private func processExists(_ pid: pid_t) -> Bool {
        if Darwin.kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private func removeStalePIDFile() throws {
        if FileManager.default.fileExists(atPath: paths.pidFile.path) {
            try FileManager.default.removeItem(at: paths.pidFile)
        }
    }
}

struct AppPaths {
    let appSupportDirectory: URL
    let logDirectory: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        appSupportDirectory = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("mx3-lite", isDirectory: true)
        logDirectory = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
    }

    var configFile: URL {
        appSupportDirectory.appendingPathComponent("config.json")
    }

    var pidFile: URL {
        appSupportDirectory.appendingPathComponent("mx3-lite.pid")
    }

    var logFile: URL {
        logDirectory.appendingPathComponent("mx3-lite.log")
    }

    func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
    }

    func ensureLogDirectory() throws {
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }
}

struct ConfigStore {
    let paths: AppPaths

    func loadOrCreate() throws -> AppConfig {
        try loadOrCreateWithSources().config
    }

    func loadOrCreateWithSources() throws -> LoadedConfig {
        if !FileManager.default.fileExists(atPath: paths.configFile.path) {
            let defaultConfig = AppConfig.default
            let data = try JSONEncoder.mx3Pretty.encode(defaultConfig)
            try data.write(to: paths.configFile, options: .atomic)
            return LoadedConfig(
                config: defaultConfig,
                configFileExisted: false,
                configFileCreated: true,
                sources: ConfigSources.all("default"),
                warnings: []
            )
        }

        let data = try Data(contentsOf: paths.configFile)
        do {
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            return LoadedConfig(
                config: config,
                configFileExisted: true,
                configFileCreated: false,
                sources: ConfigSources(data: data),
                warnings: ConfigValidator.warnings(data: data, config: config)
            )
        } catch {
            throw CLIError("invalid config.json at \(paths.configFile.path): \(error)")
        }
    }
}

struct LoadedConfig {
    let config: AppConfig
    let configFileExisted: Bool
    let configFileCreated: Bool
    let sources: ConfigSources
    let warnings: [String]
}

struct ConfigSources {
    let threshold: String
    let downAction: String
    let invertY: String
    let actionBackend: String
    let invertDesktopGestureDirection: String
    let invertVerticalScroll: String
    let invertHorizontalScroll: String
    let scrollMultiplier: String
    let smoothScroll: String
    let smoothScrollMode: String
    let smoothScrollFactor: String
    let scrollDeadzone: String
    let maxScrollStep: String
    let scrollAcceleration: String
    let freeSpinDamping: String
    let ratchetStepMultiplier: String
    let allowGlobalScrollTransform: String
    let scrollTransformMode: String
    let gestureButton: String
    let backButton: String
    let forwardButton: String

    static func all(_ source: String) -> ConfigSources {
        ConfigSources(
            threshold: source,
            downAction: source,
            invertY: source,
            actionBackend: source,
            invertDesktopGestureDirection: source,
            invertVerticalScroll: source,
            invertHorizontalScroll: source,
            scrollMultiplier: source,
            smoothScroll: source,
            smoothScrollMode: source,
            smoothScrollFactor: source,
            scrollDeadzone: source,
            maxScrollStep: source,
            scrollAcceleration: source,
            freeSpinDamping: source,
            ratchetStepMultiplier: source,
            allowGlobalScrollTransform: source,
            scrollTransformMode: source,
            gestureButton: source,
            backButton: source,
            forwardButton: source
        )
    }

    init(data: Data) {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let buttons = json["buttons"] as? [String: Any]

        threshold = ConfigSources.topLevelSource("threshold", in: json)
        downAction = ConfigSources.topLevelSource("downAction", in: json)
        invertY = ConfigSources.topLevelSource("invertY", in: json)
        actionBackend = ConfigSources.topLevelSource("actionBackend", in: json)
        invertDesktopGestureDirection = ConfigSources.topLevelSource("invertDesktopGestureDirection", in: json)
        invertVerticalScroll = ConfigSources.topLevelSource("invertVerticalScroll", in: json)
        invertHorizontalScroll = ConfigSources.topLevelSource("invertHorizontalScroll", in: json)
        scrollMultiplier = ConfigSources.topLevelSource("scrollMultiplier", in: json)
        smoothScroll = ConfigSources.topLevelSource("smoothScroll", in: json)
        smoothScrollMode = ConfigSources.topLevelSource("smoothScrollMode", in: json)
        smoothScrollFactor = ConfigSources.topLevelSource("smoothScrollFactor", in: json)
        scrollDeadzone = ConfigSources.topLevelSource("scrollDeadzone", in: json)
        maxScrollStep = ConfigSources.topLevelSource("maxScrollStep", in: json)
        scrollAcceleration = ConfigSources.topLevelSource("scrollAcceleration", in: json)
        freeSpinDamping = ConfigSources.topLevelSource("freeSpinDamping", in: json)
        ratchetStepMultiplier = ConfigSources.topLevelSource("ratchetStepMultiplier", in: json)
        allowGlobalScrollTransform = ConfigSources.topLevelSource("allowGlobalScrollTransform", in: json)
        scrollTransformMode = ConfigSources.topLevelSource("scrollTransformMode", in: json)
        gestureButton = ConfigSources.buttonSource("gesture", buttons: buttons, rootHasButtons: json.keys.contains("buttons"))
        backButton = ConfigSources.buttonSource("back", buttons: buttons, rootHasButtons: json.keys.contains("buttons"))
        forwardButton = ConfigSources.buttonSource("forward", buttons: buttons, rootHasButtons: json.keys.contains("buttons"))
    }

    private init(
        threshold: String,
        downAction: String,
        invertY: String,
        actionBackend: String,
        invertDesktopGestureDirection: String,
        invertVerticalScroll: String,
        invertHorizontalScroll: String,
        scrollMultiplier: String,
        smoothScroll: String,
        smoothScrollMode: String,
        smoothScrollFactor: String,
        scrollDeadzone: String,
        maxScrollStep: String,
        scrollAcceleration: String,
        freeSpinDamping: String,
        ratchetStepMultiplier: String,
        allowGlobalScrollTransform: String,
        scrollTransformMode: String,
        gestureButton: String,
        backButton: String,
        forwardButton: String
    ) {
        self.threshold = threshold
        self.downAction = downAction
        self.invertY = invertY
        self.actionBackend = actionBackend
        self.invertDesktopGestureDirection = invertDesktopGestureDirection
        self.invertVerticalScroll = invertVerticalScroll
        self.invertHorizontalScroll = invertHorizontalScroll
        self.scrollMultiplier = scrollMultiplier
        self.smoothScroll = smoothScroll
        self.smoothScrollMode = smoothScrollMode
        self.smoothScrollFactor = smoothScrollFactor
        self.scrollDeadzone = scrollDeadzone
        self.maxScrollStep = maxScrollStep
        self.scrollAcceleration = scrollAcceleration
        self.freeSpinDamping = freeSpinDamping
        self.ratchetStepMultiplier = ratchetStepMultiplier
        self.allowGlobalScrollTransform = allowGlobalScrollTransform
        self.scrollTransformMode = scrollTransformMode
        self.gestureButton = gestureButton
        self.backButton = backButton
        self.forwardButton = forwardButton
    }

    private static func topLevelSource(_ key: String, in json: [String: Any]) -> String {
        json.keys.contains(key) ? "config.json" : "default"
    }

    private static func buttonSource(_ key: String, buttons: [String: Any]?, rootHasButtons: Bool) -> String {
        guard rootHasButtons else {
            return "default"
        }
        guard let buttons else {
            return "config.json (invalid buttons object)"
        }
        return buttons.keys.contains(key) ? "config.json" : "config.json (missing -> disabled)"
    }
}

enum ConfigPrinter {
    static func printLoadedConfig(_ loadedConfig: LoadedConfig, path: URL) {
        let config = loadedConfig.config
        let sources = loadedConfig.sources

        print("configPath: \(path.path)")
        print("configFileExisted: \(loadedConfig.configFileExisted)")
        print("configFileCreated: \(loadedConfig.configFileCreated)")
        print("values:")
        print("  threshold: \(format(config.threshold)) source=\(sources.threshold)")
        print("  actionBackend: \(config.actionBackend.rawValue) source=\(sources.actionBackend)")
        print("  downAction: \(config.downAction.rawValue) source=\(sources.downAction)")
        print("  invertY: \(config.invertY) source=\(sources.invertY)")
        print("  invertDesktopGestureDirection: \(config.invertDesktopGestureDirection) source=\(sources.invertDesktopGestureDirection)")
        print("  buttons.gesture: \(formatOptional(config.buttons.gesture)) source=\(sources.gestureButton)")
        print("  buttons.back: \(formatOptional(config.buttons.back)) source=\(sources.backButton)")
        print("  buttons.forward: \(formatOptional(config.buttons.forward)) source=\(sources.forwardButton)")
        print("  invertVerticalScroll: \(config.invertVerticalScroll) source=\(sources.invertVerticalScroll)")
        print("  invertHorizontalScroll: \(config.invertHorizontalScroll) source=\(sources.invertHorizontalScroll)")
        print("  scrollMultiplier: \(format(config.scrollMultiplier)) source=\(sources.scrollMultiplier)")
        print("  smoothScroll: \(config.smoothScroll) source=\(sources.smoothScroll)")
        print("  smoothScrollMode: \(config.smoothScrollMode.rawValue) source=\(sources.smoothScrollMode)")
        print("  smoothScrollFactor: \(format(config.smoothScrollFactor)) source=\(sources.smoothScrollFactor)")
        print("  scrollDeadzone: \(format(config.scrollDeadzone)) source=\(sources.scrollDeadzone)")
        print("  maxScrollStep: \(format(config.maxScrollStep)) source=\(sources.maxScrollStep)")
        print("  scrollAcceleration: \(format(config.scrollAcceleration)) source=\(sources.scrollAcceleration)")
        print("  freeSpinDamping: \(format(config.freeSpinDamping)) source=\(sources.freeSpinDamping)")
        print("  ratchetStepMultiplier: \(format(config.ratchetStepMultiplier)) source=\(sources.ratchetStepMultiplier)")
        print("  allowGlobalScrollTransform: \(config.allowGlobalScrollTransform) source=\(sources.allowGlobalScrollTransform)")
        print("  scrollTransformMode: \(config.scrollTransformMode.rawValue) source=\(sources.scrollTransformMode)")

        if !loadedConfig.warnings.isEmpty {
            print("warnings:")
            loadedConfig.warnings.forEach { warning in
                print("  - \(warning)")
            }
        }
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func formatOptional(_ value: Int?) -> String {
        value.map(String.init) ?? "null"
    }
}

enum ConfigValidator {
    static func warnings(data: Data, config: AppConfig) -> [String] {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        var warnings: [String] = []

        appendEnumWarning(
            key: "actionBackend",
            value: json["actionBackend"],
            allowedValues: [ActionBackend.cgEvent.rawValue, ActionBackend.systemEvents.rawValue],
            fallback: config.actionBackend.rawValue,
            warnings: &warnings
        )
        appendEnumWarning(
            key: "scrollTransformMode",
            value: json["scrollTransformMode"],
            allowedValues: [ScrollTransformMode.mxMasterOnly.rawValue, ScrollTransformMode.global.rawValue, ScrollTransformMode.disabled.rawValue],
            fallback: config.scrollTransformMode.rawValue,
            warnings: &warnings
        )
        appendEnumWarning(
            key: "smoothScrollMode",
            value: json["smoothScrollMode"],
            allowedValues: [SmoothScrollMode.ema.rawValue, SmoothScrollMode.dampenSpikes.rawValue, SmoothScrollMode.inertia.rawValue],
            fallback: config.smoothScrollMode.rawValue,
            warnings: &warnings
        )
        appendEnumWarning(
            key: "downAction",
            value: json["downAction"],
            allowedValues: [DownAction.ctrlDown.rawValue, DownAction.disabled.rawValue],
            fallback: config.downAction.rawValue,
            warnings: &warnings
        )

        appendPositiveWarning(key: "threshold", value: json["threshold"], fallback: config.threshold, warnings: &warnings)
        appendRangeWarning(key: "smoothScrollFactor", value: json["smoothScrollFactor"], range: 0...0.95, resolved: config.smoothScrollFactor, warnings: &warnings)
        appendRangeWarning(key: "scrollMultiplier", value: json["scrollMultiplier"], range: 0.1...5, resolved: config.scrollMultiplier, warnings: &warnings)
        appendRangeWarning(key: "maxScrollStep", value: json["maxScrollStep"], range: 1...100, resolved: config.maxScrollStep, warnings: &warnings)
        appendRangeWarning(key: "scrollAcceleration", value: json["scrollAcceleration"], range: 0.1...3, resolved: config.scrollAcceleration, warnings: &warnings)
        appendRangeWarning(key: "freeSpinDamping", value: json["freeSpinDamping"], range: 0...1, resolved: config.freeSpinDamping, warnings: &warnings)
        appendRangeWarning(key: "ratchetStepMultiplier", value: json["ratchetStepMultiplier"], range: 0.1...5, resolved: config.ratchetStepMultiplier, warnings: &warnings)
        appendRangeWarning(key: "scrollDeadzone", value: json["scrollDeadzone"], range: 0...100, resolved: config.scrollDeadzone, warnings: &warnings)

        return warnings
    }

    private static func appendEnumWarning(
        key: String,
        value: Any?,
        allowedValues: [String],
        fallback: String,
        warnings: inout [String]
    ) {
        guard let value else {
            return
        }
        guard let raw = value as? String else {
            warnings.append("\(key) has invalid type; using \(fallback)")
            return
        }
        if !allowedValues.contains(raw) {
            warnings.append("\(key) has unknown value \"\(raw)\"; using \(fallback)")
        }
    }

    private static func appendPositiveWarning(key: String, value: Any?, fallback: Double, warnings: inout [String]) {
        guard let value else {
            return
        }
        guard let raw = numericValue(value) else {
            warnings.append("\(key) has invalid type; using \(format(fallback))")
            return
        }
        if !raw.isFinite || raw <= 0 {
            warnings.append("\(key) must be greater than 0; using \(format(fallback))")
        }
    }

    private static func appendRangeWarning(
        key: String,
        value: Any?,
        range: ClosedRange<Double>,
        resolved: Double,
        warnings: inout [String]
    ) {
        guard let value else {
            return
        }
        guard let raw = numericValue(value) else {
            warnings.append("\(key) has invalid type; using \(format(resolved))")
            return
        }
        if !raw.isFinite || !range.contains(raw) {
            warnings.append("\(key) outside \(format(range.lowerBound))...\(format(range.upperBound)); using \(format(resolved))")
        }
    }

    private static func numericValue(_ value: Any) -> Double? {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return nil
            }
            return number.doubleValue
        case is Bool:
            return nil
        case let number as Double:
            return number
        case let number as Float:
            return Double(number)
        case let number as Int:
            return Double(number)
        case let number as Int64:
            return Double(number)
        case let number as UInt:
            return Double(number)
        case let number as UInt64:
            return Double(number)
        default:
            return nil
        }
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

struct AppConfig: Codable {
    var threshold: Double
    var buttons: ButtonConfig
    var downAction: DownAction
    var invertY: Bool
    var invertDesktopGestureDirection: Bool
    var actionBackend: ActionBackend
    var invertVerticalScroll: Bool
    var invertHorizontalScroll: Bool
    var scrollMultiplier: Double
    var smoothScroll: Bool
    var smoothScrollMode: SmoothScrollMode
    var smoothScrollFactor: Double
    var scrollDeadzone: Double
    var maxScrollStep: Double
    var scrollAcceleration: Double
    var freeSpinDamping: Double
    var ratchetStepMultiplier: Double
    var allowGlobalScrollTransform: Bool
    var scrollTransformMode: ScrollTransformMode

    static let `default` = AppConfig(
        threshold: 220,
        buttons: ButtonConfig(gesture: 5, back: 3, forward: 4),
        downAction: .ctrlDown,
        invertY: false,
        invertDesktopGestureDirection: true,
        actionBackend: .systemEvents,
        invertVerticalScroll: true,
        invertHorizontalScroll: false,
        scrollMultiplier: 1,
        smoothScroll: true,
        smoothScrollMode: .ema,
        smoothScrollFactor: 0.35,
        scrollDeadzone: 0,
        maxScrollStep: 8,
        scrollAcceleration: 1,
        freeSpinDamping: 0.75,
        ratchetStepMultiplier: 1,
        allowGlobalScrollTransform: false,
        scrollTransformMode: .mxMasterOnly
    )

    var needsMXMasterRegistry: Bool {
        scrollTransformMode == .mxMasterOnly
    }

    enum CodingKeys: String, CodingKey {
        case threshold
        case buttons
        case downAction
        case invertY
        case invertDesktopGestureDirection
        case actionBackend
        case invertVerticalScroll
        case invertHorizontalScroll
        case scrollMultiplier
        case smoothScroll
        case smoothScrollMode
        case smoothScrollFactor
        case scrollDeadzone
        case maxScrollStep
        case scrollAcceleration
        case freeSpinDamping
        case ratchetStepMultiplier
        case allowGlobalScrollTransform
        case scrollTransformMode
    }

    init(
        threshold: Double,
        buttons: ButtonConfig,
        downAction: DownAction,
        invertY: Bool,
        invertDesktopGestureDirection: Bool,
        actionBackend: ActionBackend,
        invertVerticalScroll: Bool,
        invertHorizontalScroll: Bool,
        scrollMultiplier: Double,
        smoothScroll: Bool,
        smoothScrollMode: SmoothScrollMode,
        smoothScrollFactor: Double,
        scrollDeadzone: Double,
        maxScrollStep: Double,
        scrollAcceleration: Double,
        freeSpinDamping: Double,
        ratchetStepMultiplier: Double,
        allowGlobalScrollTransform: Bool,
        scrollTransformMode: ScrollTransformMode
    ) {
        self.threshold = threshold
        self.buttons = buttons
        self.downAction = downAction
        self.invertY = invertY
        self.invertDesktopGestureDirection = invertDesktopGestureDirection
        self.actionBackend = actionBackend
        self.invertVerticalScroll = invertVerticalScroll
        self.invertHorizontalScroll = invertHorizontalScroll
        self.scrollMultiplier = scrollMultiplier
        self.smoothScroll = smoothScroll
        self.smoothScrollMode = smoothScrollMode
        self.smoothScrollFactor = smoothScrollFactor
        self.scrollDeadzone = scrollDeadzone
        self.maxScrollStep = maxScrollStep
        self.scrollAcceleration = scrollAcceleration
        self.freeSpinDamping = freeSpinDamping
        self.ratchetStepMultiplier = ratchetStepMultiplier
        self.allowGlobalScrollTransform = allowGlobalScrollTransform
        self.scrollTransformMode = scrollTransformMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threshold = AppConfig.positiveOrDefault(AppConfig.decodeDouble(container, .threshold, defaultValue: AppConfig.default.threshold), defaultValue: AppConfig.default.threshold)
        buttons = (try? container.decodeIfPresent(ButtonConfig.self, forKey: .buttons)) ?? AppConfig.default.buttons
        downAction = AppConfig.decodeRawValue(container, .downAction, defaultValue: AppConfig.default.downAction)
        invertY = AppConfig.decodeBool(container, .invertY, defaultValue: AppConfig.default.invertY)
        invertDesktopGestureDirection = AppConfig.decodeBool(container, .invertDesktopGestureDirection, defaultValue: AppConfig.default.invertDesktopGestureDirection)
        actionBackend = AppConfig.decodeRawValue(container, .actionBackend, defaultValue: AppConfig.default.actionBackend)
        invertVerticalScroll = AppConfig.decodeBool(container, .invertVerticalScroll, defaultValue: AppConfig.default.invertVerticalScroll)
        invertHorizontalScroll = AppConfig.decodeBool(container, .invertHorizontalScroll, defaultValue: AppConfig.default.invertHorizontalScroll)
        scrollMultiplier = AppConfig.clamp(AppConfig.decodeDouble(container, .scrollMultiplier, defaultValue: AppConfig.default.scrollMultiplier), min: 0.1, max: 5, defaultValue: AppConfig.default.scrollMultiplier)
        smoothScroll = AppConfig.decodeBool(container, .smoothScroll, defaultValue: AppConfig.default.smoothScroll)
        smoothScrollMode = AppConfig.decodeRawValue(container, .smoothScrollMode, defaultValue: AppConfig.default.smoothScrollMode)
        smoothScrollFactor = AppConfig.clamp(AppConfig.decodeDouble(container, .smoothScrollFactor, defaultValue: AppConfig.default.smoothScrollFactor), min: 0, max: 0.95, defaultValue: AppConfig.default.smoothScrollFactor)
        scrollDeadzone = AppConfig.clamp(AppConfig.decodeDouble(container, .scrollDeadzone, defaultValue: AppConfig.default.scrollDeadzone), min: 0, max: 100, defaultValue: AppConfig.default.scrollDeadzone)
        maxScrollStep = AppConfig.clamp(AppConfig.decodeDouble(container, .maxScrollStep, defaultValue: AppConfig.default.maxScrollStep), min: 1, max: 100, defaultValue: AppConfig.default.maxScrollStep)
        scrollAcceleration = AppConfig.clamp(AppConfig.decodeDouble(container, .scrollAcceleration, defaultValue: AppConfig.default.scrollAcceleration), min: 0.1, max: 3, defaultValue: AppConfig.default.scrollAcceleration)
        freeSpinDamping = AppConfig.clamp(AppConfig.decodeDouble(container, .freeSpinDamping, defaultValue: AppConfig.default.freeSpinDamping), min: 0, max: 1, defaultValue: AppConfig.default.freeSpinDamping)
        ratchetStepMultiplier = AppConfig.clamp(AppConfig.decodeDouble(container, .ratchetStepMultiplier, defaultValue: AppConfig.default.ratchetStepMultiplier), min: 0.1, max: 5, defaultValue: AppConfig.default.ratchetStepMultiplier)
        allowGlobalScrollTransform = AppConfig.decodeBool(container, .allowGlobalScrollTransform, defaultValue: AppConfig.default.allowGlobalScrollTransform)
        scrollTransformMode = AppConfig.decodeRawValue(container, .scrollTransformMode, defaultValue: AppConfig.default.scrollTransformMode)
    }

    private static func decodeDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys,
        defaultValue: Double
    ) -> Double {
        (try? container.decode(Double.self, forKey: key)) ?? defaultValue
    }

    private static func decodeBool(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys,
        defaultValue: Bool
    ) -> Bool {
        (try? container.decode(Bool.self, forKey: key)) ?? defaultValue
    }

    private static func decodeRawValue<T>(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys,
        defaultValue: T
    ) -> T where T: RawRepresentable, T.RawValue == String {
        guard let rawValue = try? container.decode(String.self, forKey: key) else {
            return defaultValue
        }
        return T(rawValue: rawValue) ?? defaultValue
    }

    private static func positiveOrDefault(_ value: Double, defaultValue: Double) -> Double {
        guard value.isFinite, value > 0 else {
            return defaultValue
        }
        return value
    }

    private static func clamp(_ value: Double, min minimum: Double, max maximum: Double, defaultValue: Double) -> Double {
        guard value.isFinite else {
            return defaultValue
        }
        return Swift.min(Swift.max(value, minimum), maximum)
    }
}

struct ButtonConfig: Codable {
    var gesture: Int?
    var back: Int?
    var forward: Int?

    enum CodingKeys: String, CodingKey {
        case gesture
        case back
        case forward
    }

    init(gesture: Int?, back: Int?, forward: Int?) {
        self.gesture = gesture
        self.back = back
        self.forward = forward
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gesture = ButtonConfig.decodeOptionalInt(container, .gesture)
        back = ButtonConfig.decodeOptionalInt(container, .back)
        forward = ButtonConfig.decodeOptionalInt(container, .forward)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encodeOptional(gesture, forKey: .gesture, into: &container)
        try encodeOptional(back, forKey: .back, into: &container)
        try encodeOptional(forward, forKey: .forward, into: &container)
    }

    private func encodeOptional(_ value: Int?, forKey key: CodingKeys, into container: inout KeyedEncodingContainer<CodingKeys>) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else {
            try container.encodeNil(forKey: key)
        }
    }

    private static func decodeOptionalInt(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        (try? container.decodeIfPresent(Int.self, forKey: key)) ?? nil
    }
}

enum DownAction: String, Codable {
    case ctrlDown
    case disabled
}

enum ActionBackend: String, Codable {
    case cgEvent
    case systemEvents
}

enum ScrollTransformMode: String, Codable {
    case mxMasterOnly
    case global
    case disabled
}

enum SmoothScrollMode: String, Codable {
    case ema
    case dampenSpikes
    case inertia
}

extension JSONEncoder {
    static var mx3Pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

enum MouseEventTapMode {
    case inspect
    case map(GestureMapper)
    case debugScroll(ScrollDebugger)

    var tapOptions: CGEventTapOptions {
        switch self {
        case .inspect:
            return .listenOnly
        case .map, .debugScroll:
            return .defaultTap
        }
    }

    var eventTypes: [CGEventType] {
        switch self {
        case .inspect:
            return [
                .leftMouseDown,
                .leftMouseUp,
                .rightMouseDown,
                .rightMouseUp,
                .otherMouseDown,
                .otherMouseUp,
                .mouseMoved,
                .leftMouseDragged,
                .rightMouseDragged,
                .otherMouseDragged,
                .scrollWheel
            ]
        case .map(let mapper):
            return mapper.eventTypes
        case .debugScroll:
            return [.scrollWheel]
        }
    }
}

final class MouseEventTap {
    private let mode: MouseEventTapMode
    private let logger: DebugLogger?
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var recoveryMessagePrinted = false

    init(mode: MouseEventTapMode, logger: DebugLogger? = nil) throws {
        self.mode = mode
        self.logger = logger
        try createTap()
    }

    func start() {
        guard let runLoopSource else {
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        if let machPort {
            CGEvent.tapEnable(tap: machPort, enable: true)
        }
    }

    func stop() {
        if let machPort {
            CGEvent.tapEnable(tap: machPort, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }

    private func createTap() throws {
        let eventTypes = mode.eventTypes
        guard !eventTypes.isEmpty else {
            throw CLIError("no mouse or scroll events are enabled by config")
        }
        let eventMask = MouseEventTap.eventMask(eventTypes)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: mode.tapOptions,
            eventsOfInterest: eventMask,
            callback: mouseEventTapCallback,
            userInfo: userInfo
        ) else {
            throw CLIError("could not create event tap. Grant Accessibility permission, then retry.")
        }

        machPort = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    }

    private static func eventMask(_ types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << CGEventMask(type.rawValue))
        }
    }

    fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let machPort {
                CGEvent.tapEnable(tap: machPort, enable: true)
            }
            logTapRecovery(type: type)
            return Unmanaged.passUnretained(event)
        }

        switch mode {
        case .inspect:
            EventInspector.printEvent(type: type, event: event)
            return Unmanaged.passUnretained(event)
        case .map(let mapper):
            if mapper.handle(type: type, event: event) {
                return nil
            }
            return Unmanaged.passUnretained(event)
        case .debugScroll(let debugger):
            debugger.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
    }

    private func logTapRecovery(type: CGEventType) {
        if let logger, logger.isEnabled {
            logger.log("event tap disabled type=\(type.label); re-enabled")
            return
        }

        guard !recoveryMessagePrinted else {
            return
        }
        recoveryMessagePrinted = true
        FileHandle.standardError.writeLine("mx3-lite: event tap was disabled; re-enabled")
    }
}

private let mouseEventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let tap = Unmanaged<MouseEventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(proxy: proxy, type: type, event: event)
}

enum EventInspector {
    static func printEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            let clickState = event.getIntegerValueField(.mouseEventClickState)
            print("cg button \(type.label) button=\(button) clickState=\(clickState) loc=\(event.location.compactDescription)")
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let deltaX = event.getIntegerValueField(.mouseEventDeltaX)
            let deltaY = event.getIntegerValueField(.mouseEventDeltaY)
            print("cg move \(type.label) dx=\(deltaX) dy=\(deltaY) loc=\(event.location.compactDescription)")
        case .scrollWheel:
            let axis1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let axis2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let pointAxis1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let pointAxis2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            print("cg scroll delta1=\(axis1) delta2=\(axis2) point1=\(pointAxis1) point2=\(pointAxis2) loc=\(event.location.compactDescription)")
        default:
            break
        }
        fflush(stdout)
    }
}

final class HIDInspector {
    private var manager: IOHIDManager?

    func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        let mouseMatching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse
        ]
        let pointerMatching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Pointer
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, [mouseMatching, pointerMatching] as CFArray)
        IOHIDManagerRegisterInputValueCallback(manager, hidInputValueCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            print("hid open failed: \(openResult). Input Monitoring permission may be required.")
        }
    }

    func stop() {
        guard let manager else {
            return
        }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    fileprivate func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)

        guard usagePage == kHIDPage_Button || usagePage == kHIDPage_GenericDesktop else {
            return
        }

        let intValue = IOHIDValueGetIntegerValue(value)
        let label = HIDInspector.label(usagePage: usagePage, usage: usage)
        let device = IOHIDElementGetDevice(element)
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "unknown"
        print("hid product=\"\(product)\" usagePage=0x\(String(usagePage, radix: 16)) usage=0x\(String(usage, radix: 16)) \(label) value=\(intValue)")
        fflush(stdout)
    }

    private static func label(usagePage: UInt32, usage: UInt32) -> String {
        if usagePage == kHIDPage_Button {
            return "button=\(usage)"
        }

        switch usage {
        case UInt32(kHIDUsage_GD_X):
            return "x"
        case UInt32(kHIDUsage_GD_Y):
            return "y"
        case UInt32(kHIDUsage_GD_Wheel):
            return "wheel"
        default:
            return "usage=\(usage)"
        }
    }
}

private let hidInputValueCallback: IOHIDValueCallback = { context, result, sender, value in
    guard result == kIOReturnSuccess, let context else {
        return
    }

    let inspector = Unmanaged<HIDInspector>.fromOpaque(context).takeUnretainedValue()
    inspector.handle(value: value)
}

struct MXMasterDeviceInfo {
    let product: String
    let vendorID: Int
    let productID: Int?

    var description: String {
        if let productID {
            return "\(product) vendorID=0x\(String(vendorID, radix: 16, uppercase: true)) productID=0x\(String(productID, radix: 16, uppercase: true))"
        }
        return "\(product) vendorID=0x\(String(vendorID, radix: 16, uppercase: true)) productID=unknown"
    }
}

struct MXMasterScrollSignal {
    let timestamp: TimeInterval
    let product: String
    let usagePage: UInt32
    let usage: UInt32
    let value: Int
}

struct MXMasterClassification {
    let isMXMaster: Bool
    let reason: String
    let connectedDevices: [MXMasterDeviceInfo]
    let recentSignal: MXMasterScrollSignal?
    let recentSignalAgeMs: Double?
}

final class MXMasterDeviceRegistry {
    private static let logitechVendorID = 0x046D
    private let logger: DebugLogger
    private let debug: Bool
    private var manager: IOHIDManager?
    private var connectedDevices: [MXMasterDeviceInfo] = []
    private var recentScrollSignal: MXMasterScrollSignal?

    init(logger: DebugLogger, debug: Bool) {
        self.logger = logger
        self.debug = debug
    }

    func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: MXMasterDeviceRegistry.logitechVendorID
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, mxMasterDeviceMatchingCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(manager, mxMasterDeviceRemovalCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterInputValueCallback(manager, mxMasterInputValueCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            logger.log("mx master registry hid open failed: \(openResult). Input Monitoring permission may be required.")
        }

        refreshDevices()
    }

    func stop() {
        guard let manager else {
            return
        }

        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func isMXMasterScrollEvent(_ event: CGEvent) -> Bool {
        guard !connectedDevices.isEmpty else {
            return false
        }

        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        if isContinuous {
            return false
        }

        return true
    }

    func classify(scrollEvent event: CGEvent) -> MXMasterClassification {
        guard !connectedDevices.isEmpty else {
            return MXMasterClassification(
                isMXMaster: false,
                reason: "no connected Logitech MX Master HID device",
                connectedDevices: [],
                recentSignal: recentScrollSignal,
                recentSignalAgeMs: recentSignalAgeMs()
            )
        }

        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        if isContinuous {
            return MXMasterClassification(
                isMXMaster: false,
                reason: "continuous scroll event, likely trackpad",
                connectedDevices: connectedDevices,
                recentSignal: recentScrollSignal,
                recentSignalAgeMs: recentSignalAgeMs()
            )
        }

        if let ageMs = recentSignalAgeMs(), ageMs <= 150 {
            return MXMasterClassification(
                isMXMaster: true,
                reason: "recent MX Master HID wheel signal ageMs=\(String(format: "%.1f", ageMs))",
                connectedDevices: connectedDevices,
                recentSignal: recentScrollSignal,
                recentSignalAgeMs: ageMs
            )
        }

        return MXMasterClassification(
            isMXMaster: true,
            reason: "non-continuous scroll while MX Master is connected; CGEvent has no reliable per-device vendor/product field",
            connectedDevices: connectedDevices,
            recentSignal: recentScrollSignal,
            recentSignalAgeMs: recentSignalAgeMs()
        )
    }

    fileprivate func refreshDevices() {
        guard let manager, let deviceSet = IOHIDManagerCopyDevices(manager) else {
            connectedDevices = []
            return
        }

        let count = CFSetGetCount(deviceSet)
        guard count > 0 else {
            connectedDevices = []
            return
        }

        var values = Array<UnsafeRawPointer?>(repeating: nil, count: count)
        CFSetGetValues(deviceSet, &values)

        connectedDevices = values.compactMap { value in
            guard let value else {
                return nil
            }
            let device = unsafeBitCast(value, to: IOHIDDevice.self)
            return MXMasterDeviceRegistry.mxMasterInfo(for: device)
        }

        if debug {
            let devices = connectedDevices.map(\.description).joined(separator: " | ")
            logger.log("mx master devices: \(devices.isEmpty ? "none" : devices)")
        }
    }

    fileprivate func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)

        guard let deviceInfo = MXMasterDeviceRegistry.mxMasterInfo(for: device) else {
            return
        }

        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        guard MXMasterDeviceRegistry.isScrollUsage(usagePage: usagePage, usage: usage), intValue != 0 else {
            return
        }

        recentScrollSignal = MXMasterScrollSignal(
            timestamp: CFAbsoluteTimeGetCurrent(),
            product: deviceInfo.product,
            usagePage: usagePage,
            usage: usage,
            value: intValue
        )

        if debug {
            logger.log("mx master hid scroll product=\"\(deviceInfo.product)\" usagePage=0x\(String(usagePage, radix: 16)) usage=0x\(String(usage, radix: 16)) value=\(intValue)")
        }
    }

    private func recentSignalAgeMs() -> Double? {
        guard let recentScrollSignal else {
            return nil
        }
        return (CFAbsoluteTimeGetCurrent() - recentScrollSignal.timestamp) * 1000
    }

    private static func mxMasterInfo(for device: IOHIDDevice) -> MXMasterDeviceInfo? {
        guard let vendorID = intProperty(kIOHIDVendorIDKey as CFString, device: device), vendorID == logitechVendorID else {
            return nil
        }

        let product = stringProperty(kIOHIDProductKey as CFString, device: device) ?? "unknown"
        guard product.range(of: "MX Master", options: [.caseInsensitive, .diacriticInsensitive]) != nil else {
            return nil
        }

        return MXMasterDeviceInfo(
            product: product,
            vendorID: vendorID,
            productID: intProperty(kIOHIDProductIDKey as CFString, device: device)
        )
    }

    private static func isScrollUsage(usagePage: UInt32, usage: UInt32) -> Bool {
        if usagePage == kHIDPage_GenericDesktop && usage == UInt32(kHIDUsage_GD_Wheel) {
            return true
        }

        // Consumer AC Pan is commonly used by horizontal wheels.
        if usagePage == 0x0C && usage == 0x0238 {
            return true
        }

        return false
    }

    private static func intProperty(_ key: CFString, device: IOHIDDevice) -> Int? {
        guard let value = IOHIDDeviceGetProperty(device, key) else {
            return nil
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        return nil
    }

    private static func stringProperty(_ key: CFString, device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, key) as? String
    }
}

private let mxMasterDeviceMatchingCallback: IOHIDDeviceCallback = { context, result, sender, device in
    guard result == kIOReturnSuccess, let context else {
        return
    }
    let registry = Unmanaged<MXMasterDeviceRegistry>.fromOpaque(context).takeUnretainedValue()
    registry.refreshDevices()
}

private let mxMasterDeviceRemovalCallback: IOHIDDeviceCallback = { context, result, sender, device in
    guard result == kIOReturnSuccess, let context else {
        return
    }
    let registry = Unmanaged<MXMasterDeviceRegistry>.fromOpaque(context).takeUnretainedValue()
    registry.refreshDevices()
}

private let mxMasterInputValueCallback: IOHIDValueCallback = { context, result, sender, value in
    guard result == kIOReturnSuccess, let context else {
        return
    }
    let registry = Unmanaged<MXMasterDeviceRegistry>.fromOpaque(context).takeUnretainedValue()
    registry.handle(value: value)
}

final class GestureMapper {
    private let config: AppConfig
    private let logger: DebugLogger
    private let liveEventDebug: Bool
    private let mxMasterRegistry: MXMasterDeviceRegistry
    private let scrollTransformer = ScrollTransformer()
    private var gestureActive = false
    private var gestureConsumed = false
    private var startLocation: CGPoint?
    private var lastLocation: CGPoint?
    private var accumulatedDx = 0.0
    private var accumulatedDy = 0.0
    private var accumulatedScrollX = 0.0
    private var accumulatedScrollY = 0.0

    init(config: AppConfig, logger: DebugLogger, liveEventDebug: Bool, mxMasterRegistry: MXMasterDeviceRegistry) {
        self.config = config
        self.logger = logger
        self.liveEventDebug = liveEventDebug
        self.mxMasterRegistry = mxMasterRegistry
    }

    var eventTypes: [CGEventType] {
        if liveEventDebug {
            return [
                .leftMouseDown,
                .leftMouseUp,
                .rightMouseDown,
                .rightMouseUp,
                .otherMouseDown,
                .otherMouseUp,
                .mouseMoved,
                .leftMouseDragged,
                .rightMouseDragged,
                .otherMouseDragged,
                .scrollWheel
            ]
        }

        var types: [CGEventType] = []
        if config.buttons.gesture != nil || config.buttons.back != nil || config.buttons.forward != nil {
            types.append(contentsOf: [.otherMouseDown, .otherMouseUp])
        }

        if config.buttons.gesture != nil {
            types.append(contentsOf: [.mouseMoved, .otherMouseDragged])
        }

        if config.scrollTransformMode != .disabled {
            types.append(.scrollWheel)
        }

        return types
    }

    func handle(type: CGEventType, event: CGEvent) -> Bool {
        let suppressed: Bool
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            suppressed = handleButtonDown(event: event)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            suppressed = handleButtonUp(event: event)
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            suppressed = handleMovement(type: type, event: event)
        case .scrollWheel:
            suppressed = handleScroll(event: event)
        default:
            suppressed = false
        }

        if liveEventDebug {
            logEvent(type: type, event: event, suppressed: suppressed)
        }

        return suppressed
    }

    private func handleButtonDown(event: CGEvent) -> Bool {
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))

        if matches(button, config.buttons.gesture) {
            gestureActive = true
            gestureConsumed = false
            startLocation = event.location
            lastLocation = event.location
            accumulatedDx = 0
            accumulatedDy = 0
            accumulatedScrollX = 0
            accumulatedScrollY = 0
            logger.log("gesture start button=\(button) startLocation=\(event.location.compactDescription)")
            return true
        }

        if gestureActive && matchesSideButton(button) {
            logger.log("side button suppressed during gesture hold button=\(button)")
            return true
        }

        if matches(button, config.buttons.back) {
            logger.log("back button=\(button) -> cmd+[")
            KeySender.sendCommandBracket(left: true)
            return true
        }

        if matches(button, config.buttons.forward) {
            logger.log("forward button=\(button) -> cmd+]")
            KeySender.sendCommandBracket(left: false)
            return true
        }

        return false
    }

    private func handleButtonUp(event: CGEvent) -> Bool {
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))

        if matches(button, config.buttons.gesture) {
            logger.log("gesture end button=\(button) final accumulatedDx=\(format(accumulatedDx)) accumulatedDy=\(format(accumulatedDy)) accumulatedScrollX=\(format(accumulatedScrollX)) accumulatedScrollY=\(format(accumulatedScrollY))")
            resetGesture()
            return true
        }

        if matchesSideButton(button) {
            return true
        }

        return false
    }

    private func handleMovement(type: CGEventType, event: CGEvent) -> Bool {
        guard gestureActive else {
            return false
        }

        let currentLocation = event.location
        let previousLocation = lastLocation ?? currentLocation
        let stepDx = Double(currentLocation.x - previousLocation.x)
        var stepDy = Double(currentLocation.y - previousLocation.y)
        if config.invertY {
            stepDy = -stepDy
        }

        accumulatedDx += stepDx
        accumulatedDy += stepDy
        lastLocation = currentLocation

        logger.log("gesture move type=\(type.label) stepDx=\(format(stepDx)) stepDy=\(format(stepDy)) accumulatedDx=\(format(accumulatedDx)) accumulatedDy=\(format(accumulatedDy))")

        if !gestureConsumed {
            evaluateGesture()
        }

        return true
    }

    private func handleScroll(event: CGEvent) -> Bool {
        guard gestureActive else {
            if let result = scrollTransformer.apply(
                to: event,
                config: config,
                mxMasterRegistry: mxMasterRegistry,
                captureDebug: liveEventDebug
            ) {
                logger.log(result.debugDescription(prefix: "scroll transform"))
            }
            return false
        }

        let axis1 = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        let axis2 = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))

        accumulatedScrollY += axis1
        accumulatedScrollX += axis2

        logger.log("gesture scroll axis1=\(format(axis1)) axis2=\(format(axis2)) accumulatedScrollX=\(format(accumulatedScrollX)) accumulatedScrollY=\(format(accumulatedScrollY))")

        if !gestureConsumed {
            evaluateGesture()
        }

        return false
    }

    private func evaluateGesture() {
        guard !gestureConsumed else {
            return
        }

        let threshold = max(config.threshold, 1)

        if accumulatedDx < -threshold {
            triggerHorizontalGesture(.left, source: "pointer")
            return
        }
        if accumulatedDx > threshold {
            triggerHorizontalGesture(.right, source: "pointer")
            return
        }
        if accumulatedDy < -threshold {
            triggerGesture(.up, source: "pointer")
            return
        }
        if accumulatedDy > threshold {
            triggerDown(source: "pointer")
            return
        }

        if accumulatedScrollX < -threshold {
            triggerHorizontalGesture(.left, source: "scroll")
            return
        }
        if accumulatedScrollX > threshold {
            triggerHorizontalGesture(.right, source: "scroll")
            return
        }
        if accumulatedScrollY < -threshold {
            triggerGesture(.up, source: "scroll")
            return
        }
        if accumulatedScrollY > threshold {
            triggerDown(source: "scroll")
        }
    }

    private func resetGesture() {
        gestureActive = false
        gestureConsumed = false
        startLocation = nil
        lastLocation = nil
        accumulatedDx = 0
        accumulatedDy = 0
        accumulatedScrollX = 0
        accumulatedScrollY = 0
    }

    private func triggerGesture(_ direction: ArrowDirection, source: String) {
        gestureConsumed = true
        logger.log("gesture \(direction.label) source=\(source) accumulatedDx=\(format(accumulatedDx)) accumulatedDy=\(format(accumulatedDy)) accumulatedScrollX=\(format(accumulatedScrollX)) accumulatedScrollY=\(format(accumulatedScrollY)) -> ctrl+\(direction.label)")
        KeySender.sendControlArrow(direction, backend: config.actionBackend, logger: logger)
    }

    private func triggerHorizontalGesture(_ physicalDirection: ArrowDirection, source: String) {
        let actionDirection = horizontalActionDirection(for: physicalDirection)
        gestureConsumed = true
        logger.log("gesture physical-\(physicalDirection.label) source=\(source) invertDesktopGestureDirection=\(config.invertDesktopGestureDirection) action=\(actionDirection.label) accumulatedDx=\(format(accumulatedDx)) accumulatedDy=\(format(accumulatedDy)) accumulatedScrollX=\(format(accumulatedScrollX)) accumulatedScrollY=\(format(accumulatedScrollY)) -> ctrl+\(actionDirection.label)")
        KeySender.sendControlArrow(actionDirection, backend: config.actionBackend, logger: logger)
    }

    private func horizontalActionDirection(for physicalDirection: ArrowDirection) -> ArrowDirection {
        guard config.invertDesktopGestureDirection else {
            return physicalDirection
        }

        switch physicalDirection {
        case .left:
            return .right
        case .right:
            return .left
        case .up, .down:
            return physicalDirection
        }
    }

    private func triggerDown(source: String) {
        switch config.downAction {
        case .ctrlDown:
            triggerGesture(.down, source: source)
        case .disabled:
            gestureConsumed = true
            logger.log("gesture down source=\(source) disabled accumulatedDx=\(format(accumulatedDx)) accumulatedDy=\(format(accumulatedDy)) accumulatedScrollX=\(format(accumulatedScrollX)) accumulatedScrollY=\(format(accumulatedScrollY))")
        }
    }

    private func logEvent(type: CGEventType, event: CGEvent, suppressed: Bool) {
        var fields = [
            "event type=\(type.label)",
            "locationX=\(format(Double(event.location.x)))",
            "locationY=\(format(Double(event.location.y)))",
            "gestureActive=\(gestureActive)",
            "gestureConsumed=\(gestureConsumed)",
            "suppressed=\(suppressed)"
        ]

        if type.isMouseButtonEvent {
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            fields.append("button=\(button)")
        }

        if type.isMouseMoveEvent {
            let deltaX = event.getIntegerValueField(.mouseEventDeltaX)
            let deltaY = event.getIntegerValueField(.mouseEventDeltaY)
            fields.append("deltaX=\(deltaX)")
            fields.append("deltaY=\(deltaY)")
            fields.append("accumulatedDx=\(format(accumulatedDx))")
            fields.append("accumulatedDy=\(format(accumulatedDy))")
        }

        if type == .scrollWheel {
            let axis1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let axis2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let pointAxis1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let pointAxis2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            fields.append("scrollAxis1=\(axis1)")
            fields.append("scrollAxis2=\(axis2)")
            fields.append("scrollPointAxis1=\(pointAxis1)")
            fields.append("scrollPointAxis2=\(pointAxis2)")
            fields.append("accumulatedScrollX=\(format(accumulatedScrollX))")
            fields.append("accumulatedScrollY=\(format(accumulatedScrollY))")
        }

        logger.log(fields.joined(separator: " "))
    }

    private func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func matches(_ button: Int, _ configuredButton: Int?) -> Bool {
        guard let configuredButton else {
            return false
        }
        return button == configuredButton
    }

    private func matchesSideButton(_ button: Int) -> Bool {
        matches(button, config.buttons.back) || matches(button, config.buttons.forward)
    }
}

final class ScrollDebugger {
    private let config: AppConfig
    private let logger: DebugLogger
    private let mxMasterRegistry: MXMasterDeviceRegistry
    private let scrollTransformer = ScrollTransformer()

    init(config: AppConfig, logger: DebugLogger, mxMasterRegistry: MXMasterDeviceRegistry) {
        self.config = config
        self.logger = logger
        self.mxMasterRegistry = mxMasterRegistry
    }

    func handle(type: CGEventType, event: CGEvent) {
        guard type == .scrollWheel else {
            return
        }

        if let result = scrollTransformer.apply(to: event, config: config, mxMasterRegistry: mxMasterRegistry, captureDebug: true) {
            logger.log(result.debugDescription(prefix: "debug-scroll"))
        }
    }
}

struct ScrollTransformResult {
    let rawAxis1: Int64
    let rawAxis2: Int64
    let afterInversionAxis1: Double
    let afterInversionAxis2: Double
    let afterMultiplierAxis1: Double
    let afterMultiplierAxis2: Double
    let afterSmoothingAxis1: Double
    let afterSmoothingAxis2: Double
    let afterClampAxis1: Double
    let afterClampAxis2: Double
    let finalAxis1: Int64
    let finalAxis2: Int64
    let sourceStateID: Int64
    let sourceUnixProcessID: Int64
    let sourceUserData: Int64
    let sourceUserID: Int64
    let sourceGroupID: Int64
    let scrollIsContinuous: Int64
    let scrollPhase: Int64
    let momentumPhase: Int64
    let scrollCount: Int64
    let instantMouser: Int64
    let invertVerticalScroll: Bool
    let invertHorizontalScroll: Bool
    let scrollMultiplier: Double
    let smoothScroll: Bool
    let smoothScrollMode: SmoothScrollMode
    let smoothScrollFactor: Double
    let scrollDeadzone: Double
    let maxScrollStep: Double
    let scrollAcceleration: Double
    let freeSpinDamping: Double
    let ratchetStepMultiplier: Double
    let allowGlobalScrollTransform: Bool
    let scrollTransformMode: ScrollTransformMode
    let classifiedAsMXMaster: Bool
    let classificationReason: String
    let connectedMXMasterDevices: [MXMasterDeviceInfo]
    let recentMXMasterSignal: MXMasterScrollSignal?
    let recentMXMasterSignalAgeMs: Double?
    let returnedModified: Bool

    func debugDescription(prefix: String) -> String {
        [
            prefix,
            "rawDeltaAxis1=\(rawAxis1)",
            "rawDeltaAxis2=\(rawAxis2)",
            "afterInversionAxis1=\(format(afterInversionAxis1))",
            "afterInversionAxis2=\(format(afterInversionAxis2))",
            "afterMultiplierAxis1=\(format(afterMultiplierAxis1))",
            "afterMultiplierAxis2=\(format(afterMultiplierAxis2))",
            "afterSmoothingAxis1=\(format(afterSmoothingAxis1))",
            "afterSmoothingAxis2=\(format(afterSmoothingAxis2))",
            "afterMaxStepClampAxis1=\(format(afterClampAxis1))",
            "afterMaxStepClampAxis2=\(format(afterClampAxis2))",
            "finalAxis1=\(finalAxis1)",
            "finalAxis2=\(finalAxis2)",
            "sourceStateID=\(sourceStateID)",
            "sourceUnixProcessID=\(sourceUnixProcessID)",
            "sourceUserData=\(sourceUserData)",
            "sourceUserID=\(sourceUserID)",
            "sourceGroupID=\(sourceGroupID)",
            "scrollIsContinuous=\(scrollIsContinuous)",
            "scrollPhase=\(scrollPhase)",
            "momentumPhase=\(momentumPhase)",
            "scrollCount=\(scrollCount)",
            "instantMouser=\(instantMouser)",
            "invertVerticalScroll=\(invertVerticalScroll)",
            "invertHorizontalScroll=\(invertHorizontalScroll)",
            "scrollMultiplier=\(String(format: "%.3f", scrollMultiplier))",
            "smoothScroll=\(smoothScroll)",
            "smoothScrollMode=\(smoothScrollMode.rawValue)",
            "smoothScrollFactor=\(String(format: "%.3f", smoothScrollFactor))",
            "scrollDeadzone=\(String(format: "%.3f", scrollDeadzone))",
            "maxScrollStep=\(String(format: "%.3f", maxScrollStep))",
            "scrollAcceleration=\(String(format: "%.3f", scrollAcceleration))",
            "freeSpinDamping=\(String(format: "%.3f", freeSpinDamping))",
            "ratchetStepMultiplier=\(String(format: "%.3f", ratchetStepMultiplier))",
            "allowGlobalScrollTransform=\(allowGlobalScrollTransform)",
            "scrollTransformMode=\(scrollTransformMode.rawValue)",
            "classifiedAsMXMaster=\(classifiedAsMXMaster)",
            "classificationReason=\"\(classificationReason)\"",
            "connectedMXMasterDevices=\"\(connectedMXMasterDevices.map(\.description).joined(separator: " | "))\"",
            "recentMXMasterSignal=\"\(recentSignalDescription())\"",
            "returned=\(returnedModified ? "modified" : "passedThroughUnchanged")"
        ].joined(separator: " ")
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private func recentSignalDescription() -> String {
        guard let recentMXMasterSignal else {
            return "none"
        }

        let age = recentMXMasterSignalAgeMs.map { String(format: "%.1fms", $0) } ?? "unknownAge"
        return "\(recentMXMasterSignal.product) usagePage=0x\(String(recentMXMasterSignal.usagePage, radix: 16)) usage=0x\(String(recentMXMasterSignal.usage, radix: 16)) value=\(recentMXMasterSignal.value) age=\(age)"
    }
}

final class ScrollTransformer {
    private var previousAxis1 = 0.0
    private var previousAxis2 = 0.0
    private var inertiaCarryAxis1 = 0.0
    private var inertiaCarryAxis2 = 0.0

    @discardableResult
    func apply(
        to event: CGEvent,
        config: AppConfig,
        mxMasterRegistry: MXMasterDeviceRegistry,
        captureDebug: Bool
    ) -> ScrollTransformResult? {
        let rawAxis1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let rawAxis2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let classification = captureDebug ? mxMasterRegistry.classify(scrollEvent: event) : nil
        let shouldTransform: Bool
        let passThroughReason: String

        switch config.scrollTransformMode {
        case .disabled:
            shouldTransform = false
            passThroughReason = "scrollTransformMode disabled"
        case .global:
            shouldTransform = true
            passThroughReason = "global mode"
        case .mxMasterOnly:
            shouldTransform = captureDebug ? (classification?.isMXMaster ?? false) : mxMasterRegistry.isMXMasterScrollEvent(event)
            passThroughReason = classification?.reason ?? "mxMasterOnly"
        }

        guard shouldTransform else {
            guard captureDebug, let classification else {
                return nil
            }
            let unchangedAxis1 = Double(rawAxis1)
            let unchangedAxis2 = Double(rawAxis2)
            return makeResult(
                event: event,
                rawAxis1: rawAxis1,
                rawAxis2: rawAxis2,
                afterInversionAxis1: unchangedAxis1,
                afterInversionAxis2: unchangedAxis2,
                afterMultiplierAxis1: unchangedAxis1,
                afterMultiplierAxis2: unchangedAxis2,
                afterSmoothingAxis1: unchangedAxis1,
                afterSmoothingAxis2: unchangedAxis2,
                afterClampAxis1: unchangedAxis1,
                afterClampAxis2: unchangedAxis2,
                finalAxis1: rawAxis1,
                finalAxis2: rawAxis2,
                config: config,
                classification: classification,
                classificationReasonOverride: passThroughReason,
                returnedModified: false
            )
        }

        var afterInversionAxis1 = Double(rawAxis1)
        var afterInversionAxis2 = Double(rawAxis2)

        if config.invertVerticalScroll {
            afterInversionAxis1 *= -1
        }

        if config.invertHorizontalScroll {
            afterInversionAxis2 *= -1
        }

        let afterMultiplierAxis1 = applyAmplitudeControls(to: afterInversionAxis1, config: config)
        let afterMultiplierAxis2 = applyAmplitudeControls(to: afterInversionAxis2, config: config)

        let smoothingInputAxis1 = applyDeadzone(to: afterMultiplierAxis1, deadzone: config.scrollDeadzone)
        let smoothingInputAxis2 = applyDeadzone(to: afterMultiplierAxis2, deadzone: config.scrollDeadzone)
        var afterSmoothingAxis1 = smoothingInputAxis1
        var afterSmoothingAxis2 = smoothingInputAxis2
        if config.smoothScroll {
            (afterSmoothingAxis1, afterSmoothingAxis2) = applySmoothing(
                axis1: smoothingInputAxis1,
                axis2: smoothingInputAxis2,
                config: config
            )
        } else {
            previousAxis1 = smoothingInputAxis1
            previousAxis2 = smoothingInputAxis2
            inertiaCarryAxis1 = 0
            inertiaCarryAxis2 = 0
        }

        let afterClampAxis1 = clampStep(afterSmoothingAxis1, maxStep: config.maxScrollStep)
        let afterClampAxis2 = clampStep(afterSmoothingAxis2, maxStep: config.maxScrollStep)
        let roundedAxis1 = Int64(afterClampAxis1.rounded())
        let roundedAxis2 = Int64(afterClampAxis2.rounded())

        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: roundedAxis1)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: roundedAxis2)

        guard captureDebug else {
            return nil
        }

        return makeResult(
            event: event,
            rawAxis1: rawAxis1,
            rawAxis2: rawAxis2,
            afterInversionAxis1: afterInversionAxis1,
            afterInversionAxis2: afterInversionAxis2,
            afterMultiplierAxis1: afterMultiplierAxis1,
            afterMultiplierAxis2: afterMultiplierAxis2,
            afterSmoothingAxis1: afterSmoothingAxis1,
            afterSmoothingAxis2: afterSmoothingAxis2,
            afterClampAxis1: afterClampAxis1,
            afterClampAxis2: afterClampAxis2,
            finalAxis1: roundedAxis1,
            finalAxis2: roundedAxis2,
            config: config,
            classification: classification ?? mxMasterRegistry.classify(scrollEvent: event),
            classificationReasonOverride: nil,
            returnedModified: true
        )
    }

    private func applyAmplitudeControls(to value: Double, config: AppConfig) -> Double {
        var adjusted = value * finiteOrDefault(config.scrollMultiplier, defaultValue: 1)
        adjusted *= finiteOrDefault(config.ratchetStepMultiplier, defaultValue: 1)

        let acceleration = finiteOrDefault(config.scrollAcceleration, defaultValue: 1)
        guard acceleration > 0, acceleration != 1, adjusted != 0 else {
            return adjusted
        }

        let magnitude = pow(abs(adjusted), acceleration)
        return adjusted < 0 ? -magnitude : magnitude
    }

    private func applySmoothing(axis1: Double, axis2: Double, config: AppConfig) -> (Double, Double) {
        switch config.smoothScrollMode {
        case .ema:
            let factor = clamp(finiteOrDefault(config.smoothScrollFactor, defaultValue: 0.35), min: 0, max: 0.95)
            previousAxis1 = factor * previousAxis1 + (1 - factor) * axis1
            previousAxis2 = factor * previousAxis2 + (1 - factor) * axis2
            boundSmoothingState(config: config)
            return (previousAxis1, previousAxis2)
        case .dampenSpikes:
            let axis1 = dampenSpike(axis1, maxStep: config.maxScrollStep, damping: config.freeSpinDamping)
            let axis2 = dampenSpike(axis2, maxStep: config.maxScrollStep, damping: config.freeSpinDamping)
            previousAxis1 = axis1
            previousAxis2 = axis2
            boundSmoothingState(config: config)
            return (axis1, axis2)
        case .inertia:
            let releaseFactor = clamp(1 - finiteOrDefault(config.smoothScrollFactor, defaultValue: 0.35), min: 0.1, max: 1)
            inertiaCarryAxis1 += axis1
            inertiaCarryAxis2 += axis2
            boundSmoothingState(config: config)
            let outputAxis1 = inertiaCarryAxis1 * releaseFactor
            let outputAxis2 = inertiaCarryAxis2 * releaseFactor
            inertiaCarryAxis1 -= outputAxis1
            inertiaCarryAxis2 -= outputAxis2
            previousAxis1 = outputAxis1
            previousAxis2 = outputAxis2
            boundSmoothingState(config: config)
            return (outputAxis1, outputAxis2)
        }
    }

    private func boundSmoothingState(config: AppConfig) {
        let maxStep = max(1, finiteOrDefault(config.maxScrollStep, defaultValue: 8))
        let limit = max(64, maxStep * 4)
        previousAxis1 = clamp(previousAxis1, min: -limit, max: limit)
        previousAxis2 = clamp(previousAxis2, min: -limit, max: limit)
        inertiaCarryAxis1 = clamp(inertiaCarryAxis1, min: -limit, max: limit)
        inertiaCarryAxis2 = clamp(inertiaCarryAxis2, min: -limit, max: limit)
    }

    private func applyDeadzone(to value: Double, deadzone: Double) -> Double {
        let deadzone = max(0, finiteOrDefault(deadzone, defaultValue: 0))
        guard deadzone > 0 else {
            return value
        }
        return abs(value) <= deadzone ? 0 : value
    }

    private func dampenSpike(_ value: Double, maxStep: Double, damping: Double) -> Double {
        let maxStep = max(0, finiteOrDefault(maxStep, defaultValue: 8))
        guard maxStep > 0, abs(value) > maxStep else {
            return value
        }

        let damping = clamp(finiteOrDefault(damping, defaultValue: 0.75), min: 0, max: 1)
        let dampedMagnitude = maxStep * damping
        return value < 0 ? -dampedMagnitude : dampedMagnitude
    }

    private func clampStep(_ value: Double, maxStep: Double) -> Double {
        let maxStep = max(0, finiteOrDefault(maxStep, defaultValue: 8))
        guard maxStep > 0 else {
            return value
        }
        return clamp(value, min: -maxStep, max: maxStep)
    }

    private func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
        Swift.min(Swift.max(value, minimum), maximum)
    }

    private func finiteOrDefault(_ value: Double, defaultValue: Double) -> Double {
        value.isFinite ? value : defaultValue
    }

    private func makeResult(
        event: CGEvent,
        rawAxis1: Int64,
        rawAxis2: Int64,
        afterInversionAxis1: Double,
        afterInversionAxis2: Double,
        afterMultiplierAxis1: Double,
        afterMultiplierAxis2: Double,
        afterSmoothingAxis1: Double,
        afterSmoothingAxis2: Double,
        afterClampAxis1: Double,
        afterClampAxis2: Double,
        finalAxis1: Int64,
        finalAxis2: Int64,
        config: AppConfig,
        classification: MXMasterClassification,
        classificationReasonOverride: String?,
        returnedModified: Bool
    ) -> ScrollTransformResult {
        ScrollTransformResult(
            rawAxis1: rawAxis1,
            rawAxis2: rawAxis2,
            afterInversionAxis1: afterInversionAxis1,
            afterInversionAxis2: afterInversionAxis2,
            afterMultiplierAxis1: afterMultiplierAxis1,
            afterMultiplierAxis2: afterMultiplierAxis2,
            afterSmoothingAxis1: afterSmoothingAxis1,
            afterSmoothingAxis2: afterSmoothingAxis2,
            afterClampAxis1: afterClampAxis1,
            afterClampAxis2: afterClampAxis2,
            finalAxis1: finalAxis1,
            finalAxis2: finalAxis2,
            sourceStateID: event.getIntegerValueField(.eventSourceStateID),
            sourceUnixProcessID: event.getIntegerValueField(.eventSourceUnixProcessID),
            sourceUserData: event.getIntegerValueField(.eventSourceUserData),
            sourceUserID: event.getIntegerValueField(.eventSourceUserID),
            sourceGroupID: event.getIntegerValueField(.eventSourceGroupID),
            scrollIsContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous),
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            scrollCount: event.getIntegerValueField(.scrollWheelEventScrollCount),
            instantMouser: event.getIntegerValueField(.scrollWheelEventInstantMouser),
            invertVerticalScroll: config.invertVerticalScroll,
            invertHorizontalScroll: config.invertHorizontalScroll,
            scrollMultiplier: config.scrollMultiplier,
            smoothScroll: config.smoothScroll,
            smoothScrollMode: config.smoothScrollMode,
            smoothScrollFactor: config.smoothScrollFactor,
            scrollDeadzone: config.scrollDeadzone,
            maxScrollStep: config.maxScrollStep,
            scrollAcceleration: config.scrollAcceleration,
            freeSpinDamping: config.freeSpinDamping,
            ratchetStepMultiplier: config.ratchetStepMultiplier,
            allowGlobalScrollTransform: config.allowGlobalScrollTransform,
            scrollTransformMode: config.scrollTransformMode,
            classifiedAsMXMaster: classification.isMXMaster,
            classificationReason: classificationReasonOverride ?? classification.reason,
            connectedMXMasterDevices: classification.connectedDevices,
            recentMXMasterSignal: classification.recentSignal,
            recentMXMasterSignalAgeMs: classification.recentSignalAgeMs,
            returnedModified: returnedModified
        )
    }
}

enum ArrowDirection {
    case left
    case right
    case up
    case down

    var label: String {
        switch self {
        case .left:
            return "left"
        case .right:
            return "right"
        case .up:
            return "up"
        case .down:
            return "down"
        }
    }
}

enum KeySender {
    private static let leftArrowKey: CGKeyCode = 0x7B
    private static let rightArrowKey: CGKeyCode = 0x7C
    private static let downArrowKey: CGKeyCode = 0x7D
    private static let upArrowKey: CGKeyCode = 0x7E
    private static let leftBracketKey: CGKeyCode = 0x21
    private static let rightBracketKey: CGKeyCode = 0x1E

    static func sendControlArrow(
        _ direction: ArrowDirection,
        backend: ActionBackend,
        logger: DebugLogger,
        waitForSystemEvents: Bool = false
    ) {
        let key: CGKeyCode
        switch direction {
        case .left:
            key = leftArrowKey
        case .right:
            key = rightArrowKey
        case .up:
            key = upArrowKey
        case .down:
            key = downArrowKey
        }

        switch backend {
        case .cgEvent:
            postControlArrow(key, label: direction.label, logger: logger)
        case .systemEvents:
            postSystemEventsControlArrow(direction, logger: logger, wait: waitForSystemEvents)
        }
    }

    static func sendCommandBracket(left: Bool) {
        sendKey(left ? leftBracketKey : rightBracketKey, flags: .maskCommand)
    }

    private static func postControlArrow(_ key: CGKeyCode, label: String, logger: DebugLogger) {
        logger.log("posting HID ctrl+\(label) keyCode=\(hexKeyCode(key))")

        let source = CGEventSource(stateID: .hidSystemState)

        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        down?.flags = [.maskControl]
        down?.post(tap: .cghidEventTap)

        usleep(10_000)

        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        up?.flags = [.maskControl]
        up?.post(tap: .cghidEventTap)
    }

    private static func sendKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else {
            return
        }

        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        usleep(10_000)
        up.post(tap: .cghidEventTap)
    }

    private static func postSystemEventsControlArrow(_ direction: ArrowDirection, logger: DebugLogger, wait: Bool) {
        let keyCode: Int
        switch direction {
        case .left:
            keyCode = 123
        case .right:
            keyCode = 124
        case .up:
            keyCode = 126
        case .down:
            keyCode = 125
        }

        logger.log("posting System Events ctrl+\(direction.label) keyCode=\(keyCode)")

        let operation = {
            runSystemEventsKeyCode(keyCode, logger: logger)
        }

        if wait {
            operation()
        } else {
            DispatchQueue.global(qos: .userInitiated).async(execute: operation)
        }
    }

    private static func runSystemEventsKeyCode(_ keyCode: Int, logger: DebugLogger) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "tell application \"System Events\" to key code \(keyCode) using control down"
        ]
        process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.log("System Events backend failed: \(error)")
        }
    }

    private static func hexKeyCode(_ key: CGKeyCode) -> String {
        "0x" + String(key, radix: 16, uppercase: true)
    }
}

final class DebugLogger {
    let isEnabled: Bool

    init(enabled: Bool) {
        self.isEnabled = enabled
    }

    func log(_ message: @autoclosure () -> String) {
        guard isEnabled else {
            return
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] \(message())")
        fflush(stdout)
    }
}

final class SignalController {
    private var sources: [DispatchSourceSignal] = []

    func start(_ handler: @escaping () -> Void) {
        [SIGINT, SIGTERM].forEach { signalNumber in
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler(handler: handler)
            source.resume()
            sources.append(source)
        }
    }
}

struct CLIError: Error {
    let message: String
    let exitCode: Int

    init(_ message: String, exitCode: Int = 1) {
        self.message = message
        self.exitCode = exitCode
    }
}

extension Array where Element == String {
    mutating func removeFlag(_ flag: String) -> Bool {
        guard let index = firstIndex(of: flag) else {
            return false
        }
        remove(at: index)
        return true
    }
}

extension FileHandle {
    func writeLine(_ line: String) {
        if let data = (line + "\n").data(using: .utf8) {
            write(data)
        }
    }
}

extension CGEventType {
    var label: String {
        switch self {
        case .leftMouseDown:
            return "leftMouseDown"
        case .leftMouseUp:
            return "leftMouseUp"
        case .rightMouseDown:
            return "rightMouseDown"
        case .rightMouseUp:
            return "rightMouseUp"
        case .otherMouseDown:
            return "otherMouseDown"
        case .otherMouseUp:
            return "otherMouseUp"
        case .mouseMoved:
            return "mouseMoved"
        case .leftMouseDragged:
            return "leftMouseDragged"
        case .rightMouseDragged:
            return "rightMouseDragged"
        case .otherMouseDragged:
            return "otherMouseDragged"
        case .scrollWheel:
            return "scrollWheel"
        default:
            return "type-\(rawValue)"
        }
    }

    var isMouseButtonEvent: Bool {
        switch self {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            return true
        default:
            return false
        }
    }

    var isMouseMoveEvent: Bool {
        switch self {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return true
        default:
            return false
        }
    }
}

extension CGPoint {
    var compactDescription: String {
        "(\(Int(x)),\(Int(y)))"
    }
}
