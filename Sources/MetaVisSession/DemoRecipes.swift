import Foundation
import MetaVisCore
import MetaVisTimeline

private enum RepoPaths {
    static let rootURL: URL = {
        // `#filePath` resolves to `.../Sources/MetaVisSession/DemoRecipes.swift`.
        let url = URL(fileURLWithPath: #filePath)
        return url
            .deletingLastPathComponent() // MetaVisSession/
            .deletingLastPathComponent() // Sources/
            .deletingLastPathComponent() // repo root
    }()

    static func filePathIfExists(_ relativePath: String) -> String? {
        let url = rootURL.appendingPathComponent(relativePath)
        if FileManager.default.fileExists(atPath: url.path) {
            return url.path
        }
        return nil
    }
}

public enum DemoRecipes {

    public struct KeithTalkEditingDemo: ProjectRecipe {
        public let id: String = "com.metavis.recipe.keith_talk_editing_demo"
        public let name: String = "Keith Talk Editing Demo"

        public init() {}

        public func makeInitialState() -> ProjectState {
            let duration = Time(seconds: 60.0)

            let talkPath = RepoPaths.filePathIfExists("Projects/keith_talk_editing_demo/assets/keith_talk.mov")
            let bgPath = RepoPaths.filePathIfExists("Projects/keith_talk_editing_demo/assets/test_bg.mov")

            let primarySource = talkPath ?? "ligm://video/frame_counter"
            let brollSource = bgPath ?? "ligm://video/smpte_bars"

            let v1 = Clip(
                name: "Talk",
                asset: AssetReference(sourceFn: primarySource),
                startTime: .zero,
                duration: duration
            )

            // Simple cutaway window.
            let v2 = Clip(
                name: "Cutaway",
                asset: AssetReference(sourceFn: brollSource),
                startTime: Time(seconds: 18.0),
                duration: Time(seconds: 3.0),
                transitionIn: .crossfade(duration: Time(seconds: 0.15), easing: .easeInOut),
                transitionOut: .crossfade(duration: Time(seconds: 0.15), easing: .easeInOut)
            )

            let video = Track(name: "Video", kind: .video, clips: [v1, v2])

            let audio = Track(
                name: "Audio",
                kind: .audio,
                clips: [
                    Clip(
                        name: "Bed Tone",
                        asset: AssetReference(sourceFn: "ligm://audio/sine?freq=220"),
                        startTime: .zero,
                        duration: duration,
                        transitionIn: .crossfade(duration: Time(seconds: 0.05), easing: .easeIn),
                        transitionOut: .crossfade(duration: Time(seconds: 0.05), easing: .easeOut)
                    )
                ]
            )

            let timeline = Timeline(tracks: [video, audio], duration: duration)
            let config = ProjectConfig(name: name)
            return ProjectState(timeline: timeline, config: config)
        }
    }

    public struct BrollMontageDemo: ProjectRecipe {
        public let id: String = "com.metavis.recipe.broll_montage_demo"
        public let name: String = "B-roll Montage Demo"

        public init() {}

        public func makeInitialState() -> ProjectState {
            let clipDuration = Time(seconds: 2.5)
            // Keep duration aligned to clip coverage to avoid trailing black frames.
            // (4 clips × 2.5s = 10.0s)
            let total = Time(seconds: 10.0)

            func p(_ file: String) -> String? {
                RepoPaths.filePathIfExists("Projects/broll_montage_demo/assets/\(file)")
            }

            let sources: [String] = [
                p("neon_rain.mp4") ?? "ligm://video/smpte_bars",
                p("spectral_prism.mp4") ?? "ligm://video/macbeth",
                p("photon_cannon.mp4") ?? "ligm://video/zone_plate?speed=1.0",
                p("liquid_chrome.mp4") ?? "ligm://video/frame_counter"
            ]

            var clips: [Clip] = []
            clips.reserveCapacity(sources.count)

            for (i, s) in sources.enumerated() {
                let start = Time(seconds: Double(i) * clipDuration.seconds)
                clips.append(
                    Clip(
                        name: "Broll_\(i)",
                        asset: AssetReference(sourceFn: s),
                        startTime: start,
                        duration: clipDuration,
                        transitionIn: .crossfade(duration: Time(seconds: 0.12), easing: .easeInOut),
                        transitionOut: .crossfade(duration: Time(seconds: 0.12), easing: .easeInOut)
                    )
                )
            }

            let video = Track(name: "Video", kind: .video, clips: clips)

            // Add per-clip tones (one tone per b-roll segment) so the export has obvious audio segmentation.
            let freqs: [Int] = [220, 330, 440, 550]
            var toneClips: [Clip] = []
            toneClips.reserveCapacity(freqs.count)
            for i in 0..<freqs.count {
                let start = Time(seconds: Double(i) * clipDuration.seconds)
                let asset = AssetReference(sourceFn: "ligm://audio/sine?freq=\(freqs[i])")
                toneClips.append(
                    Clip(
                        name: "Tone_\(freqs[i])Hz",
                        asset: asset,
                        startTime: start,
                        duration: clipDuration
                    )
                )
            }
            let audio = Track(name: "Audio", kind: .audio, clips: toneClips)

            let timeline = Timeline(tracks: [video, audio], duration: total)
            let config = ProjectConfig(name: name)
            return ProjectState(timeline: timeline, config: config)
        }
    }

