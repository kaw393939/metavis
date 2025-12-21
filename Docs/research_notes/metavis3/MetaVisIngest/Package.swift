// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MetaVisIngest",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "MetaVisIngest", targets: ["MetaVisIngest"])],
    dependencies: [
        .package(path: "../MetaVisCore"),
        .package(path: "../MetaVisSimulation")
    ],
    targets: [
        .target(name: "MetaVisIngest", dependencies: ["MetaVisCore", "MetaVisSimulation"]),
        .testTarget(name: "MetaVisIngestTests", dependencies: ["MetaVisIngest"]),
    ]
)
