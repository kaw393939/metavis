import Foundation
import MetaVisCore
import MetaVisIngest

#if canImport(ImageIO) && canImport(CoreGraphics) && canImport(UniformTypeIdentifiers)
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
#endif

enum FITSRenderPNGCommand {
    enum ColorMode: String {
        case gray
    }

    struct Options {
        var inputURL: URL
        var outputDirURL: URL
        var outputFilename: String

        var exposure: Float
        var gamma: Float
        var alpha: Float

        var blackP: Float
        var whiteP: Float
        var mode: ColorMode
    }

    static func run(args: [String]) async throws {
        let options = try parse(args: args)
        try await run(options: options)
    }

    static func run(options: Options) async throws {
        #if !(canImport(ImageIO) && canImport(CoreGraphics) && canImport(UniformTypeIdentifiers))
        throw NSError(domain: "MetaVisLab", code: 490, userInfo: [NSLocalizedDescriptionKey: "PNG export requires ImageIO/CoreGraphics/UniformTypeIdentifiers"])
        #else
        let fm = FileManager.default
        try fm.createDirectory(at: options.outputDirURL, withIntermediateDirectories: true)

        print("⏳ Loading FITS: \(options.inputURL.lastPathComponent)")
        let reader = FITSReader()
        let asset = try reader.read(url: options.inputURL)

        let w = asset.width
        let h = asset.height
        guard w > 0, h > 0 else {
            throw NSError(domain: "MetaVisLab", code: 491, userInfo: [NSLocalizedDescriptionKey: "Invalid FITS dimensions"])
        }
        guard asset.bitpix == -32 else {
            throw NSError(domain: "MetaVisLab", code: 492, userInfo: [NSLocalizedDescriptionKey: "Unsupported BITPIX (expected -32 Float32)"])
        }

        let count = w * h

        func computePercentileRange(_ asset: FITSAsset, blackP: Float, whiteP: Float) -> (black: Float, white: Float) {
            let blackP = min(max(blackP, 0.0 as Float), 1.0 as Float)
            let whiteP = min(max(whiteP, 0.0 as Float), 1.0 as Float)

            var minVal: Float = .greatestFiniteMagnitude
            var maxVal: Float = -.greatestFiniteMagnitude
            var finiteCount = 0

            asset.rawData.withUnsafeBytes { raw in
                let floats = raw.bindMemory(to: Float.self)
                let n = min(floats.count, count)
                for i in 0..<n {
                    let v = floats[i]
                    guard v.isFinite else { continue }
                    if v < minVal { minVal = v }
                    if v > maxVal { maxVal = v }
                    finiteCount += 1
                }
            }

            guard finiteCount > 0, minVal.isFinite, maxVal.isFinite, maxVal > minVal else {
                return (black: 0, white: 1)
            }

            let numBins = 16_384
            var histogram = [Int](repeating: 0, count: numBins)
            let range = maxVal - minVal

            asset.rawData.withUnsafeBytes { raw in
                let floats = raw.bindMemory(to: Float.self)
                let n = min(floats.count, count)
                for i in 0..<n {
                    let v = floats[i]
                    guard v.isFinite else { continue }
                    let t = (v - minVal) / range
                    let bin = Int(t * Float(numBins - 1))
                    let safeBin = min(max(bin, 0), numBins - 1)
                    histogram[safeBin] += 1
                }
            }

            func valueAtPercentile(_ p: Float) -> Float {
                let target = max(1, Int(Float(finiteCount) * p))
                var current = 0
                for i in 0..<numBins {
                    current += histogram[i]
                    if current >= target {
                        let f = Float(i) / Float(numBins - 1)
                        return minVal + f * range
                    }
                }
                return maxVal
            }

            let black = valueAtPercentile(blackP)
            let white = valueAtPercentile(max(whiteP, blackP + 1e-6 as Float))
            return (black: black, white: white)
        }

        print("⏳ Stretching…")
        let (black, white) = computePercentileRange(asset, blackP: options.blackP, whiteP: options.whiteP)
        let denom = max(1e-20 as Float, white - black)

        let exposureMul = exp2(options.exposure)
        let invAsinh = 1.0 / asinh(max(1e-6 as Float, options.alpha))
        let outGamma = max(1e-6 as Float, options.gamma)

        @inline(__always)
        func clamp01(_ x: Float) -> Float { min(max(x, 0), 1) }

        var rgba8 = [UInt8](repeating: 0, count: count * 4)

        asset.rawData.withUnsafeBytes { raw in
            let floats = raw.bindMemory(to: Float.self)
            let n = min(floats.count, count)
            for i in 0..<n {
                let v = floats[i]
                if !v.isFinite {
                    rgba8[(i * 4) + 0] = 0
                    rgba8[(i * 4) + 1] = 0
                    rgba8[(i * 4) + 2] = 0
                    rgba8[(i * 4) + 3] = 255
                    continue
                }

                var x = (v - black) / denom
                x = clamp01(x)

                // Asinh stretch for local contrast (common for astronomical FITS)
                x = asinh(options.alpha * x) * invAsinh

                // Exposure and output gamma (display encoding)
                x = clamp01(x * exposureMul)
                x = pow(x, 1.0 / outGamma)

                let u8 = UInt8(clamp01(x) * 255.0 + 0.5)
                rgba8[(i * 4) + 0] = u8
                rgba8[(i * 4) + 1] = u8
                rgba8[(i * 4) + 2] = u8
                rgba8[(i * 4) + 3] = 255
            }
        }

        let outURL = options.outputDirURL.appendingPathComponent(options.outputFilename)
        print("⏳ Writing PNG (\(w)x\(h))…")
        try writePNG(rgba8: rgba8, width: w, height: h, to: outURL)
        print("✅ Wrote: \(outURL.path)")
        #endif
    }

