// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "AvalonClient",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "AvalonClient",
            targets: ["AvalonClient"]
        ),
    ],
    targets: [
        .target(
            name: "AvalonClient"
        ),
        .testTarget(
            name: "AvalonClientTests",
            dependencies: ["AvalonClient"]
        ),
    ]
)
