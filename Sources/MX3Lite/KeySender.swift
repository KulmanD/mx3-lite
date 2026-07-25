import CoreGraphics
import Darwin
import Foundation

enum ArrowDirection {
    case left
    case right
    case up
    case down

    var label: String {
        switch self {
        case .left:
            return "left"
        case .right:
            return "right"
        case .up:
            return "up"
        case .down:
            return "down"
        }
    }
}

enum KeySender {
    private static let leftArrowKey: CGKeyCode = 0x7B
    private static let rightArrowKey: CGKeyCode = 0x7C
    private static let downArrowKey: CGKeyCode = 0x7D
    private static let upArrowKey: CGKeyCode = 0x7E
    private static let leftBracketKey: CGKeyCode = 0x21
    private static let rightBracketKey: CGKeyCode = 0x1E

    static func sendControlArrow(
        _ direction: ArrowDirection,
        backend: ActionBackend,
        logger: DebugLogger,
        waitForSystemEvents: Bool = false
    ) {
        let key: CGKeyCode
        switch direction {
        case .left:
            key = leftArrowKey
        case .right:
            key = rightArrowKey
        case .up:
            key = upArrowKey
        case .down:
            key = downArrowKey
        }

        switch backend {
        case .cgEvent:
            postControlArrow(key, label: direction.label, logger: logger)
        case .systemEvents:
            postSystemEventsControlArrow(direction, logger: logger, wait: waitForSystemEvents)
        }
    }

    static func sendCommandBracket(left: Bool) {
        sendKey(left ? leftBracketKey : rightBracketKey, flags: .maskCommand)
    }

    private static func postControlArrow(_ key: CGKeyCode, label: String, logger: DebugLogger) {
        logger.log("posting HID ctrl+\(label) keyCode=\(hexKeyCode(key))")

        let source = CGEventSource(stateID: .hidSystemState)

        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        down?.flags = [.maskControl]
        down?.post(tap: .cghidEventTap)

        usleep(10_000)

        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        up?.flags = [.maskControl]
        up?.post(tap: .cghidEventTap)
    }

    private static func sendKey(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        else {
            return
        }

        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        usleep(10_000)
        up.post(tap: .cghidEventTap)
    }

    private static func postSystemEventsControlArrow(_ direction: ArrowDirection, logger: DebugLogger, wait: Bool) {
        let keyCode: Int
        switch direction {
        case .left:
            keyCode = 123
        case .right:
            keyCode = 124
        case .up:
            keyCode = 126
        case .down:
            keyCode = 125
        }

        logger.log("posting System Events ctrl+\(direction.label) keyCode=\(keyCode)")

        let operation = {
            runSystemEventsKeyCode(keyCode, logger: logger)
        }

        if wait {
            operation()
        } else {
            DispatchQueue.global(qos: .userInitiated).async(execute: operation)
        }
    }

    private static func runSystemEventsKeyCode(_ keyCode: Int, logger: DebugLogger) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-e",
            "tell application \"System Events\" to key code \(keyCode) using control down"
        ]
        process.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            logger.log("System Events backend failed: \(error)")
        }
    }

    private static func hexKeyCode(_ key: CGKeyCode) -> String {
        "0x" + String(key, radix: 16, uppercase: true)
    }
}
