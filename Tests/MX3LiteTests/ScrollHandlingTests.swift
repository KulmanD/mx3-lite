import CoreGraphics
import XCTest
@testable import MX3Lite

final class ScrollHandlingTests: XCTestCase {
    private let logger = DebugLogger(enabled: false)

    func testTransformModeDecision() {
        XCTAssertFalse(ScrollTransformer.shouldTransform(mode: .disabled, classifiedAsMXMaster: true))
        XCTAssertTrue(ScrollTransformer.shouldTransform(mode: .global, classifiedAsMXMaster: false))
        XCTAssertTrue(ScrollTransformer.shouldTransform(mode: .mxMasterOnly, classifiedAsMXMaster: true))
        XCTAssertFalse(ScrollTransformer.shouldTransform(mode: .mxMasterOnly, classifiedAsMXMaster: false))
    }

    func testEMAReducesJitterWithoutHistoryBuffer() throws {
        var config = AppConfig.default
        config.scrollTransformMode = .global
        config.invertVerticalScroll = false
        config.smoothScroll = true
        config.smoothScrollMode = .ema
        config.smoothScrollFactor = 0.35
        config.maxScrollStep = 100

        let result = try apply(axis1: 10, config: config, transformer: ScrollTransformer())

        XCTAssertEqual(result.afterSmoothingAxis1, 6.5, accuracy: 0.0001)
        XCTAssertEqual(result.finalAxis1, 7)
    }

    func testEMAContinuesWithinOneScrollSequence() throws {
        let config = emaConfig()
        let transformer = ScrollTransformer()

        _ = try apply(axis1: 10, timestamp: 1, config: config, transformer: transformer)
        let result = try apply(
            axis1: 10,
            timestamp: 1 + ScrollTransformer.sequenceIdleGap - 1,
            config: config,
            transformer: transformer
        )

        XCTAssertEqual(result.afterSmoothingAxis1, 8.775, accuracy: 0.0001)
    }

    func testEMADirectionReversalResetsOnlyTheReversedAxis() throws {
        let config = emaConfig()
        let transformer = ScrollTransformer()

        _ = try apply(axis1: 10, axis2: 10, timestamp: 1, config: config, transformer: transformer)
        let result = try apply(
            axis1: 10,
            axis2: -10,
            timestamp: 2,
            config: config,
            transformer: transformer
        )

        XCTAssertEqual(result.afterSmoothingAxis1, 8.775, accuracy: 0.0001)
        XCTAssertEqual(result.afterSmoothingAxis2, -6.5, accuracy: 0.0001)
    }

    func testEMAIdleGapStartsAnIndependentSequence() throws {
        let config = emaConfig()
        let transformer = ScrollTransformer()

        _ = try apply(axis1: 10, timestamp: 1, config: config, transformer: transformer)
        let result = try apply(
            axis1: 10,
            timestamp: 1 + ScrollTransformer.sequenceIdleGap,
            config: config,
            transformer: transformer
        )

        XCTAssertEqual(result.afterSmoothingAxis1, 6.5, accuracy: 0.0001)
    }

    func testDisabledSmoothingDoesNotRetainSequenceTimestamp() throws {
        var config = emaConfig()
        config.smoothScroll = false
        let transformer = ScrollTransformer()

        let result = try apply(axis1: 10, timestamp: 123, config: config, transformer: transformer)

        XCTAssertEqual(result.afterSmoothingAxis1, 10)
        XCTAssertNil(transformer.smoothingState.lastTransformedScrollTimestamp)
    }

    func testDampenSpikesUsesConfiguredDamping() throws {
        var config = AppConfig.default
        config.scrollTransformMode = .global
        config.invertVerticalScroll = false
        config.smoothScroll = true
        config.smoothScrollMode = .dampenSpikes
        config.freeSpinDamping = 0.75
        config.maxScrollStep = 8

        let result = try apply(axis1: 20, config: config, transformer: ScrollTransformer())

        XCTAssertEqual(result.afterSmoothingAxis1, 6, accuracy: 0.0001)
        XCTAssertEqual(result.afterClampAxis1, 6, accuracy: 0.0001)
        XCTAssertEqual(result.finalAxis1, 6)
    }

    func testInertiaStateRemainsBounded() throws {
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
        XCTAssertLessThanOrEqual(abs(state.previousAxis1), 64)
        XCTAssertLessThanOrEqual(abs(state.previousAxis2), 64)
        XCTAssertLessThanOrEqual(abs(state.inertiaCarryAxis1), 64)
        XCTAssertLessThanOrEqual(abs(state.inertiaCarryAxis2), 64)
    }

    func testInertiaDirectionReversalClearsCarry() throws {
        var config = emaConfig()
        config.smoothScrollMode = .inertia
        let transformer = ScrollTransformer()

        _ = try apply(axis1: 10, timestamp: 1, config: config, transformer: transformer)
        let result = try apply(axis1: -10, timestamp: 2, config: config, transformer: transformer)

        XCTAssertEqual(result.afterSmoothingAxis1, -6.5, accuracy: 0.0001)
        XCTAssertEqual(transformer.smoothingState.inertiaCarryAxis1, -3.5, accuracy: 0.0001)
    }

    func testDisabledAndUnclassifiedMXMasterOnlyEventsPassThrough() throws {
        var disabled = AppConfig.default
        disabled.scrollTransformMode = .disabled
        let disabledResult = try apply(axis1: 4, config: disabled, transformer: ScrollTransformer())
        XCTAssertFalse(disabledResult.returnedModified)
        XCTAssertEqual(disabledResult.finalAxis1, 4)

        var mxMasterOnly = AppConfig.default
        mxMasterOnly.scrollTransformMode = .mxMasterOnly
        let mxOnlyTransformer = ScrollTransformer()
        let mxOnlyResult = try apply(axis1: 4, config: mxMasterOnly, transformer: mxOnlyTransformer)
        XCTAssertFalse(mxOnlyResult.classifiedAsMXMaster)
        XCTAssertFalse(mxOnlyResult.returnedModified)
        XCTAssertEqual(mxOnlyResult.finalAxis1, 4)
        XCTAssertNil(mxOnlyTransformer.smoothingState.lastTransformedScrollTimestamp)
    }

    private func emaConfig() -> AppConfig {
        var config = AppConfig.default
        config.scrollTransformMode = .global
        config.invertVerticalScroll = false
        config.invertHorizontalScroll = false
        config.smoothScroll = true
        config.smoothScrollMode = .ema
        config.smoothScrollFactor = 0.35
        config.maxScrollStep = 100
        return config
    }

    private func apply(
        axis1: Int32,
        axis2: Int32 = 0,
        timestamp: CGEventTimestamp = 0,
        config: AppConfig,
        transformer: ScrollTransformer
    ) throws -> ScrollTransformResult {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: axis1,
            wheel2: axis2,
            wheel3: 0
        ) else {
            throw TestError.missingEvent
        }
        event.timestamp = timestamp
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
