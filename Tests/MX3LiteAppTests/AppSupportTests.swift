import Foundation
import MX3AppSupport
import XCTest
@testable import MX3Lite

final class AppSupportTests: XCTestCase {
    func testSettingsStoreCreatesAndRoundTripsNormalizedConfig() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let store = AppSettingsStore(homeDirectory: home)

        let initial = try store.loadOrCreate()
        XCTAssertTrue(initial.created)
        XCTAssertEqual(initial.settings, .default)

        var changed = initial.settings
        changed.threshold = 310
        changed.scrollMultiplier = 99
        try store.save(changed)

        let reloaded = try store.loadOrCreate()
        XCTAssertFalse(reloaded.created)
        XCTAssertEqual(reloaded.settings.threshold, 310)
        XCTAssertEqual(reloaded.settings.scrollMultiplier, 5)
    }

    func testAppSettingsRemainCompatibleWithCLIConfigSchema() throws {
        let encoder = JSONEncoder()
        let appData = try encoder.encode(AppSettings.default)
        let cliConfig = try JSONDecoder().decode(AppConfig.self, from: appData)
        XCTAssertEqual(cliConfig.buttons.gesture, 5)
        XCTAssertEqual(cliConfig.actionBackend, .systemEvents)
        XCTAssertEqual(cliConfig.scrollTransformMode, .mxMasterOnly)

        let cliData = try encoder.encode(AppConfig.default)
        let appConfig = try JSONDecoder().decode(AppSettings.self, from: cliData)
        XCTAssertEqual(appConfig.buttons, AppButtonSettings(gesture: 5, back: 3, forward: 4))
        XCTAssertEqual(appConfig.actionBackend, .systemEvents)
        XCTAssertEqual(appConfig.scrollTransformMode, .mxMasterOnly)
        XCTAssertTrue(try jsonObject(appData).isEqual(jsonObject(cliData)))
    }

    func testNeutralDefaultsSourceMatchesCompiledDefaults() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let defaultsData = try Data(contentsOf: projectRoot.appendingPathComponent("config/defaults.json"))
        let appSettings = try JSONDecoder().decode(AppSettings.self, from: defaultsData)
        let cliSettings = try JSONDecoder().decode(AppConfig.self, from: defaultsData)
        let encoder = JSONEncoder()

        XCTAssertEqual(appSettings, .default)
        XCTAssertTrue(try jsonObject(encoder.encode(cliSettings)).isEqual(jsonObject(encoder.encode(AppConfig.default))))
    }

    func testOlderConfigGetsTopLevelDefaultsWithoutInventingMissingButtons() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let store = AppSettingsStore(homeDirectory: home)
        try FileManager.default.createDirectory(
            at: store.configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"threshold":300,"buttons":{"gesture":5},"actionBackend":"unknown"}"#.utf8)
            .write(to: store.configURL)

        let loaded = try store.loadOrCreate().settings
        XCTAssertEqual(loaded.threshold, 300)
        XCTAssertEqual(loaded.buttons.gesture, 5)
        XCTAssertNil(loaded.buttons.back)
        XCTAssertNil(loaded.buttons.forward)
        XCTAssertEqual(loaded.actionBackend, .systemEvents)
        XCTAssertEqual(loaded.scrollTransformMode, .mxMasterOnly)
    }

    func testWorkerStatusParserHandlesRunningStoppedAndUnknownOutput() {
        XCTAssertEqual(
            WorkerStatusParser.parse(HelperCommandResult(
                exitCode: 0,
                standardOutput: "mx3-lite is running (pid 412)\n",
                standardError: ""
            )),
            .running(pid: 412)
        )
        XCTAssertEqual(
            WorkerStatusParser.parse(HelperCommandResult(
                exitCode: 0,
                standardOutput: "mx3-lite is stopped\n",
                standardError: ""
            )),
            .stopped
        )
        XCTAssertEqual(
            WorkerStatusParser.parse(HelperCommandResult(
                exitCode: 127,
                standardOutput: "",
                standardError: "missing helper"
            )),
            .unknown("missing helper")
        )
    }

    private func jsonObject(_ data: Data) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }
}
