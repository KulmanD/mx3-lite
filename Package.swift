// swift-tools-version: 5.9

import PackageDescription
import Foundation

var packageTargets: [Target] = [
    .executableTarget(name: "MX3Lite"),
    .target(name: "MX3AppSupport"),
    .executableTarget(
        name: "MX3LiteApp",
        dependencies: ["MX3AppSupport"]
    )
]

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let testDirectory = packageRoot.appendingPathComponent("Tests/MX3LiteTests", isDirectory: true)
if FileManager.default.fileExists(atPath: testDirectory.path) {
    packageTargets.append(
        .testTarget(
            name: "MX3LiteTests",
            dependencies: ["MX3Lite"]
        )
    )

    let appTestDirectory = packageRoot.appendingPathComponent("Tests/MX3LiteAppTests", isDirectory: true)
    if FileManager.default.fileExists(atPath: appTestDirectory.path) {
        packageTargets.append(
            .testTarget(
                name: "MX3LiteAppTests",
                dependencies: ["MX3AppSupport", "MX3Lite"]
            )
        )
    }
}

let package = Package(
    name: "mx3-lite",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "mx3-lite", targets: ["MX3Lite"]),
        .executable(name: "mx3-lite-app", targets: ["MX3LiteApp"])
    ],
    targets: packageTargets
)
