import Foundation
import MetaVisCore
import MetaVisTimeline
import MetaVisSession
import MetaVisIngest
import MetaVisSimulation
import MetaVisExport

enum MetaVisLabProgram {
    static func run(args: [String]) async throws {
        if args.first == "--help" || args.first == "-h" {
            print(MetaVisLabHelp.text)
            return
        }

        if let cmd = args.first {
            switch cmd {
            case "export-demos":
                try await ExportDemosCommand.run(args: Array(args.dropFirst()))
                return

            case "exr-timeline", "exr-tmeline":
                try await EXRTimelineCommand.run(args: Array(args.dropFirst()))
                return

            case "fits-timeline", "fits-video":
                try await FITSTimelineCommand.run(args: Array(args.dropFirst()))
                return

            case "fits-composite-png", "fits-png":
                try await FITSCompositePNGCommand.run(args: Array(args.dropFirst()))
                return

            case "fits-render-png":
                try await FITSRenderPNGCommand.run(args: Array(args.dropFirst()))
                return

            case "fits-nircam-cosmic-cliffs", "fits-cosmic-cliffs":
                try await FITSNIRCamCosmicCliffsCommand.run(args: Array(args.dropFirst()))
                return

            case "nebula-debug":
                try await NebulaDebugCommand.run(args: Array(args.dropFirst()))
                return

            case "probe-clip":
                try await ProbeClipCommand.run(args: Array(args.dropFirst()))
                return

            case "gemini-analyze":
                try await GeminiAnalyzeCommand.run(args: Array(args.dropFirst()), io: .default())
                return

            case "sensors":
                try await SensorsCommand.run(args: Array(args.dropFirst()))
                return

            case "mobilesam":
                try await MobileSAMCommand.run(args: Array(args.dropFirst()))
                return

            case "auto-speaker-audio":
                try await AutoSpeakerAudioCommand.run(args: Array(args.dropFirst()))
                return

            case "auto-color-correct":
                try await AutoColorCorrectCommand.run(args: Array(args.dropFirst()))
                return

            case "auto-enhance":
                try await AutoEnhanceCommand.run(args: Array(args.dropFirst()))
                return

            case "transcript":
                try await TranscriptCommand.run(args: Array(args.dropFirst()))
                return

            case "diarize":
                try await DiarizeCommand.run(args: Array(args.dropFirst()))
                return

            default:
                let msg = "Unknown command: \(cmd)"
                print(msg)
                print("")
                print(MetaVisLabHelp.text)
                throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
            }
        }

        print("🧪 Starting MetaVis Lab \"Gemini Loop\" Verification")

        // 1. Setup Config
        let license = ProjectLicense(ownerId: "lab", maxExportResolution: 4320, requiresWatermark: true, allowOpenEXR: false)
        let config = ProjectConfig(name: "Lab Validation Project", license: license)

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

        // 4. Construct Timeline (explicit duration; reducers do not auto-update timeline.duration)
        let assetRef = AssetReference(id: UUID(), sourceFn: sourceUrl)
        let clipDuration = Time(seconds: 10.0)
        let clip = Clip(name: "Test Pattern", asset: assetRef, startTime: .zero, duration: clipDuration)

        let track = Track(name: "Video Layer 1", kind: .video, clips: [clip])
        let timeline = Timeline(tracks: [track], duration: clipDuration)

        let session = ProjectSession(initialState: ProjectState(timeline: timeline, config: config))
        print("✅ Session Initialized")
        print("✅ Track Added: \(track.name)")
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
            MetaVisLab sensors ingest --input <movie.mov> --out <dir> [--stride <s>] [--max-video-seconds <s>] [--audio-seconds <s>] [--allow-large]
        MetaVisLab mobilesam segment --input <movie.mov> --time <seconds> --x <0..1> --y <0..1> --out <dir> [--width <w>] [--height <h>] [--label <0|1>] [--cache-key <k>] [--x2 <0..1> --y2 <0..1>]
            MetaVisLab export-demos [--out <dir>] [--allow-large]
            MetaVisLab probe-clip --input <movie.mp4> [--width <w>] [--height <h>] [--start <s>] [--end <s>] [--step <s>]
                        MetaVisLab gemini-analyze --input <movie.mov> --out <dir>
            MetaVisLab auto-speaker-audio --sensors <sensors.json> --out <dir> [--seed <s>] [--snippet-seconds <s>] [--input <movie.mov>] [--qa off|local-text|gemini] [--qa-cycles <n>]
            MetaVisLab auto-color-correct --sensors <sensors.json> --out <dir> [--seed <s>] [--input <movie.mov>] [--qa off|local-text|gemini] [--qa-cycles <n>] [--qa-max-frames <n>]
            MetaVisLab auto-enhance --sensors <sensors.json> --input <movie.mov> --out <dir> [--export <enhanced.mov>] [--export-start <seconds>] [--export-seconds <seconds>] [--seed <s>] [--qa off|local-text|gemini] [--qa-cycles <n>] [--qa-max-frames <n>] [--qa-max-audio-clips <n>] [--qa-audio-clip-seconds <s>] [--qa-max-concurrency <n>] [--height <h>] [--fps <n>] [--codec hevc|prores4444|prores422hq] [--allow-large]
            MetaVisLab transcript generate --input <movie.mov> --out <dir> [--start-seconds <s>] [--max-seconds <s>] [--language <code>] [--write-adjacent-captions true|false] [--allow-large]
            MetaVisLab diarize --sensors <sensors.json> --transcript <transcript.words.v1.jsonl> --out <dir>
            MetaVisLab fits-timeline [--input-dir <dir>] [--out <dir>] [--seconds-per <s>] [--transition cut|crossfade|dip] [--transition-seconds <s>] [--easing linear|easeIn|easeOut|easeInOut] [--color gray|turbo] [--color-exposure <ev>] [--color-gamma <g>] [--height <h>] [--fps <n>] [--codec hevc|prores4444|prores422hq] [--extract-exr]
            MetaVisLab fits-composite-png [--input-dir <dir>] [--out <dir>] [--name <file.png>] [--exposure <ev>] [--contrast <c>] [--saturation <s>] [--gamma <g>]
            MetaVisLab fits-render-png --input <file.fits> [--out <dir>] [--name <file.png>] [--exposure <ev>] [--gamma <g>] [--alpha <a>] [--black-p <p>] [--white-p <p>]
            MetaVisLab fits-nircam-cosmic-cliffs [--input-dir <dir>] [--out <dir>] [--name <base>] [--exposure <ev>] [--contrast <c>] [--saturation <s>] [--gamma <g>]
            MetaVisLab nebula-debug [--out <dir>] [--width <w>] [--height <h>]
            MetaVisLab exr-timeline [--input-dir <dir>] [--out <dir>] [--seconds-per <s>] [--transition cut|crossfade|dip] [--transition-seconds <s>] [--easing linear|easeIn|easeOut|easeInOut] [--height <h>] [--fps <n>] [--codec hevc|prores4444|prores422hq] [--no-extract-exr]

        export-demos:
            Exports the built-in demo project recipes to .mov files for review.
            Outputs are written under test_outputs/project_exports/ by default.

        exr-timeline:
            Builds a timeline from .exr stills (loaded via ffmpeg), applies a deterministic edit,
            exports a movie, and (by default) extracts one edited .exr per source still.
            If --input-dir is omitted, defaults to ./assets/exr.

        fits-timeline:
            Builds a timeline from .fits stills (loaded via the built-in FITS reader),
            exports a movie, and writes timeline.json for inspection.
            If --extract-exr is set, extracts one edited .exr per source still.
            If --input-dir is omitted, defaults to ./Tests/Assets/fits.

        fits-composite-png:
            Generates a native-resolution (no upscaling) JWST-style false-color composite PNG
            from the four MIRI bands in ./Tests/Assets/fits (f770w, f1130w, f1280w, f1800w).
            If --input-dir is omitted, defaults to ./Tests/Assets/fits.
            Outputs are written under ./test_outputs/_fits_composite_png by default.

        fits-nircam-cosmic-cliffs:
            Generates a native-resolution (no upscaling) 6-filter NIRCam composite PNG set
            using percentile windowing (P0.5–P99.5) and explicit NASA hue mapping:
                F090W→Blue, F187N→Cyan, F200W→Green, F470N→Yellow, F335M→Orange, F444W→Red.
            Also writes required debug PNGs (per-filter contributions, star mask, ridge boundary, steam field).
            Outputs are written under ./test_outputs/_fits_cosmic_cliffs by default.

                fits-render-png:
                        Renders a single FITS image plane to a native-resolution (no upscaling) grayscale PNG
                        using a robust percentile-based asinh stretch.
                        Outputs are written under ./test_outputs/_fits_render_png by default.

                nebula-debug:
                        Renders the volumetric nebula and required debug views:
                            - blue ratio (pre/post clamp)
                            - edge width visualization
                            - density pre/post remap
                            - star–medium interaction composite
                        Outputs are written under ./test_outputs/_nebula_debug by default.

    Safety:
      Large assets (e.g. keith_talk.mov) require --allow-large.
    """
}
