import Foundation

struct ConfigStore {
    let paths: AppPaths

    func loadOrCreate() throws -> AppConfig {
        try loadOrCreateWithSources().config
    }

    func loadOrCreateWithSources() throws -> LoadedConfig {
        if !FileManager.default.fileExists(atPath: paths.configFile.path) {
            let defaultConfig = AppConfig.default
            let data = try JSONEncoder.mx3Pretty.encode(defaultConfig)
            try data.write(to: paths.configFile, options: .atomic)
            return LoadedConfig(
                config: defaultConfig,
                configFileExisted: false,
                configFileCreated: true,
                sources: ConfigSources.all("default"),
                warnings: []
            )
        }

        guard let loadedConfig = try loadExistingWithSources() else {
            throw CLIError("config.json disappeared while reading (paths.configFile.path)")
        }
        return loadedConfig
    }

    func loadExistingWithSources() throws -> LoadedConfig? {
        guard FileManager.default.fileExists(atPath: paths.configFile.path) else {
            return nil
        }
        let data = try Data(contentsOf: paths.configFile)
        do {
            let config = try JSONDecoder().decode(AppConfig.self, from: data)
            return LoadedConfig(
                config: config,
                configFileExisted: true,
                configFileCreated: false,
                sources: ConfigSources(data: data),
                warnings: ConfigValidator.warnings(data: data, config: config)
            )
        } catch {
            throw CLIError("invalid config.json at \(paths.configFile.path): \(error)")
        }
    }
}

struct LoadedConfig {
    let config: AppConfig
    let configFileExisted: Bool
    let configFileCreated: Bool
    let sources: ConfigSources
    let warnings: [String]
}

struct ConfigSources {
    let threshold: String
    let downAction: String
    let invertY: String
    let actionBackend: String
    let invertDesktopGestureDirection: String
    let invertVerticalScroll: String
    let invertHorizontalScroll: String
    let scrollMultiplier: String
    let smoothScroll: String
    let smoothScrollMode: String
    let smoothScrollFactor: String
    let scrollDeadzone: String
    let maxScrollStep: String
    let scrollAcceleration: String
    let freeSpinDamping: String
    let ratchetStepMultiplier: String
    let allowGlobalScrollTransform: String
    let scrollTransformMode: String
    let gestureButton: String
    let backButton: String
    let forwardButton: String

    static func all(_ source: String) -> ConfigSources {
        ConfigSources(
            threshold: source,
            downAction: source,
            invertY: source,
            actionBackend: source,
            invertDesktopGestureDirection: source,
            invertVerticalScroll: source,
            invertHorizontalScroll: source,
            scrollMultiplier: source,
            smoothScroll: source,
            smoothScrollMode: source,
            smoothScrollFactor: source,
            scrollDeadzone: source,
            maxScrollStep: source,
            scrollAcceleration: source,
            freeSpinDamping: source,
            ratchetStepMultiplier: source,
            allowGlobalScrollTransform: source,
            scrollTransformMode: source,
            gestureButton: source,
            backButton: source,
            forwardButton: source
        )
    }

    init(data: Data) {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let buttons = json["buttons"] as? [String: Any]

        threshold = ConfigSources.topLevelSource("threshold", in: json)
        downAction = ConfigSources.topLevelSource("downAction", in: json)
        invertY = ConfigSources.topLevelSource("invertY", in: json)
        actionBackend = ConfigSources.topLevelSource("actionBackend", in: json)
        invertDesktopGestureDirection = ConfigSources.topLevelSource("invertDesktopGestureDirection", in: json)
        invertVerticalScroll = ConfigSources.topLevelSource("invertVerticalScroll", in: json)
        invertHorizontalScroll = ConfigSources.topLevelSource("invertHorizontalScroll", in: json)
        scrollMultiplier = ConfigSources.topLevelSource("scrollMultiplier", in: json)
        smoothScroll = ConfigSources.topLevelSource("smoothScroll", in: json)
        smoothScrollMode = ConfigSources.topLevelSource("smoothScrollMode", in: json)
        smoothScrollFactor = ConfigSources.topLevelSource("smoothScrollFactor", in: json)
        scrollDeadzone = ConfigSources.topLevelSource("scrollDeadzone", in: json)
        maxScrollStep = ConfigSources.topLevelSource("maxScrollStep", in: json)
        scrollAcceleration = ConfigSources.topLevelSource("scrollAcceleration", in: json)
        freeSpinDamping = ConfigSources.topLevelSource("freeSpinDamping", in: json)
        ratchetStepMultiplier = ConfigSources.topLevelSource("ratchetStepMultiplier", in: json)
        allowGlobalScrollTransform = ConfigSources.topLevelSource("allowGlobalScrollTransform", in: json)
        scrollTransformMode = ConfigSources.topLevelSource("scrollTransformMode", in: json)
        gestureButton = ConfigSources.buttonSource("gesture", buttons: buttons, rootHasButtons: json.keys.contains("buttons"))
        backButton = ConfigSources.buttonSource("back", buttons: buttons, rootHasButtons: json.keys.contains("buttons"))
        forwardButton = ConfigSources.buttonSource("forward", buttons: buttons, rootHasButtons: json.keys.contains("buttons"))
    }

