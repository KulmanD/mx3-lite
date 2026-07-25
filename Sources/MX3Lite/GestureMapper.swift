import CoreGraphics
import Foundation

final class GestureMapper {
    private let config: AppConfig
    private let logger: DebugLogger
    private let liveEventDebug: Bool
    private let mxMasterRegistry: MXMasterDeviceRegistry
    private let scrollTransformer = ScrollTransformer()
    private var gestureActive = false
    private var gestureConsumed = false
    private var startLocation: CGPoint?
    private var lastLocation: CGPoint?
    private var accumulatedDx = 0.0
    private var accumulatedDy = 0.0
    private var accumulatedScrollX = 0.0
    private var accumulatedScrollY = 0.0

    init(config: AppConfig, logger: DebugLogger, liveEventDebug: Bool, mxMasterRegistry: MXMasterDeviceRegistry) {
        self.config = config
        self.logger = logger
        self.liveEventDebug = liveEventDebug
        self.mxMasterRegistry = mxMasterRegistry
    }

    var eventTypes: [CGEventType] {
        if liveEventDebug {
            return [
                .leftMouseDown,
                .leftMouseUp,
                .rightMouseDown,
                .rightMouseUp,
                .otherMouseDown,
                .otherMouseUp,
                .mouseMoved,
                .leftMouseDragged,
                .rightMouseDragged,
                .otherMouseDragged,
                .scrollWheel
            ]
        }

        var types: [CGEventType] = []
        if config.buttons.gesture != nil || config.buttons.back != nil || config.buttons.forward != nil {
            types.append(contentsOf: [.otherMouseDown, .otherMouseUp])
        }

        if config.buttons.gesture != nil {
            types.append(contentsOf: [.mouseMoved, .otherMouseDragged])
        }

        if config.scrollTransformMode != .disabled {
            types.append(.scrollWheel)
        }

        return types
    }

    func handle(type: CGEventType, event: CGEvent) -> Bool {
        let suppressed: Bool
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            suppressed = handleButtonDown(event: event)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            suppressed = handleButtonUp(event: event)
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            suppressed = handleMovement(type: type, event: event)
        case .scrollWheel:
            suppressed = handleScroll(event: event)
        default:
            suppressed = false
        }

        if liveEventDebug {
            logEvent(type: type, event: event, suppressed: suppressed)
        }

