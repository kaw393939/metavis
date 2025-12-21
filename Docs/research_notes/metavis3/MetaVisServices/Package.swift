// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MetaVisServices",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MetaVisServices",
            targets: ["MetaVisServices"]),
    ],
    dependencies: [
        // Internal dependencies
        .package(path: "../MetaVisCore"),
        .package(path: "../MetaVisImageGen")
    ],
    targets: [
        .target(
            name: "MetaVisServices",
            dependencies: [
                "MetaVisCore",
                "MetaVisImageGen"
            ]
        ),
        .testTarget(
            name: "MetaVisServicesTests",
            dependencies: ["MetaVisServices"]),
    ]
)