    private init(
        threshold: String,
        downAction: String,
        invertY: String,
        actionBackend: String,
        invertDesktopGestureDirection: String,
        invertVerticalScroll: String,
        invertHorizontalScroll: String,
        scrollMultiplier: String,
        smoothScroll: String,
        smoothScrollMode: String,
        smoothScrollFactor: String,
        scrollDeadzone: String,
        maxScrollStep: String,
        scrollAcceleration: String,
        freeSpinDamping: String,
        ratchetStepMultiplier: String,
        allowGlobalScrollTransform: String,
        scrollTransformMode: String,
        gestureButton: String,
        backButton: String,
        forwardButton: String
    ) {
        self.threshold = threshold
        self.downAction = downAction
        self.invertY = invertY
        self.actionBackend = actionBackend
        self.invertDesktopGestureDirection = invertDesktopGestureDirection
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
        self.gestureButton = gestureButton
        self.backButton = backButton
        self.forwardButton = forwardButton
    }

    private static func topLevelSource(_ key: String, in json: [String: Any]) -> String {
        json.keys.contains(key) ? "config.json" : "default"
    }

    private static func buttonSource(_ key: String, buttons: [String: Any]?, rootHasButtons: Bool) -> String {
        guard rootHasButtons else {
            return "default"
        }
        guard let buttons else {
            return "config.json (invalid buttons object)"
        }
        return buttons.keys.contains(key) ? "config.json" : "config.json (missing -> disabled)"
    }
}

