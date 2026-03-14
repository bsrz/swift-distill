// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "distill",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Distill", targets: ["Distill"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.1"),
    ],
    targets: [
        .executableTarget(
            name: "distill-cli",
            dependencies: [
                "Distill",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "Distill",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "DistillTests",
            dependencies: ["Distill"],
            resources: [
                .process("Fixtures"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
