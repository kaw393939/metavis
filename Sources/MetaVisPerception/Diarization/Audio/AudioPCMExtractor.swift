import Foundation
import AVFoundation

public enum AudioPCMExtractor {

    private static func loadFirstAudioTrack(asset: AVAsset) throws -> AVAssetTrack {
        var result: Result<AVAssetTrack, Error>?
        let sema = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let tracks = try await asset.loadTracks(withMediaType: .audio)
                if let track = tracks.first {
                    result = .success(track)
                } else {
                    result = .failure(ExtractError.missingAudioTrack)
                }
            } catch {
                result = .failure(error)
            }
            sema.signal()
        }
        sema.wait()
        switch result {
        case .success(let track):
            return track
        case .failure(let error):
            throw error
        case .none:
            throw ExtractError.readerFailed("loadTracks returned no result")
        }
    }

    private static func loadDuration(asset: AVAsset) throws -> CMTime {
        var result: Result<CMTime, Error>?
        let sema = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let duration = try await asset.load(.duration)
                result = .success(duration)
            } catch {
                result = .failure(error)
            }
            sema.signal()
        }
        sema.wait()
        switch result {
        case .success(let duration):
            return duration
        case .failure:
            return CMTime(seconds: 60.0, preferredTimescale: 600)
        case .none:
            return CMTime(seconds: 60.0, preferredTimescale: 600)
        }
    }

    public enum ExtractError: Error, Sendable, Equatable {
        case missingAudioTrack
        case readerFailed(String)
        case nonFloat32PCM
        case invalidDuration
        case tooManySamples
    }

    /// Reads audio samples as mono float32 at the requested sample rate.
    ///
    /// Notes:
    /// - Uses `AVAssetReader` with output settings to request sample-rate + channel conversion.
    /// - Returns interleaved mono samples.
    public static func readMonoFloat32(
        movieURL: URL,
        startSeconds: Double = 0,
        durationSeconds: Double? = nil,
        targetSampleRate: Double = 16_000,
        maxSamples: Int = 16_000 * 60 * 10
    ) throws -> [Float] {
        guard targetSampleRate > 1 else { throw ExtractError.invalidDuration }

        let asset = AVURLAsset(url: movieURL)
        let track = try loadFirstAudioTrack(asset: asset)

        let reader = try AVAssetReader(asset: asset)

        let start = CMTime(seconds: max(0.0, startSeconds), preferredTimescale: 600)
        let duration: CMTime
        if let durationSeconds {
            duration = CMTime(seconds: max(0.01, durationSeconds), preferredTimescale: 600)
        } else {
            // Default: read full duration.
            let loadedDuration = try loadDuration(asset: asset)
            duration = loadedDuration.isNumeric ? loadedDuration : CMTime(seconds: 60.0, preferredTimescale: 600)
        }

        if duration.seconds.isFinite {
            reader.timeRange = CMTimeRange(start: start, duration: duration)
        }

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ])
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw ExtractError.readerFailed("cannot add audio output")
        }
        reader.add(output)

        guard reader.startReading() else {
            throw ExtractError.readerFailed(reader.error?.localizedDescription ?? "startReading failed")
        }

        var samples: [Float] = []
        samples.reserveCapacity(Int(targetSampleRate * (durationSeconds ?? 10.0)))

        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }

            var length: Int = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            if status != kCMBlockBufferNoErr { continue }
            guard let dataPointer else { continue }

            guard length % MemoryLayout<Float>.size == 0 else { throw ExtractError.nonFloat32PCM }
            let floatCount = length / MemoryLayout<Float>.size

            if samples.count + floatCount > maxSamples {
                throw ExtractError.tooManySamples
            }

            let floats = dataPointer.withMemoryRebound(to: Float.self, capacity: floatCount) { ptr in
                UnsafeBufferPointer(start: ptr, count: floatCount)
            }

            samples.append(contentsOf: floats)
        }

        if reader.status == .failed {
            throw ExtractError.readerFailed(reader.error?.localizedDescription ?? "reader failed")
        }

        return samples
    }
}
