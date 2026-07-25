import Foundation
import XCTest
@testable import MX3Lite

final class ConfigTests: XCTestCase {
    func testDefaultConfigMatchesShippedBehavior() {
        let config = AppConfig.default

        XCTAssertEqual(config.threshold, 220)
        XCTAssertEqual(config.buttons.gesture, 5)
        XCTAssertEqual(config.buttons.back, 3)
        XCTAssertEqual(config.buttons.forward, 4)
        XCTAssertEqual(config.actionBackend, .systemEvents)
        XCTAssertTrue(config.invertDesktopGestureDirection)
        XCTAssertEqual(config.scrollTransformMode, .mxMasterOnly)
        XCTAssertTrue(config.smoothScroll)
        XCTAssertEqual(config.smoothScrollMode, .ema)
        XCTAssertEqual(config.smoothScrollFactor, 0.35)
    }

    func testMissingTopLevelValuesUseDefaultsAndReportDefaultSources() throws {
        let data = Data("{}".utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        let sources = ConfigSources(data: data)

        XCTAssertEqual(config.threshold, AppConfig.default.threshold)
        XCTAssertEqual(config.buttons.gesture, 5)
        XCTAssertEqual(sources.threshold, "default")
        XCTAssertEqual(sources.actionBackend, "default")
        XCTAssertEqual(sources.gestureButton, "default")
    }

    func testPresentButtonsObjectKeepsMissingMappingsDisabled() throws {
        let data = Data(#"{"buttons":{"gesture":5}}"#.utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        let sources = ConfigSources(data: data)

        XCTAssertEqual(config.buttons.gesture, 5)
        XCTAssertNil(config.buttons.back)
        XCTAssertNil(config.buttons.forward)
        XCTAssertEqual(sources.backButton, "config.json (missing -> disabled)")
        XCTAssertEqual(sources.forwardButton, "config.json (missing -> disabled)")
    }

    func testInvalidValuesFallbackOrClampAndProduceWarnings() throws {
        let data = Data(#"""
        {
          "threshold": 0,
          "actionBackend": "unknown",
          "scrollTransformMode": "unknown",
          "smoothScrollMode": "unknown",
          "smoothScrollFactor": 2,
          "scrollMultiplier": 0.01,
          "maxScrollStep": -4
        }
        """#.utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        let warnings = ConfigValidator.warnings(data: data, config: config)

        XCTAssertEqual(config.threshold, AppConfig.default.threshold)
        XCTAssertEqual(config.actionBackend, .systemEvents)
        XCTAssertEqual(config.scrollTransformMode, .mxMasterOnly)
        XCTAssertEqual(config.smoothScrollMode, .ema)
        XCTAssertEqual(config.smoothScrollFactor, 0.95)
        XCTAssertEqual(config.scrollMultiplier, 0.1)
        XCTAssertEqual(config.maxScrollStep, 1)
        XCTAssertTrue(warnings.contains { $0.contains("threshold must be greater than 0") })
        XCTAssertTrue(warnings.contains { $0.contains("actionBackend has unknown value") })
        XCTAssertTrue(warnings.contains { $0.contains("scrollTransformMode has unknown value") })
        XCTAssertTrue(warnings.contains { $0.contains("smoothScrollFactor outside") })
    }

    func testConfigStoreCreatesDefaultsAndReportsTheirSource() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let paths = AppPaths(home: home)
        try paths.ensureDirectories()
        let loaded = try ConfigStore(paths: paths).loadOrCreateWithSources()

        XCTAssertFalse(loaded.configFileExisted)
        XCTAssertTrue(loaded.configFileCreated)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.configFile.path))
        XCTAssertEqual(loaded.config.buttons.gesture, 5)
        XCTAssertEqual(loaded.sources.threshold, "default")
        XCTAssertEqual(loaded.sources.gestureButton, "default")
        XCTAssertTrue(loaded.warnings.isEmpty)
    }

    func testReadOnlyConfigLoadDoesNotCreateMissingFile() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let paths = AppPaths(home: home)
        let loaded = try ConfigStore(paths: paths).loadExistingWithSources()

        XCTAssertNil(loaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.appSupportDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.configFile.path))
    }
}
