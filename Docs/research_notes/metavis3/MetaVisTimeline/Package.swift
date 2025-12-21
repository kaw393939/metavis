// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MetaVisTimeline",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "MetaVisTimeline", targets: ["MetaVisTimeline"])],
    dependencies: [
        .package(path: "../MetaVisCore")
    ],
    targets: [
        .target(
            name: "MetaVisTimeline",
            dependencies: ["MetaVisCore"]
        ),
        .testTarget(name: "MetaVisTimelineTests", dependencies: ["MetaVisTimeline"]),
    ]
)
