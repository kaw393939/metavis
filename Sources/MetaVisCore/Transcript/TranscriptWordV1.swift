import Foundation

/// JSONL record schema emitted by MetaVisLab transcript generation (Sprint 23).
///
/// This record is written one-per-line to `transcript.words.v1.jsonl`.
public struct TranscriptWordV1: Codable, Sendable, Equatable {
    public var schema: String
    public var wordId: String
    public var word: String
    public var confidence: Double

    public var sourceTimeTicks: Int64
    public var sourceTimeEndTicks: Int64

    public var speakerId: String?
    public var speakerLabel: String?

    public var timelineTimeTicks: Int64?
    public var timelineTimeEndTicks: Int64?

    public var clipId: String?
    public var segmentId: String?

    public init(
        schema: String = "transcript.word.v1",
        wordId: String,
        word: String,
        confidence: Double,
        sourceTimeTicks: Int64,
        sourceTimeEndTicks: Int64,
        speakerId: String? = nil,
        speakerLabel: String? = nil,
        timelineTimeTicks: Int64? = nil,
        timelineTimeEndTicks: Int64? = nil,
        clipId: String? = nil,
        segmentId: String? = nil
    ) {
        self.schema = schema
        self.wordId = wordId
        self.word = word
        self.confidence = confidence
        self.sourceTimeTicks = sourceTimeTicks
        self.sourceTimeEndTicks = sourceTimeEndTicks
        self.speakerId = speakerId
        self.speakerLabel = speakerLabel
        self.timelineTimeTicks = timelineTimeTicks
        self.timelineTimeEndTicks = timelineTimeEndTicks
        self.clipId = clipId
        self.segmentId = segmentId
    }
}
