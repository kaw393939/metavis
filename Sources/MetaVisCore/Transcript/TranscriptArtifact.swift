import Foundation

/// Stable, word-level transcript contract for edit-point work.
///
/// Times are expressed in `MetaVisCore.Time` ticks: 1 tick = 1/60000 seconds.
public struct TranscriptArtifact: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var createdAt: Date

    /// Fixed tick scale for all time fields.
    public var tickScale: Int

    public var words: [Word]

    public init(
        schemaVersion: Int = 1,
        createdAt: Date = Date(),
        tickScale: Int = 60000,
        words: [Word]
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.tickScale = tickScale
        self.words = words
    }

    public struct Word: Codable, Sendable, Equatable {
        public var text: String
        public var speaker: String?

        /// Time in the source media.
        public var sourceStartTicks: Int64
        public var sourceEndTicks: Int64

        /// Time in the edited timeline.
        public var timelineStartTicks: Int64
        public var timelineEndTicks: Int64

        public init(
            text: String,
            speaker: String? = nil,
            sourceStartTicks: Int64,
            sourceEndTicks: Int64,
            timelineStartTicks: Int64,
            timelineEndTicks: Int64
        ) {
            self.text = text
            self.speaker = speaker
            self.sourceStartTicks = sourceStartTicks
            self.sourceEndTicks = sourceEndTicks
            self.timelineStartTicks = timelineStartTicks
            self.timelineEndTicks = timelineEndTicks
        }
    }
}