        return suppressed
    }

    private func handleButtonDown(event: CGEvent) -> Bool {
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))

        if matches(button, config.buttons.gesture) {
            gestureActive = true
            gestureConsumed = false
            startLocation = event.location
            lastLocation = event.location
            accumulatedDx = 0
            accumulatedDy = 0
            accumulatedScrollX = 0
            accumulatedScrollY = 0
            logger.log("gesture start button=\(button) startLocation=\(event.location.compactDescription)")
            return true
        }

        if gestureActive && matchesSideButton(button) {
            logger.log("side button suppressed during gesture hold button=\(button)")
            return true
        }

        if matches(button, config.buttons.back) {
            logger.log("back button=\(button) -> cmd+[")
            KeySender.sendCommandBracket(left: true)
            return true
        }

        if matches(button, config.buttons.forward) {
            logger.log("forward button=\(button) -> cmd+]")
            KeySender.sendCommandBracket(left: false)
            return true
        }

        return false
    }

    private func handleButtonUp(event: CGEvent) -> Bool {
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))

        if matches(button, config.buttons.gesture) {
            logger.log("gesture end button=\(button) final accumulatedDx=\(format(accumulatedDx)) accumulatedDy=\(format(accumulatedDy)) accumulatedScrollX=\(format(accumulatedScrollX)) accumulatedScrollY=\(format(accumulatedScrollY))")
            resetGesture()
            return true
        }

        if matchesSideButton(button) {
            return true
        }

        return false
    }

    private func handleMovement(type: CGEventType, event: CGEvent) -> Bool {
        guard gestureActive else {
            return false
        }

        let currentLocation = event.location
        let previousLocation = lastLocation ?? currentLocation
        let stepDx = Double(currentLocation.x - previousLocation.x)
        var stepDy = Double(currentLocation.y - previousLocation.y)
        if config.invertY {
            stepDy = -stepDy
        }

        accumulatedDx += stepDx
        accumulatedDy += stepDy
        lastLocation = currentLocation

        logger.log("gesture move type=\(type.label) stepDx=\(format(stepDx)) stepDy=\(format(stepDy)) accumulatedDx=\(format(accumulatedDx)) accumulatedDy=\(format(accumulatedDy))")

        if !gestureConsumed {
            evaluateGesture()
        }

        return true
    }

    private func handleScroll(event: CGEvent) -> Bool {
        guard gestureActive else {
            if let result = scrollTransformer.apply(
                to: event,
                config: config,
                mxMasterRegistry: mxMasterRegistry,
                captureDebug: liveEventDebug
            ) {
                logger.log(result.debugDescription(prefix: "scroll transform"))
            }
            return false
        }

        let axis1 = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        let axis2 = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))

        accumulatedScrollY += axis1
        accumulatedScrollX += axis2

        logger.log("gesture scroll axis1=\(format(axis1)) axis2=\(format(axis2)) accumulatedScrollX=\(format(accumulatedScrollX)) accumulatedScrollY=\(format(accumulatedScrollY))")

        if !gestureConsumed {
            evaluateGesture()
        }

        return false
    }

    private func evaluateGesture() {
        guard !gestureConsumed else {
            return
        }

        let threshold = max(config.threshold, 1)

        if accumulatedDx < -threshold {
            triggerHorizontalGesture(.left, source: "pointer")
            return
        }
        if accumulatedDx > threshold {
            triggerHorizontalGesture(.right, source: "pointer")
            return
        }
        if accumulatedDy < -threshold {
            triggerGesture(.up, source: "pointer")
            return
        }
        if accumulatedDy > threshold {
            triggerDown(source: "pointer")
            return
        }

        if accumulatedScrollX < -threshold {
            triggerHorizontalGesture(.left, source: "scroll")
            return
        }
        if accumulatedScrollX > threshold {
            triggerHorizontalGesture(.right, source: "scroll")
            return
        }
        if accumulatedScrollY < -threshold {
            triggerGesture(.up, source: "scroll")
            return
        }
        if accumulatedScrollY > threshold {
            triggerDown(source: "scroll")
        }
    }

    private func resetGesture() {
        gestureActive = false
        gestureConsumed = false
        startLocation = nil
        lastLocation = nil
        accumulatedDx = 0
        accumulatedDy = 0
        accumulatedScrollX = 0
        accumulatedScrollY = 0
    }

    private func triggerGesture(_ direction: ArrowDirection, source: String) {
        gestureConsumed = true
        logger.log("gesture \(direction.label) source=\(source) accumulatedDx=\(format(accumulatedDx)) accumulatedDy=\(format(accumulatedDy)) accumulatedScrollX=\(format(accumulatedScrollX)) accumulatedScrollY=\(format(accumulatedScrollY)) -> ctrl+\(direction.label)")
        KeySender.sendControlArrow(direction, backend: config.actionBackend, logger: logger)
    }

    private func triggerHorizontalGesture(_ physicalDirection: ArrowDirection, source: String) {
        let actionDirection = horizontalActionDirection(for: physicalDirection)
        gestureConsumed = true
        logger.log("gesture physical-\(physicalDirection.label) source=\(source) invertDesktopGestureDirection=\(config.invertDesktopGestureDirection) action=\(actionDirection.label) accumulatedDx=\(format(accumulatedDx)) accumulatedDy=\(format(accumulatedDy)) accumulatedScrollX=\(format(accumulatedScrollX)) accumulatedScrollY=\(format(accumulatedScrollY)) -> ctrl+\(actionDirection.label)")
        KeySender.sendControlArrow(actionDirection, backend: config.actionBackend, logger: logger)
    }

    private func horizontalActionDirection(for physicalDirection: ArrowDirection) -> ArrowDirection {
        guard config.invertDesktopGestureDirection else {
            return physicalDirection
        }

        switch physicalDirection {
        case .left:
            return .right
        case .right:
            return .left
        case .up, .down:
            return physicalDirection
        }
    }

    private func triggerDown(source: String) {
        switch config.downAction {
        case .ctrlDown:
            triggerGesture(.down, source: source)
        case .disabled:
            gestureConsumed = true
            logger.log("gesture down source=\(source) disabled accumulatedDx=\(format(accumulatedDx)) accumulatedDy=\(format(accumulatedDy)) accumulatedScrollX=\(format(accumulatedScrollX)) accumulatedScrollY=\(format(accumulatedScrollY))")
        }
    }

    private func logEvent(type: CGEventType, event: CGEvent, suppressed: Bool) {
        var fields = [
            "event type=\(type.label)",
            "locationX=\(format(Double(event.location.x)))",
            "locationY=\(format(Double(event.location.y)))",
            "gestureActive=\(gestureActive)",
            "gestureConsumed=\(gestureConsumed)",
            "suppressed=\(suppressed)"
        ]

        if type.isMouseButtonEvent {
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            fields.append("button=\(button)")
        }

        if type.isMouseMoveEvent {
            let deltaX = event.getIntegerValueField(.mouseEventDeltaX)
            let deltaY = event.getIntegerValueField(.mouseEventDeltaY)
            fields.append("deltaX=\(deltaX)")
            fields.append("deltaY=\(deltaY)")
            fields.append("accumulatedDx=\(format(accumulatedDx))")
            fields.append("accumulatedDy=\(format(accumulatedDy))")
        }

        if type == .scrollWheel {
            let axis1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let axis2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let pointAxis1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let pointAxis2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            fields.append("scrollAxis1=\(axis1)")
            fields.append("scrollAxis2=\(axis2)")
            fields.append("scrollPointAxis1=\(pointAxis1)")
            fields.append("scrollPointAxis2=\(pointAxis2)")
            fields.append("accumulatedScrollX=\(format(accumulatedScrollX))")
            fields.append("accumulatedScrollY=\(format(accumulatedScrollY))")
        }

        logger.log(fields.joined(separator: " "))
    }

    private func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func matches(_ button: Int, _ configuredButton: Int?) -> Bool {
        guard let configuredButton else {
            return false
        }
        return button == configuredButton
    }

    private func matchesSideButton(_ button: Int) -> Bool {
        matches(button, config.buttons.back) || matches(button, config.buttons.forward)
    }
}