enum ConfigPrinter {
    static func printLoadedConfig(_ loadedConfig: LoadedConfig, path: URL) {
        let config = loadedConfig.config
        let sources = loadedConfig.sources

        print("configPath: \(path.path)")
        print("configFileExisted: \(loadedConfig.configFileExisted)")
        print("configFileCreated: \(loadedConfig.configFileCreated)")
        print("values:")
        print("  threshold: \(format(config.threshold)) source=\(sources.threshold)")
        print("  actionBackend: \(config.actionBackend.rawValue) source=\(sources.actionBackend)")
        print("  downAction: \(config.downAction.rawValue) source=\(sources.downAction)")
        print("  invertY: \(config.invertY) source=\(sources.invertY)")
        print("  invertDesktopGestureDirection: \(config.invertDesktopGestureDirection) source=\(sources.invertDesktopGestureDirection)")
        print("  buttons.gesture: \(formatOptional(config.buttons.gesture)) source=\(sources.gestureButton)")
        print("  buttons.back: \(formatOptional(config.buttons.back)) source=\(sources.backButton)")
        print("  buttons.forward: \(formatOptional(config.buttons.forward)) source=\(sources.forwardButton)")
        print("  invertVerticalScroll: \(config.invertVerticalScroll) source=\(sources.invertVerticalScroll)")
        print("  invertHorizontalScroll: \(config.invertHorizontalScroll) source=\(sources.invertHorizontalScroll)")
        print("  scrollMultiplier: \(format(config.scrollMultiplier)) source=\(sources.scrollMultiplier)")
        print("  smoothScroll: \(config.smoothScroll) source=\(sources.smoothScroll)")
        print("  smoothScrollMode: \(config.smoothScrollMode.rawValue) source=\(sources.smoothScrollMode)")
        print("  smoothScrollFactor: \(format(config.smoothScrollFactor)) source=\(sources.smoothScrollFactor)")
        print("  scrollDeadzone: \(format(config.scrollDeadzone)) source=\(sources.scrollDeadzone)")
        print("  maxScrollStep: \(format(config.maxScrollStep)) source=\(sources.maxScrollStep)")
        print("  scrollAcceleration: \(format(config.scrollAcceleration)) source=\(sources.scrollAcceleration)")
        print("  freeSpinDamping: \(format(config.freeSpinDamping)) source=\(sources.freeSpinDamping)")
        print("  ratchetStepMultiplier: \(format(config.ratchetStepMultiplier)) source=\(sources.ratchetStepMultiplier)")
        print("  allowGlobalScrollTransform: \(config.allowGlobalScrollTransform) source=\(sources.allowGlobalScrollTransform)")
        print("  scrollTransformMode: \(config.scrollTransformMode.rawValue) source=\(sources.scrollTransformMode)")

        if !loadedConfig.warnings.isEmpty {
            print("warnings:")
            loadedConfig.warnings.forEach { warning in
                print("  - \(warning)")
            }
        }
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func formatOptional(_ value: Int?) -> String {
        value.map(String.init) ?? "null"
    }
}

enum ConfigValidator {
    static func warnings(data: Data, config: AppConfig) -> [String] {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        var warnings: [String] = []

        appendEnumWarning(
            key: "actionBackend",
            value: json["actionBackend"],
            allowedValues: [ActionBackend.cgEvent.rawValue, ActionBackend.systemEvents.rawValue],
            fallback: config.actionBackend.rawValue,
            warnings: &warnings
        )
        appendEnumWarning(
            key: "scrollTransformMode",
            value: json["scrollTransformMode"],
            allowedValues: [ScrollTransformMode.mxMasterOnly.rawValue, ScrollTransformMode.global.rawValue, ScrollTransformMode.disabled.rawValue],
            fallback: config.scrollTransformMode.rawValue,
            warnings: &warnings
        )
        appendEnumWarning(
            key: "smoothScrollMode",
            value: json["smoothScrollMode"],
            allowedValues: [SmoothScrollMode.ema.rawValue, SmoothScrollMode.dampenSpikes.rawValue, SmoothScrollMode.inertia.rawValue],
            fallback: config.smoothScrollMode.rawValue,
            warnings: &warnings
        )
        appendEnumWarning(
            key: "downAction",
            value: json["downAction"],
            allowedValues: [DownAction.ctrlDown.rawValue, DownAction.disabled.rawValue],
            fallback: config.downAction.rawValue,
            warnings: &warnings
        )

        appendPositiveWarning(key: "threshold", value: json["threshold"], fallback: config.threshold, warnings: &warnings)
        appendRangeWarning(key: "smoothScrollFactor", value: json["smoothScrollFactor"], range: 0...0.95, resolved: config.smoothScrollFactor, warnings: &warnings)
        appendRangeWarning(key: "scrollMultiplier", value: json["scrollMultiplier"], range: 0.1...5, resolved: config.scrollMultiplier, warnings: &warnings)
        appendRangeWarning(key: "maxScrollStep", value: json["maxScrollStep"], range: 1...100, resolved: config.maxScrollStep, warnings: &warnings)
        appendRangeWarning(key: "scrollAcceleration", value: json["scrollAcceleration"], range: 0.1...3, resolved: config.scrollAcceleration, warnings: &warnings)
        appendRangeWarning(key: "freeSpinDamping", value: json["freeSpinDamping"], range: 0...1, resolved: config.freeSpinDamping, warnings: &warnings)
        appendRangeWarning(key: "ratchetStepMultiplier", value: json["ratchetStepMultiplier"], range: 0.1...5, resolved: config.ratchetStepMultiplier, warnings: &warnings)
        appendRangeWarning(key: "scrollDeadzone", value: json["scrollDeadzone"], range: 0...100, resolved: config.scrollDeadzone, warnings: &warnings)

        return warnings
    }

    private static func appendEnumWarning(
        key: String,
        value: Any?,
        allowedValues: [String],
        fallback: String,
        warnings: inout [String]
    ) {
        guard let value else {
            return
        }
        guard let raw = value as? String else {
            warnings.append("\(key) has invalid type; using \(fallback)")
            return
        }
        if !allowedValues.contains(raw) {
            warnings.append("\(key) has unknown value \"\(raw)\"; using \(fallback)")
        }
    }

    private static func appendPositiveWarning(key: String, value: Any?, fallback: Double, warnings: inout [String]) {
        guard let value else {
            return
        }
        guard let raw = numericValue(value) else {
            warnings.append("\(key) has invalid type; using \(format(fallback))")
            return
        }
        if !raw.isFinite || raw <= 0 {
            warnings.append("\(key) must be greater than 0; using \(format(fallback))")
        }
    }

    private static func appendRangeWarning(
        key: String,
        value: Any?,
        range: ClosedRange<Double>,
        resolved: Double,
        warnings: inout [String]
    ) {
        guard let value else {
            return
        }
        guard let raw = numericValue(value) else {
            warnings.append("\(key) has invalid type; using \(format(resolved))")
            return
        }
        if !raw.isFinite || !range.contains(raw) {
            warnings.append("\(key) outside \(format(range.lowerBound))...\(format(range.upperBound)); using \(format(resolved))")
        }
    }

