import Foundation
import CoreGraphics
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import Metal
import MetaVisPerception
import MetaVisSimulation

enum MobileSAMCommand {

    static func run(args: [String]) async throws {
        guard let sub = args.first else {
            print(help)
            throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing subcommand. Try: MetaVisLab mobilesam segment --help"])
        }

        switch sub {
        case "segment":
            try await MobileSAMSegmentCommand.run(args: Array(args.dropFirst()))
        case "--help", "-h", "help":
            print(help)
        default:
            print(help)
            throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown mobilesam subcommand: \(sub)"])
        }
    }

    static let help = """
    MetaVisLab mobilesam

    Usage:
      MetaVisLab mobilesam segment --input <movie.mov> --time <seconds> --x <0..1> --y <0..1> --out <dir> [--width <w>] [--height <h>] [--label <0|1>] [--cache-key <k>]
                                  [--x2 <0..1> --y2 <0..1> [--label2 <0|1>]]

    Notes:
      - Uses a canonical `cacheKey` by default (asset+time+size) to enable interactive reuse.
      - If --x2/--y2 are provided, runs a second prompt on the same frame with the same cacheKey.
    """
}

enum MobileSAMSegmentCommand {

    struct Options {
        var inputURL: URL
        var timeSeconds: Double
        var width: Int
        var height: Int
        var x: Double
        var y: Double
        var label: Int
        var outDir: URL
        var cacheKey: String?
        var x2: Double?
        var y2: Double?
        var label2: Int
    }

