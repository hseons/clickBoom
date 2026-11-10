// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClickBoom",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "ClickBoom", targets: ["ClickBoom"])
    ],
    targets: [
        .executableTarget(
            name: "ClickBoom",
            path: "clickBoom",
            exclude: ["Assets.xcassets"],
            swiftSettings: [
                .unsafeFlags(["-default-isolation", "MainActor"])
            ]
        ),
        .testTarget(
            name: "ClickBoomTests",
            dependencies: ["ClickBoom"],
            path: "Tests/ClickBoomTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
