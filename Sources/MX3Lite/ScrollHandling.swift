import CoreGraphics
import Foundation

final class ScrollDebugger {
    private let config: AppConfig
    private let logger: DebugLogger
    private let mxMasterRegistry: MXMasterDeviceRegistry
    private let scrollTransformer = ScrollTransformer()

    init(config: AppConfig, logger: DebugLogger, mxMasterRegistry: MXMasterDeviceRegistry) {
        self.config = config
        self.logger = logger
        self.mxMasterRegistry = mxMasterRegistry
    }

    func handle(type: CGEventType, event: CGEvent) {
        guard type == .scrollWheel else {
            return
        }

        if let result = scrollTransformer.apply(to: event, config: config, mxMasterRegistry: mxMasterRegistry, captureDebug: true) {
            logger.log(result.debugDescription(prefix: "debug-scroll"))
        }
    }
}

struct ScrollTransformResult {
    let rawAxis1: Int64
    let rawAxis2: Int64
    let afterInversionAxis1: Double
    let afterInversionAxis2: Double
    let afterMultiplierAxis1: Double
    let afterMultiplierAxis2: Double
    let afterSmoothingAxis1: Double
    let afterSmoothingAxis2: Double
    let afterClampAxis1: Double
    let afterClampAxis2: Double
    let finalAxis1: Int64
    let finalAxis2: Int64
    let sourceStateID: Int64
    let sourceUnixProcessID: Int64
    let sourceUserData: Int64
    let sourceUserID: Int64
    let sourceGroupID: Int64
    let scrollIsContinuous: Int64
    let scrollPhase: Int64
    let momentumPhase: Int64
    let scrollCount: Int64
    let instantMouser: Int64
    let invertVerticalScroll: Bool
    let invertHorizontalScroll: Bool
    let scrollMultiplier: Double
    let smoothScroll: Bool
    let smoothScrollMode: SmoothScrollMode
    let smoothScrollFactor: Double
    let scrollDeadzone: Double
    let maxScrollStep: Double
    let scrollAcceleration: Double
    let freeSpinDamping: Double
    let ratchetStepMultiplier: Double
    let allowGlobalScrollTransform: Bool
    let scrollTransformMode: ScrollTransformMode
    let classifiedAsMXMaster: Bool
    let classificationReason: String
    let connectedMXMasterDevices: [MXMasterDeviceInfo]
    let recentMXMasterSignal: MXMasterScrollSignal?
    let recentMXMasterSignalAgeMs: Double?
    let returnedModified: Bool

