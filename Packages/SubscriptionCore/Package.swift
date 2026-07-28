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
        .executable(
            name: "CatalogValidator",
            targets: ["CatalogValidator"]
        ),
    ],
    targets: [
        .target(name: "SubscriptionCore"),
        .executableTarget(
            name: "CatalogValidator",
            dependencies: ["SubscriptionCore"]
        ),
        .testTarget(
            name: "SubscriptionCoreTests",
            dependencies: ["SubscriptionCore"]
        ),
    ]
)
