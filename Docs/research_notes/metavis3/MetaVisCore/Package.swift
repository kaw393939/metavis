// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MetaVisCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "MetaVisCore", targets: ["MetaVisCore"])],
    targets: [
        .target(name: "MetaVisCore"),
        .testTarget(name: "MetaVisCoreTests", dependencies: ["MetaVisCore"]),
    ]
)
