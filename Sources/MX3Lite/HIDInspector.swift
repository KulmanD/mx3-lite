import Foundation
import IOKit.hid

final class HIDInspector {
    private var manager: IOHIDManager?

    func start() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager

        let mouseMatching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse
        ]
        let pointerMatching: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Pointer
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, [mouseMatching, pointerMatching] as CFArray)
        IOHIDManagerRegisterInputValueCallback(manager, hidInputValueCallback, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult != kIOReturnSuccess {
            print("hid open failed: \(openResult). Input Monitoring permission may be required.")
        }
    }

    func stop() {
        guard let manager else {
            return
        }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    fileprivate func handle(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)

        guard usagePage == kHIDPage_Button || usagePage == kHIDPage_GenericDesktop else {
            return
        }

        let intValue = IOHIDValueGetIntegerValue(value)
        let label = HIDInspector.label(usagePage: usagePage, usage: usage)
        let device = IOHIDElementGetDevice(element)
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "unknown"
        print("hid product=\"\(product)\" usagePage=0x\(String(usagePage, radix: 16)) usage=0x\(String(usage, radix: 16)) \(label) value=\(intValue)")
        fflush(stdout)
    }

    private static func label(usagePage: UInt32, usage: UInt32) -> String {
        if usagePage == kHIDPage_Button {
            return "button=\(usage)"
        }

        switch usage {
        case UInt32(kHIDUsage_GD_X):
            return "x"
        case UInt32(kHIDUsage_GD_Y):
            return "y"
        case UInt32(kHIDUsage_GD_Wheel):
            return "wheel"
        default:
            return "usage=\(usage)"
        }
    }
}

private let hidInputValueCallback: IOHIDValueCallback = { context, result, sender, value in
    guard result == kIOReturnSuccess, let context else {
        return
    }

    let inspector = Unmanaged<HIDInspector>.fromOpaque(context).takeUnretainedValue()
    inspector.handle(value: value)
}
