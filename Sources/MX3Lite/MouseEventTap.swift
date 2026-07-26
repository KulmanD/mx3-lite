import CoreGraphics
import Foundation

enum MouseEventTapMode {
    case inspect
    case map(GestureMapper)
    case debugScroll(ScrollDebugger)

    var tapOptions: CGEventTapOptions {
        switch self {
        case .inspect:
            return .listenOnly
        case .map, .debugScroll:
            return .defaultTap
        }
    }

    var eventTypes: [CGEventType] {
        switch self {
        case .inspect:
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
        case .map(let mapper):
            return mapper.eventTypes
        case .debugScroll:
            return [.scrollWheel]
        }
    }
}

final class MouseEventTap {
    private let mode: MouseEventTapMode
    private let configuredEventTypes: [CGEventType]
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isStarted = false
    private var shouldBeEnabled = false
    private var recoveryMessagePrinted = false

    init(mode: MouseEventTapMode, eventTypes: [CGEventType]? = nil) throws {
        self.mode = mode
        self.configuredEventTypes = eventTypes ?? mode.eventTypes
        try createTap()
    }

    func start(enabled: Bool = true) {
        guard let runLoopSource else {
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        isStarted = true
        setEnabled(enabled)
    }

    func setEnabled(_ enabled: Bool) {
        shouldBeEnabled = enabled
        guard isStarted, let machPort else {
            return
        }
        CGEvent.tapEnable(tap: machPort, enable: enabled)
    }

    func stop() {
        setEnabled(false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        isStarted = false
    }

    private func createTap() throws {
        let eventTypes = configuredEventTypes
        guard !eventTypes.isEmpty else {
            throw CLIError("no mouse or scroll events are enabled by config")
        }
        let eventMask = MouseEventTap.eventMask(eventTypes)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: mode.tapOptions,
            eventsOfInterest: eventMask,
            callback: mouseEventTapCallback,
            userInfo: userInfo
        ) else {
            throw CLIError("could not create event tap. Grant Accessibility permission, then retry.")
        }

        machPort = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    }

    private static func eventMask(_ types: [CGEventType]) -> CGEventMask {
        types.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << CGEventMask(type.rawValue))
        }
    }

    fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if case .map(let mapper) = mode {
                mapper.cancelGestureForEventTapInterruption()
            }

            if shouldBeEnabled, let machPort {
                CGEvent.tapEnable(tap: machPort, enable: true)
            }
            logTapRecovery()
            return Unmanaged.passUnretained(event)
        }

        switch mode {
        case .inspect:
            EventInspector.printEvent(type: type, event: event)
            return Unmanaged.passUnretained(event)
        case .map(let mapper):
            if mapper.handle(type: type, event: event) {
                return nil
            }
            return Unmanaged.passUnretained(event)
        case .debugScroll(let debugger):
            debugger.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
    }

    private func logTapRecovery() {
        guard !recoveryMessagePrinted else {
            return
        }
        recoveryMessagePrinted = true
        FileHandle.standardError.writeLine("mx3-lite: event tap re-enabled; gesture reset")
    }
}

private let mouseEventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let tap = Unmanaged<MouseEventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(proxy: proxy, type: type, event: event)
}

enum EventInspector {
    static func printEvent(type: CGEventType, event: CGEvent) {
        switch type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            let button = event.getIntegerValueField(.mouseEventButtonNumber)
            let clickState = event.getIntegerValueField(.mouseEventClickState)
            print("cg button \(type.label) button=\(button) clickState=\(clickState) loc=\(event.location.compactDescription)")
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let deltaX = event.getIntegerValueField(.mouseEventDeltaX)
            let deltaY = event.getIntegerValueField(.mouseEventDeltaY)
            print("cg move \(type.label) dx=\(deltaX) dy=\(deltaY) loc=\(event.location.compactDescription)")
        case .scrollWheel:
            let axis1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let axis2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
            let pointAxis1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            let pointAxis2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            print("cg scroll delta1=\(axis1) delta2=\(axis2) point1=\(pointAxis1) point2=\(pointAxis2) loc=\(event.location.compactDescription)")
        default:
            break
        }
        fflush(stdout)
    }
}
