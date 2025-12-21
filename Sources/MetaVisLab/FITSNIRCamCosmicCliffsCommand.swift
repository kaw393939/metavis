import Foundation
import MetaVisCore
import MetaVisIngest

#if canImport(ImageIO) && canImport(CoreGraphics) && canImport(UniformTypeIdentifiers)
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
#endif

enum FITSNIRCamCosmicCliffsCommand {
    struct Options {
        var inputDirURL: URL
        var outputDirURL: URL
        var outputBasename: String

        // Cinematic grading applied only to the final beauty.
        var exposureEV: Float
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
        throw NSError(domain: "MetaVisLab", code: 510, userInfo: [NSLocalizedDescriptionKey: "PNG export requires ImageIO/CoreGraphics/UniformTypeIdentifiers"])
        #else
        let fm = FileManager.default
        try fm.createDirectory(at: options.outputDirURL, withIntermediateDirectories: true)

        let fitsURLs = try fm.contentsOfDirectory(at: options.inputDirURL, includingPropertiesForKeys: nil)
            .filter {
                let ext = $0.pathExtension.lowercased()
                return ext == "fits" || ext == "fit"
            }

        guard !fitsURLs.isEmpty else {
            throw NSError(domain: "MetaVisLab", code: 511, userInfo: [NSLocalizedDescriptionKey: "No .fits files found in: \(options.inputDirURL.path)"])
        }

        func pick(_ token: String) -> URL? {
            fitsURLs.first(where: { $0.lastPathComponent.lowercased().contains(token) })
        }

        // NASA hue mapping (explicit):
        // F090W→Blue, F187N→Cyan, F200W→Green, F470N→Yellow, F335M→Orange, F444W→Red
        guard
            let f090w = pick("f090w"),
            let f187n = pick("f187n"),
            let f200w = pick("f200w"),
            let f470n = pick("f470n"),
            let f335m = pick("f335m"),
            let f444w = pick("f444w")
        else {
            let names = fitsURLs.map { $0.lastPathComponent }.sorted().joined(separator: "\n")
            throw NSError(
                domain: "MetaVisLab",
                code: 512,
                userInfo: [NSLocalizedDescriptionKey: "Expected NIRCam filters f090w/f187n/f200w/f470n/f335m/f444w in filenames under: \(options.inputDirURL.path)\nFound:\n\(names)"]
            )
        }

        print("⏳ Loading FITS bands (NIRCam)…")
        let reader = FITSReader()
        let a090w = try reader.read(url: f090w)
        let a187n = try reader.read(url: f187n)
        let a200w = try reader.read(url: f200w)
        let a470n = try reader.read(url: f470n)
        let a335m = try reader.read(url: f335m)
        let a444w = try reader.read(url: f444w)

        let bands: [(token: String, asset: FITSAsset)] = [
            ("f090w", a090w),
            ("f187n", a187n),
            ("f200w", a200w),
            ("f470n", a470n),
            ("f335m", a335m),
            ("f444w", a444w)
        ]

        guard bands.allSatisfy({ $0.asset.width > 0 && $0.asset.height > 0 }) else {
            throw NSError(domain: "MetaVisLab", code: 513, userInfo: [NSLocalizedDescriptionKey: "Invalid FITS dimensions (one or more bands have non-positive width/height)"])
        }
        guard bands.allSatisfy({ $0.asset.bitpix == -32 }) else {
            throw NSError(domain: "MetaVisLab", code: 515, userInfo: [NSLocalizedDescriptionKey: "Unsupported BITPIX (expected -32 Float32 for all bands)"])
        }

        // Real JWST NIRCam products often have different output grids between short/long channels.
        // Normalize each band at native resolution, then resample to a common working grid.
        let base = bands.max(by: { $0.asset.pixelCount < $1.asset.pixelCount })!.asset
        let w = base.width
        let h = base.height
        let count = w * h

