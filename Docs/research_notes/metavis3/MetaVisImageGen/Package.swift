// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MetaVisImageGen",
    platforms: [
        .macOS(.v14), .iOS(.v17)
    ],
    products: [
        .library(
            name: "MetaVisImageGen",
            targets: ["MetaVisImageGen"]),
    ],
    targets: [
        .target(
            name: "MetaVisImageGen",
            resources: [
                .process("Resources"),
                .process("Shaders")
            ]
        ),
        .testTarget(
            name: "MetaVisImageGenTests",
            dependencies: ["MetaVisImageGen"]),
    ]
)
