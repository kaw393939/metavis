import Foundation
import Metal
import MetaVisSimulation
import AVFoundation

enum ProbeClipCommand {
    static func run(args: [String]) async throws {
        var inputPath: String?
        var width: Int = 1920
        var height: Int = 1080
        var startSeconds: Double = 0.0
        var endSeconds: Double = 2.5
        var stepSeconds: Double = 1.0 / 24.0

        var i = 0
        while i < args.count {
            switch args[i] {
            case "--input":
                i += 1
                inputPath = (i < args.count) ? args[i] : nil
            case "--width":
                i += 1
                if i < args.count { width = Int(args[i]) ?? width }
            case "--height":
                i += 1
                if i < args.count { height = Int(args[i]) ?? height }
            case "--start":
                i += 1
                if i < args.count { startSeconds = Double(args[i]) ?? startSeconds }
            case "--end":
                i += 1
                if i < args.count { endSeconds = Double(args[i]) ?? endSeconds }
            case "--step":
                i += 1
                if i < args.count { stepSeconds = Double(args[i]) ?? stepSeconds }
            case "--help", "-h":
                print(help)
                return
            default:
                break
            }
            i += 1
        }

        guard let inputPath else {
            print(help)
            throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing --input <path>"])
        }

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "MetaVisLab", code: 3, userInfo: [NSLocalizedDescriptionKey: "No Metal device available"])
        }

        let url = URL(fileURLWithPath: inputPath)
        var times: [Double] = []
        if stepSeconds <= 0 {
            throw NSError(domain: "MetaVisLab", code: 4, userInfo: [NSLocalizedDescriptionKey: "--step must be > 0"])
        }

        var t = startSeconds
        while t <= endSeconds + 1e-9 {
            times.append(t)
            t += stepSeconds
        }

        print("probe-clip: \(url.lastPathComponent) (\(width)x\(height))")
        print(String(format: "range: start=%.3fs end=%.3fs step=%.5fs", startSeconds, endSeconds, stepSeconds))

        // Sanity: prove AVAssetReader works in this process (isolates ClipReader issues).
        do {
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            if let track = tracks.first {
                let avReader = try AVAssetReader(asset: asset)
                let settings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                let out = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
                out.alwaysCopiesSampleData = false
                if avReader.canAdd(out) {
                    avReader.add(out)
                    let started = avReader.startReading()
                    let first = out.copyNextSampleBuffer()
                    print("direct-avreader: started=\(started) status=\(avReader.status.rawValue) firstSample=\(first != nil) err=\(String(describing: avReader.error))")
                } else {
                    print("direct-avreader: cannot add output")
                }
            } else {
                print("direct-avreader: no video tracks")
            }
        } catch {
            print("direct-avreader: error: \(error)")
        }

        let results = await ClipReaderProbe.probe(device: device, assetURL: url, times: times, width: width, height: height)
        let okCount = results.filter { $0.success }.count
        let failCount = results.count - okCount
        for r in results {
            if r.success {
                print(String(format: "t=%.3fs ok", r.timeSeconds))
            } else {
                print(String(format: "t=%.3fs FAIL: %@", r.timeSeconds, r.errorDescription ?? "unknown"))
            }
        }
        print("done: ok=\(okCount) fail=\(failCount)")
    }

    private static let help = """
    probe-clip

    Usage:
      MetaVisLab probe-clip --input <movie.mp4> [--width <w>] [--height <h>] [--start <s>] [--end <s>] [--step <s>]

    Example:
      MetaVisLab probe-clip --input assets/liquid_chrome.mp4 --start 0 --end 1 --step 0.0416667
    """
}
