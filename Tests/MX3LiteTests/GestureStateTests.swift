import CoreGraphics
import XCTest
@testable import MX3Lite

final class GestureStateTests: XCTestCase {
    func testNormalEventTypesSeparateContinuousMovementFromPrimaryEvents() {
        var config = AppConfig.default
        config.scrollTransformMode = .mxMasterOnly
        let mapper = GestureMapper(
            config: config,
            logger: DebugLogger(enabled: false),
            liveEventDebug: false,
            mxMasterRegistry: MXMasterDeviceRegistry(logger: DebugLogger(enabled: false), debug: false)
        )

        XCTAssertEqual(mapper.primaryEventTypes, [.otherMouseDown, .otherMouseUp, .scrollWheel])
        XCTAssertEqual(mapper.movementEventTypes, [.mouseMoved, .otherMouseDragged])
    }

    func testMapperSignalsMovementTapForGestureHold() throws {
        let logger = DebugLogger(enabled: false)
        let mapper = GestureMapper(
            config: AppConfig.default,
            logger: logger,
            liveEventDebug: false,
            mxMasterRegistry: MXMasterDeviceRegistry(logger: logger, debug: false)
        )
        var activityChanges: [Bool] = []
        mapper.onGestureActivityChanged = { activityChanges.append($0) }

        let down = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDown,
            mouseCursorPosition: .zero,
            mouseButton: .center
        ))
        down.setIntegerValueField(.mouseEventButtonNumber, value: 5)
        XCTAssertTrue(mapper.handle(type: .otherMouseDown, event: down))

        let up = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseUp,
            mouseCursorPosition: .zero,
            mouseButton: .center
        ))
        up.setIntegerValueField(.mouseEventButtonNumber, value: 5)
        XCTAssertTrue(mapper.handle(type: .otherMouseUp, event: up))

        XCTAssertEqual(activityChanges, [true, false])
    }

    func testHorizontalDirectionIsInvertedWhenConfigured() {
        var left = GestureState()
        left.begin()
        left.addMovement(deltaX: -221, deltaY: 0, invertY: false)
        XCTAssertEqual(
            left.consumeAction(threshold: 220, downAction: .ctrlDown, invertDesktopDirection: true),
            .controlArrow(.right)
        )

        var right = GestureState()
        right.begin()
        right.addMovement(deltaX: 221, deltaY: 0, invertY: false)
        XCTAssertEqual(
            right.consumeAction(threshold: 220, downAction: .ctrlDown, invertDesktopDirection: true),
            .controlArrow(.left)
        )
    }

    func testHorizontalDirectionIsNaturalWhenNotInverted() {
        var state = GestureState()
        state.begin()
        state.addMovement(deltaX: -221, deltaY: 0, invertY: false)

        XCTAssertEqual(
            state.consumeAction(threshold: 220, downAction: .ctrlDown, invertDesktopDirection: false),
            .controlArrow(.left)
        )
    }

    func testGestureTriggersOnlyOnceUntilReleaseThenResets() {
        var state = GestureState()
        state.begin()
        state.addMovement(deltaX: 221, deltaY: 0, invertY: false)

        XCTAssertEqual(
            state.consumeAction(threshold: 220, downAction: .ctrlDown, invertDesktopDirection: false),
            .controlArrow(.right)
        )
        state.addMovement(deltaX: -500, deltaY: 0, invertY: false)
        XCTAssertNil(state.consumeAction(threshold: 220, downAction: .ctrlDown, invertDesktopDirection: false))

        state.end()
        XCTAssertFalse(state.isActive)
        XCTAssertFalse(state.isConsumed)
        XCTAssertEqual(state.accumulatedDx, 0)

        state.begin()
        state.addMovement(deltaX: 0, deltaY: -221, invertY: false)
        XCTAssertEqual(
            state.consumeAction(threshold: 220, downAction: .ctrlDown, invertDesktopDirection: true),
            .controlArrow(.up)
        )
    }

    func testSideButtonsAreSuppressedDuringGestureHold() {
        let buttons = ButtonConfig(gesture: 5, back: 3, forward: 4)

        XCTAssertEqual(
            GestureState.buttonDownDecision(button: 3, buttons: buttons, gestureActive: true),
            .suppressSideButton
        )
        XCTAssertEqual(
            GestureState.buttonDownDecision(button: 4, buttons: buttons, gestureActive: true),
            .suppressSideButton
        )
        XCTAssertEqual(
            GestureState.buttonDownDecision(button: 3, buttons: buttons, gestureActive: false),
            .commandBracket(left: true)
        )
    }

    func testDisabledDownConsumesGestureWithoutSendingArrow() {
        var state = GestureState()
        state.begin()
        state.addMovement(deltaX: 0, deltaY: 221, invertY: false)

        XCTAssertEqual(
            state.consumeAction(threshold: 220, downAction: .disabled, invertDesktopDirection: true),
            .disabledDown
        )
        XCTAssertTrue(state.isConsumed)
    }

    func testDeltaMovementSupportsVerticalInversion() {
        var up = GestureState()
        up.begin()
        up.addMovement(deltaX: 0, deltaY: 221, invertY: true)
        XCTAssertEqual(
            up.consumeAction(threshold: 220, downAction: .disabled, invertDesktopDirection: false),
            .controlArrow(.up)
        )

        var down = GestureState()
        down.begin()
        down.addMovement(deltaX: 0, deltaY: -221, invertY: true)
        XCTAssertEqual(
            down.consumeAction(threshold: 220, downAction: .disabled, invertDesktopDirection: false),
            .disabledDown
        )
    }

    func testDeltaThresholdIsStrictAndAccumulatesAcrossEvents() {
        var state = GestureState()
        state.begin()
        state.addMovement(deltaX: -100, deltaY: 0, invertY: false)
        state.addMovement(deltaX: -120, deltaY: 0, invertY: false)
        XCTAssertNil(state.consumeAction(
            threshold: 220,
            downAction: .disabled,
            invertDesktopDirection: false
        ))

        state.addMovement(deltaX: -1, deltaY: 0, invertY: false)
        XCTAssertEqual(
            state.consumeAction(threshold: 220, downAction: .disabled, invertDesktopDirection: false),
            .controlArrow(.left)
        )
    }

    func testHorizontalDeltaKeepsPrecedenceForDiagonalMovement() {
        var state = GestureState()
        state.begin()
        state.addMovement(deltaX: -221, deltaY: -500, invertY: false)

        XCTAssertEqual(
            state.consumeAction(threshold: 220, downAction: .disabled, invertDesktopDirection: false),
            .controlArrow(.left)
        )
    }

    func testMapperUsesDeltaWhenLocationDoesNotChange() throws {
        var config = AppConfig.default
        config.threshold = 10
        config.downAction = .disabled
        let logger = DebugLogger(enabled: false)
        let mapper = GestureMapper(
            config: config,
            logger: logger,
            liveEventDebug: false,
            mxMasterRegistry: MXMasterDeviceRegistry(logger: logger, debug: false)
        )
        let location = CGPoint(x: 500, y: 500)
        let down = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .otherMouseDown,
            mouseCursorPosition: location,
            mouseButton: .center
        ))
        down.setIntegerValueField(.mouseEventButtonNumber, value: 5)
        XCTAssertTrue(mapper.handle(type: .otherMouseDown, event: down))

        let movement = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: location,
            mouseButton: .left
        ))
        movement.setIntegerValueField(.mouseEventDeltaY, value: 11)
        XCTAssertTrue(mapper.handle(type: .mouseMoved, event: movement))

        XCTAssertEqual(movement.location, location)
        XCTAssertTrue(mapper.gestureStateForTesting.isConsumed)
        XCTAssertEqual(mapper.gestureStateForTesting.accumulatedDy, 11)
    }
}
