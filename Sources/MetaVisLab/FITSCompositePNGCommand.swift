import Foundation
import MetaVisCore
import MetaVisIngest

#if canImport(ImageIO) && canImport(CoreGraphics) && canImport(UniformTypeIdentifiers)
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
#endif

enum FITSCompositePNGCommand {
    struct Options {
        var inputDirURL: URL
        var outputDirURL: URL
        var outputFilename: String

        var exposure: Float
        var contrast: Float
        var saturation: Float
        var gamma: Float
    }

    static func run(args: [String]) async throws {
        let options = try parse(args: args)
        try await run(options: options)
    }

    static func run(options: Options) async throws {
        #if !(canImport(ImageIO) && canImport(CoreGraphics) && canImport(UniformTypeIdentifiers))
        throw NSError(domain: "MetaVisLab", code: 470, userInfo: [NSLocalizedDescriptionKey: "PNG export requires ImageIO/CoreGraphics/UniformTypeIdentifiers"]) 
        #else
        let fm = FileManager.default
        try fm.createDirectory(at: options.outputDirURL, withIntermediateDirectories: true)

        let fitsURLs = try fm.contentsOfDirectory(at: options.inputDirURL, includingPropertiesForKeys: nil)
            .filter {
                let ext = $0.pathExtension.lowercased()
                return ext == "fits" || ext == "fit"
            }

        guard !fitsURLs.isEmpty else {
            throw NSError(domain: "MetaVisLab", code: 471, userInfo: [NSLocalizedDescriptionKey: "No .fits files found in: \(options.inputDirURL.path)"])
        }

        func pick(_ token: String) -> URL? {
            fitsURLs.first(where: { $0.lastPathComponent.lowercased().contains(token) })
        }

        guard
            let f770 = pick("f770"),
            let f1130 = pick("f1130"),
            let f1280 = pick("f1280"),
            let f1800 = pick("f1800")
        else {
            let names = fitsURLs.map { $0.lastPathComponent }.sorted().joined(separator: "\n")
            throw NSError(
                domain: "MetaVisLab",
                code: 472,
                userInfo: [NSLocalizedDescriptionKey: "Expected JWST MIRI filters f770w/f1130w/f1280w/f1800w in filenames under: \(options.inputDirURL.path)\nFound:\n\(names)"]
            )
        }

        print("⏳ Loading FITS bands…")
        let reader = FITSReader()
        let a770 = try reader.read(url: f770)
        let a1130 = try reader.read(url: f1130)
        let a1280 = try reader.read(url: f1280)
        let a1800 = try reader.read(url: f1800)

        let w = a770.width
        let h = a770.height
        guard w > 0, h > 0 else {
            throw NSError(domain: "MetaVisLab", code: 473, userInfo: [NSLocalizedDescriptionKey: "Invalid FITS dimensions"]) 
        }
        guard a1130.width == w, a1130.height == h, a1280.width == w, a1280.height == h, a1800.width == w, a1800.height == h else {
            throw NSError(domain: "MetaVisLab", code: 474, userInfo: [NSLocalizedDescriptionKey: "FITS band dimensions do not match (expected all \(w)x\(h))"]) 
        }
        guard a770.bitpix == -32, a1130.bitpix == -32, a1280.bitpix == -32, a1800.bitpix == -32 else {
            throw NSError(domain: "MetaVisLab", code: 475, userInfo: [NSLocalizedDescriptionKey: "Unsupported BITPIX (expected -32 Float32 for all bands)"]) 
        }

        let count = w * h

        func computePercentileRange(_ asset: FITSAsset, blackP: Float, whiteP: Float) -> (black: Float, white: Float) {
            let blackP = min(max(blackP, 0.0 as Float), 1.0 as Float)
            let whiteP = min(max(whiteP, 0.0 as Float), 1.0 as Float)

            // Deterministic histogram percentiles (similar to FITSReader.computeStats, but local)
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

        func stretch(_ asset: FITSAsset, alpha: Float) -> [Float] {
            // Use percentiles instead of min/max to avoid single hot pixels blowing out the stretch.
            let (black, white) = computePercentileRange(asset, blackP: 0.01, whiteP: 0.999)
            let denom = max(1e-20 as Float, white - black)
            let invAsinh = 1.0 / asinh(max(1e-6 as Float, alpha))

            var out = [Float](repeating: 0, count: count)
            asset.rawData.withUnsafeBytes { raw in
                let floats = raw.bindMemory(to: Float.self)
                let n = min(floats.count, count)
                for i in 0..<n {
                    let v = floats[i]
                    if !v.isFinite {
                        out[i] = 0
                        continue
                    }
                    var x = (v - black) / denom
                    x = min(max(x, 0), 1)
                    // Asinh stretch normalized to [0,1]
                    x = asinh(alpha * x) * invAsinh
                    out[i] = min(max(x, 0), 1)
                }
            }
            return out
        }

        // Softer stretch than before; we'll do highlight rolloff after compositing.
        let v770 = stretch(a770, alpha: 5.0)
        let v1130 = stretch(a1130, alpha: 4.0)
        let v1280 = stretch(a1280, alpha: 3.5)
        let v1800 = stretch(a1800, alpha: 3.0)

        print("⏳ Compositing to RGB…")

        // Weighting modeled after a JWST-style false color mapping.
        // Shorter wavelength pushes blue/cyan; longer wavelength pushes orange/gold.
        var rgba8 = [UInt8](repeating: 0, count: count * 4)

        let exposureMul = exp2(options.exposure)
        let contrastAmount = max(0.0 as Float, options.contrast)
        let saturationAmount = max(0.0 as Float, options.saturation)
        let outGamma = max(1e-6 as Float, options.gamma)

        @inline(__always)
        func clamp01(_ x: Float) -> Float { min(max(x, 0), 1) }

        @inline(__always)
        func tonemapExp(_ x: Float, shoulder: Float) -> Float {
            // Smooth highlight rolloff. x is assumed >= 0.
            let v = 1.0 as Float - exp(-x * shoulder)
            return clamp01(v)
        }

        for i in 0..<count {
            // Rebalanced weights to avoid global gold cast.
            var r = 0.85 as Float * v1800[i] + 0.30 as Float * v1280[i] + 0.10 as Float * v1130[i] + 0.00 as Float * v770[i]
            var g = 0.08 as Float * v1800[i] + 0.65 as Float * v1280[i] + 0.25 as Float * v1130[i] + 0.18 as Float * v770[i]
            var b = 0.00 as Float * v1800[i] + 0.12 as Float * v1280[i] + 0.35 as Float * v1130[i] + 0.90 as Float * v770[i]

            let m = max(r, max(g, b))
            if m > 1 {
                let inv = 1.0 / m
                r *= inv
                g *= inv
                b *= inv
            }

            // Global exposure
            r *= exposureMul
            g *= exposureMul
            b *= exposureMul

            // Highlight compression BEFORE contrast/gamma to keep stars and hot regions from clipping.
            // Higher shoulder -> brighter overall; lower -> more conservative.
            let shoulder = 1.25 as Float
            r = tonemapExp(max(0.0 as Float, r), shoulder: shoulder)
            g = tonemapExp(max(0.0 as Float, g), shoulder: shoulder)
            b = tonemapExp(max(0.0 as Float, b), shoulder: shoulder)

            // Contrast around 0.5
            r = (r - 0.5 as Float) * contrastAmount + 0.5 as Float
            g = (g - 0.5 as Float) * contrastAmount + 0.5 as Float
            b = (b - 0.5 as Float) * contrastAmount + 0.5 as Float

            // Saturation
            let luma = r * 0.2126 as Float + g * 0.7152 as Float + b * 0.0722 as Float
            r = luma + (r - luma) * saturationAmount
            g = luma + (g - luma) * saturationAmount
            b = luma + (b - luma) * saturationAmount

            // Output gamma (approx display encoding)
            r = pow(clamp01(r), 1.0 / outGamma)
            g = pow(clamp01(g), 1.0 / outGamma)
            b = pow(clamp01(b), 1.0 / outGamma)

            rgba8[(i * 4) + 0] = UInt8(clamp01(r) * 255.0 + 0.5)
            rgba8[(i * 4) + 1] = UInt8(clamp01(g) * 255.0 + 0.5)
            rgba8[(i * 4) + 2] = UInt8(clamp01(b) * 255.0 + 0.5)
            rgba8[(i * 4) + 3] = 255
        }

        let outURL = options.outputDirURL.appendingPathComponent(options.outputFilename)

        print("⏳ Writing PNG (\(w)x\(h))…")
        try writePNG(rgba8: rgba8, width: w, height: h, to: outURL)
        print("✅ Wrote: \(outURL.path)")
        #endif
    }

    // MARK: - PNG

    #if canImport(ImageIO) && canImport(CoreGraphics) && canImport(UniformTypeIdentifiers)
    private static func writePNG(rgba8: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard width > 0, height > 0 else {
            throw NSError(domain: "MetaVisLab", code: 476, userInfo: [NSLocalizedDescriptionKey: "Invalid output dimensions"]) 
        }
        let expected = width * height * 4
        guard rgba8.count == expected else {
            throw NSError(domain: "MetaVisLab", code: 477, userInfo: [NSLocalizedDescriptionKey: "Invalid RGBA buffer size"]) 
        }

        let data = Data(rgba8)
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw NSError(domain: "MetaVisLab", code: 478, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGDataProvider"]) 
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
            throw NSError(domain: "MetaVisLab", code: 479, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"]) 
        }

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "MetaVisLab", code: 480, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG destination"]) 
        }

        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "MetaVisLab", code: 481, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize PNG write"]) 
        }
    }
    #endif