    static func run(args: [String]) async throws {
        if args.first == "--help" || args.first == "-h" {
            print(MobileSAMCommand.help)
            return
        }

        let opt = try parse(args: args)
        try FileManager.default.createDirectory(at: opt.outDir, withIntermediateDirectories: true)

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "MetaVisLab", code: 3, userInfo: [NSLocalizedDescriptionKey: "No Metal device available"])
        }

        let reader = ClipReader(device: device)
        let pb = try await reader.pixelBuffer(assetURL: opt.inputURL, timeSeconds: opt.timeSeconds, width: opt.width, height: opt.height)

        let service = MobileSAMSegmentationService(
            options: .init(enableEmbeddingCache: true)
        )

        let ck = try opt.cacheKey ?? MobileSAMSegmentationService.CacheKey.make(
            url: opt.inputURL,
            timeSeconds: opt.timeSeconds,
            width: opt.width,
            height: opt.height
        )

        let prompt1 = MobileSAMDevice.PointPrompt(pointTopLeft: CGPoint(x: opt.x, y: opt.y), label: opt.label)
        let r1 = await service.segment(pixelBuffer: pb, prompt: prompt1, cacheKey: ck)

        print("mobilesam: input=\(opt.inputURL.lastPathComponent) t=\(String(format: "%.3f", opt.timeSeconds)) size=\(opt.width)x\(opt.height)")
        print("mobilesam: cacheKey=\(ck)")
        print("mobilesam: prompt1=(\(String(format: "%.4f", opt.x)),\(String(format: "%.4f", opt.y))) label=\(opt.label)")
        if let cov = r1.metrics.maskCoverage {
            print("mobilesam: mask1Coverage=\(String(format: "%.5f", cov)) encoderReused=\(r1.metrics.encoderReused == true)")
        } else {
            print("mobilesam: mask1Coverage=nil encoderReused=\(r1.metrics.encoderReused == true)")
        }

        if let mask = r1.mask {
            let outURL = opt.outDir.appendingPathComponent("mobilesam_mask1.png")
            try writeOneComponent8MaskPNG(mask, to: outURL)
            print("✅ Wrote mask: \(outURL.path)")
        } else {
            print("mobilesam: mask1=nil (model missing or inference failed; see evidenceConfidence)")
        }

        if let x2 = opt.x2, let y2 = opt.y2 {
            let prompt2 = MobileSAMDevice.PointPrompt(pointTopLeft: CGPoint(x: x2, y: y2), label: opt.label2)
            let r2 = await service.segment(pixelBuffer: pb, prompt: prompt2, cacheKey: ck)
            print("mobilesam: prompt2=(\(String(format: "%.4f", x2)),\(String(format: "%.4f", y2))) label=\(opt.label2)")
            if let cov = r2.metrics.maskCoverage {
                print("mobilesam: mask2Coverage=\(String(format: "%.5f", cov)) encoderReused=\(r2.metrics.encoderReused == true)")
            } else {
                print("mobilesam: mask2Coverage=nil encoderReused=\(r2.metrics.encoderReused == true)")
            }

            if let mask = r2.mask {
                let outURL = opt.outDir.appendingPathComponent("mobilesam_mask2.png")
                try writeOneComponent8MaskPNG(mask, to: outURL)
                print("✅ Wrote mask: \(outURL.path)")
            } else {
                print("mobilesam: mask2=nil")
            }
        }
    }

    private static func parse(args: [String]) throws -> Options {
        var inputPath: String?
        var outPath: String?
        var timeSeconds: Double = 0.0
        var width: Int = 1024
        var height: Int = 1024
        var x: Double?
        var y: Double?
        var label: Int = 1
        var cacheKey: String?

        var x2: Double?
        var y2: Double?
        var label2: Int = 1

        func parseDouble(_ s: String, _ flag: String) throws -> Double {
            guard let v = Double(s), v.isFinite else {
                throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid value for \(flag): \(s)"])
            }
            return v
        }

        func parseInt(_ s: String, _ flag: String) throws -> Int {
            guard let v = Int(s) else {
                throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid value for \(flag): \(s)"])
            }
            return v
        }

        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--input":
                i += 1; if i < args.count { inputPath = args[i] }
            case "--out":
                i += 1; if i < args.count { outPath = args[i] }
            case "--time":
                i += 1; if i < args.count { timeSeconds = try parseDouble(args[i], "--time") }
            case "--width":
                i += 1; if i < args.count { width = try parseInt(args[i], "--width") }
            case "--height":
                i += 1; if i < args.count { height = try parseInt(args[i], "--height") }
            case "--x":
                i += 1; if i < args.count { x = try parseDouble(args[i], "--x") }
            case "--y":
                i += 1; if i < args.count { y = try parseDouble(args[i], "--y") }
            case "--label":
                i += 1; if i < args.count { label = try parseInt(args[i], "--label") }
            case "--cache-key":
                i += 1; if i < args.count { cacheKey = args[i] }
            case "--x2":
                i += 1; if i < args.count { x2 = try parseDouble(args[i], "--x2") }
            case "--y2":
                i += 1; if i < args.count { y2 = try parseDouble(args[i], "--y2") }
            case "--label2":
                i += 1; if i < args.count { label2 = try parseInt(args[i], "--label2") }
            default:
                break
            }
            i += 1
        }

        guard let inputPath else {
            throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing required flag: --input <movie.mov>"])
        }
        guard let outPath else {
            throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing required flag: --out <dir>"])
        }
        guard let x, let y else {
            throw NSError(domain: "MetaVisLab", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing required flags: --x <0..1> --y <0..1>"])
        }

        func absoluteFileURL(_ path: String) -> URL {
            if path.hasPrefix("/") {
                return URL(fileURLWithPath: path).standardizedFileURL
            }
            let cwd = FileManager.default.currentDirectoryPath
            return URL(fileURLWithPath: cwd).appendingPathComponent(path).standardizedFileURL
        }

        return Options(
            inputURL: absoluteFileURL(inputPath),
            timeSeconds: max(0.0, timeSeconds),
            width: max(16, width),
            height: max(16, height),
            x: x,
            y: y,
            label: label,
            outDir: absoluteFileURL(outPath),
            cacheKey: cacheKey,
            x2: x2,
            y2: y2,
            label2: label2
        )
    }

    private static func writeOneComponent8MaskPNG(_ mask: CVPixelBuffer, to url: URL) throws {
        let w = CVPixelBufferGetWidth(mask)
        let h = CVPixelBufferGetHeight(mask)
        let fmt = CVPixelBufferGetPixelFormatType(mask)
        guard fmt == kCVPixelFormatType_OneComponent8 else {
            throw NSError(domain: "MetaVisLab", code: 5, userInfo: [NSLocalizedDescriptionKey: "Expected OneComponent8 mask, got pixelFormat=\(fmt)"])
        }

        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else {
            throw NSError(domain: "MetaVisLab", code: 6, userInfo: [NSLocalizedDescriptionKey: "Mask had no base address"])
        }

        let bpr = CVPixelBufferGetBytesPerRow(mask)
        let src = base.bindMemory(to: UInt8.self, capacity: bpr * h)

        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        rgba.withUnsafeMutableBytes { dstBytes in
            guard let dst = dstBytes.bindMemory(to: UInt8.self).baseAddress else { return }
            for y in 0..<h {
                let row = src.advanced(by: y * bpr)
                for x in 0..<w {
                    let v = row[x]
                    let o = (y * w + x) * 4
                    dst[o + 0] = v
                    dst[o + 1] = v
                    dst[o + 2] = v
                    dst[o + 3] = 255
                }
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let provider = CGDataProvider(data: Data(rgba) as CFData),
            let cg = CGImage(
                width: w,
                height: h,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: w * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        else {
            throw NSError(domain: "MetaVisLab", code: 7, userInfo: [NSLocalizedDescriptionKey: "Failed to build CGImage for PNG"])
        }

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "MetaVisLab", code: 8, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG destination"])
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "MetaVisLab", code: 9, userInfo: [NSLocalizedDescriptionKey: "Failed to write PNG"])
        }
    }
}
