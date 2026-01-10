// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "HashRipperKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "HashRipperKit",
            targets: ["HashRipperKit"]
        ),
    ],
    dependencies: [
        .package(path: "../AxeOSClient")
    ],
    targets: [
        .target(
            name: "HashRipperKit",
            dependencies: ["AxeOSClient"]
        ),
        .testTarget(
            name: "HashRipperKitTests",
            dependencies: ["HashRipperKit"]
        ),
    ]
)

