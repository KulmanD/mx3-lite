enum ConfigDefaults {
    static let threshold = 220.0
    static let gestureButton = 5
    static let backButton = 3
    static let forwardButton = 4
    static let downAction = AppDownAction.ctrlDown
    static let invertY = false
    static let invertDesktopGestureDirection = true
    static let actionBackend = AppActionBackend.systemEvents
    static let invertVerticalScroll = true
    static let invertHorizontalScroll = false
    static let scrollMultiplier = 1.0
    static let smoothScroll = true
    static let smoothScrollMode = AppSmoothScrollMode.ema
    static let smoothScrollFactor = 0.35
    static let scrollDeadzone = 0.0
    static let maxScrollStep = 8.0
    static let scrollAcceleration = 1.0
    static let freeSpinDamping = 0.75
    static let ratchetStepMultiplier = 1.0
    static let allowGlobalScrollTransform = false
    static let scrollTransformMode = AppScrollTransformMode.mxMasterOnly
}
