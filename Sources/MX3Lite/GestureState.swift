import CoreGraphics

enum GestureAction: Equatable {
    case controlArrow(ArrowDirection)
    case disabledDown
}

enum ButtonDownDecision: Equatable {
    case beginGesture
    case suppressSideButton
    case commandBracket(left: Bool)
    case passThrough
}

struct GestureState {
    private(set) var isActive = false
    private(set) var isConsumed = false
    private(set) var lastLocation: CGPoint?
    private(set) var accumulatedDx = 0.0
    private(set) var accumulatedDy = 0.0
    private(set) var accumulatedScrollX = 0.0
    private(set) var accumulatedScrollY = 0.0

    static func buttonDownDecision(button: Int, buttons: ButtonConfig, gestureActive: Bool) -> ButtonDownDecision {
        if button == buttons.gesture {
            return .beginGesture
        }
        if button == buttons.back {
            return gestureActive ? .suppressSideButton : .commandBracket(left: true)
        }
        if button == buttons.forward {
            return gestureActive ? .suppressSideButton : .commandBracket(left: false)
        }
        return .passThrough
    }

    mutating func begin(at location: CGPoint) {
        isActive = true
        isConsumed = false
        lastLocation = location
        accumulatedDx = 0
        accumulatedDy = 0
        accumulatedScrollX = 0
        accumulatedScrollY = 0
    }

    mutating func end() {
        isActive = false
        isConsumed = false
        lastLocation = nil
        accumulatedDx = 0
        accumulatedDy = 0
        accumulatedScrollX = 0
        accumulatedScrollY = 0
    }

    mutating func addMovement(to location: CGPoint, invertY: Bool) {
        guard isActive else {
            return
        }

        let previousLocation = lastLocation ?? location
        accumulatedDx += Double(location.x - previousLocation.x)
        let stepDy = Double(location.y - previousLocation.y)
        accumulatedDy += invertY ? -stepDy : stepDy
        lastLocation = location
    }

    mutating func addScroll(axis1: Double, axis2: Double) {
        guard isActive else {
            return
        }
        accumulatedScrollY += axis1
        accumulatedScrollX += axis2
    }

    mutating func consumeAction(
        threshold: Double,
        downAction: DownAction,
        invertDesktopDirection: Bool
    ) -> GestureAction? {
        guard isActive, !isConsumed else {
            return nil
        }

        let threshold = max(threshold, 1)
        let physicalDirection: ArrowDirection?
        if accumulatedDx < -threshold {
            physicalDirection = .left
        } else if accumulatedDx > threshold {
            physicalDirection = .right
        } else if accumulatedDy < -threshold {
            physicalDirection = .up
        } else if accumulatedDy > threshold {
            physicalDirection = .down
        } else if accumulatedScrollX < -threshold {
            physicalDirection = .left
        } else if accumulatedScrollX > threshold {
            physicalDirection = .right
        } else if accumulatedScrollY < -threshold {
            physicalDirection = .up
        } else if accumulatedScrollY > threshold {
            physicalDirection = .down
        } else {
            physicalDirection = nil
        }

        guard let physicalDirection else {
            return nil
        }

        isConsumed = true
        switch physicalDirection {
        case .left:
            return .controlArrow(invertDesktopDirection ? .right : .left)
        case .right:
            return .controlArrow(invertDesktopDirection ? .left : .right)
        case .up:
            return .controlArrow(.up)
        case .down:
            return downAction == .ctrlDown ? .controlArrow(.down) : .disabledDown
        }
    }
}
