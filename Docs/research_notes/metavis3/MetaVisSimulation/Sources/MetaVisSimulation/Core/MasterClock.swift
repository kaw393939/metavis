import Foundation
import CoreMedia

/// The Master Clock for the MetaVis Simulation Engine.
///
/// This clock unifies Audio and Video timebases.
/// In "Offline" mode, it drives the render loop deterministically.
/// In "Live" mode, it slaves to the Audio Hardware clock to prevent drift.
public actor MasterClock {
    
    public enum Mode: Sendable {
        case offline
        case live
    }
    
    public private(set) var mode: Mode
    public private(set) var currentTime: CMTime = .zero
    public private(set) var frameRate: Int32 = 60
    
    public init(mode: Mode = .offline, frameRate: Int32 = 60) {
        self.mode = mode
        self.frameRate = frameRate
    }
    
    /// Advances the clock by one frame (Offline Mode only)
    public func tick() {
        guard mode == .offline else { return }
        let frameDuration = CMTime(value: 1, timescale: frameRate)
        currentTime = currentTime + frameDuration
    }
    
    /// Syncs to an external time source (Live Mode only)
    public func sync(to time: CMTime) {
        guard mode == .live else { return }
        currentTime = time
    }
    
    /// Resets the clock to zero
    public func reset() {
        currentTime = .zero
    }
    
    /// Seeks to a specific time (Offline Mode only)
    public func seek(to time: CMTime) {
        guard mode == .offline else { return }
        currentTime = time
    }
}