        // P0.5–P99.5 windowing (explicit requirement).
        func computePercentileRange(_ asset: FITSAsset, blackP: Float, whiteP: Float) -> (black: Float, white: Float) {
            let blackP = min(max(blackP, 0.0 as Float), 1.0 as Float)
            let whiteP = min(max(whiteP, 0.0 as Float), 1.0 as Float)

            var minVal: Float = .greatestFiniteMagnitude
            var maxVal: Float = -.greatestFiniteMagnitude
            var finiteCount = 0

            let n = asset.pixelCount

            asset.rawData.withUnsafeBytes { raw in
                let floats = raw.bindMemory(to: Float.self)
                let m = min(floats.count, n)
                for i in 0..<m {
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
                let m = min(floats.count, n)
                for i in 0..<m {
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

        @inline(__always)
        func clamp01(_ x: Float) -> Float { min(max(x, 0), 1) }

        func normalizeWindowed(_ asset: FITSAsset, blackP: Float, whiteP: Float) -> [Float] {
            let (black, white) = computePercentileRange(asset, blackP: blackP, whiteP: whiteP)
            let denom = max(1e-20 as Float, white - black)
            var out = [Float](repeating: 0, count: asset.pixelCount)
            let n = asset.pixelCount
            asset.rawData.withUnsafeBytes { raw in
                let floats = raw.bindMemory(to: Float.self)
                let m = min(floats.count, n)
                for i in 0..<m {
                    let v = floats[i]
                    guard v.isFinite else { out[i] = 0; continue }
                    out[i] = clamp01((v - black) / denom)
                }
            }
            return out
        }

        func resampleBilinear(_ src: [Float], srcW: Int, srcH: Int, dstW: Int, dstH: Int) -> [Float] {
            if srcW == dstW, srcH == dstH { return src }
            if srcW <= 1 || srcH <= 1 || dstW <= 0 || dstH <= 0 {
                return [Float](repeating: 0, count: max(0, dstW * dstH))
            }

            var dst = [Float](repeating: 0, count: dstW * dstH)
            let scaleX = Float(srcW) / Float(dstW)
            let scaleY = Float(srcH) / Float(dstH)

            for y in 0..<dstH {
                let sy = (Float(y) + 0.5 as Float) * scaleY - 0.5 as Float
                let y0 = max(0, min(srcH - 1, Int(floor(sy))))
                let y1 = max(0, min(srcH - 1, y0 + 1))
                let fy = sy - Float(y0)

                for x in 0..<dstW {
                    let sx = (Float(x) + 0.5 as Float) * scaleX - 0.5 as Float
                    let x0 = max(0, min(srcW - 1, Int(floor(sx))))
                    let x1 = max(0, min(srcW - 1, x0 + 1))
                    let fx = sx - Float(x0)

                    let i00 = y0 * srcW + x0
                    let i10 = y0 * srcW + x1
                    let i01 = y1 * srcW + x0
                    let i11 = y1 * srcW + x1

                    let v00 = src[i00]
                    let v10 = src[i10]
                    let v01 = src[i01]
                    let v11 = src[i11]

                    let vx0 = v00 + (v10 - v00) * fx
                    let vx1 = v01 + (v11 - v01) * fx
                    let v = vx0 + (vx1 - vx0) * fy
                    dst[y * dstW + x] = v
                }
            }

            return dst
        }

        print("⏳ Normalizing bands (P0.5–P99.5)…")
        let blackP: Float = 0.005
        let whiteP: Float = 0.995
        func normalizeAndResample(_ asset: FITSAsset) -> [Float] {
            let normalized = normalizeWindowed(asset, blackP: blackP, whiteP: whiteP)
            if asset.width == w, asset.height == h { return normalized }
            print("↪︎ Resampling \(asset.url.lastPathComponent) from \(asset.width)x\(asset.height) → \(w)x\(h)")
            return resampleBilinear(normalized, srcW: asset.width, srcH: asset.height, dstW: w, dstH: h)
        }

        let v090w = normalizeAndResample(a090w)
        let v187n = normalizeAndResample(a187n)
        let v200w = normalizeAndResample(a200w)
        let v470n = normalizeAndResample(a470n)
        let v335m = normalizeAndResample(a335m)
        let v444w = normalizeAndResample(a444w)

        // Composite in linear (pre-grade).
        print("⏳ Building composite + semantic fields…")

        var compR = [Float](repeating: 0, count: count)
        var compG = [Float](repeating: 0, count: count)
        var compB = [Float](repeating: 0, count: count)

        var signal = [Float](repeating: 0, count: count)

        for i in 0..<count {
            // Direct mapping per hue definition (no ad-hoc weighting).
            let r = v470n[i] + v335m[i] + v444w[i]
            let g = v187n[i] + v200w[i] + v470n[i] + 0.5 as Float * v335m[i]
            let b = v090w[i] + v187n[i]

            compR[i] = r
            compG[i] = g
            compB[i] = b

            // A scalar “intensity” used for masks/fields.
            signal[i] = (r + g + b) / 3.0 as Float
        }

        func boxBlur(_ src: [Float], width: Int, height: Int, radius: Int) -> [Float] {
            if radius <= 0 { return src }
            let r = radius
            let kernel = 2 * r + 1

            var tmp = [Float](repeating: 0, count: width * height)
            var dst = [Float](repeating: 0, count: width * height)

            // Horizontal pass (sliding window)
            for y in 0..<height {
                let rowBase = y * width
                var sum: Float = 0
                for x in -r...r {
                    let sx = min(max(x, 0), width - 1)
                    sum += src[rowBase + sx]
                }
                for x in 0..<width {
                    tmp[rowBase + x] = sum / Float(kernel)
                    let xRemove = x - r
                    let xAdd = x + r + 1
                    let rx = min(max(xRemove, 0), width - 1)
                    let ax = min(max(xAdd, 0), width - 1)
                    sum += src[rowBase + ax] - src[rowBase + rx]
                }
            }

            // Vertical pass (sliding window)
            for x in 0..<width {
                var sum: Float = 0
                for y in -r...r {
                    let sy = min(max(y, 0), height - 1)
                    sum += tmp[sy * width + x]
                }
                for y in 0..<height {
                    dst[y * width + x] = sum / Float(kernel)
                    let yRemove = y - r
                    let yAdd = y + r + 1
                    let ry = min(max(yRemove, 0), height - 1)
                    let ay = min(max(yAdd, 0), height - 1)
                    sum += tmp[ay * width + x] - tmp[ry * width + x]
                }
            }

            return dst
        }

        // Star mask: point sources = high-frequency highlights.
        // (Keep deterministic + cheap; intended as an operational mask for spikes.)
        let signalBlurSmall = boxBlur(signal, width: w, height: h, radius: 2)
        var starCandidate = [Float](repeating: 0, count: count)
        var maxStar: Float = 0
        for i in 0..<count {
            let v = max(0, signal[i] - signalBlurSmall[i])
            starCandidate[i] = v
            if v > maxStar { maxStar = v }
        }
        let starT0 = maxStar * 0.10 as Float
        let starT1 = maxStar * 0.35 as Float
        var starMask = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let x = starCandidate[i]
            let t = clamp01((x - starT0) / max(1e-20 as Float, (starT1 - starT0)))
            starMask[i] = t * t * (3.0 as Float - 2.0 as Float * t)
        }

        // Wall / ridge boundary: low-frequency structure + gradient magnitude.
        let wallLF = boxBlur(signal, width: w, height: h, radius: 16)
        var grad = [Float](repeating: 0, count: count)
        var maxGrad: Float = 0
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                let xm = max(x - 1, 0)
                let xp = min(x + 1, w - 1)
                let ym = max(y - 1, 0)
                let yp = min(y + 1, h - 1)
                let dx = wallLF[y * w + xp] - wallLF[y * w + xm]
                let dy = wallLF[yp * w + x] - wallLF[ym * w + x]
                let g = sqrt(dx * dx + dy * dy)
                grad[i] = g
                if g > maxGrad { maxGrad = g }
            }
        }
        let ridgeT0 = maxGrad * 0.18 as Float
        let ridgeT1 = maxGrad * 0.45 as Float
        var ridgeMask = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let x = grad[i]
            let t = clamp01((x - ridgeT0) / max(1e-20 as Float, (ridgeT1 - ridgeT0)))
            ridgeMask[i] = t * t * (3.0 as Float - 2.0 as Float * t)
        }

