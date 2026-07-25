import Foundation

public struct AppButtonSettings: Codable, Equatable, Sendable {
    public var gesture: Int?
    public var back: Int?
    public var forward: Int?

    public init(gesture: Int?, back: Int?, forward: Int?) {
        self.gesture = gesture
        self.back = back
        self.forward = forward
    }

    private enum CodingKeys: String, CodingKey {
        case gesture
        case back
        case forward
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gesture = try? container.decodeIfPresent(Int.self, forKey: .gesture)
        back = try? container.decodeIfPresent(Int.self, forKey: .back)
        forward = try? container.decodeIfPresent(Int.self, forKey: .forward)
    }
}

public enum AppDownAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case ctrlDown
    case disabled

    public var id: String { rawValue }
    public var title: String { self == .ctrlDown ? "Control + Down" : "Disabled" }
}

public enum AppActionBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case cgEvent
    case systemEvents

    public var id: String { rawValue }
    public var title: String { self == .systemEvents ? "System Events" : "CGEvent" }
}

public enum AppScrollTransformMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case mxMasterOnly
    case global
    case disabled

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .mxMasterOnly: return "MX Master only"
        case .global: return "All pointing devices"
        case .disabled: return "Disabled"
        }
    }
}

public enum AppSmoothScrollMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case ema
    case dampenSpikes
    case inertia

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .ema: return "Balanced (EMA)"
        case .dampenSpikes: return "Dampen free-spin spikes"
        case .inertia: return "Inertia (experimental)"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var threshold: Double
    public var buttons: AppButtonSettings
    public var downAction: AppDownAction
    public var invertY: Bool
    public var invertDesktopGestureDirection: Bool
    public var actionBackend: AppActionBackend
    public var invertVerticalScroll: Bool
    public var invertHorizontalScroll: Bool
    public var scrollMultiplier: Double
    public var smoothScroll: Bool
    public var smoothScrollMode: AppSmoothScrollMode
    public var smoothScrollFactor: Double
    public var scrollDeadzone: Double
    public var maxScrollStep: Double
    public var scrollAcceleration: Double
    public var freeSpinDamping: Double
    public var ratchetStepMultiplier: Double
    public var allowGlobalScrollTransform: Bool
    public var scrollTransformMode: AppScrollTransformMode

    public static let `default` = AppSettings(
        threshold: 220,
        buttons: AppButtonSettings(gesture: 5, back: 3, forward: 4),
        downAction: .ctrlDown,
        invertY: false,
        invertDesktopGestureDirection: true,
        actionBackend: .systemEvents,
        invertVerticalScroll: true,
        invertHorizontalScroll: false,
        scrollMultiplier: 1,
        smoothScroll: true,
        smoothScrollMode: .ema,
        smoothScrollFactor: 0.35,
        scrollDeadzone: 0,
        maxScrollStep: 8,
        scrollAcceleration: 1,
        freeSpinDamping: 0.75,
        ratchetStepMultiplier: 1,
        allowGlobalScrollTransform: false,
        scrollTransformMode: .mxMasterOnly
    )

    public init(
        threshold: Double,
        buttons: AppButtonSettings,
        downAction: AppDownAction,
        invertY: Bool,
        invertDesktopGestureDirection: Bool,
        actionBackend: AppActionBackend,
        invertVerticalScroll: Bool,
        invertHorizontalScroll: Bool,
        scrollMultiplier: Double,
        smoothScroll: Bool,
        smoothScrollMode: AppSmoothScrollMode,
        smoothScrollFactor: Double,
        scrollDeadzone: Double,
        maxScrollStep: Double,
        scrollAcceleration: Double,
        freeSpinDamping: Double,
        ratchetStepMultiplier: Double,
        allowGlobalScrollTransform: Bool,
        scrollTransformMode: AppScrollTransformMode
    ) {
        self.threshold = threshold
        self.buttons = buttons
        self.downAction = downAction
        self.invertY = invertY
        self.invertDesktopGestureDirection = invertDesktopGestureDirection
        self.actionBackend = actionBackend
        self.invertVerticalScroll = invertVerticalScroll
        self.invertHorizontalScroll = invertHorizontalScroll
        self.scrollMultiplier = scrollMultiplier
        self.smoothScroll = smoothScroll
        self.smoothScrollMode = smoothScrollMode
        self.smoothScrollFactor = smoothScrollFactor
        self.scrollDeadzone = scrollDeadzone
        self.maxScrollStep = maxScrollStep
        self.scrollAcceleration = scrollAcceleration
        self.freeSpinDamping = freeSpinDamping
        self.ratchetStepMultiplier = ratchetStepMultiplier
        self.allowGlobalScrollTransform = allowGlobalScrollTransform
        self.scrollTransformMode = scrollTransformMode
    }

    public var normalized: AppSettings {
        var value = self
        value.threshold = Self.positive(threshold, fallback: Self.default.threshold)
        value.scrollMultiplier = Self.clamped(scrollMultiplier, 0.1...5, fallback: Self.default.scrollMultiplier)
        value.smoothScrollFactor = Self.clamped(smoothScrollFactor, 0...0.95, fallback: Self.default.smoothScrollFactor)
        value.scrollDeadzone = Self.clamped(scrollDeadzone, 0...100, fallback: Self.default.scrollDeadzone)
        value.maxScrollStep = Self.clamped(maxScrollStep, 1...100, fallback: Self.default.maxScrollStep)
        value.scrollAcceleration = Self.clamped(scrollAcceleration, 0.1...3, fallback: Self.default.scrollAcceleration)
        value.freeSpinDamping = Self.clamped(freeSpinDamping, 0...1, fallback: Self.default.freeSpinDamping)
        value.ratchetStepMultiplier = Self.clamped(ratchetStepMultiplier, 0.1...5, fallback: Self.default.ratchetStepMultiplier)
        return value
    }

    public var validationWarnings: [String] {
        var warnings: [String] = []
        appendWarning(threshold > 0 && threshold.isFinite, "Gesture threshold must be greater than zero.", to: &warnings)
        appendWarning((0.1...5).contains(scrollMultiplier) && scrollMultiplier.isFinite, "Scroll multiplier must be between 0.1 and 5.", to: &warnings)
        appendWarning((0...0.95).contains(smoothScrollFactor) && smoothScrollFactor.isFinite, "Smoothing factor must be between 0 and 0.95.", to: &warnings)
        appendWarning((1...100).contains(maxScrollStep) && maxScrollStep.isFinite, "Maximum scroll step must be between 1 and 100.", to: &warnings)
        return warnings
    }

    private static func positive(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value > 0 ? value : fallback
    }

    private static func clamped(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private func appendWarning(_ condition: Bool, _ warning: String, to warnings: inout [String]) {
        if !condition { warnings.append(warning) }
    }
}

