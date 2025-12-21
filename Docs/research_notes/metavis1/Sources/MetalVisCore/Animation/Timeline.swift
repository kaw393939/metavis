import Foundation

/// Timeline manages playback state and frame-by-frame rendering control
/// Designed for deterministic, frame-perfect video generation
public struct Timeline {
    // MARK: - Properties

    /// Total duration in seconds
    public let duration: Double

    /// Frames per second
    public let fps: Int

    /// Total number of frames to render
    public let totalFrames: Int

    /// Current playback time in seconds
    public private(set) var currentTime: Double

    /// Current frame index (0-based)
    public private(set) var currentFrame: Int

    /// Whether timeline is currently playing
    public private(set) var isPlaying: Bool

    /// Playback speed multiplier (0.5x - 2.0x)
    public private(set) var speed: Double

    // MARK: - Computed Properties

    /// Progress through timeline (0.0 - 1.0)
    public var progress: Double {
        guard duration > 0 else { return 1.0 }
        return currentTime / duration
    }

    /// Whether timeline has reached the end
    public var isComplete: Bool {
        currentFrame >= totalFrames
    }

    /// Effective duration considering speed multiplier
    public var effectiveDuration: Double {
        duration / speed
    }

    // MARK: - Initialization

    public init(duration: Double, fps: Int) {
        self.duration = max(0.0, duration)
        self.fps = fps
        totalFrames = Int(ceil(duration * Double(fps)))
        currentTime = 0.0
        currentFrame = 0
        isPlaying = false
        speed = 1.0
    }

    // MARK: - Playback Control

    /// Start playback
    public mutating func play() {
        isPlaying = true
    }

    /// Pause playback
    public mutating func pause() {
        isPlaying = false
    }

    /// Toggle playback state
    public mutating func toggle() {
        isPlaying.toggle()
    }

    /// Stop playback and reset to beginning
    public mutating func stop() {
        isPlaying = false
        currentTime = 0.0
        currentFrame = 0
    }

    // MARK: - Seeking

    /// Seek to specific time in seconds
    public mutating func seek(to time: Double) {
        let clampedTime = max(0.0, min(time, duration))
        currentTime = clampedTime
        currentFrame = frameForTime(clampedTime)
    }

    /// Seek to specific frame index
    public mutating func seek(toFrame frame: Int) {
        let clampedFrame = max(0, min(frame, totalFrames))
        currentFrame = clampedFrame
        currentTime = timeForFrame(clampedFrame)
    }

    // MARK: - Frame Control

    /// Advance to next frame
    public mutating func advanceFrame() {
        guard currentFrame < totalFrames else { return }
        currentFrame += 1
        currentTime = timeForFrame(currentFrame)
    }

    // MARK: - Speed Control

    /// Set playback speed (clamped to 0.5x - 2.0x)
    public mutating func setSpeed(_ newSpeed: Double) {
        speed = max(0.5, min(2.0, newSpeed))
    }

    // MARK: - Time/Frame Conversion

    /// Convert time to frame index
    public func frameForTime(_ time: Double) -> Int {
        Int(round(time * Double(fps)))
    }

    /// Convert frame index to time
    public func timeForFrame(_ frame: Int) -> Double {
        Double(frame) / Double(fps)
    }
}

// MARK: - CustomStringConvertible

extension Timeline: CustomStringConvertible {
    public var description: String {
        """
        Timeline(
            duration: \(duration)s,
            fps: \(fps),
            frames: \(currentFrame)/\(totalFrames),
            time: \(String(format: "%.2f", currentTime))s,
            progress: \(String(format: "%.1f", progress * 100))%,
            playing: \(isPlaying),
            speed: \(speed)x
        )
        """
    }
}
