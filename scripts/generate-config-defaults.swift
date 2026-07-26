import Foundation

private struct ButtonValues: Decodable {
    let back: Int
    let forward: Int
    let gesture: Int
}

private struct DefaultValues: Decodable {
    let buttons: ButtonValues
    let threshold: Double
    let downAction: String
    let invertY: Bool
    let invertDesktopGestureDirection: Bool
    let actionBackend: String
    let scrollTransformMode: String
    let invertVerticalScroll: Bool
    let invertHorizontalScroll: Bool
    let scrollMultiplier: Double
    let smoothScroll: Bool
    let smoothScrollMode: String
    let smoothScrollFactor: Double
    let scrollDeadzone: Double
    let maxScrollStep: Double
    let scrollAcceleration: Double
    let freeSpinDamping: Double
    let ratchetStepMultiplier: Double
    let allowGlobalScrollTransform: Bool
}

private let projectRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private let values = try JSONDecoder().decode(
    DefaultValues.self,
    from: Data(contentsOf: projectRoot.appendingPathComponent("config/defaults.json"))
)

private func number(_ value: Double) -> String {
    value.rounded() == value ? String(format: "%.1f", value) : String(value)
}

private func bool(_ value: Bool) -> String {
    value ? "true" : "false"
}

private func source(app: Bool) -> String {
    let prefix = app ? "App" : ""
    return """
    enum ConfigDefaults {
        static let threshold = \(number(values.threshold))
        static let gestureButton = \(values.buttons.gesture)
        static let backButton = \(values.buttons.back)
        static let forwardButton = \(values.buttons.forward)
        static let downAction = \(prefix)DownAction.\(values.downAction)
        static let invertY = \(bool(values.invertY))
        static let invertDesktopGestureDirection = \(bool(values.invertDesktopGestureDirection))
        static let actionBackend = \(prefix)ActionBackend.\(values.actionBackend)
        static let invertVerticalScroll = \(bool(values.invertVerticalScroll))
        static let invertHorizontalScroll = \(bool(values.invertHorizontalScroll))
        static let scrollMultiplier = \(number(values.scrollMultiplier))
        static let smoothScroll = \(bool(values.smoothScroll))
        static let smoothScrollMode = \(prefix)SmoothScrollMode.\(values.smoothScrollMode)
        static let smoothScrollFactor = \(number(values.smoothScrollFactor))
        static let scrollDeadzone = \(number(values.scrollDeadzone))
        static let maxScrollStep = \(number(values.maxScrollStep))
        static let scrollAcceleration = \(number(values.scrollAcceleration))
        static let freeSpinDamping = \(number(values.freeSpinDamping))
        static let ratchetStepMultiplier = \(number(values.ratchetStepMultiplier))
        static let allowGlobalScrollTransform = \(bool(values.allowGlobalScrollTransform))
        static let scrollTransformMode = \(prefix)ScrollTransformMode.\(values.scrollTransformMode)
    }

    """
}

private let outputs = [
    projectRoot.appendingPathComponent("Sources/MX3Lite/ConfigDefaults.generated.swift"): source(app: false),
    projectRoot.appendingPathComponent("Sources/MX3AppSupport/ConfigDefaults.generated.swift"): source(app: true)
]
private let checkOnly = CommandLine.arguments.dropFirst() == ["--check"]

for (url, expected) in outputs {
    if checkOnly {
        guard (try? String(contentsOf: url, encoding: .utf8)) == expected else {
            FileHandle.standardError.write(Data("Generated defaults are stale: \(url.path)\n".utf8))
            exit(1)
        }
    } else {
        try expected.write(to: url, atomically: true, encoding: .utf8)
    }
}
