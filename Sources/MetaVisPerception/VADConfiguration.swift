import Foundation

/// Configuration for deterministic voice activity detection (VAD) heuristics.
///
/// Defaults are chosen to preserve current behavior.
public struct VADConfiguration: Sendable, Hashable {
    public var windowSeconds: Double
    public var hopSeconds: Double

    public var silenceFloorPercentile: Double
    public var silenceFloorAddDB: Double
    public var silenceClampMaxDB: Double
    public var silenceClampMinDB: Double
    public var silenceFallbackDB: Double

    public var speechCentroidHzMin: Double
    public var speechCentroidHzMax: Double
    public var speechZCRMin: Double
    public var speechZCRMax: Double
    public var voiceFundamentalHzMin: Double
    public var voiceFundamentalHzMax: Double

    public var musicFlatnessMax: Double
    public var musicCentroidHzMax: Double

    public var minMusicLikeDurationSeconds: Double
    public var minSegmentDurationSeconds: Double

    public init(
        windowSeconds: Double = 0.5,
        hopSeconds: Double = 0.25,
        silenceFloorPercentile: Double = 0.15,
        silenceFloorAddDB: Double = 8.0,
        silenceClampMaxDB: Double = -45.0,
        silenceClampMinDB: Double = -70.0,
        silenceFallbackDB: Double = -50.0,
        speechCentroidHzMin: Double = 250.0,
        speechCentroidHzMax: Double = 4200.0,
        speechZCRMin: Double = 0.005,
        speechZCRMax: Double = 0.25,
        voiceFundamentalHzMin: Double = 70.0,
        voiceFundamentalHzMax: Double = 350.0,
        musicFlatnessMax: Double = 0.22,
        musicCentroidHzMax: Double = 6000.0,
        minMusicLikeDurationSeconds: Double = 1.5,
        minSegmentDurationSeconds: Double = 0.2
    ) {
        self.windowSeconds = windowSeconds
        self.hopSeconds = hopSeconds

        self.silenceFloorPercentile = silenceFloorPercentile
        self.silenceFloorAddDB = silenceFloorAddDB
        self.silenceClampMaxDB = silenceClampMaxDB
        self.silenceClampMinDB = silenceClampMinDB
        self.silenceFallbackDB = silenceFallbackDB

        self.speechCentroidHzMin = speechCentroidHzMin
        self.speechCentroidHzMax = speechCentroidHzMax
        self.speechZCRMin = speechZCRMin
        self.speechZCRMax = speechZCRMax
        self.voiceFundamentalHzMin = voiceFundamentalHzMin
        self.voiceFundamentalHzMax = voiceFundamentalHzMax

        self.musicFlatnessMax = musicFlatnessMax
        self.musicCentroidHzMax = musicCentroidHzMax

        self.minMusicLikeDurationSeconds = minMusicLikeDurationSeconds
        self.minSegmentDurationSeconds = minSegmentDurationSeconds
    }

    public static let `default` = VADConfiguration()
}
