import Foundation
import Testing
@testable import MX3Lite

@Suite struct ConfigTests {
    @Test func defaultConfigMatchesShippedBehavior() {
        let config = AppConfig.default

        #expect(config.threshold == 220)
        #expect(config.buttons.gesture == 5)
        #expect(config.buttons.back == 3)
        #expect(config.buttons.forward == 4)
        #expect(config.actionBackend == .systemEvents)
        #expect(config.invertDesktopGestureDirection)
        #expect(config.scrollTransformMode == .mxMasterOnly)
        #expect(config.smoothScroll)
        #expect(config.smoothScrollMode == .ema)
        #expect(config.smoothScrollFactor == 0.35)
    }

    @Test func missingTopLevelValuesUseDefaultsAndReportDefaultSources() throws {
        let data = Data("{}".utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        let sources = ConfigSources(data: data)

        #expect(config.threshold == AppConfig.default.threshold)
        #expect(config.buttons.gesture == 5)
        #expect(sources.threshold == "default")
        #expect(sources.actionBackend == "default")
        #expect(sources.gestureButton == "default")
    }

    @Test func presentButtonsObjectKeepsMissingMappingsDisabled() throws {
        let data = Data(#"{"buttons":{"gesture":5}}"#.utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        let sources = ConfigSources(data: data)

        #expect(config.buttons.gesture == 5)
        #expect(config.buttons.back == nil)
        #expect(config.buttons.forward == nil)
        #expect(sources.backButton == "config.json (missing -> disabled)")
        #expect(sources.forwardButton == "config.json (missing -> disabled)")
    }

    @Test func invalidValuesFallbackOrClampAndProduceWarnings() throws {
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

        #expect(config.threshold == AppConfig.default.threshold)
        #expect(config.actionBackend == .systemEvents)
        #expect(config.scrollTransformMode == .mxMasterOnly)
        #expect(config.smoothScrollMode == .ema)
        #expect(config.smoothScrollFactor == 0.95)
        #expect(config.scrollMultiplier == 0.1)
        #expect(config.maxScrollStep == 1)
        #expect(warnings.contains { $0.contains("threshold must be greater than 0") })
        #expect(warnings.contains { $0.contains("actionBackend has unknown value") })
        #expect(warnings.contains { $0.contains("scrollTransformMode has unknown value") })
        #expect(warnings.contains { $0.contains("smoothScrollFactor outside") })
    }

    @Test func configStoreCreatesDefaultsAndReportsTheirSource() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let paths = AppPaths(home: home)
        try paths.ensureDirectories()
        let loaded = try ConfigStore(paths: paths).loadOrCreateWithSources()

        #expect(!loaded.configFileExisted)
        #expect(loaded.configFileCreated)
        #expect(FileManager.default.fileExists(atPath: paths.configFile.path))
        #expect(loaded.config.buttons.gesture == 5)
        #expect(loaded.sources.threshold == "default")
        #expect(loaded.sources.gestureButton == "default")
        #expect(loaded.warnings.isEmpty)
    }
}
