// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MetaVisCLI",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "metavis", targets: ["MetaVisCLI"])],
    dependencies: [
        .package(path: "../MetaVisKit"),
        .package(path: "../MetaVisCore"),
        .package(path: "../MetaVisIngest"),
        .package(path: "../MetaVisCalibration"),
        .package(path: "../MetaVisImageGen"),
        .package(path: "../MetaVisExport"),
        .package(path: "../MetaVisSimulation"),
        .package(path: "../MetaVisTimeline"),
        .package(path: "../MetaVisAudio"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "MetaVisCLI",
            dependencies: [
                "MetaVisKit",
                "MetaVisCore",
                "MetaVisIngest",
                "MetaVisCalibration",
                "MetaVisImageGen",
                "MetaVisExport",
                "MetaVisSimulation",
                "MetaVisTimeline",
                "MetaVisAudio",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