        // Steam field: mid-frequency wisps near ridge boundary (suppressed for stars).
        let ridgeWide = boxBlur(ridgeMask, width: w, height: h, radius: 8)
        var steam = [Float](repeating: 0, count: count)
        for y in 0..<h {
            let yNorm = Float(y) / Float(max(1, h - 1))
            let lift = pow(1.0 as Float - yNorm, 0.4 as Float)
            for x in 0..<w {
                let i = y * w + x
                let hf = max(0, signal[i] - wallLF[i])
                let v = hf * 2.0 as Float
                steam[i] = clamp01(v) * ridgeWide[i] * (1.0 as Float - starMask[i]) * lift
            }
        }

        // Mandatory debug outputs:
        // - per-filter contribution
        // - star mask
        // - ridge boundary
        // - steam field
        func writeGrayPNG(_ field: [Float], name: String, gamma: Float = 1.0) throws {
            var rgba8 = [UInt8](repeating: 0, count: count * 4)
            let invGamma = 1.0 as Float / max(1e-6 as Float, gamma)
            for i in 0..<count {
                let v = pow(clamp01(field[i]), invGamma)
                let u = UInt8(v * 255.0 + 0.5)
                rgba8[(i * 4) + 0] = u
                rgba8[(i * 4) + 1] = u
                rgba8[(i * 4) + 2] = u
                rgba8[(i * 4) + 3] = 255
            }
            try writePNG(rgba8: rgba8, width: w, height: h, to: options.outputDirURL.appendingPathComponent(name))
        }

