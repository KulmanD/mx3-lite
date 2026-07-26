import CoreGraphics
import Foundation

final class GestureMapper {
    private let config: AppConfig
    private let logger: DebugLogger
    private let liveEventDebug: Bool
    private let mxMasterRegistry: MXMasterDeviceRegistry
    private let scrollTransformer = ScrollTransformer()
    private var gestureState = GestureState()
    var onGestureActivityChanged: ((Bool) -> Void)?

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

        return primaryEventTypes + movementEventTypes
    }

    var primaryEventTypes: [CGEventType] {
        var types: [CGEventType] = []
        if config.buttons.gesture != nil || config.buttons.back != nil || config.buttons.forward != nil {
            types.append(contentsOf: [.otherMouseDown, .otherMouseUp])
        }

        if config.scrollTransformMode != .disabled {
            types.append(.scrollWheel)
        }

        return types
    }

    var movementEventTypes: [CGEventType] {
        config.buttons.gesture == nil ? [] : [.mouseMoved, .otherMouseDragged]
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

    func cancelGestureForEventTapInterruption() {
        guard gestureState.isActive else {
            return
        }

        logger.log("active gesture cancelled after event tap interruption")
        gestureState.end()
        onGestureActivityChanged?(false)
    }

#if DEBUG
    var gestureStateForTesting: GestureState {
        gestureState
    }
#endif

    private func handleButtonDown(event: CGEvent) -> Bool {
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        if gestureState.isActive {
            _ = cancelGestureIfStale(event: event)
        }

        switch GestureState.buttonDownDecision(button: button, buttons: config.buttons, gestureActive: gestureState.isActive) {
        case .beginGesture:
            gestureState.begin(at: event.location, timestamp: event.timestamp)
            onGestureActivityChanged?(true)
            logger.log("gesture start button=\(button) startLocation=\(event.location.compactDescription)")
            return true
        case .suppressSideButton:
            logger.log("side button suppressed during gesture hold button=\(button)")
            return true
        case .commandBracket(let left):
            logger.log("\(left ? "back" : "forward") button=\(button) -> cmd+\(left ? "[" : "]")")
            KeySender.sendCommandBracket(left: left)
            return true
        case .passThrough:
            return false
        }
    }

    private func handleButtonUp(event: CGEvent) -> Bool {
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let staleGestureCancelled = gestureState.isActive && cancelGestureIfStale(event: event)

        if matches(button, config.buttons.gesture) {
            if !staleGestureCancelled {
                logger.log("gesture end button=\(button) final accumulatedDx=\(format(gestureState.accumulatedDx)) accumulatedDy=\(format(gestureState.accumulatedDy)) accumulatedScrollX=\(format(gestureState.accumulatedScrollX)) accumulatedScrollY=\(format(gestureState.accumulatedScrollY))")
                gestureState.end()
                onGestureActivityChanged?(false)
            }
            return true
        }

        if matchesSideButton(button) {
            return true
        }

        return false
    }

    private func handleMovement(type: CGEventType, event: CGEvent) -> Bool {
        guard gestureState.isActive else {
            return false
        }
        guard !cancelGestureIfStale(event: event) else {
            return false
        }

        let currentLocation = event.location
        let previousLocation = gestureState.lastLocation ?? currentLocation
        let stepDx = Double(currentLocation.x - previousLocation.x)
        let rawStepDy = Double(currentLocation.y - previousLocation.y)
        let stepDy = config.invertY ? -rawStepDy : rawStepDy
        gestureState.addMovement(to: currentLocation, invertY: config.invertY)

        logger.log("gesture move type=\(type.label) stepDx=\(format(stepDx)) stepDy=\(format(stepDy)) accumulatedDx=\(format(gestureState.accumulatedDx)) accumulatedDy=\(format(gestureState.accumulatedDy))")

        evaluateGesture(source: "pointer")

        return true
    }

    private func handleScroll(event: CGEvent) -> Bool {
        guard gestureState.isActive else {
            transformInactiveScroll(event: event)
            return false
        }
        guard !cancelGestureIfStale(event: event) else {
            transformInactiveScroll(event: event)
            return false
        }

        let axis1 = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        let axis2 = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))

        gestureState.addScroll(axis1: axis1, axis2: axis2)

        logger.log("gesture scroll axis1=\(format(axis1)) axis2=\(format(axis2)) accumulatedScrollX=\(format(gestureState.accumulatedScrollX)) accumulatedScrollY=\(format(gestureState.accumulatedScrollY))")

        evaluateGesture(source: "scroll")

        return false
    }

    private func cancelGestureIfStale(event: CGEvent) -> Bool {
        guard gestureState.isStale(at: event.timestamp) else {
            return false
        }

        logger.log("stale gesture cancelled after \(Double(event.timestamp - (gestureState.startedAt ?? event.timestamp)) / 1_000_000_000) seconds")
        gestureState.end()
        onGestureActivityChanged?(false)
        return true
    }

    private func transformInactiveScroll(event: CGEvent) {
        if let result = scrollTransformer.apply(
            to: event,
            config: config,
            mxMasterRegistry: mxMasterRegistry,
            captureDebug: liveEventDebug
        ) {
            logger.log(result.debugDescription(prefix: "scroll transform"))
        }
    }

    private func evaluateGesture(source: String) {
        guard let action = gestureState.consumeAction(
            threshold: config.threshold,
            downAction: config.downAction,
            invertDesktopDirection: config.invertDesktopGestureDirection
        ) else {
            return
        }

        switch action {
        case .controlArrow(let direction):
            logger.log("gesture action=ctrl+\(direction.label) source=\(source) invertDesktopGestureDirection=\(config.invertDesktopGestureDirection) accumulatedDx=\(format(gestureState.accumulatedDx)) accumulatedDy=\(format(gestureState.accumulatedDy)) accumulatedScrollX=\(format(gestureState.accumulatedScrollX)) accumulatedScrollY=\(format(gestureState.accumulatedScrollY))")
            KeySender.sendControlArrow(direction, backend: config.actionBackend, logger: logger)
        case .disabledDown:
            logger.log("gesture down source=\(source) disabled accumulatedDx=\(format(gestureState.accumulatedDx)) accumulatedDy=\(format(gestureState.accumulatedDy)) accumulatedScrollX=\(format(gestureState.accumulatedScrollX)) accumulatedScrollY=\(format(gestureState.accumulatedScrollY))")
        }
    }

    private func logEvent(type: CGEventType, event: CGEvent, suppressed: Bool) {
        var fields = [
            "event type=\(type.label)",
            "locationX=\(format(Double(event.location.x)))",
            "locationY=\(format(Double(event.location.y)))",
            "gestureActive=\(gestureState.isActive)",
            "gestureConsumed=\(gestureState.isConsumed)",
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
            fields.append("accumulatedDx=\(format(gestureState.accumulatedDx))")
            fields.append("accumulatedDy=\(format(gestureState.accumulatedDy))")
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
            fields.append("accumulatedScrollX=\(format(gestureState.accumulatedScrollX))")
            fields.append("accumulatedScrollY=\(format(gestureState.accumulatedScrollY))")
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