    // MARK: - Parsing

    private static func parse(args: [String]) throws -> Options {
        func usage(_ message: String) -> NSError {
            NSError(domain: "MetaVisLab", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(message)\n\n" + MetaVisLabHelp.text])
        }

        var inputDir: String?
        var outDir: String?
        var outName: String = "fits_composite.png"

        var exposure: Float = 0.15
        var contrast: Float = 1.18
        var saturation: Float = 1.08
        var gamma: Float = 1.0

        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--input-dir":
                i += 1
                guard i < args.count else { throw usage("Missing value for --input-dir") }
                inputDir = args[i]
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
            case "--contrast":
                i += 1
                guard i < args.count else { throw usage("Missing value for --contrast") }
                contrast = Float(args[i]) ?? contrast
            case "--saturation":
                i += 1
                guard i < args.count else { throw usage("Missing value for --saturation") }
                saturation = Float(args[i]) ?? saturation
            case "--gamma":
                i += 1
                guard i < args.count else { throw usage("Missing value for --gamma") }
                gamma = Float(args[i]) ?? gamma
            default:
                if a.hasPrefix("-") {
                    throw usage("Unknown option: \(a)")
                }
            }
            i += 1
        }

        let inputURL = URL(fileURLWithPath: inputDir ?? "./Tests/Assets/fits")
        let outURL = URL(fileURLWithPath: outDir ?? "./test_outputs/_fits_composite_png")

        return Options(
            inputDirURL: inputURL,
            outputDirURL: outURL,
            outputFilename: outName,
            exposure: exposure,
            contrast: contrast,
            saturation: saturation,
            gamma: gamma
        )
    }
}
