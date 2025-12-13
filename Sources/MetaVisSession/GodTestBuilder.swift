import Foundation
import MetaVisCore
import MetaVisTimeline

/// Factory for creating the "God Test" reference timeline.
public struct GodTestBuilder {
    
    public static func build() -> Timeline {
        
        // Duration: 20 Seconds
        let totalDuration = Time(seconds: 20.0)
        
        // --- Video Track ---
        var videoClips: [Clip] = []
        
        // 1. SMPTE Bars (0-5s)
        videoClips.append(Clip(
            name: "SMPTE Bars",
            asset: AssetReference(sourceFn: "ligm://video/smpte_bars"),
            startTime: Time(seconds: 0),
            duration: Time(seconds: 5)
        ))
        
        // 2. Macbeth Chart (5-10s)
        videoClips.append(Clip(
            name: "Macbeth Chart",
            asset: AssetReference(sourceFn: "ligm://video/macbeth"),
            startTime: Time(seconds: 5),
            duration: Time(seconds: 5)
        ))
        
        // 3. Zone Plate (10-15s)
        videoClips.append(Clip(
            name: "Zone Plate",
            asset: AssetReference(sourceFn: "ligm://video/zone_plate?speed=1.0"),
            startTime: Time(seconds: 10),
            duration: Time(seconds: 5)
        ))
        
        // 4. Frame Counter (15-20s) - Fallback to SMPTE for now if Counter not ready
        videoClips.append(Clip(
            name: "Frame Counter",
            asset: AssetReference(sourceFn: "ligm://video/frame_counter"),
            startTime: Time(seconds: 15),
            duration: Time(seconds: 5)
        ))
        
        let videoTrack = Track(name: "Reference Video", kind: .video, clips: videoClips)
        
        // --- Audio Track ---
        var audioClips: [Clip] = []
        
        // 1. 1kHz Tone (0-5s)
        audioClips.append(Clip(
            name: "1kHz Tone",
            asset: AssetReference(sourceFn: "ligm://audio/sine?freq=1000"),
            startTime: Time(seconds: 0),
            duration: Time(seconds: 5)
        ))
        
        // 2. Pink Noise (5-10s)
        audioClips.append(Clip(
            name: "Pink Noise",
            asset: AssetReference(sourceFn: "ligm://audio/pink_noise"),
            startTime: Time(seconds: 5),
            duration: Time(seconds: 5)
        ))
        
        // 3. Log Sweep (10-15s)
        // 20Hz to 20kHz
        audioClips.append(Clip(
            name: "Log Sweep",
            asset: AssetReference(sourceFn: "ligm://audio/sweep?start=20&end=20000"),
            startTime: Time(seconds: 10),
            duration: Time(seconds: 5)
        ))
        
        // 4. Impulse (15-20s)
        audioClips.append(Clip(
            name: "Impulse",
            asset: AssetReference(sourceFn: "ligm://audio/impulse?interval=1.0"),
            startTime: Time(seconds: 15),
            duration: Time(seconds: 5)
        ))
        
        let audioTrack = Track(name: "Reference Audio", kind: .audio, clips: audioClips)
        
        return Timeline(tracks: [videoTrack, audioTrack], duration: totalDuration)
    }
}
