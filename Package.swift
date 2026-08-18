// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CithubNativeCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v15),
    ],
    products: [
        .library(name: "CithubNativeCore", targets: ["CithubNativeCore"]),
    ],
    targets: [
        .target(
            name: "CithubNativeCore",
            path: "packages/cithub_native/ios/Classes/Core"
        ),
        .testTarget(
            name: "CithubNativeCoreTests",
            dependencies: ["CithubNativeCore"],
            path: "packages/cithub_native/ios/Tests"
        ),
    ]
)