public struct LoadedAppSettings: Sendable {
    public let settings: AppSettings
    public let created: Bool

    public init(settings: AppSettings, created: Bool) {
        self.settings = settings
        self.created = created
    }
}

public struct AppSettingsStore: Sendable {
    public let configURL: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        configURL = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("mx3-lite", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    public func loadOrCreate() throws -> LoadedAppSettings {
        if !FileManager.default.fileExists(atPath: configURL.path) {
            try save(.default)
            return LoadedAppSettings(settings: .default, created: true)
        }

        let data = try Data(contentsOf: configURL)
        return LoadedAppSettings(settings: try decodeSettings(data), created: false)
    }

    public func save(_ settings: AppSettings) throws {
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings.normalized).write(to: configURL, options: .atomic)
    }

    private func decodeSettings(_ data: Data) throws -> AppSettings {
        let encoder = JSONEncoder()
        let defaultData = try encoder.encode(AppSettings.default)
        guard
            var merged = try JSONSerialization.jsonObject(with: defaultData) as? [String: Any],
            let supplied = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw CocoaError(.fileReadCorruptFile)
        }

        supplied.forEach { merged[$0.key] = $0.value }
        restoreUnknownEnum(
            "actionBackend",
            in: &merged,
            allowed: Set(AppActionBackend.allCases.map(\.rawValue)),
            fallback: AppSettings.default.actionBackend.rawValue
        )
        restoreUnknownEnum(
            "downAction",
            in: &merged,
            allowed: Set(AppDownAction.allCases.map(\.rawValue)),
            fallback: AppSettings.default.downAction.rawValue
        )
        restoreUnknownEnum(
            "scrollTransformMode",
            in: &merged,
            allowed: Set(AppScrollTransformMode.allCases.map(\.rawValue)),
            fallback: AppSettings.default.scrollTransformMode.rawValue
        )
        restoreUnknownEnum(
            "smoothScrollMode",
            in: &merged,
            allowed: Set(AppSmoothScrollMode.allCases.map(\.rawValue)),
            fallback: AppSettings.default.smoothScrollMode.rawValue
        )

        let mergedData = try JSONSerialization.data(withJSONObject: merged)
        return try JSONDecoder().decode(AppSettings.self, from: mergedData)
    }

    private func restoreUnknownEnum(
        _ key: String,
        in values: inout [String: Any],
        allowed: Set<String>,
        fallback: String
    ) {
        guard let raw = values[key] as? String, allowed.contains(raw) else {
            values[key] = fallback
            return
        }
    }
}
