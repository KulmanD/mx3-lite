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

        let event = try makeEvent(units: .line, axis1: 10)
        _ = try apply(event: event, config: config, transformer: ScrollTransformer())
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), 6.5, accuracy: 0.0001)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 65)
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

    func testVerticalAndHorizontalRepresentationsTransformTogether() throws {
        var config = identityConfig()
        config.invertVerticalScroll = true
        config.invertHorizontalScroll = true
        config.scrollMultiplier = 2
        let event = try makeEvent(units: .pixel, axis1: 15, axis2: -5)

        _ = try apply(event: event, config: config, transformer: ScrollTransformer())

        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), -3)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), -3, accuracy: 0.0001)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), -30)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis2), 1)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2), 1, accuracy: 0.0001)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), 10)
    }

    func testFractionalHorizontalDeltaIsPreserved() throws {
        var config = identityConfig()
        config.invertHorizontalScroll = true
        let event = try makeEvent(units: .pixel, axis1: 0, axis2: 3)
        let rawFixed = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)

        _ = try apply(event: event, config: config, transformer: ScrollTransformer())

        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis2), -1)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2), -rawFixed, accuracy: 0.0001)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), -3)
    }

    func testAccelerationAndClampUpdateEveryRepresentation() throws {
        var config = identityConfig()
        config.scrollMultiplier = 2
        config.scrollAcceleration = 2
        config.maxScrollStep = 8
        let event = try makeEvent(units: .line, axis1: 4)

        _ = try apply(event: event, config: config, transformer: ScrollTransformer())

        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventDeltaAxis1), 8)
        XCTAssertEqual(event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), 8, accuracy: 0.0001)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 80)
    }

    func testScrollPhaseMetadataIsPreserved() throws {
        let config = identityConfig()
        let event = try makeEvent(units: .line, axis1: 2)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 8)
        event.setIntegerValueField(.scrollWheelEventScrollCount, value: 7)

        _ = try apply(event: event, config: config, transformer: ScrollTransformer())

        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventScrollPhase), 2)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventMomentumPhase), 8)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventScrollCount), 7)
    }

    func testDisabledAndUnclassifiedMXMasterOnlyEventsPassThrough() throws {
        var disabled = AppConfig.default
        disabled.scrollTransformMode = .disabled
        let disabledEvent = try makeEvent(units: .pixel, axis1: 7, axis2: -3)
        let rawFixedAxis1 = disabledEvent.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let rawPointAxis2 = disabledEvent.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let disabledResult = try apply(event: disabledEvent, config: disabled, transformer: ScrollTransformer())
        XCTAssertFalse(disabledResult.returnedModified)
        XCTAssertEqual(disabledEvent.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1), rawFixedAxis1)
        XCTAssertEqual(disabledEvent.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), rawPointAxis2)

        var mxMasterOnly = AppConfig.default
        mxMasterOnly.scrollTransformMode = .mxMasterOnly
        let mxOnlyEvent = try makeEvent(units: .pixel, axis1: 7, axis2: -3)
        let mxOnlyFixedAxis2 = mxOnlyEvent.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        let mxOnlyResult = try apply(event: mxOnlyEvent, config: mxMasterOnly, transformer: ScrollTransformer())
        XCTAssertFalse(mxOnlyResult.classifiedAsMXMaster)
        XCTAssertFalse(mxOnlyResult.returnedModified)
        XCTAssertEqual(mxOnlyEvent.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2), mxOnlyFixedAxis2)
    }

    private func apply(axis1: Int32, config: AppConfig, transformer: ScrollTransformer) throws -> ScrollTransformResult {
        try apply(
            event: makeEvent(units: .line, axis1: axis1),
            config: config,
            transformer: transformer
        )
    }

    private func apply(event: CGEvent, config: AppConfig, transformer: ScrollTransformer) throws -> ScrollTransformResult {
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

    private func makeEvent(units: CGScrollEventUnit, axis1: Int32, axis2: Int32 = 0) throws -> CGEvent {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: units,
            wheelCount: 2,
            wheel1: axis1,
            wheel2: axis2,
            wheel3: 0
        ) else {
            throw TestError.missingEvent
        }
        return event
    }

    private func identityConfig() -> AppConfig {
        var config = AppConfig.default
        config.scrollTransformMode = .global
        config.invertVerticalScroll = false
        config.invertHorizontalScroll = false
        config.scrollMultiplier = 1
        config.ratchetStepMultiplier = 1
        config.scrollAcceleration = 1
        config.scrollDeadzone = 0
        config.smoothScroll = false
        config.maxScrollStep = 100
        return config
    }

    private enum TestError: Error {
        case missingEvent
        case missingResult
    }
}
