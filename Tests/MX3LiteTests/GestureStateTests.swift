import CoreGraphics
import XCTest
@testable import MX3Lite

final class GestureStateTests: XCTestCase {
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
}
