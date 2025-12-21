import Foundation

/// Utilities for converting RationalTime to/from SMPTE Timecode strings (HH:MM:SS:FF).
public struct Timecode {
    
    /// Formats a RationalTime as a timecode string.
    /// - Parameters:
    ///   - time: The time to format.
    ///   - frameRate: The frame rate to use for frame calculation.
    ///   - dropFrame: Whether to use drop-frame timecode (not fully implemented in this basic version).
    /// - Returns: A string in "HH:MM:SS:FF" format.
    public static func string(from time: RationalTime, at frameRate: RationalTime, dropFrame: Bool = false) -> String {
        // 1. Calculate total frames
        // time (seconds) * frameRate (frames/second)
        // (val/scale) * (frVal/frScale)
        // But frameRate is usually duration of a frame? No, usually frames per second.
        // Let's assume frameRate passed here is "frames per second" (e.g. 30/1 or 30000/1001).
        
        // If frameRate is actually frameDuration (e.g. 1001/30000), we invert it.
        // Let's standardize: The ProjectConfiguration has `frameDuration`.
        // So `frames per second` = 1 / frameDuration.
        
        let fpsNumerator = Int64(frameRate.timescale)
        let fpsDenominator = Int64(frameRate.value)
        
        // Total seconds
        let totalSeconds = Double(time.value) / Double(time.timescale)
        
        // Total frames (approximate for display)
        // For exact math, we should do: (time.value * fpsNumerator) / (time.timescale * fpsDenominator)
        // But we need to be careful about overflow.
        
        // Let's use Double for the calculation to handle the large numbers, then floor.
        // In a strict implementation we'd use 128-bit int.
        let fps = Double(fpsNumerator) / Double(fpsDenominator)
        let totalFrames = Int(floor(totalSeconds * fps))
        
        let frames = totalFrames % Int(fps)
        let seconds = (totalFrames / Int(fps)) % 60
        let minutes = (totalFrames / (Int(fps) * 60)) % 60
        let hours = (totalFrames / (Int(fps) * 3600))
        
        return String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }
    
    /// Calculates the frame number for a given time.
    public static func frameIndex(from time: RationalTime, step: RationalTime) -> Int64 {
        // time / step
        // (tV / tS) / (sV / sS) = (tV * sS) / (tS * sV)
        
        let num = time.value * Int64(step.timescale)
        let den = Int64(time.timescale) * step.value
        
        if den == 0 { return 0 }
        return num / den
    }
}
