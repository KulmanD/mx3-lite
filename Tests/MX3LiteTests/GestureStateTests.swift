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

    func testInterruptionWhileIdleIsIdempotent() throws {
        let mapper = makeMapper()
        var activityChanges: [Bool] = []
        mapper.onGestureActivityChanged = { activityChanges.append($0) }

        mapper.cancelGestureForEventTapInterruption()
        mapper.cancelGestureForEventTapInterruption()

        XCTAssertEqual(activityChanges, [])
        XCTAssertFalse(mapper.gestureStateForTesting.isActive)
        XCTAssertFalse(mapper.handle(
            type: .mouseMoved,
            event: try mouseEvent(type: .mouseMoved, location: CGPoint(x: 50, y: 0))
        ))
    }

    func testInterruptionAfterGestureDownClearsStateAndDisablesMovement() throws {
        let mapper = makeMapper()
        var activityChanges: [Bool] = []
        mapper.onGestureActivityChanged = { activityChanges.append($0) }

        XCTAssertTrue(mapper.handle(
            type: .otherMouseDown,
            event: try buttonEvent(type: .otherMouseDown, button: 5)
        ))
        XCTAssertTrue(mapper.gestureStateForTesting.isActive)

        mapper.cancelGestureForEventTapInterruption()

        XCTAssertEqual(activityChanges, [true, false])
        assertInactiveAndCleared(mapper.gestureStateForTesting)
        XCTAssertFalse(mapper.handle(
            type: .mouseMoved,
            event: try mouseEvent(type: .mouseMoved, location: CGPoint(x: 500, y: 0))
        ))
    }

    func testInterruptionClearsBelowThresholdMovementAndRepeatedNotificationIsSafe() throws {
        var config = AppConfig.default
        config.threshold = 220
        let mapper = makeMapper(config: config)
        var activityChanges: [Bool] = []
        mapper.onGestureActivityChanged = { activityChanges.append($0) }

        XCTAssertTrue(mapper.handle(
            type: .otherMouseDown,
            event: try buttonEvent(type: .otherMouseDown, button: 5)
        ))
        XCTAssertTrue(mapper.handle(
            type: .mouseMoved,
            event: try mouseEvent(type: .mouseMoved, location: CGPoint(x: 100, y: 40))
        ))
        XCTAssertEqual(mapper.gestureStateForTesting.accumulatedDx, 100)
        XCTAssertEqual(mapper.gestureStateForTesting.accumulatedDy, 40)

        mapper.cancelGestureForEventTapInterruption()
        mapper.cancelGestureForEventTapInterruption()

        XCTAssertEqual(activityChanges, [true, false])
        assertInactiveAndCleared(mapper.gestureStateForTesting)
    }

    func testInterruptionAfterConsumedGestureAllowsImmediateNewGesture() throws {
        var config = AppConfig.default
        config.threshold = 10
        config.downAction = .disabled
        let mapper = makeMapper(config: config)
        var activityChanges: [Bool] = []
        mapper.onGestureActivityChanged = { activityChanges.append($0) }

        XCTAssertTrue(mapper.handle(
            type: .otherMouseDown,
            event: try buttonEvent(type: .otherMouseDown, button: 5)
        ))
        XCTAssertTrue(mapper.handle(
            type: .mouseMoved,
            event: try mouseEvent(type: .mouseMoved, location: CGPoint(x: 0, y: 11))
        ))
        XCTAssertTrue(mapper.gestureStateForTesting.isConsumed)

        mapper.cancelGestureForEventTapInterruption()
        assertInactiveAndCleared(mapper.gestureStateForTesting)

        XCTAssertTrue(mapper.handle(
            type: .otherMouseDown,
            event: try buttonEvent(
                type: .otherMouseDown,
                button: 5,
                location: CGPoint(x: 25, y: 25)
            )
        ))
        XCTAssertTrue(mapper.handle(
            type: .mouseMoved,
            event: try mouseEvent(type: .mouseMoved, location: CGPoint(x: 25, y: 36))
        ))
        XCTAssertTrue(mapper.gestureStateForTesting.isActive)
        XCTAssertTrue(mapper.gestureStateForTesting.isConsumed)
        XCTAssertEqual(activityChanges, [true, false, true])
    }

    func testHorizontalDirectionIsInvertedWhenConfigured() {
        var left = GestureState()
        left.begin(at: .zero)
        left.addMovement(to: CGPoint(x: -221, y: 0), invertY: false)
        XCTAssertEqual(
            left.consumeAction(threshold: 220, downAction: .ctrlDown, invertDesktopDirection: true),
            .controlArrow(.right)
        )

        var right = GestureState()
        right.begin(at: .zero)
        right.addMovement(to: CGPoint(x: 221, y: 0), invertY: false)
        XCTAssertEqual(
            right.consumeAction(threshold: 220, downAction: .ctrlDown, invertDesktopDirection: true),
            .controlArrow(.left)
        )
    }

    func testHorizontalDirectionIsNaturalWhenNotInverted() {
        var state = GestureState()
        state.begin(at: .zero)
        state.addMovement(to: CGPoint(x: -221, y: 0), invertY: false)

        XCTAssertEqual(
            state.consumeAction(threshold: 220, downAction: .ctrlDown, invertDesktopDirection: false),
            .controlArrow(.left)
        )
    }

    func testGestureTriggersOnlyOnceUntilReleaseThenResets() {
        var state = GestureState()
        state.begin(at: .zero)
        state.addMovement(to: CGPoint(x: 221, y: 0), invertY: false)

        XCTAssertEqual(
            state.consumeAction(threshold: 220, downAction: .ctrlDown, invertDesktopDirection: false),
            .controlArrow(.right)
        )
        state.addMovement(to: CGPoint(x: -500, y: 0), invertY: false)
        XCTAssertNil(state.consumeAction(threshold: 220, downAction: .ctrlDown, invertDesktopDirection: false))

        state.end()
        XCTAssertFalse(state.isActive)
        XCTAssertFalse(state.isConsumed)
        XCTAssertEqual(state.accumulatedDx, 0)

        state.begin(at: .zero)
        state.addMovement(to: CGPoint(x: 0, y: -221), invertY: false)
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
        state.begin(at: .zero)
        state.addMovement(to: CGPoint(x: 0, y: 221), invertY: false)

        XCTAssertEqual(
            state.consumeAction(threshold: 220, downAction: .disabled, invertDesktopDirection: true),
            .disabledDown
        )
        XCTAssertTrue(state.isConsumed)
    }

    private func makeMapper(config: AppConfig = .default) -> GestureMapper {
        let logger = DebugLogger(enabled: false)
        return GestureMapper(
            config: config,
            logger: logger,
            liveEventDebug: false,
            mxMasterRegistry: MXMasterDeviceRegistry(logger: logger, debug: false)
        )
    }

    private func buttonEvent(
        type: CGEventType,
        button: Int,
        location: CGPoint = .zero
    ) throws -> CGEvent {
        let event = try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: .center
        ))
        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        return event
    }

    private func mouseEvent(type: CGEventType, location: CGPoint) throws -> CGEvent {
        try XCTUnwrap(CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: location,
            mouseButton: .left
        ))
    }

    private func assertInactiveAndCleared(
        _ state: GestureState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(state.isActive, file: file, line: line)
        XCTAssertFalse(state.isConsumed, file: file, line: line)
        XCTAssertNil(state.lastLocation, file: file, line: line)
        XCTAssertEqual(state.accumulatedDx, 0, file: file, line: line)
        XCTAssertEqual(state.accumulatedDy, 0, file: file, line: line)
        XCTAssertEqual(state.accumulatedScrollX, 0, file: file, line: line)
        XCTAssertEqual(state.accumulatedScrollY, 0, file: file, line: line)
    }
}