    private static func numericValue(_ value: Any) -> Double? {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return nil
            }
            return number.doubleValue
        case is Bool:
            return nil
        case let number as Double:
            return number
        case let number as Float:
            return Double(number)
        case let number as Int:
            return Double(number)
        case let number as Int64:
            return Double(number)
        case let number as UInt:
            return Double(number)
        case let number as UInt64:
            return Double(number)
        default:
            return nil
        }
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

struct AppConfig: Codable {
    var threshold: Double
    var buttons: ButtonConfig
    var downAction: DownAction
    var invertY: Bool
    var invertDesktopGestureDirection: Bool
    var actionBackend: ActionBackend
    var invertVerticalScroll: Bool
    var invertHorizontalScroll: Bool
    var scrollMultiplier: Double
    var smoothScroll: Bool
    var smoothScrollMode: SmoothScrollMode
    var smoothScrollFactor: Double
    var scrollDeadzone: Double
    var maxScrollStep: Double
    var scrollAcceleration: Double
    var freeSpinDamping: Double
    var ratchetStepMultiplier: Double
    var allowGlobalScrollTransform: Bool
    var scrollTransformMode: ScrollTransformMode

    static let `default` = AppConfig(
        threshold: 220,
        buttons: ButtonConfig(gesture: 5, back: 3, forward: 4),
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

    var needsMXMasterRegistry: Bool {
        scrollTransformMode == .mxMasterOnly
    }

    enum CodingKeys: String, CodingKey {
        case threshold
        case buttons
        case downAction
        case invertY
        case invertDesktopGestureDirection
        case actionBackend
        case invertVerticalScroll
        case invertHorizontalScroll
        case scrollMultiplier
        case smoothScroll
        case smoothScrollMode
        case smoothScrollFactor
        case scrollDeadzone
        case maxScrollStep
        case scrollAcceleration
        case freeSpinDamping
        case ratchetStepMultiplier
        case allowGlobalScrollTransform
        case scrollTransformMode
    }

    init(
        threshold: Double,
        buttons: ButtonConfig,
        downAction: DownAction,
        invertY: Bool,
        invertDesktopGestureDirection: Bool,
        actionBackend: ActionBackend,
        invertVerticalScroll: Bool,
        invertHorizontalScroll: Bool,
        scrollMultiplier: Double,
        smoothScroll: Bool,
        smoothScrollMode: SmoothScrollMode,
        smoothScrollFactor: Double,
        scrollDeadzone: Double,
        maxScrollStep: Double,
        scrollAcceleration: Double,
        freeSpinDamping: Double,
        ratchetStepMultiplier: Double,
        allowGlobalScrollTransform: Bool,
        scrollTransformMode: ScrollTransformMode
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threshold = AppConfig.positiveOrDefault(AppConfig.decodeDouble(container, .threshold, defaultValue: AppConfig.default.threshold), defaultValue: AppConfig.default.threshold)
        buttons = (try? container.decodeIfPresent(ButtonConfig.self, forKey: .buttons)) ?? AppConfig.default.buttons
        downAction = AppConfig.decodeRawValue(container, .downAction, defaultValue: AppConfig.default.downAction)
        invertY = AppConfig.decodeBool(container, .invertY, defaultValue: AppConfig.default.invertY)
        invertDesktopGestureDirection = AppConfig.decodeBool(container, .invertDesktopGestureDirection, defaultValue: AppConfig.default.invertDesktopGestureDirection)
        actionBackend = AppConfig.decodeRawValue(container, .actionBackend, defaultValue: AppConfig.default.actionBackend)
        invertVerticalScroll = AppConfig.decodeBool(container, .invertVerticalScroll, defaultValue: AppConfig.default.invertVerticalScroll)
        invertHorizontalScroll = AppConfig.decodeBool(container, .invertHorizontalScroll, defaultValue: AppConfig.default.invertHorizontalScroll)
        scrollMultiplier = AppConfig.clamp(AppConfig.decodeDouble(container, .scrollMultiplier, defaultValue: AppConfig.default.scrollMultiplier), min: 0.1, max: 5, defaultValue: AppConfig.default.scrollMultiplier)
        smoothScroll = AppConfig.decodeBool(container, .smoothScroll, defaultValue: AppConfig.default.smoothScroll)
        smoothScrollMode = AppConfig.decodeRawValue(container, .smoothScrollMode, defaultValue: AppConfig.default.smoothScrollMode)
        smoothScrollFactor = AppConfig.clamp(AppConfig.decodeDouble(container, .smoothScrollFactor, defaultValue: AppConfig.default.smoothScrollFactor), min: 0, max: 0.95, defaultValue: AppConfig.default.smoothScrollFactor)
        scrollDeadzone = AppConfig.clamp(AppConfig.decodeDouble(container, .scrollDeadzone, defaultValue: AppConfig.default.scrollDeadzone), min: 0, max: 100, defaultValue: AppConfig.default.scrollDeadzone)
        maxScrollStep = AppConfig.clamp(AppConfig.decodeDouble(container, .maxScrollStep, defaultValue: AppConfig.default.maxScrollStep), min: 1, max: 100, defaultValue: AppConfig.default.maxScrollStep)
        scrollAcceleration = AppConfig.clamp(AppConfig.decodeDouble(container, .scrollAcceleration, defaultValue: AppConfig.default.scrollAcceleration), min: 0.1, max: 3, defaultValue: AppConfig.default.scrollAcceleration)
        freeSpinDamping = AppConfig.clamp(AppConfig.decodeDouble(container, .freeSpinDamping, defaultValue: AppConfig.default.freeSpinDamping), min: 0, max: 1, defaultValue: AppConfig.default.freeSpinDamping)
        ratchetStepMultiplier = AppConfig.clamp(AppConfig.decodeDouble(container, .ratchetStepMultiplier, defaultValue: AppConfig.default.ratchetStepMultiplier), min: 0.1, max: 5, defaultValue: AppConfig.default.ratchetStepMultiplier)
        allowGlobalScrollTransform = AppConfig.decodeBool(container, .allowGlobalScrollTransform, defaultValue: AppConfig.default.allowGlobalScrollTransform)
        scrollTransformMode = AppConfig.decodeRawValue(container, .scrollTransformMode, defaultValue: AppConfig.default.scrollTransformMode)
    }

    private static func decodeDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys,
        defaultValue: Double
    ) -> Double {
        (try? container.decode(Double.self, forKey: key)) ?? defaultValue
    }

