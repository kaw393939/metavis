import AVFoundation
import Foundation
import Shared

/// Manages the AVAudioEngine graph for multi-track playback
/// Implements the 3-Bus Architecture: Voice, Music, SFX
public final class AudioController: ObservableObject, @unchecked Sendable {
    // MARK: - Core Engine

    private let engine = AVAudioEngine()
    private let mainMixer: AVAudioMixerNode

    // MARK: - Buses

    public let voiceBus = AVAudioMixerNode()
    public let musicBus = AVAudioMixerNode()
    public let sfxBus = AVAudioMixerNode()

    // MARK: - State

    private var tracks: [AudioTrack] = []
    private var players: [String: AVAudioPlayerNode] = [:]
    private var audioFiles: [String: AVAudioFile] = [:]

    public var isEngineRunning: Bool {
        return engine.isRunning
    }

    public init() {
        mainMixer = engine.mainMixerNode
        setupAudioGraph()
    }

    private func setupAudioGraph() {
        // Attach nodes
        engine.attach(voiceBus)
        engine.attach(musicBus)
        engine.attach(sfxBus)

        // Connect buses to main mixer
        // We use the main mixer's output format to ensure compatibility
        let format = mainMixer.outputFormat(forBus: 0)

        engine.connect(voiceBus, to: mainMixer, format: format)
        engine.connect(musicBus, to: mainMixer, format: format)
        engine.connect(sfxBus, to: mainMixer, format: format)

        // Set initial volumes
        voiceBus.outputVolume = 1.0
        musicBus.outputVolume = 0.8 // Slightly lower for background
        sfxBus.outputVolume = 1.0

        // Start engine
        do {
            try engine.start()
            print("✅ AudioController: Engine started")
        } catch {
            print("❌ AudioController: Failed to start engine: \(error)")
        }
    }

    // MARK: - Track Management

    public func loadTracks(_ newTracks: [AudioTrack]) async {
        // Stop existing playback
        stopAll()

        tracks = newTracks
        players.removeAll()
        audioFiles.removeAll()

        print("AudioController: Loading \(newTracks.count) tracks...")

        for track in newTracks {
            do {
                // Verify file exists
                guard FileManager.default.fileExists(atPath: track.url.path) else {
                    print("⚠️ AudioController: File not found: \(track.url.path)")
                    continue
                }

                let file = try AVAudioFile(forReading: track.url)
                audioFiles[track.id] = file

                let player = AVAudioPlayerNode()
                engine.attach(player)

                // Route to correct bus
                let destNode: AVAudioMixerNode
                switch track.type {
                case .voice: destNode = voiceBus
                case .music: destNode = musicBus
                case .sfx: destNode = sfxBus
                }

                engine.connect(player, to: destNode, format: file.processingFormat)
                player.volume = track.volume
                players[track.id] = player

            } catch {
                print("❌ AudioController: Failed to load track \(track.id): \(error)")
            }
        }
    }

    // MARK: - Playback Control

    public func play() {
        if !engine.isRunning {
            try? engine.start()
        }

        // For Phase 1, we just start all players that should be playing at t=0
        // In Phase 2, we will implement the Timeline sync logic
        for (id, player) in players {
            if let track = tracks.first(where: { $0.id == id }) {
                // Simple logic: if start time is 0, play now
                if track.startTime == 0 {
                    if let file = audioFiles[id] {
                        player.scheduleFile(file, at: nil, completionHandler: nil)
                        player.play()
                    }
                }
            }
        }
    }

    public func pause() {
        for player in players.values {
            player.pause()
        }
        engine.pause()
    }

    public func stopAll() {
        for player in players.values {
            player.stop()
            engine.detach(player)
        }
        players.removeAll()
    }

