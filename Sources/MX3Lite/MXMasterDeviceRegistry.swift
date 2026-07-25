import CoreGraphics
import Foundation
import IOKit.hid

struct MXMasterDeviceInfo {
    let product: String
    let vendorID: Int
    let productID: Int?

    var description: String {
        if let productID {
            return "\(product) vendorID=0x\(String(vendorID, radix: 16, uppercase: true)) productID=0x\(String(productID, radix: 16, uppercase: true))"
        }
        return "\(product) vendorID=0x\(String(vendorID, radix: 16, uppercase: true)) productID=unknown"
    }
}

struct MXMasterScrollSignal {
    let timestamp: TimeInterval
    let product: String
    let usagePage: UInt32
    let usage: UInt32
    let value: Int
}

struct MXMasterClassification {
    let isMXMaster: Bool
    let reason: String
    let connectedDevices: [MXMasterDeviceInfo]
    let recentSignal: MXMasterScrollSignal?
    let recentSignalAgeMs: Double?
}

struct MXMasterDeviceSnapshot {
    let devices: [MXMasterDeviceInfo]
    let openResult: IOReturn
}

final class MXMasterDeviceRegistry {
    private static let logitechVendorID = 0x046D
    private let logger: DebugLogger
    private let debug: Bool
    private var manager: IOHIDManager?
    private var connectedDevices: [MXMasterDeviceInfo] = []
    private var recentScrollSignal: MXMasterScrollSignal?

    init(logger: DebugLogger, debug: Bool) {
        self.logger = logger
        self.debug = debug
    }

    static func connectedDeviceSnapshot() -> MXMasterDeviceSnapshot {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: logitechVendorID
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        guard let deviceSet = IOHIDManagerCopyDevices(manager) else {
            return MXMasterDeviceSnapshot(devices: [], openResult: openResult)
        }

        let count = CFSetGetCount(deviceSet)
        guard count > 0 else {
            return MXMasterDeviceSnapshot(devices: [], openResult: openResult)
        }

        var values = Array<UnsafeRawPointer?>(repeating: nil, count: count)
        CFSetGetValues(deviceSet, &values)
        let devices = values.compactMap { value -> MXMasterDeviceInfo? in
            guard let value else {
                return nil
            }
            return mxMasterInfo(for: unsafeBitCast(value, to: IOHIDDevice.self))
        }
        return MXMasterDeviceSnapshot(devices: devices, openResult: openResult)
    }