    public struct ProceduralValidationDemo: ProjectRecipe {
        public let id: String = "com.metavis.recipe.procedural_validation_demo"
        public let name: String = "Procedural Validation Demo"

        public init() {}

        public func makeInitialState() -> ProjectState {
            // Keep the timeline deterministic and already covered by existing tests.
            let timeline = GodTestBuilder.build()
            let config = ProjectConfig(name: name)
            return ProjectState(timeline: timeline, config: config)
        }
    }

    public struct AudioCleanwaterDemo: ProjectRecipe {
        public let id: String = "com.metavis.recipe.audio_cleanwater_demo"
        public let name: String = "Audio Cleanwater Demo"

        public init() {}

        public func makeInitialState() -> ProjectState {
            let duration = Time(seconds: 6.0)

            let bg = RepoPaths.filePathIfExists("Projects/audio_cleanwater_demo/assets/grey_void.mp4") ?? "ligm://video/smpte_bars"

            let video = Track(
                name: "Video",
                kind: .video,
                clips: [
                    Clip(
                        name: "Background",
                        asset: AssetReference(sourceFn: bg),
                        startTime: .zero,
                        duration: duration
                    )
                ]
            )

            let audio = Track(
                name: "Audio",
                kind: .audio,
                clips: [
                    Clip(
                        name: "Tone",
                        asset: AssetReference(sourceFn: "ligm://audio/sine?freq=1000"),
                        startTime: .zero,
                        duration: duration,
                        effects: [FeatureApplication(id: "audio.dialogCleanwater.v1")]
                    )
                ]
            )

            let timeline = Timeline(tracks: [video, audio], duration: duration)
            let config = ProjectConfig(name: name)
            return ProjectState(timeline: timeline, config: config)
        }
    }

    public struct ColorCapabilitiesDemo: ProjectRecipe {
        public let id: String = "com.metavis.recipe.color_capabilities_demo"
        public let name: String = "Color Capabilities Demo"

        public init() {}

        public func makeInitialState() -> ProjectState {
            // A compact, high-signal demo: known test patterns + graded variants + highlight rolloff.
            let segment = Time(seconds: 2.0)
            let total = Time(seconds: 14.0) // 7 segments × 2.0s

            func vclip(
                _ name: String,
                _ source: String,
                _ index: Int,
                effects: [FeatureApplication] = []
            ) -> Clip {
                let start = Time(seconds: Double(index) * segment.seconds)
                return Clip(
                    name: name,
                    asset: AssetReference(sourceFn: source),
                    startTime: start,
                    duration: segment,
                    transitionIn: .crossfade(duration: Time(seconds: 0.10), easing: .easeInOut),
                    transitionOut: .crossfade(duration: Time(seconds: 0.10), easing: .easeInOut),
                    effects: effects
                )
            }

            let gradeWarm = FeatureApplication(
                id: "com.metavis.fx.grade.simple",
                parameters: [
                    "exposure": .float(0.2),
                    "contrast": .float(1.15),
                    "saturation": .float(1.35),
                    "temperature": .float(0.60),
                    "tint": .float(0.10)
                ]
            )

            let gradeCool = FeatureApplication(
                id: "com.metavis.fx.grade.simple",
                parameters: [
                    "exposure": .float(-0.2),
                    "contrast": .float(1.10),
                    "saturation": .float(0.90),
                    "temperature": .float(-0.60),
                    "tint": .float(-0.20)
                ]
            )

            let acesTonemap = FeatureApplication(
                id: "com.metavis.fx.tonemap.aces",
                parameters: [
                    // Push the ramp into highlight rolloff without depending on external footage.
                    "exposure": .float(1.0)
                ]
            )

            let video = Track(
                name: "Video",
                kind: .video,
                clips: [
                    vclip("SMPTE_Bars", "ligm://video/smpte_bars", 0),
                    vclip("Macbeth_Chart", "ligm://video/macbeth", 1),
                    vclip("Linear_Ramp_Raw", "ligm://video/linear_ramp", 2),
                    vclip("Linear_Ramp_Tonemapped", "ligm://video/linear_ramp", 3, effects: [acesTonemap]),
                    vclip("TestColor_Raw", "ligm://video/test_color", 4),
                    vclip("TestColor_Warm_Grade", "ligm://video/test_color", 5, effects: [gradeWarm]),
                    vclip("TestColor_Cool_Grade", "ligm://video/test_color", 6, effects: [gradeCool])
                ]
            )

            let freqs: [Int] = [220, 277, 330, 392, 440, 523, 659]
            var toneClips: [Clip] = []
            toneClips.reserveCapacity(freqs.count)
            for i in 0..<freqs.count {
                let start = Time(seconds: Double(i) * segment.seconds)
                toneClips.append(
                    Clip(
                        name: "Tone_\(freqs[i])Hz",
                        asset: AssetReference(sourceFn: "ligm://audio/sine?freq=\(freqs[i])"),
                        startTime: start,
                        duration: segment
                    )
                )
            }
            let audio = Track(name: "Audio", kind: .audio, clips: toneClips)

            let timeline = Timeline(tracks: [video, audio], duration: total)
            let config = ProjectConfig(name: name)
            return ProjectState(timeline: timeline, config: config)
        }
    }
}