        func writeContributionPNG(_ v: [Float], hue: (Float, Float, Float), name: String) throws {
            var rgba8 = [UInt8](repeating: 0, count: count * 4)
            let invGamma = 1.0 as Float / 1.0 as Float
            for i in 0..<count {
                let s = clamp01(v[i])
                let r = pow(clamp01(hue.0 * s), invGamma)
                let g = pow(clamp01(hue.1 * s), invGamma)
                let b = pow(clamp01(hue.2 * s), invGamma)
                rgba8[(i * 4) + 0] = UInt8(r * 255.0 + 0.5)
                rgba8[(i * 4) + 1] = UInt8(g * 255.0 + 0.5)
                rgba8[(i * 4) + 2] = UInt8(b * 255.0 + 0.5)
                rgba8[(i * 4) + 3] = 255
            }
            try writePNG(rgba8: rgba8, width: w, height: h, to: options.outputDirURL.appendingPathComponent(name))
        }

        try writeContributionPNG(v090w, hue: (0, 0, 1), name: "\(options.outputBasename)_filter_f090w.png")
        try writeContributionPNG(v187n, hue: (0, 1, 1), name: "\(options.outputBasename)_filter_f187n.png")
        try writeContributionPNG(v200w, hue: (0, 1, 0), name: "\(options.outputBasename)_filter_f200w.png")
        try writeContributionPNG(v470n, hue: (1, 1, 0), name: "\(options.outputBasename)_filter_f470n.png")
        try writeContributionPNG(v335m, hue: (1, 0.5, 0), name: "\(options.outputBasename)_filter_f335m.png")
        try writeContributionPNG(v444w, hue: (1, 0, 0), name: "\(options.outputBasename)_filter_f444w.png")

        try writeGrayPNG(starMask, name: "\(options.outputBasename)_star_mask.png")
        try writeGrayPNG(ridgeMask, name: "\(options.outputBasename)_ridge_boundary.png")
        try writeGrayPNG(steam, name: "\(options.outputBasename)_steam_field.png")

        // Beauty: add simple Webb-like diffraction spikes driven by starMask, then apply a cinematic grade.
        let spikeX = boxBlur(starMask, width: w, height: h, radius: 12)
        let spikeY = boxBlur(starMask, width: w, height: h, radius: 12)
        var spikes = [Float](repeating: 0, count: count)
        for i in 0..<count {
            spikes[i] = max(spikeX[i], spikeY[i])
        }

        let exposureMul = exp2(options.exposureEV)
        let contrastAmount = max(0.0 as Float, options.contrast)
        let saturationAmount = max(0.0 as Float, options.saturation)
        let outGamma = max(1e-6 as Float, options.gamma)

