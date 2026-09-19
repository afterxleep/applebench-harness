// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AppleBench",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "applebench", targets: ["AppleBenchCLI"]),
        .library(name: "AppleBenchCore", targets: ["AppleBenchCore"]),
        .library(name: "AppleBenchAgents", targets: ["AppleBenchAgents"]),
        .library(name: "AppleBenchGraders", targets: ["AppleBenchGraders"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "AppleBenchCore",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ]
        ),
        .target(
            name: "AppleBenchAgents",
            dependencies: ["AppleBenchCore"]
        ),
        .target(
            name: "AppleBenchGraders",
            dependencies: ["AppleBenchCore"]
        ),
        .executableTarget(
            name: "AppleBenchCLI",
            dependencies: [
                "AppleBenchCore",
                "AppleBenchAgents",
                "AppleBenchGraders",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "AppleBenchCoreTests",
            dependencies: ["AppleBenchCore"]
        ),
        .testTarget(
            name: "AppleBenchGradersTests",
            dependencies: ["AppleBenchGraders", "AppleBenchCore"]
        ),
        .testTarget(
            name: "AppleBenchAgentsTests",
            dependencies: ["AppleBenchAgents", "AppleBenchCore"]
        ),
    ]
)
