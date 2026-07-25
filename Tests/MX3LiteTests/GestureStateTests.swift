import CoreGraphics
import Testing
@testable import MX3Lite

@Suite struct GestureStateTests {
    @Test func horizontalDirectionIsInvertedWhenConfigured() {
        var left = GestureState()
        left.begin(at: .zero)
        left.addMovement(to: CGPoint(x: -221, y: 0), invertY: false)
        #expect(left.consumeAction(
            threshold: 220,
            downAction: .ctrlDown,
            invertDesktopDirection: true
        ) == .controlArrow(.right))

        var right = GestureState()
        right.begin(at: .zero)
        right.addMovement(to: CGPoint(x: 221, y: 0), invertY: false)
        #expect(right.consumeAction(
            threshold: 220,
            downAction: .ctrlDown,
            invertDesktopDirection: true
        ) == .controlArrow(.left))
    }

    @Test func horizontalDirectionIsNaturalWhenNotInverted() {
        var state = GestureState()
        state.begin(at: .zero)
        state.addMovement(to: CGPoint(x: -221, y: 0), invertY: false)

        #expect(state.consumeAction(
            threshold: 220,
            downAction: .ctrlDown,
            invertDesktopDirection: false
        ) == .controlArrow(.left))
    }

    @Test func gestureTriggersOnlyOnceUntilReleaseThenResets() {
        var state = GestureState()
        state.begin(at: .zero)
        state.addMovement(to: CGPoint(x: 221, y: 0), invertY: false)

        #expect(state.consumeAction(
            threshold: 220,
            downAction: .ctrlDown,
            invertDesktopDirection: false
        ) == .controlArrow(.right))
        state.addMovement(to: CGPoint(x: -500, y: 0), invertY: false)
        #expect(state.consumeAction(
            threshold: 220,
            downAction: .ctrlDown,
            invertDesktopDirection: false
        ) == nil)

        state.end()
        #expect(!state.isActive)
        #expect(!state.isConsumed)
        #expect(state.accumulatedDx == 0)

        state.begin(at: .zero)
        state.addMovement(to: CGPoint(x: 0, y: -221), invertY: false)
        #expect(state.consumeAction(
            threshold: 220,
            downAction: .ctrlDown,
            invertDesktopDirection: true
        ) == .controlArrow(.up))
    }

    @Test func sideButtonsAreSuppressedDuringGestureHold() {
        let buttons = ButtonConfig(gesture: 5, back: 3, forward: 4)

        #expect(GestureState.buttonDownDecision(
            button: 3,
            buttons: buttons,
            gestureActive: true
        ) == .suppressSideButton)
        #expect(GestureState.buttonDownDecision(
            button: 4,
            buttons: buttons,
            gestureActive: true
        ) == .suppressSideButton)
        #expect(GestureState.buttonDownDecision(
            button: 3,
            buttons: buttons,
            gestureActive: false
        ) == .commandBracket(left: true))
    }

    @Test func disabledDownConsumesGestureWithoutSendingArrow() {
        var state = GestureState()
        state.begin(at: .zero)
        state.addMovement(to: CGPoint(x: 0, y: 221), invertY: false)

        #expect(state.consumeAction(
            threshold: 220,
            downAction: .disabled,
            invertDesktopDirection: true
        ) == .disabledDown)
        #expect(state.isConsumed)
    }
}
