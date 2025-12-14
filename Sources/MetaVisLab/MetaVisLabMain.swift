import Foundation
import MetaVisCore
import MetaVisTimeline
import MetaVisSession
import MetaVisIngest
import MetaVisSimulation
import MetaVisExport

enum MetaVisLabProgram {
    static func run(args: [String]) async throws {
        if let cmd = args.first, cmd == "assess-local" {
            try await LocalAssessmentCommand.run(args: Array(args.dropFirst()))
            return
        }

        if let cmd = args.first, cmd == "export-demos" {
            try await ExportDemosCommand.run(args: Array(args.dropFirst()))
            return
        }

        if let cmd = args.first, cmd == "probe-clip" {
            try await ProbeClipCommand.run(args: Array(args.dropFirst()))
            return
        }

        if args.first == "--help" || args.first == "-h" {
            print(MetaVisLabHelp.text)
            return
        }

        print("🧪 Starting MetaVis Lab \"Gemini Loop\" Verification")

        // 1. Setup Session
        let license = ProjectLicense(ownerId: "lab", maxExportResolution: 4320, requiresWatermark: true, allowOpenEXR: false)
        let session = ProjectSession(initialState: ProjectState(config: ProjectConfig(name: "Lab Validation Project", license: license)))
        print("✅ Session Initialized")

        // 2. Setup Device
        let ligm = LIGMDevice()
        print("✅ LIGM Device Connected")

        // 3. Generate Content
        print("⏳ Generating Asset...")
        let result = try await ligm.perform(action: "generate", with: ["prompt": .string("Test Pattern ACEScg")])

        guard case .string(let assetId) = result["assetId"],
              case .string(let sourceUrl) = result["sourceUrl"] else {
            throw NSError(domain: "MetaVisLab", code: 100, userInfo: [NSLocalizedDescriptionKey: "Generation failed: missing outputs"])
        }
        print("✅ Generated Asset: \(assetId)")

        // 4. Edit Timeline
        let trackId = UUID()
        let track = Track(id: trackId, name: "Video Layer 1")
        await session.dispatch(.addTrack(track))
        print("✅ Track Added: \(track.name)")

        let assetRef = AssetReference(id: UUID(), sourceFn: sourceUrl)
        let clip = Clip(
            name: "Test Pattern",
            asset: assetRef,
            startTime: .zero,
            duration: Time(seconds: 10.0)
        )
        await session.dispatch(.addClip(clip, toTrackId: trackId))
        print("✅ Clip Added: \(clip.name) to \(track.name)")

        // 5. Verification
        let state = await session.state
        let clipCount = state.timeline.tracks.first?.clips.count ?? 0
        guard clipCount == 1 else {
            throw NSError(domain: "MetaVisLab", code: 101, userInfo: [NSLocalizedDescriptionKey: "Clip not found in timeline"])
        }

        print("🎉 SUCCESS: Lab Project Created Successfully!")
        print("   - Project: \(state.config.name)")
        print("   - Timeline: \(state.timeline.tracks.count) Track, \(clipCount) Clip")
        print("   - Asset Source: \(sourceUrl)")

        // 6. Export (governance enforced via ProjectSession)
        let engine = try MetalSimulationEngine()
        let exporter = VideoExporter(engine: engine)
        let outputURL = URL(fileURLWithPath: "\(FileManager.default.currentDirectoryPath)/test_outputs/lab_watermarked_1080p.mov")
        let quality = QualityProfile(name: "Lab1080", fidelity: .high, resolutionHeight: 1080, colorDepth: 10)
        print("⏳ Exporting to: \(outputURL.path)")
        try await session.exportMovie(using: exporter, to: outputURL, quality: quality, frameRate: 24, codec: .hevc, audioPolicy: .auto)
        print("✅ Export Complete")
    }
}

enum MetaVisLabHelp {
    static let text = """
    MetaVisLab

    Usage:
      MetaVisLab                       Runs the legacy lab validation flow (may invoke generators).
      MetaVisLab assess-local --input <movie.mov> [--out <dir>] [--samples <n>] [--allow-large]
    MetaVisLab export-demos [--out <dir>] [--allow-large]
            MetaVisLab probe-clip --input <movie.mp4> [--width <w>] [--height <h>] [--start <s>] [--end <s>] [--step <s>]

    assess-local (local-only):
      Produces a reviewable pack with sampled frames, a thumbnail, a contact sheet, and local_report.json.
      No network calls; uses deterministic QC + on-device Vision face detection.

        export-demos:
            Exports the built-in demo project recipes to .mov files for review.
            Outputs are written under test_outputs/project_exports/ by default.

    Safety:
      Large assets (e.g. keith_talk.mov) require --allow-large.
    """
}
