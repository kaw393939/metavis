// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MetaVisKit2",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        // Core Libraries
        .library(name: "MetaVisCore", targets: ["MetaVisCore"]),
        .library(name: "MetaVisTimeline", targets: ["MetaVisTimeline"]),
        .library(name: "MetaVisSession", targets: ["MetaVisSession"]),
        
        // Engine Libraries
        .library(name: "MetaVisSimulation", targets: ["MetaVisSimulation"]),
        .library(name: "MetaVisGraphics", targets: ["MetaVisGraphics"]),
        
        // Feature Libraries
        .library(name: "MetaVisKit", targets: ["MetaVisKit"]),
        .library(name: "MetaVisIngest", targets: ["MetaVisIngest"]),
        .library(name: "MetaVisExport", targets: ["MetaVisExport"]),
        .library(name: "MetaVisServices", targets: ["MetaVisServices"]),
        .library(name: "MetaVisPerception", targets: ["MetaVisPerception"]),
        .library(name: "MetaVisAudio", targets: ["MetaVisAudio"]),

        // Quality Control / Verification
        .library(name: "MetaVisQC", targets: ["MetaVisQC"]),
        
        // Lab Runner
        .executable(name: "MetaVisLab", targets: ["MetaVisLab"]),
    ],
    dependencies: [
        // GRDB for JobQueue and Persistence
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0"),
        // Swift Algorithms for efficient data processing
        .package(url: "https://github.com/apple/swift-algorithms", from: "1.0.0"),
    ],
    targets: [
        // 1. MetaVisCore (Low Level)
        // No internal dependencies. Pure Data.
        .target(
            name: "MetaVisCore",
            dependencies: [
                .product(name: "Algorithms", package: "swift-algorithms")
            ]
        ),
        .testTarget(name: "MetaVisCoreTests", dependencies: ["MetaVisCore"]),

        // 2. MetaVisTimeline (NLE Model)
        // Depends on Core.
        .target(
            name: "MetaVisTimeline",
            dependencies: ["MetaVisCore"]
        ),
        .testTarget(name: "MetaVisTimelineTests", dependencies: ["MetaVisTimeline"]),

        // 3. MetaVisGraphics (Shader Lib)
        // Depends on Core (for primitive types).
        .target(
            name: "MetaVisGraphics",
            dependencies: ["MetaVisCore"],
            resources: [.process("Resources")] // Metal files will go here
        ),
        .testTarget(name: "MetaVisGraphicsTests", dependencies: ["MetaVisGraphics"]),

        // 4. MetaVisSimulation (Metal Engine)
        // Depends on Graphics (Shaders) and Core.
        .target(
            name: "MetaVisSimulation",
            dependencies: ["MetaVisCore", "MetaVisGraphics", "MetaVisTimeline"]
        ),
        .testTarget(name: "MetaVisSimulationTests", dependencies: ["MetaVisSimulation", "MetaVisPerception", "MetaVisSession"]),

        // 5. MetaVisIngest (Hardware/IO)
        // Depends on Core.
        .target(
            name: "MetaVisIngest",
            dependencies: ["MetaVisCore"]
        ),
        .testTarget(name: "MetaVisIngestTests", dependencies: ["MetaVisIngest"]),

        // 6. MetaVisExport (Delivery)
        // Depends on Core, Simulation (to drive export).
        .target(
            name: "MetaVisExport",
            dependencies: ["MetaVisCore", "MetaVisTimeline", "MetaVisSimulation", "MetaVisAudio"]
        ),
        .testTarget(name: "MetaVisExportTests", dependencies: ["MetaVisExport", "MetaVisQC", "MetaVisSession", "MetaVisSimulation", "MetaVisAudio", "MetaVisTimeline", "MetaVisCore"]),
        
        // 7. MetaVisServices (Cloud AI)
        // Depends on Core.
        .target(
            name: "MetaVisServices",
            dependencies: ["MetaVisCore"]
        ),
        .testTarget(name: "MetaVisServicesTests", dependencies: ["MetaVisServices"]),

        // 7.5 MetaVisQC (Verification)
        // Depends on Core + Services (optional Gemini calls) + Export (AVFoundation types live there too).
        .target(
            name: "MetaVisQC",
            dependencies: [
                "MetaVisCore",
                "MetaVisServices",
                "MetaVisExport",
                "MetaVisPerception"
            ],
            resources: [.process("Resources")]
        ),

        // 8. MetaVisPerception (Computer Vision)
        // Depends on Core, Ingest (for camera input).
        .target(
            name: "MetaVisPerception",
            dependencies: ["MetaVisCore", "MetaVisIngest"]
        ),
        .testTarget(name: "MetaVisPerceptionTests", dependencies: ["MetaVisPerception", "MetaVisAudio", "MetaVisCore"]),

        // 9. MetaVisAudio (Audio Engine)
        // Depends on Core, Timeline.
        .target(
            name: "MetaVisAudio",
            dependencies: ["MetaVisCore", "MetaVisTimeline"]
        ),
        .testTarget(name: "MetaVisAudioTests", dependencies: ["MetaVisAudio"]),

        // 10. MetaVisSession (The Brain / State)
        // Orchestrates Everything.
        .target(
            name: "MetaVisSession",
            dependencies: [
                "MetaVisCore",
                "MetaVisTimeline",
                "MetaVisSimulation",
                "MetaVisIngest",
                "MetaVisExport",
                "MetaVisQC",
                "MetaVisServices",
                "MetaVisPerception",
                "MetaVisAudio",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(name: "MetaVisSessionTests", dependencies: ["MetaVisSession", "MetaVisPerception", "MetaVisExport", "MetaVisSimulation", "MetaVisQC"]),

        // 11. MetaVisKit (UI / Agent Layer)
        // Depends on Session (state), Services (tools).
        .target(
            name: "MetaVisKit",
            dependencies: ["MetaVisSession", "MetaVisServices"]
        ),
        .testTarget(name: "MetaVisKitTests", dependencies: ["MetaVisKit"]),
        
        // 12. MetaVisLab (CLI Runner)
        .executableTarget(
            name: "MetaVisLab",
            dependencies: [
                "MetaVisSession",
                "MetaVisIngest",
                "MetaVisTimeline",
                "MetaVisCore",
                "MetaVisSimulation",
                "MetaVisExport",
                "MetaVisQC",
                "MetaVisPerception"
            ]
        ),
    ]
)
