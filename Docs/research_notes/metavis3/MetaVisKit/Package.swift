// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MetaVisKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "MetaVisKit",
            targets: ["MetaVisKit"]),
    ],
    dependencies: [
        .package(path: "../MetaVisCore"),
        .package(path: "../MetaVisServices"),
        .package(path: "../MetaVisScheduler"),
        .package(path: "../MetaVisImageGen"),
        .package(path: "../MetaVisTimeline"),
        // .package(path: "../MetaVisIngest"), // Add when ready
        // .package(path: "../MetaVisSimulation"), // Add when ready
    ],
    targets: [
        .target(
            name: "MetaVisKit",
            dependencies: [
                "MetaVisCore",
                "MetaVisServices",
                "MetaVisScheduler",
                "MetaVisImageGen",
                "MetaVisTimeline"
            ]
        ),
        .testTarget(
            name: "MetaVisKitTests",
            dependencies: ["MetaVisKit"]),
    ]
)
