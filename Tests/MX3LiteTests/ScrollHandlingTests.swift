import CoreGraphics
import Testing
@testable import MX3Lite

@Suite struct ScrollHandlingTests {
    private let logger = DebugLogger(enabled: false)

    @Test func transformModeDecision() {
        #expect(!ScrollTransformer.shouldTransform(mode: .disabled, classifiedAsMXMaster: true))
        #expect(ScrollTransformer.shouldTransform(mode: .global, classifiedAsMXMaster: false))
        #expect(ScrollTransformer.shouldTransform(mode: .mxMasterOnly, classifiedAsMXMaster: true))
        #expect(!ScrollTransformer.shouldTransform(mode: .mxMasterOnly, classifiedAsMXMaster: false))
    }

    @Test func emaReducesJitterWithoutHistoryBuffer() throws {
        var config = AppConfig.default
        config.scrollTransformMode = .global
        config.invertVerticalScroll = false
        config.smoothScroll = true
        config.smoothScrollMode = .ema
        config.smoothScrollFactor = 0.35
        config.maxScrollStep = 100

        let result = try apply(axis1: 10, config: config, transformer: ScrollTransformer())

        #expect(abs(result.afterSmoothingAxis1 - 6.5) < 0.0001)
        #expect(result.finalAxis1 == 7)
    }

    @Test func dampenSpikesUsesConfiguredDamping() throws {
        var config = AppConfig.default
        config.scrollTransformMode = .global
        config.invertVerticalScroll = false
        config.smoothScroll = true
        config.smoothScrollMode = .dampenSpikes
        config.freeSpinDamping = 0.75
        config.maxScrollStep = 8

        let result = try apply(axis1: 20, config: config, transformer: ScrollTransformer())

        #expect(abs(result.afterSmoothingAxis1 - 6) < 0.0001)
        #expect(abs(result.afterClampAxis1 - 6) < 0.0001)
        #expect(result.finalAxis1 == 6)
    }

    @Test func inertiaStateRemainsBounded() throws {
        var config = AppConfig.default
        config.scrollTransformMode = .global
        config.invertVerticalScroll = false
        config.smoothScroll = true
        config.smoothScrollMode = .inertia
        config.maxScrollStep = 8
        let transformer = ScrollTransformer()

        for _ in 0..<100 {
            _ = try apply(axis1: 1_000, config: config, transformer: transformer)
        }

        let state = transformer.smoothingState
        #expect(abs(state.previousAxis1) <= 64)
        #expect(abs(state.previousAxis2) <= 64)
        #expect(abs(state.inertiaCarryAxis1) <= 64)
        #expect(abs(state.inertiaCarryAxis2) <= 64)
    }

    @Test func disabledAndUnclassifiedMXMasterOnlyEventsPassThrough() throws {
        var disabled = AppConfig.default
        disabled.scrollTransformMode = .disabled
        let disabledResult = try apply(axis1: 4, config: disabled, transformer: ScrollTransformer())
        #expect(!disabledResult.returnedModified)
        #expect(disabledResult.finalAxis1 == 4)

        var mxMasterOnly = AppConfig.default
        mxMasterOnly.scrollTransformMode = .mxMasterOnly
        let mxOnlyResult = try apply(axis1: 4, config: mxMasterOnly, transformer: ScrollTransformer())
        #expect(!mxOnlyResult.classifiedAsMXMaster)
        #expect(!mxOnlyResult.returnedModified)
        #expect(mxOnlyResult.finalAxis1 == 4)
    }

    private func apply(axis1: Int32, config: AppConfig, transformer: ScrollTransformer) throws -> ScrollTransformResult {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: axis1,
            wheel2: 0,
            wheel3: 0
        ) else {
            throw TestError.missingEvent
        }
        let registry = MXMasterDeviceRegistry(logger: logger, debug: false)
        guard let result = transformer.apply(
            to: event,
            config: config,
            mxMasterRegistry: registry,
            captureDebug: true
        ) else {
            throw TestError.missingResult
        }
        return result
    }

    private enum TestError: Error {
        case missingEvent
        case missingResult
    }
}
