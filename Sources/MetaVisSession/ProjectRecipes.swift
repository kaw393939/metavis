import Foundation
import MetaVisCore
import MetaVisTimeline

public protocol ProjectRecipe: Sendable {
    var id: String { get }
    var name: String { get }

    func makeInitialState() -> ProjectState
}

public enum StandardRecipes {

    /// Minimal deterministic recipe intended for fast, no-mock E2E export validation.
    public struct SmokeTest2s: ProjectRecipe {
        public let id: String = "com.metavis.recipe.smoke_test_2s"
        public let name: String = "Smoke Test (2s)"

        public init() {}

        public func makeInitialState() -> ProjectState {
            let duration = Time(seconds: 2.0)

            let videoClip = Clip(
                name: "SMPTE Bars",
                asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
                startTime: .zero,
                duration: duration
            )
            let videoTrack = Track(name: "Video", kind: .video, clips: [videoClip])

            let audioClip = Clip(
                name: "1kHz Tone",
                asset: AssetReference(sourceFn: "ligm://audio/sine?freq=1000"),
                startTime: .zero,
                duration: duration
            )
            let audioTrack = Track(name: "Audio", kind: .audio, clips: [audioClip])

            let timeline = Timeline(tracks: [videoTrack, audioTrack], duration: duration)
            let license = ProjectLicense(ownerId: "test", maxExportResolution: 4320, requiresWatermark: false, allowOpenEXR: false)
            let config = ProjectConfig(name: name, license: license)
            return ProjectState(timeline: timeline, config: config)
        }
    }

    public struct GodTest20s: ProjectRecipe {
        public let id: String = "com.metavis.recipe.god_test_20s"
        public let name: String = "God Test (20s)"

        public init() {}

        public func makeInitialState() -> ProjectState {
            let timeline = GodTestBuilder.build()
            let config = ProjectConfig(name: name)
            return ProjectState(timeline: timeline, config: config)
        }
    }
}
