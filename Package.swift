// swift-tools-version: 5.9

import PackageDescription
import Foundation

let developerFrameworksPath: String? = {
    let candidates = [
        ProcessInfo.processInfo.environment["DEVELOPER_DIR"],
        "/Applications/Xcode.app/Contents/Developer",
        "/Library/Developer/CommandLineTools"
    ].compactMap { $0 }

    return candidates
        .map { URL(fileURLWithPath: $0).appendingPathComponent("Library/Developer/Frameworks").path }
        .first { FileManager.default.fileExists(atPath: "\($0)/Testing.framework") }
}()

let testingSwiftSettings: [SwiftSetting] = developerFrameworksPath.map {
    [.unsafeFlags(["-F", $0])]
} ?? []

let testingLinkerSettings: [LinkerSetting] = developerFrameworksPath.map {
    let testingInteropPath = URL(fileURLWithPath: $0)
        .deletingLastPathComponent()
        .appendingPathComponent("usr/lib")
        .path
    return [
        LinkerSetting.unsafeFlags([
            "-F", $0,
            "-Xlinker", "-rpath", "-Xlinker", $0,
            "-Xlinker", "-rpath", "-Xlinker", testingInteropPath
        ]),
        LinkerSetting.linkedFramework("Testing")
    ]
} ?? []

let package = Package(
    name: "mx3-lite",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "mx3-lite", targets: ["MX3Lite"])
    ],
    targets: [
        .executableTarget(name: "MX3Lite"),
        .testTarget(
            name: "MX3LiteTests",
            dependencies: ["MX3Lite"],
            swiftSettings: testingSwiftSettings,
            linkerSettings: testingLinkerSettings
        )
    ]
)