        @inline(__always)
        func tonemapExp(_ x: Float, shoulder: Float) -> Float {
            let v = 1.0 as Float - exp(-max(0.0 as Float, x) * shoulder)
            return clamp01(v)
        }

        var beautyRGBA8 = [UInt8](repeating: 0, count: count * 4)
        for i in 0..<count {
            var r = compR[i]
            var g = compG[i]
            var b = compB[i]

            // Medium interaction proxy: add steam as a cool veil, and spikes as bright highlights.
            let s = steam[i]
            r += 0.10 as Float * s
            g += 0.14 as Float * s
            b += 0.20 as Float * s

            let sp = spikes[i] * 1.25 as Float
            r += sp
            g += sp
            b += sp

            // Exposure
            r *= exposureMul
            g *= exposureMul
            b *= exposureMul

            // Highlight rolloff
            let shoulder = 1.20 as Float
            r = tonemapExp(r, shoulder: shoulder)
            g = tonemapExp(g, shoulder: shoulder)
            b = tonemapExp(b, shoulder: shoulder)

            // Contrast around 0.5
            r = (r - 0.5 as Float) * contrastAmount + 0.5 as Float
            g = (g - 0.5 as Float) * contrastAmount + 0.5 as Float
            b = (b - 0.5 as Float) * contrastAmount + 0.5 as Float

            // Saturation
            let luma = r * 0.2126 as Float + g * 0.7152 as Float + b * 0.0722 as Float
            r = luma + (r - luma) * saturationAmount
            g = luma + (g - luma) * saturationAmount
            b = luma + (b - luma) * saturationAmount

            // Output gamma
            r = pow(clamp01(r), 1.0 as Float / outGamma)
            g = pow(clamp01(g), 1.0 as Float / outGamma)
            b = pow(clamp01(b), 1.0 as Float / outGamma)

            beautyRGBA8[(i * 4) + 0] = UInt8(clamp01(r) * 255.0 + 0.5)
            beautyRGBA8[(i * 4) + 1] = UInt8(clamp01(g) * 255.0 + 0.5)
            beautyRGBA8[(i * 4) + 2] = UInt8(clamp01(b) * 255.0 + 0.5)
            beautyRGBA8[(i * 4) + 3] = 255
        }

        let beautyURL = options.outputDirURL.appendingPathComponent("\(options.outputBasename)_beauty.png")
        print("⏳ Writing PNGs (\(w)x\(h))…")
        try writePNG(rgba8: beautyRGBA8, width: w, height: h, to: beautyURL)

        print("✅ Wrote Cosmic Cliffs set to: \(options.outputDirURL.path)")
        #endif
    }

    // MARK: - PNG

    #if canImport(ImageIO) && canImport(CoreGraphics) && canImport(UniformTypeIdentifiers)
    private static func writePNG(rgba8: [UInt8], width: Int, height: Int, to url: URL) throws {
        let expected = width * height * 4
        guard rgba8.count == expected else {
            throw NSError(domain: "MetaVisLab", code: 516, userInfo: [NSLocalizedDescriptionKey: "Invalid RGBA buffer size"])
        }

        let data = Data(rgba8)
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw NSError(domain: "MetaVisLab", code: 517, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGDataProvider"])
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
            throw NSError(domain: "MetaVisLab", code: 518, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
        }

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "MetaVisLab", code: 519, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG destination"])
        }

        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "MetaVisLab", code: 520, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize PNG write"])
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
        var basename: String = "cosmic_cliffs"

        var exposureEV: Float = 0.0
        var contrast: Float = 1.12
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
                basename = args[i]
            case "--exposure":
                i += 1
                guard i < args.count else { throw usage("Missing value for --exposure") }
                exposureEV = Float(args[i]) ?? exposureEV
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
        let outURL = URL(fileURLWithPath: outDir ?? "./test_outputs/_fits_cosmic_cliffs")

        return Options(
            inputDirURL: inputURL,
            outputDirURL: outURL,
            outputBasename: basename,
            exposureEV: exposureEV,
            contrast: contrast,
            saturation: saturation,
            gamma: gamma
        )
    }
}