    /// Seek to a specific time in the timeline
    /// - Parameter time: The time in seconds
    public func seek(to time: TimeInterval) {
        // Stop all players first
        for player in players.values {
            player.stop()
        }

        // Reschedule based on the new time
        for track in tracks {
            guard let player = players[track.id],
                  let file = audioFiles[track.id] else { continue }

            // Check if the track should be playing at this time
            let trackEndTime = track.startTime + track.duration

            if time >= track.startTime, time < trackEndTime {
                // Calculate offset into the file
                let offset = time - track.startTime
                let sampleRate = file.processingFormat.sampleRate
                let startFrame = AVAudioFramePosition(offset * sampleRate)
                let frameCount = AVAudioFramePosition((track.duration - offset) * sampleRate)

                if startFrame < file.length {
                    player.scheduleSegment(
                        file,
                        startingFrame: startFrame,
                        frameCount: AVAudioFrameCount(frameCount),
                        at: nil,
                        completionHandler: nil
                    )

                    if engine.isRunning {
                        player.play()
                    }
                }
            }
        }
    }

    // MARK: - Offline Rendering

    /// Configures the engine for offline manual rendering
    /// - Parameters:
    ///   - format: The output format (e.g. 44.1kHz, 2ch)
    ///   - maxFrameCount: The maximum number of frames to render in one pass
    public func enableManualRendering(format: AVAudioFormat, maxFrameCount: AVAudioFrameCount) throws {
        engine.stop()
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maxFrameCount)
        try engine.start()
        print("✅ AudioController: Enabled manual rendering mode")
    }

    /// Renders a chunk of audio data
    /// - Parameter frameCount: Number of frames to render
    /// - Returns: The rendered audio buffer, or nil if failed
    public func renderOffline(frameCount: AVAudioFrameCount) throws -> AVAudioPCMBuffer? {
        guard engine.manualRenderingMode == .offline else {
            throw AudioError.manualRenderingNotEnabled
        }

        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: frameCount)!

        let status = try engine.renderOffline(frameCount, to: buffer)

        switch status {
        case .success:
            return buffer
        case .insufficientDataFromInputNode:
            // This is fine, just means silence
            return buffer
        case .cannotDoInCurrentContext:
            print("⚠️ AudioController: Cannot render in current context")
            return nil
        case .error:
            print("❌ AudioController: Error rendering offline")
            return nil
        @unknown default:
            return nil
        }
    }

    /// Schedules all tracks for playback/rendering
    public func prepareForRendering() {
        // Ensure engine is running (it should be, either in realtime or manual mode)
        if !engine.isRunning {
            try? engine.start()
        }

        let sampleRate = engine.manualRenderingFormat.sampleRate
        _ = sampleRate // Silence unused warning if we want to keep it for clarity, or just remove

        for track in tracks {
            guard let player = players[track.id],
                  let file = audioFiles[track.id] else { continue }

            // Calculate start time in samples
            // CRITICAL FIX: Use the FILE'S sample rate for the time calculation
            // The player node is connected with the file's format, so its timebase is the file's sample rate.
            let fileSampleRate = file.processingFormat.sampleRate
            let startSample = AVAudioFramePosition(track.startTime * fileSampleRate)
            let startTime = AVAudioTime(sampleTime: startSample, atRate: fileSampleRate)

            // Calculate segment
            let startFrame = AVAudioFramePosition(track.offset * fileSampleRate)
            let frameCount = AVAudioFrameCount(track.duration * fileSampleRate)

            print("🎵 Scheduling Track: \(track.id)")
            print("   Start Time: \(track.startTime)s (Sample: \(startSample) @ \(fileSampleRate)Hz)")
            print("   Offset: \(track.offset)s (Frame: \(startFrame))")
            print("   Duration: \(track.duration)s (Frames: \(frameCount))")

            if startFrame < file.length {
                // Schedule the segment
                player.scheduleSegment(
                    file,
                    startingFrame: startFrame,
                    frameCount: frameCount,
                    at: startTime,
                    completionHandler: nil
                )

                // Start the player immediately. It will wait until the scheduled time to emit sound.
                player.play()
            } else {
                print("⚠️ AudioController: Track \(track.id) offset is beyond file length")
            }
        }
        print("✅ AudioController: Scheduled \(tracks.count) tracks for rendering")
    }

    public enum AudioError: Error {
        case manualRenderingNotEnabled
    }
}
