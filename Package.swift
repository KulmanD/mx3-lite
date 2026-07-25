// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "mx3-lite",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "mx3-lite", targets: ["MX3Lite"])
    ],
    targets: [
        .executableTarget(name: "MX3Lite")
    ]
)
