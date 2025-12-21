// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MetaVisExport",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "MetaVisExport", targets: ["MetaVisExport"])],
    dependencies: [
        .package(path: "../MetaVisCore")
    ],
    targets: [
        .target(
            name: "MetaVisExport",
            dependencies: ["MetaVisCore"],
            resources: [.process("Shaders")]
        ),
        .testTarget(name: "MetaVisExportTests", dependencies: ["MetaVisExport"]),
    ]
)
