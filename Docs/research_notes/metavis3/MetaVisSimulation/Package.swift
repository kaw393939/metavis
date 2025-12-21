// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MetaVisSimulation",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .visionOS(.v1)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MetaVisSimulation",
            targets: ["MetaVisSimulation"]
        ),
        .executable(
            name: "Validation",
            targets: ["Validation"]
        ),
    ],
    dependencies: [
        .package(path: "../MetaVisCore"),
        .package(path: "../MetaVisImageGen"),
        .package(path: "../MetaVisTimeline"),
        .package(path: "../MetaVisAudio"),
        .package(path: "../MetaVisExport")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MetaVisSimulation",
            dependencies: ["MetaVisCore", "MetaVisImageGen", "MetaVisTimeline", "MetaVisAudio"],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "Validation",
            dependencies: ["MetaVisSimulation", "MetaVisExport", "MetaVisTimeline", "MetaVisCore"]
        ),
        .testTarget(
            name: "MetaVisSimulationTests",
            dependencies: ["MetaVisSimulation"]
        ),
    ]
)
