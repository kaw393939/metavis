// ProbeCommand.swift
// MetaVisCLI
//
// Sprint 03: Media probe command
// Extracts detailed technical metadata from a single file

import Foundation
import ArgumentParser
import MetaVisRender

struct Probe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Probe a media file for detailed technical metadata",
        discussion: """
            Extracts comprehensive metadata from a media file including
            codec details, HDR information, timecode, and audio tracks.
            
            Examples:
              metavis probe video.mov
              metavis probe --json --output metadata.json video.mov
              metavis probe --all interview.mp4
            """
    )
    
    // MARK: - Arguments
    
    @Argument(help: "Path to the media file to probe")
    var input: String
    
    @Option(name: .shortAndLong, help: "Output path for probe results")
    var output: String?
    
    // MARK: - Output Options
    
    @Flag(name: .long, help: "Output as JSON")
    var json: Bool = false
    
    @Flag(name: .long, help: "Show all available metadata")
    var all: Bool = false
    
    @Flag(name: .long, help: "Include raw track information")
    var tracks: Bool = false
    
    @Flag(name: .long, help: "Include HDR metadata details")
    var hdr: Bool = false
    
    @Flag(name: .long, help: "Include color space details")
    var color: Bool = false
    
    @Flag(name: .long, help: "Include timecode information")
    var timecode: Bool = false
    
    // MARK: - Run
    
    mutating func run() async throws {
        let inputURL = URL(fileURLWithPath: input)
        
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            print("Error: File not found: \(inputURL.path)")
            throw ExitCode.failure
        }
        
        if !json {
            print("Probing \(inputURL.lastPathComponent)...")
            print("")
        }
        
        let profile = try await EnhancedMediaProbe.probe(inputURL)
        
        if json {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(profile)
            
            if let outputPath = output {
                try data.write(to: URL(fileURLWithPath: outputPath))
                print("Results written to \(outputPath)")
            } else if let jsonString = String(data: data, encoding: .utf8) {
                print(jsonString)
            }
        } else {
            printHumanReadable(profile)
        }
    }
    
    private func printHumanReadable(_ profile: EnhancedMediaProfile) {
        // Basic info
        print("File: \(profile.filename)")
        print("Container: \(profile.container.rawValue)")
        print("Duration: \(profile.durationFormatted)")
        print("File Size: \(profile.fileSizeFormatted)")
        if let created = profile.creationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            print("Created: \(formatter.string(from: created))")
        }
        print("")
        
        // Video track
        if let video = profile.video {
            print("VIDEO:")
            print("  Codec: \(video.codec.rawValue)")
            let (width, height) = video.effectiveSize
            print("  Resolution: \(width)×\(height)")
            print("  Frame Rate: \(String(format: "%.3f", video.fps)) fps")
            if let br = video.bitrate {
                print("  Bit Rate: \(formatBitrate(br))")
            }
            print("  Bit Depth: \(video.bitDepth) bit")
            
            if all || color {
                print("  Color Space: \(video.colorSpace.primaries.displayName)")
                print("  Transfer: \(video.colorSpace.transfer.displayName)")
                if let matrix = video.colorSpace.matrix {
                    print("  Matrix: \(matrix)")
                }
            }
            
            if all || hdr {
                if let hdrMeta = video.colorSpace.hdrMetadata, hdrMeta.hasMetadata {
                    print("  HDR: Yes")
                    if let maxCLL = hdrMeta.maxContentLightLevel {
                        print("    Max CLL: \(Int(maxCLL)) nits")
                    }
                    if let maxFrameAverage = hdrMeta.maxFrameAverageLightLevel {
                        print("    Max FALL: \(Int(maxFrameAverage)) nits")
                    }
                } else {
                    print("  HDR: No")
                }
            }
            
            if video.rotation != 0 {
                print("  Rotation: \(video.rotation)°")
            }
            print("")
        }
        
        // Audio tracks
        if !profile.audioTracks.isEmpty {
            print("AUDIO TRACKS:")
            for (index, track) in profile.audioTracks.enumerated() {
                print("  Track \(index + 1):")
                print("    Codec: \(track.codec.rawValue)")
                print("    Sample Rate: \(formatSampleRate(track.sampleRate))")
                print("    Channels: \(track.channels) (\(track.channelLayout.rawValue))")
                if let bd = track.bitDepth {
                    print("    Bit Depth: \(bd) bit")
                }
                if let br = track.bitrate {
                    print("    Bit Rate: \(formatBitrate(br))")
                }
                
                if track.isSpatial {
                    print("    Spatial: Yes")
                }
                
                if let lang = track.language {
                    print("    Language: \(lang)")
                }
            }
            print("")
        }
        
        // Timecode
        if all || timecode {
            if let tc = profile.startTimecode {
                print("TIMECODE:")
                print("  Start: \(tc.description)")
                if let frames = profile.frameCount {
                    print("  Frame Count: \(frames)")
                }
                print("")
            }
        }
        
        // Summary
        print("SUMMARY:")
        print("  Has Video: \(profile.hasVideo ? "Yes" : "No")")
        print("  Has Audio: \(profile.hasAudio ? "Yes" : "No")")
    }
    
    private func formatBitrate(_ bps: Int) -> String {
        if bps >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bps) / 1_000_000)
        } else if bps >= 1000 {
            return String(format: "%.0f Kbps", Double(bps) / 1000)
        } else {
            return "\(bps) bps"
        }
    }
    
    private func formatSampleRate(_ hz: Int) -> String {
        if hz >= 1000 {
            return String(format: "%.1f kHz", Double(hz) / 1000)
        } else {
            return "\(hz) Hz"
        }
    }
}
