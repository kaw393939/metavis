// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MetaVisPerception",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MetaVisPerception",
            targets: ["MetaVisPerception"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MetaVisPerception",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]),
        .testTarget(
            name: "MetaVisPerceptionTests",
            dependencies: ["MetaVisPerception"]),
    ]
)