    func debugDescription(prefix: String) -> String {
        [
            prefix,
            "rawDeltaAxis1=\(rawAxis1)",
            "rawDeltaAxis2=\(rawAxis2)",
            "afterInversionAxis1=\(format(afterInversionAxis1))",
            "afterInversionAxis2=\(format(afterInversionAxis2))",
            "afterMultiplierAxis1=\(format(afterMultiplierAxis1))",
            "afterMultiplierAxis2=\(format(afterMultiplierAxis2))",
            "afterSmoothingAxis1=\(format(afterSmoothingAxis1))",
            "afterSmoothingAxis2=\(format(afterSmoothingAxis2))",
            "afterMaxStepClampAxis1=\(format(afterClampAxis1))",
            "afterMaxStepClampAxis2=\(format(afterClampAxis2))",
            "finalAxis1=\(finalAxis1)",
            "finalAxis2=\(finalAxis2)",
            "sourceStateID=\(sourceStateID)",
            "sourceUnixProcessID=\(sourceUnixProcessID)",
            "sourceUserData=\(sourceUserData)",
            "sourceUserID=\(sourceUserID)",
            "sourceGroupID=\(sourceGroupID)",
            "scrollIsContinuous=\(scrollIsContinuous)",
            "scrollPhase=\(scrollPhase)",
            "momentumPhase=\(momentumPhase)",
            "scrollCount=\(scrollCount)",
            "instantMouser=\(instantMouser)",
            "invertVerticalScroll=\(invertVerticalScroll)",
            "invertHorizontalScroll=\(invertHorizontalScroll)",
            "scrollMultiplier=\(String(format: "%.3f", scrollMultiplier))",
            "smoothScroll=\(smoothScroll)",
            "smoothScrollMode=\(smoothScrollMode.rawValue)",
            "smoothScrollFactor=\(String(format: "%.3f", smoothScrollFactor))",
            "scrollDeadzone=\(String(format: "%.3f", scrollDeadzone))",
            "maxScrollStep=\(String(format: "%.3f", maxScrollStep))",
            "scrollAcceleration=\(String(format: "%.3f", scrollAcceleration))",
            "freeSpinDamping=\(String(format: "%.3f", freeSpinDamping))",
            "ratchetStepMultiplier=\(String(format: "%.3f", ratchetStepMultiplier))",
            "allowGlobalScrollTransform=\(allowGlobalScrollTransform)",
            "scrollTransformMode=\(scrollTransformMode.rawValue)",
            "classifiedAsMXMaster=\(classifiedAsMXMaster)",
            "classificationReason=\"\(classificationReason)\"",
            "connectedMXMasterDevices=\"\(connectedMXMasterDevices.map(\.description).joined(separator: " | "))\"",
            "recentMXMasterSignal=\"\(recentSignalDescription())\"",
            "returned=\(returnedModified ? "modified" : "passedThroughUnchanged")"
        ].joined(separator: " ")
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private func recentSignalDescription() -> String {
        guard let recentMXMasterSignal else {
            return "none"
        }

        let age = recentMXMasterSignalAgeMs.map { String(format: "%.1fms", $0) } ?? "unknownAge"
        return "\(recentMXMasterSignal.product) usagePage=0x\(String(recentMXMasterSignal.usagePage, radix: 16)) usage=0x\(String(recentMXMasterSignal.usage, radix: 16)) value=\(recentMXMasterSignal.value) age=\(age)"
    }
}

final class ScrollTransformer {
    private var previousAxis1 = 0.0
    private var previousAxis2 = 0.0
    private var inertiaCarryAxis1 = 0.0
    private var inertiaCarryAxis2 = 0.0

    #if DEBUG
    var smoothingState: ScrollSmoothingState {
        ScrollSmoothingState(
            previousAxis1: previousAxis1,
            previousAxis2: previousAxis2,
            inertiaCarryAxis1: inertiaCarryAxis1,
            inertiaCarryAxis2: inertiaCarryAxis2
        )
    }
    #endif

    static func shouldTransform(mode: ScrollTransformMode, classifiedAsMXMaster: Bool) -> Bool {
        switch mode {
        case .disabled:
            return false
        case .global:
            return true
        case .mxMasterOnly:
            return classifiedAsMXMaster
        }
    }

