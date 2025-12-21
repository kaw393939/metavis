// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MetaVisAudio",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "MetaVisAudio", targets: ["MetaVisAudio"])],
    targets: [
        .target(name: "MetaVisAudio"),
        .testTarget(name: "MetaVisAudioTests", dependencies: ["MetaVisAudio"]),
    ]
)
