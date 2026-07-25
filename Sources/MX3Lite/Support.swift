import CoreGraphics
import Darwin
import Dispatch
import Foundation

final class DebugLogger {
    let isEnabled: Bool

    init(enabled: Bool) {
        self.isEnabled = enabled
    }

    func log(_ message: @autoclosure () -> String) {
        guard isEnabled else {
            return
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("[\(timestamp)] \(message())")
        fflush(stdout)
    }
}

final class SignalController {
    private var sources: [DispatchSourceSignal] = []

    func start(_ handler: @escaping () -> Void) {
        [SIGINT, SIGTERM].forEach { signalNumber in
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler(handler: handler)
            source.resume()
            sources.append(source)
        }
    }
}

struct CLIError: Error {
    let message: String
    let exitCode: Int

    init(_ message: String, exitCode: Int = 1) {
        self.message = message
        self.exitCode = exitCode
    }
}

struct CLIExit: Error {
    let exitCode: Int32
}

extension Array where Element == String {
    mutating func removeFlag(_ flag: String) -> Bool {
        guard let index = firstIndex(of: flag) else {
            return false
        }
        remove(at: index)
        return true
    }
}

extension FileHandle {
    func writeLine(_ line: String) {
        if let data = (line + "\n").data(using: .utf8) {
            write(data)
        }
    }
}

extension CGEventType {
    var label: String {
        switch self {
        case .leftMouseDown:
            return "leftMouseDown"
        case .leftMouseUp:
            return "leftMouseUp"
        case .rightMouseDown:
            return "rightMouseDown"
        case .rightMouseUp:
            return "rightMouseUp"
        case .otherMouseDown:
            return "otherMouseDown"
        case .otherMouseUp:
            return "otherMouseUp"
        case .mouseMoved:
            return "mouseMoved"
        case .leftMouseDragged:
            return "leftMouseDragged"
        case .rightMouseDragged:
            return "rightMouseDragged"
        case .otherMouseDragged:
            return "otherMouseDragged"
        case .scrollWheel:
            return "scrollWheel"
        default:
            return "type-\(rawValue)"
        }
    }

    var isMouseButtonEvent: Bool {
        switch self {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            return true
        default:
            return false
        }
    }

    var isMouseMoveEvent: Bool {
        switch self {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return true
        default:
            return false
        }
    }
}

extension CGPoint {
    var compactDescription: String {
        "(\(Int(x)),\(Int(y)))"
    }
}