    @discardableResult
    func apply(
        to event: CGEvent,
        config: AppConfig,
        mxMasterRegistry: MXMasterDeviceRegistry,
        captureDebug: Bool
    ) -> ScrollTransformResult? {
        let rawAxis1 = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
        let rawAxis2 = event.getIntegerValueField(.scrollWheelEventDeltaAxis2)
        let classification = captureDebug ? mxMasterRegistry.classify(scrollEvent: event) : nil
        let classifiedAsMXMaster: Bool
        let passThroughReason: String

        switch config.scrollTransformMode {
        case .disabled:
            classifiedAsMXMaster = false
            passThroughReason = "scrollTransformMode disabled"
        case .global:
            classifiedAsMXMaster = false
            passThroughReason = "global mode"
        case .mxMasterOnly:
            classifiedAsMXMaster = captureDebug ? (classification?.isMXMaster ?? false) : mxMasterRegistry.isMXMasterScrollEvent(event)
            passThroughReason = classification?.reason ?? "mxMasterOnly"
        }
        let shouldTransform = ScrollTransformer.shouldTransform(
            mode: config.scrollTransformMode,
            classifiedAsMXMaster: classifiedAsMXMaster
        )

        guard shouldTransform else {
            guard captureDebug, let classification else {
                return nil
            }
            let unchangedAxis1 = Double(rawAxis1)
            let unchangedAxis2 = Double(rawAxis2)
            return makeResult(
                event: event,
                rawAxis1: rawAxis1,
                rawAxis2: rawAxis2,
                afterInversionAxis1: unchangedAxis1,
                afterInversionAxis2: unchangedAxis2,
                afterMultiplierAxis1: unchangedAxis1,
                afterMultiplierAxis2: unchangedAxis2,
                afterSmoothingAxis1: unchangedAxis1,
                afterSmoothingAxis2: unchangedAxis2,
                afterClampAxis1: unchangedAxis1,
                afterClampAxis2: unchangedAxis2,
                finalAxis1: rawAxis1,
                finalAxis2: rawAxis2,
                config: config,
                classification: classification,
                classificationReasonOverride: passThroughReason,
                returnedModified: false
            )
        }

        let rawFixedAxis1 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let rawFixedAxis2 = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        let rawPointAxis1 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let rawPointAxis2 = event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
        let inputAxis1 = canonicalDelta(integer: rawAxis1, fixed: rawFixedAxis1, point: rawPointAxis1)
        let inputAxis2 = canonicalDelta(integer: rawAxis2, fixed: rawFixedAxis2, point: rawPointAxis2)

        var afterInversionAxis1 = inputAxis1
        var afterInversionAxis2 = inputAxis2

        if config.invertVerticalScroll {
            afterInversionAxis1 *= -1
        }

        if config.invertHorizontalScroll {
            afterInversionAxis2 *= -1
        }

        let afterMultiplierAxis1 = applyAmplitudeControls(to: afterInversionAxis1, config: config)
        let afterMultiplierAxis2 = applyAmplitudeControls(to: afterInversionAxis2, config: config)

        let smoothingInputAxis1 = applyDeadzone(to: afterMultiplierAxis1, deadzone: config.scrollDeadzone)
        let smoothingInputAxis2 = applyDeadzone(to: afterMultiplierAxis2, deadzone: config.scrollDeadzone)
        var afterSmoothingAxis1 = smoothingInputAxis1
        var afterSmoothingAxis2 = smoothingInputAxis2
        if config.smoothScroll {
            (afterSmoothingAxis1, afterSmoothingAxis2) = applySmoothing(
                axis1: smoothingInputAxis1,
                axis2: smoothingInputAxis2,
                config: config
            )
        } else {
            previousAxis1 = smoothingInputAxis1
            previousAxis2 = smoothingInputAxis2
            inertiaCarryAxis1 = 0
            inertiaCarryAxis2 = 0
        }

        let afterClampAxis1 = clampStep(afterSmoothingAxis1, maxStep: config.maxScrollStep)
        let afterClampAxis2 = clampStep(afterSmoothingAxis2, maxStep: config.maxScrollStep)
        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        let roundedAxis1 = integerDelta(afterClampAxis1, continuous: isContinuous)
        let roundedAxis2 = integerDelta(afterClampAxis2, continuous: isContinuous)
        let pointAxis1 = roundedInt64(afterClampAxis1 * pointScale(fixed: rawFixedAxis1, point: rawPointAxis1))
        let pointAxis2 = roundedInt64(afterClampAxis2 * pointScale(fixed: rawFixedAxis2, point: rawPointAxis2))

        event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: roundedAxis1)
        event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: roundedAxis2)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: afterClampAxis1)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: afterClampAxis2)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: pointAxis1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: pointAxis2)

        guard captureDebug else {
            return nil
        }

        return makeResult(
            event: event,
            rawAxis1: rawAxis1,
            rawAxis2: rawAxis2,
            afterInversionAxis1: afterInversionAxis1,
            afterInversionAxis2: afterInversionAxis2,
            afterMultiplierAxis1: afterMultiplierAxis1,
            afterMultiplierAxis2: afterMultiplierAxis2,
            afterSmoothingAxis1: afterSmoothingAxis1,
            afterSmoothingAxis2: afterSmoothingAxis2,
            afterClampAxis1: afterClampAxis1,
            afterClampAxis2: afterClampAxis2,
            finalAxis1: roundedAxis1,
            finalAxis2: roundedAxis2,
            config: config,
            classification: classification ?? mxMasterRegistry.classify(scrollEvent: event),
            classificationReasonOverride: nil,
            returnedModified: true
        )
    }

    private func applyAmplitudeControls(to value: Double, config: AppConfig) -> Double {
        var adjusted = value * finiteOrDefault(config.scrollMultiplier, defaultValue: 1)
        adjusted *= finiteOrDefault(config.ratchetStepMultiplier, defaultValue: 1)

        let acceleration = finiteOrDefault(config.scrollAcceleration, defaultValue: 1)
        guard acceleration > 0, acceleration != 1, adjusted != 0 else {
            return adjusted
        }

        let magnitude = pow(abs(adjusted), acceleration)
        return adjusted < 0 ? -magnitude : magnitude
    }

    private func canonicalDelta(integer: Int64, fixed: Double, point: Int64) -> Double {
        if fixed.isFinite, fixed != 0 {
            return fixed
        }
        if point != 0 {
            return Double(point) / 10
        }
        return Double(integer)
    }

    private func pointScale(fixed: Double, point: Int64) -> Double {
        guard fixed.isFinite, fixed != 0, point != 0 else {
            // CoreGraphics-generated line and pixel events use ten points per fixed delta unit.
            return 10
        }
        let scale = Double(point) / fixed
        return scale.isFinite && scale > 0 ? scale : 10
    }

    private func integerDelta(_ value: Double, continuous: Bool) -> Int64 {
        guard value.isFinite, value != 0 else {
            return 0
        }
        // Match CoreGraphics pixel events while retaining the existing nearest-line behavior.
        let rounded = roundedInt64(continuous ? value.rounded(.towardZero) : value.rounded())
        if continuous, rounded == 0 {
            return value < 0 ? -1 : 1
        }
        return rounded
    }

    private func roundedInt64(_ value: Double) -> Int64 {
        guard value.isFinite else {
            return 0
        }
        if value >= Double(Int64.max) {
            return Int64.max
        }
        if value <= Double(Int64.min) {
            return Int64.min
        }
        return Int64(value.rounded())
    }

    private func applySmoothing(axis1: Double, axis2: Double, config: AppConfig) -> (Double, Double) {
        switch config.smoothScrollMode {
        case .ema:
            let factor = clamp(finiteOrDefault(config.smoothScrollFactor, defaultValue: 0.35), min: 0, max: 0.95)
            previousAxis1 = factor * previousAxis1 + (1 - factor) * axis1
            previousAxis2 = factor * previousAxis2 + (1 - factor) * axis2
            boundSmoothingState(config: config)
            return (previousAxis1, previousAxis2)
        case .dampenSpikes:
            let axis1 = dampenSpike(axis1, maxStep: config.maxScrollStep, damping: config.freeSpinDamping)
            let axis2 = dampenSpike(axis2, maxStep: config.maxScrollStep, damping: config.freeSpinDamping)
            previousAxis1 = axis1
            previousAxis2 = axis2
            boundSmoothingState(config: config)
            return (axis1, axis2)
        case .inertia:
            let releaseFactor = clamp(1 - finiteOrDefault(config.smoothScrollFactor, defaultValue: 0.35), min: 0.1, max: 1)
            inertiaCarryAxis1 += axis1
            inertiaCarryAxis2 += axis2
            boundSmoothingState(config: config)
            let outputAxis1 = inertiaCarryAxis1 * releaseFactor
            let outputAxis2 = inertiaCarryAxis2 * releaseFactor
            inertiaCarryAxis1 -= outputAxis1
            inertiaCarryAxis2 -= outputAxis2
            previousAxis1 = outputAxis1
            previousAxis2 = outputAxis2
            boundSmoothingState(config: config)
            return (outputAxis1, outputAxis2)
        }
    }

    private func boundSmoothingState(config: AppConfig) {
        let maxStep = max(1, finiteOrDefault(config.maxScrollStep, defaultValue: 8))
        let limit = max(64, maxStep * 4)
        previousAxis1 = clamp(previousAxis1, min: -limit, max: limit)
        previousAxis2 = clamp(previousAxis2, min: -limit, max: limit)
        inertiaCarryAxis1 = clamp(inertiaCarryAxis1, min: -limit, max: limit)
        inertiaCarryAxis2 = clamp(inertiaCarryAxis2, min: -limit, max: limit)
    }

    private func applyDeadzone(to value: Double, deadzone: Double) -> Double {
        let deadzone = max(0, finiteOrDefault(deadzone, defaultValue: 0))
        guard deadzone > 0 else {
            return value
        }
        return abs(value) <= deadzone ? 0 : value
    }

    private func dampenSpike(_ value: Double, maxStep: Double, damping: Double) -> Double {
        let maxStep = max(0, finiteOrDefault(maxStep, defaultValue: 8))
        guard maxStep > 0, abs(value) > maxStep else {
            return value
        }

        let damping = clamp(finiteOrDefault(damping, defaultValue: 0.75), min: 0, max: 1)
        let dampedMagnitude = maxStep * damping
        return value < 0 ? -dampedMagnitude : dampedMagnitude
    }

    private func clampStep(_ value: Double, maxStep: Double) -> Double {
        let maxStep = max(0, finiteOrDefault(maxStep, defaultValue: 8))
        guard maxStep > 0 else {
            return value
        }
        return clamp(value, min: -maxStep, max: maxStep)
    }

    private func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
        Swift.min(Swift.max(value, minimum), maximum)
    }

    private func finiteOrDefault(_ value: Double, defaultValue: Double) -> Double {
        value.isFinite ? value : defaultValue
    }

    private func makeResult(
        event: CGEvent,
        rawAxis1: Int64,
        rawAxis2: Int64,
        afterInversionAxis1: Double,
        afterInversionAxis2: Double,
        afterMultiplierAxis1: Double,
        afterMultiplierAxis2: Double,
        afterSmoothingAxis1: Double,
        afterSmoothingAxis2: Double,
        afterClampAxis1: Double,
        afterClampAxis2: Double,
        finalAxis1: Int64,
        finalAxis2: Int64,
        config: AppConfig,
        classification: MXMasterClassification,
        classificationReasonOverride: String?,
        returnedModified: Bool
    ) -> ScrollTransformResult {
        ScrollTransformResult(
            rawAxis1: rawAxis1,
            rawAxis2: rawAxis2,
            afterInversionAxis1: afterInversionAxis1,
            afterInversionAxis2: afterInversionAxis2,
            afterMultiplierAxis1: afterMultiplierAxis1,
            afterMultiplierAxis2: afterMultiplierAxis2,
            afterSmoothingAxis1: afterSmoothingAxis1,
            afterSmoothingAxis2: afterSmoothingAxis2,
            afterClampAxis1: afterClampAxis1,
            afterClampAxis2: afterClampAxis2,
            finalAxis1: finalAxis1,
            finalAxis2: finalAxis2,
            sourceStateID: event.getIntegerValueField(.eventSourceStateID),
            sourceUnixProcessID: event.getIntegerValueField(.eventSourceUnixProcessID),
            sourceUserData: event.getIntegerValueField(.eventSourceUserData),
            sourceUserID: event.getIntegerValueField(.eventSourceUserID),
            sourceGroupID: event.getIntegerValueField(.eventSourceGroupID),
            scrollIsContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous),
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            scrollCount: event.getIntegerValueField(.scrollWheelEventScrollCount),
            instantMouser: event.getIntegerValueField(.scrollWheelEventInstantMouser),
            invertVerticalScroll: config.invertVerticalScroll,
            invertHorizontalScroll: config.invertHorizontalScroll,
            scrollMultiplier: config.scrollMultiplier,
            smoothScroll: config.smoothScroll,
            smoothScrollMode: config.smoothScrollMode,
            smoothScrollFactor: config.smoothScrollFactor,
            scrollDeadzone: config.scrollDeadzone,
            maxScrollStep: config.maxScrollStep,
            scrollAcceleration: config.scrollAcceleration,
            freeSpinDamping: config.freeSpinDamping,
            ratchetStepMultiplier: config.ratchetStepMultiplier,
            allowGlobalScrollTransform: config.allowGlobalScrollTransform,
            scrollTransformMode: config.scrollTransformMode,
            classifiedAsMXMaster: classification.isMXMaster,
            classificationReason: classificationReasonOverride ?? classification.reason,
            connectedMXMasterDevices: classification.connectedDevices,
            recentMXMasterSignal: classification.recentSignal,
            recentMXMasterSignalAgeMs: classification.recentSignalAgeMs,
            returnedModified: returnedModified
        )
    }
}

#if DEBUG
struct ScrollSmoothingState: Equatable {
    let previousAxis1: Double
    let previousAxis2: Double
    let inertiaCarryAxis1: Double
    let inertiaCarryAxis2: Double
}
#endif