    func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: MXMasterDeviceRegistry.logitechVendorID
        ]

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, mxMasterDeviceMatchingCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceRemovalCallback(manager, mxMasterDeviceRemovalCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterInputValueCallback(manager, mxMasterInputValueCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            logger.log("mx master registry hid open failed: \(openResult). Input Monitoring permission may be required.")
        }

        refreshDevices()
    }

    func stop() {
        guard let manager else {
            return
        }

        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func isMXMasterScrollEvent(_ event: CGEvent) -> Bool {
        guard !connectedDevices.isEmpty else {
            return false
        }

        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        if isContinuous {
            return false
        }

        return true
    }

    func classify(scrollEvent event: CGEvent) -> MXMasterClassification {
        guard !connectedDevices.isEmpty else {
            return MXMasterClassification(
                isMXMaster: false,
                reason: "no connected Logitech MX Master HID device",
                connectedDevices: [],
                recentSignal: recentScrollSignal,
                recentSignalAgeMs: recentSignalAgeMs()
            )
        }

        let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
        if isContinuous {
            return MXMasterClassification(
                isMXMaster: false,
                reason: "continuous scroll event, likely trackpad",
                connectedDevices: connectedDevices,
                recentSignal: recentScrollSignal,
                recentSignalAgeMs: recentSignalAgeMs()
            )
        }

        if let ageMs = recentSignalAgeMs(), ageMs <= 150 {
            return MXMasterClassification(
                isMXMaster: true,
                reason: "recent MX Master HID wheel signal ageMs=\(String(format: "%.1f", ageMs))",
                connectedDevices: connectedDevices,
                recentSignal: recentScrollSignal,
                recentSignalAgeMs: ageMs
            )
        }

        return MXMasterClassification(
            isMXMaster: true,
            reason: "non-continuous scroll while MX Master is connected; CGEvent has no reliable per-device vendor/product field",
            connectedDevices: connectedDevices,
            recentSignal: recentScrollSignal,
            recentSignalAgeMs: recentSignalAgeMs()
        )
    }

    fileprivate func refreshDevices() {
        guard let manager, let deviceSet = IOHIDManagerCopyDevices(manager) else {
            connectedDevices = []
            return
        }

        let count = CFSetGetCount(deviceSet)
        guard count > 0 else {
            connectedDevices = []
            return
        }

        var values = Array<UnsafeRawPointer?>(repeating: nil, count: count)
        CFSetGetValues(deviceSet, &values)

        connectedDevices = values.compactMap { value in
            guard let value else {
                return nil
            }
            let device = unsafeBitCast(value, to: IOHIDDevice.self)
            return MXMasterDeviceRegistry.mxMasterInfo(for: device)
        }

        if debug {
            let devices = connectedDevices.map(\.description).joined(separator: " | ")
            logger.log("mx master devices: \(devices.isEmpty ? "none" : devices)")
        }
    }

    fileprivate func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)

        guard let deviceInfo = MXMasterDeviceRegistry.mxMasterInfo(for: device) else {
            return
        }

        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        guard MXMasterDeviceRegistry.isScrollUsage(usagePage: usagePage, usage: usage), intValue != 0 else {
            return
        }

        recentScrollSignal = MXMasterScrollSignal(
            timestamp: CFAbsoluteTimeGetCurrent(),
            product: deviceInfo.product,
            usagePage: usagePage,
            usage: usage,
            value: intValue
        )

        if debug {
            logger.log("mx master hid scroll product=\"\(deviceInfo.product)\" usagePage=0x\(String(usagePage, radix: 16)) usage=0x\(String(usage, radix: 16)) value=\(intValue)")
        }
    }

    private func recentSignalAgeMs() -> Double? {
        guard let recentScrollSignal else {
            return nil
        }
        return (CFAbsoluteTimeGetCurrent() - recentScrollSignal.timestamp) * 1000
    }

    private static func mxMasterInfo(for device: IOHIDDevice) -> MXMasterDeviceInfo? {
        guard let vendorID = intProperty(kIOHIDVendorIDKey as CFString, device: device), vendorID == logitechVendorID else {
            return nil
        }

        let product = stringProperty(kIOHIDProductKey as CFString, device: device) ?? "unknown"
        guard product.range(of: "MX Master", options: [.caseInsensitive, .diacriticInsensitive]) != nil else {
            return nil
        }

        return MXMasterDeviceInfo(
            product: product,
            vendorID: vendorID,
            productID: intProperty(kIOHIDProductIDKey as CFString, device: device)
        )
    }

    private static func isScrollUsage(usagePage: UInt32, usage: UInt32) -> Bool {
        if usagePage == kHIDPage_GenericDesktop && usage == UInt32(kHIDUsage_GD_Wheel) {
            return true
        }

        // Consumer AC Pan is commonly used by horizontal wheels.
        if usagePage == 0x0C && usage == 0x0238 {
            return true
        }

        return false
    }

    private static func intProperty(_ key: CFString, device: IOHIDDevice) -> Int? {
        guard let value = IOHIDDeviceGetProperty(device, key) else {
            return nil
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        return nil
    }

    private static func stringProperty(_ key: CFString, device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, key) as? String
    }
}

private let mxMasterDeviceMatchingCallback: IOHIDDeviceCallback = { context, result, sender, device in
    guard result == kIOReturnSuccess, let context else {
        return
    }
    let registry = Unmanaged<MXMasterDeviceRegistry>.fromOpaque(context).takeUnretainedValue()
    registry.refreshDevices()
}

private let mxMasterDeviceRemovalCallback: IOHIDDeviceCallback = { context, result, sender, device in
    guard result == kIOReturnSuccess, let context else {
        return
    }
    let registry = Unmanaged<MXMasterDeviceRegistry>.fromOpaque(context).takeUnretainedValue()
    registry.refreshDevices()
}

private let mxMasterInputValueCallback: IOHIDValueCallback = { context, result, sender, value in
    guard result == kIOReturnSuccess, let context else {
        return
    }
    let registry = Unmanaged<MXMasterDeviceRegistry>.fromOpaque(context).takeUnretainedValue()
    registry.handle(value: value)
}