    private static func decodeBool(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys,
        defaultValue: Bool
    ) -> Bool {
        (try? container.decode(Bool.self, forKey: key)) ?? defaultValue
    }

    private static func decodeRawValue<T>(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys,
        defaultValue: T
    ) -> T where T: RawRepresentable, T.RawValue == String {
        guard let rawValue = try? container.decode(String.self, forKey: key) else {
            return defaultValue
        }
        return T(rawValue: rawValue) ?? defaultValue
    }

    private static func positiveOrDefault(_ value: Double, defaultValue: Double) -> Double {
        guard value.isFinite, value > 0 else {
            return defaultValue
        }
        return value
    }

    private static func clamp(_ value: Double, min minimum: Double, max maximum: Double, defaultValue: Double) -> Double {
        guard value.isFinite else {
            return defaultValue
        }
        return Swift.min(Swift.max(value, minimum), maximum)
    }
}

struct ButtonConfig: Codable {
    var gesture: Int?
    var back: Int?
    var forward: Int?

    enum CodingKeys: String, CodingKey {
        case gesture
        case back
        case forward
    }

    init(gesture: Int?, back: Int?, forward: Int?) {
        self.gesture = gesture
        self.back = back
        self.forward = forward
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gesture = ButtonConfig.decodeOptionalInt(container, .gesture)
        back = ButtonConfig.decodeOptionalInt(container, .back)
        forward = ButtonConfig.decodeOptionalInt(container, .forward)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try encodeOptional(gesture, forKey: .gesture, into: &container)
        try encodeOptional(back, forKey: .back, into: &container)
        try encodeOptional(forward, forKey: .forward, into: &container)
    }

    private func encodeOptional(_ value: Int?, forKey key: CodingKeys, into container: inout KeyedEncodingContainer<CodingKeys>) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else {
            try container.encodeNil(forKey: key)
        }
    }

    private static func decodeOptionalInt(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        (try? container.decodeIfPresent(Int.self, forKey: key)) ?? nil
    }
}

enum DownAction: String, Codable {
    case ctrlDown
    case disabled
}

enum ActionBackend: String, Codable {
    case cgEvent
    case systemEvents
}

enum ScrollTransformMode: String, Codable {
    case mxMasterOnly
    case global
    case disabled
}

enum SmoothScrollMode: String, Codable {
    case ema
    case dampenSpikes
    case inertia
}

extension JSONEncoder {
    static var mx3Pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
