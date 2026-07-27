import Darwin
import Foundation

struct CLI {
    private let paths = AppPaths()

    private var lifecycle: WorkerLifecycle {
        WorkerLifecycle(paths: paths)
    }

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
        case "--doctor", "doctor":
            let verbose = args.removeFlag("--verbose")
            guard args.isEmpty else {
                throw CLIError("doctor accepts only --verbose", exitCode: 64)
            }
            try doctor(verbose: verbose)
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
          mx3-lite doctor [--verbose]
                                  Run read-only installation and readiness checks
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

        try lifecycle.withExclusiveLock {
            try startLocked(debug: debug)
        }
    }

    private func startLocked(debug: Bool) throws {
        if let worker = try lifecycle.liveWorker() {
            print("mx3-lite is already running (pid \(worker.pid))")
            return
        }

        guard let executableURL = Bundle.main.executableURL else {
            throw CLIError("could not resolve executable path")
        }

        let resolvedExecutableURL = executableURL.resolvingSymlinksInPath()

        let process = Process()
        process.executableURL = resolvedExecutableURL
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

        guard
            let identity = lifecycle.inspectProcess(pid: process.processIdentifier),
            identity.executablePath == lifecycle.expectedExecutablePath
        else {
            process.terminate()
            throw CLIError("could not verify the new worker process identity")
        }

        do {
            try lifecycle.writeMetadata(identity)
        } catch {
            process.terminate()
            throw error
        }

        usleep(150_000)
        if !lifecycle.isAlive(identity) {
            lifecycle.removeMetadata(ifOwnedBy: identity)
            throw CLIError("worker exited immediately. Check macOS permissions or run mx3-lite run --debug.")
        }

        print("mx3-lite started (pid \(process.processIdentifier))")
        if debug {
            print("debug log: \(paths.logFile.path)")
        }
    }

    private func stop() throws {
        try paths.ensureDirectories()

        try lifecycle.withExclusiveLock {
            try stopLocked()
        }
    }

    private func stopLocked() throws {
        guard let worker = try lifecycle.liveWorker() else {
            print("mx3-lite is stopped")
            return
        }

        try lifecycle.send(signal: SIGTERM, to: worker)

        let deadline = Date().addingTimeInterval(2.0)
        while lifecycle.isAlive(worker), Date() < deadline {
            usleep(50_000)
        }

        if lifecycle.isAlive(worker) {
            try lifecycle.send(signal: SIGKILL, to: worker)
            let killDeadline = Date().addingTimeInterval(0.5)
            while lifecycle.isAlive(worker), Date() < killDeadline {
                usleep(25_000)
            }
        }

        guard !lifecycle.isAlive(worker) else {
            throw CLIError("worker pid \(worker.pid) did not exit")
        }

        lifecycle.removeMetadata(ifOwnedBy: worker)
        print("mx3-lite stopped")
    }

    private func toggle(debug: Bool) throws {
        try paths.ensureDirectories()

        try lifecycle.withExclusiveLock {
            if try lifecycle.liveWorker() != nil {
                try stopLocked()
            } else {
                try startLocked(debug: debug)
            }
        }
    }

    private func status() throws {
        try paths.ensureDirectories()

        try lifecycle.withExclusiveLock {
            if let worker = try lifecycle.liveWorker() {
                print("mx3-lite is running (pid \(worker.pid))")
            } else {
                print("mx3-lite is stopped")
            }
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

    private func doctor(verbose: Bool) throws {
        let report = try DoctorRunner(paths: paths).report()
        print(report.rendered(verbose: verbose))
        if report.exitCode != 0 {
            throw CLIExit(exitCode: Int32(report.exitCode))
        }
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
        let eventTap = try MouseEventTap(mode: .debugScroll(debugger))

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
        let eventTap = try MouseEventTap(
            mode: .map(mapper),
            eventTypes: debug ? nil : mapper.primaryEventTypes
        )
        let movementEventTap = try makeMovementEventTap(for: mapper, shouldCreate: !debug)

        let signalController = SignalController()
        signalController.start {
            logger.log("foreground worker stopping")
            eventTap.stop()
            movementEventTap?.stop()
            mxMasterRegistry.stop()
            CFRunLoopStop(CFRunLoopGetMain())
        }

        movementEventTap?.start(enabled: false)
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
        let workerIdentity = try lifecycle.currentProcessIdentity()
        try lifecycle.writeMetadata(workerIdentity)
        defer {
            lifecycle.removeMetadata(ifOwnedBy: workerIdentity)
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
        let eventTap = try MouseEventTap(mode: .map(mapper), eventTypes: mapper.primaryEventTypes)
        let movementEventTap = try makeMovementEventTap(for: mapper, shouldCreate: true)

        let signalController = SignalController()
        signalController.start {
            logger.log("worker stopping")
            eventTap.stop()
            movementEventTap?.stop()
            mxMasterRegistry.stop()
            lifecycle.removeMetadata(ifOwnedBy: workerIdentity)
            CFRunLoopStop(CFRunLoopGetMain())
        }

        movementEventTap?.start(enabled: false)
        eventTap.start()
        CFRunLoopRun()
    }

    private func makeMovementEventTap(
        for mapper: GestureMapper,
        shouldCreate: Bool
    ) throws -> MouseEventTap? {
        guard shouldCreate, !mapper.movementEventTypes.isEmpty else {
            return nil
        }

        let movementEventTap = try MouseEventTap(
            mode: .map(mapper),
            eventTypes: mapper.movementEventTypes
        )
        mapper.onGestureActivityChanged = { [weak movementEventTap] isActive in
            movementEventTap?.setEnabled(isActive)
        }
        return movementEventTap
    }

    private func currentLivePID() throws -> pid_t? {
        try lifecycle.liveWorker().map { pid_t($0.pid) }
    }
}
