// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SubscriptionCore",
    platforms: [
        .iOS("27.0"),
        .macOS("27.0"),
    ],
    products: [
        .library(
            name: "SubscriptionCore",
            targets: ["SubscriptionCore"]
        ),
    ],
    targets: [
        .target(name: "SubscriptionCore"),
        .testTarget(
            name: "SubscriptionCoreTests",
            dependencies: ["SubscriptionCore"]
        ),
    ]
)
