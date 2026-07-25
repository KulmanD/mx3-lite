import Foundation

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