    #if canImport(ImageIO) && canImport(CoreGraphics) && canImport(UniformTypeIdentifiers)
    private static func writePNG(rgba8: [UInt8], width: Int, height: Int, to url: URL) throws {
        let expected = width * height * 4
        guard rgba8.count == expected else {
            throw NSError(domain: "MetaVisLab", code: 493, userInfo: [NSLocalizedDescriptionKey: "Invalid RGBA buffer size"])
        }

        let data = Data(rgba8)
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw NSError(domain: "MetaVisLab", code: 494, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGDataProvider"])
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw NSError(domain: "MetaVisLab", code: 495, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
        }

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "MetaVisLab", code: 496, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG destination"])
        }

        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "MetaVisLab", code: 497, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize PNG write"])
        }
    }
    #endif

    private static func parse(args: [String]) throws -> Options {
        func usage(_ message: String) -> NSError {
            NSError(domain: "MetaVisLab", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(message)\n\n" + MetaVisLabHelp.text])
        }

        var input: String?
        var outDir: String?
        var outName: String?

        var exposure: Float = 0.0
        var gamma: Float = 1.0
        var alpha: Float = 6.0

        var blackP: Float = 0.01
        var whiteP: Float = 0.999

        var mode: ColorMode = .gray

        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--input":
                i += 1
                guard i < args.count else { throw usage("Missing value for --input") }
                input = args[i]
            case "--out":
                i += 1
                guard i < args.count else { throw usage("Missing value for --out") }
                outDir = args[i]
            case "--name":
                i += 1
                guard i < args.count else { throw usage("Missing value for --name") }
                outName = args[i]
            case "--exposure":
                i += 1
                guard i < args.count else { throw usage("Missing value for --exposure") }
                exposure = Float(args[i]) ?? exposure
            case "--gamma":
                i += 1
                guard i < args.count else { throw usage("Missing value for --gamma") }
                gamma = Float(args[i]) ?? gamma
            case "--alpha":
                i += 1
                guard i < args.count else { throw usage("Missing value for --alpha") }
                alpha = Float(args[i]) ?? alpha
            case "--black-p":
                i += 1
                guard i < args.count else { throw usage("Missing value for --black-p") }
                blackP = Float(args[i]) ?? blackP
            case "--white-p":
                i += 1
                guard i < args.count else { throw usage("Missing value for --white-p") }
                whiteP = Float(args[i]) ?? whiteP
            case "--mode":
                i += 1
                guard i < args.count else { throw usage("Missing value for --mode") }
                mode = ColorMode(rawValue: args[i]) ?? mode
            default:
                if a.hasPrefix("-") {
                    throw usage("Unknown option: \(a)")
                }
            }
            i += 1
        }

        guard let input else {
            throw usage("Missing required --input <file.fits>")
        }

        let inputURL = URL(fileURLWithPath: input)
        let outputDirURL = URL(fileURLWithPath: outDir ?? "./test_outputs/_fits_render_png")
        let outputFilename = outName ?? (inputURL.deletingPathExtension().lastPathComponent + "_render.png")

        return Options(
            inputURL: inputURL,
            outputDirURL: outputDirURL,
            outputFilename: outputFilename,
            exposure: exposure,
            gamma: gamma,
            alpha: alpha,
            blackP: blackP,
            whiteP: whiteP,
            mode: mode
        )
    }
}
