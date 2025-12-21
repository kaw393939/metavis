// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MetaVisScheduler",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MetaVisScheduler",
            targets: ["MetaVisScheduler"]),
    ],
    dependencies: [
        // Internal dependencies
        .package(path: "../MetaVisCore"),
        .package(path: "../MetaVisServices"),
        .package(path: "../MetaVisImageGen"),
        .package(path: "../MetaVisExport"),
        .package(path: "../MetaVisSimulation"),
        .package(path: "../MetaVisTimeline"),
        
        // External dependencies
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
    ],
    targets: [
        .target(
            name: "MetaVisScheduler",
            dependencies: [
                "MetaVisCore",
                "MetaVisServices",
                "MetaVisImageGen",
                "MetaVisExport",
                "MetaVisSimulation",
                "MetaVisTimeline",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "MetaVisSchedulerTests",
            dependencies: ["MetaVisScheduler"]),
    ]
)
