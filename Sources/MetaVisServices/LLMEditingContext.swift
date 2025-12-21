import Foundation
import MetaVisTimeline
import MetaVisPerception

/// Context given to an LLM (local or remote) for deterministic editing commands.
/// Designed to be stable, small, and safe to serialize.
public struct LLMEditingContext: Codable, Sendable, Equatable {

    public struct ClipSummary: Codable, Sendable, Equatable {
        public var id: UUID
        public var name: String
        public var trackKind: TrackKind
        public var assetSourceFn: String
        public var startSeconds: Double
        public var durationSeconds: Double
        public var offsetSeconds: Double

        public init(
            id: UUID,
            name: String,
            trackKind: TrackKind,
            assetSourceFn: String,
            startSeconds: Double,
            durationSeconds: Double,
            offsetSeconds: Double
        ) {
            self.id = id
            self.name = name
            self.trackKind = trackKind
            self.assetSourceFn = assetSourceFn
            self.startSeconds = startSeconds
            self.durationSeconds = durationSeconds
            self.offsetSeconds = offsetSeconds
        }
    }

    public var clips: [ClipSummary]
    public var visualContext: SemanticFrame?

    public init(clips: [ClipSummary], visualContext: SemanticFrame? = nil) {
        self.clips = clips
        self.visualContext = visualContext
    }

    public static func fromTimeline(_ timeline: Timeline, visualContext: SemanticFrame? = nil) -> LLMEditingContext {
        var clips: [ClipSummary] = []
        clips.reserveCapacity(timeline.tracks.reduce(0) { $0 + $1.clips.count })

        for track in timeline.tracks {
            for clip in track.clips {
                clips.append(
                    ClipSummary(
                        id: clip.id,
                        name: clip.name,
                        trackKind: track.kind,
                        assetSourceFn: clip.asset.sourceFn,
                        startSeconds: clip.startTime.seconds,
                        durationSeconds: clip.duration.seconds,
                        offsetSeconds: clip.offset.seconds
                    )
                )
            }
        }

        // Deterministic ordering for downstream consumers.
        clips.sort {
            if $0.trackKind != $1.trackKind { return $0.trackKind.rawValue < $1.trackKind.rawValue }
            if $0.startSeconds != $1.startSeconds { return $0.startSeconds < $1.startSeconds }
            return $0.id.uuidString < $1.id.uuidString
        }

        return LLMEditingContext(clips: clips, visualContext: visualContext)
    }
}
