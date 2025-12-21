import Foundation
import MetaVisCore
import MetaVisSimulation
import simd

#if canImport(ImageIO) && canImport(CoreGraphics) && canImport(UniformTypeIdentifiers)
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
#endif

enum NebulaDebugCommand {
    struct Options {
        var outDirURL: URL
        var width: Int
        var height: Int
    }

    static func run(args: [String]) async throws {
        let options = try parse(args: args)
        try await run(options: options)
    }

    static func run(options: Options) async throws {
        #if !(canImport(ImageIO) && canImport(CoreGraphics) && canImport(UniformTypeIdentifiers))
        throw NSError(domain: "MetaVisLab", code: 880, userInfo: [NSLocalizedDescriptionKey: "Nebula debug requires ImageIO/CoreGraphics/UniformTypeIdentifiers"])
        #else
        let fm = FileManager.default
        try fm.createDirectory(at: options.outDirURL, withIntermediateDirectories: true)

        let engine = try MetalSimulationEngine()
        try await engine.configure()

        // Pillars-like framing: slightly elevated, looking into the volume.
        let camPos = SIMD3<Double>(0.0, 1.5, 12.0)
        let target = SIMD3<Double>(0.0, -1.0, -2.0)
        let forward = simd_normalize(target - camPos)
        let worldUp = SIMD3<Double>(0, 1, 0)
        let right = simd_normalize(simd_cross(forward, worldUp))
        let up = simd_normalize(simd_cross(right, forward))

        // Graph: depth_one -> fx_volumetric_nebula -> odt_acescg_to_rec709
        func renderNebula(debugMode: Double, name: String) async throws {
            let depth = RenderNode(name: "DepthOne", shader: "depth_one")
            let nebula = RenderNode(
                name: "Nebula",
                shader: "fx_volumetric_nebula",
                inputs: ["depth": depth.id],
                parameters: [
                    "cameraPosition": .vector3(camPos),
                    "cameraForward": .vector3(forward),
                    "cameraUp": .vector3(up),
                    "cameraRight": .vector3(right),
                    "fov": .float(60),
                    "aspectRatio": .float(Double(options.width) / Double(options.height)),

                    "volumeMin": .vector3(SIMD3<Double>(-10, -10, -10)),
                    "volumeMax": .vector3(SIMD3<Double>(10, 10, 10)),

                    "baseFrequency": .float(1.0),
                    "octaves": .float(3),
                    "lacunarity": .float(2.0),
                    "gain": .float(0.5),
                    "densityScale": .float(2.4),
                    "densityOffset": .float(0.0),
                    "time": .float(0.0),
                    "windVelocity": .vector3(SIMD3<Double>(0.06, 0.0, 0.0)),

                    // Back/side light to get bright rims on dust columns.
                    "lightDirection": .vector3(SIMD3<Double>(-0.35, -0.15, 0.92)),
                    "lightColor": .vector3(SIMD3<Double>(1.0, 0.98, 0.90)),
                    "ambientIntensity": .float(0.10),

                    "scatteringCoeff": .float(1.10),
                    "absorptionCoeff": .float(0.10),
                    "phaseG": .float(0.45),

                    "maxSteps": .float(96),
                    "shadowSteps": .float(6),
                    "stepSize": .float(0.09),

                    // Palette: warm dusty pillars + cooler surrounding glow.
                    "emissionColorWarm": .vector3(SIMD3<Double>(1.15, 0.55, 0.16)),
                    "emissionColorCool": .vector3(SIMD3<Double>(0.10, 0.38, 0.95)),
                    "emissionIntensity": .float(1.25),
                    "hdrScale": .float(1.0),
                    "debugMode": .float(debugMode)
                ]
            )

            // Beauty should be viewable (ACEScg -> Rec709). Debug outputs must bypass ODT
            // so their numeric values (e.g. 0.65 cap) survive unchanged.
            let graph: RenderGraph
            if debugMode < 0.5 {
                let odt = RenderNode(
                    name: "ODT",
                    shader: "odt_acescg_to_rec709",
                    inputs: ["input": nebula.id]
                )
                graph = RenderGraph(nodes: [depth, nebula, odt], rootNodeID: odt.id)
            } else {
                graph = RenderGraph(nodes: [depth, nebula], rootNodeID: nebula.id)
            }
            let quality = QualityProfile(name: "NebulaDebug", fidelity: .high, resolutionHeight: options.height, colorDepth: 10)
            let req = RenderRequest(graph: graph, time: .zero, quality: quality)

            let result = try await engine.render(request: req)
            guard let data = result.imageBuffer else {
                throw NSError(domain: "MetaVisLab", code: 881, userInfo: [NSLocalizedDescriptionKey: "No imageBuffer from engine render"])
            }

            let outURL = options.outDirURL.appendingPathComponent(name)
            try writeRGBA16FloatAsPNG(floatRGBA: data, width: options.width, height: options.height, to: outURL)
            print("✅ Wrote: \(outURL.path)")

            if debugMode >= 2.5 && debugMode < 3.5 {
                let histURL = options.outDirURL.appendingPathComponent("nebula_density_histogram.png")
                try writeDensityHistogramPNG(floatRGBA: data, width: options.width, height: options.height, to: histURL)
                print("✅ Wrote: \(histURL.path)")
            }
        }

        // Beauty render + required debug views.
        try await renderNebula(debugMode: 0.0, name: "nebula_beauty.png")
        try await renderNebula(debugMode: 1.0, name: "nebula_blue_ratio_pre_post.png")
        try await renderNebula(debugMode: 2.0, name: "nebula_edge_width.png")
        try await renderNebula(debugMode: 3.0, name: "nebula_density_pre_post.png")

        // Star–medium interaction validation: starfield -> composite with nebula -> odt.
        do {
            let depth = RenderNode(name: "DepthOne", shader: "depth_one")
            let stars = RenderNode(name: "Stars", shader: "fx_starfield")
            let nebula = RenderNode(
                name: "Nebula",
                shader: "fx_volumetric_nebula",
                inputs: ["depth": depth.id],
                parameters: [
                    "cameraPosition": .vector3(SIMD3<Double>(0, 0, 10)),
                    "cameraForward": .vector3(SIMD3<Double>(0, 0, -1)),
                    "cameraUp": .vector3(SIMD3<Double>(0, 1, 0)),
                    "cameraRight": .vector3(SIMD3<Double>(1, 0, 0)),
                    "fov": .float(60),
                    "aspectRatio": .float(Double(options.width) / Double(options.height)),
                    "volumeMin": .vector3(SIMD3<Double>(-10, -10, -10)),
                    "volumeMax": .vector3(SIMD3<Double>(10, 10, 10)),
                    "baseFrequency": .float(1.0),
                    "octaves": .float(3),
                    "lacunarity": .float(2.0),
                    "gain": .float(0.5),
                    "densityScale": .float(1.0),
                    "densityOffset": .float(0.0),
                    "time": .float(0.0),
                    "windVelocity": .vector3(SIMD3<Double>(0.1, 0.0, 0.0)),
                    "lightDirection": .vector3(SIMD3<Double>(0.5, -0.5, -0.5)),
                    "lightColor": .vector3(SIMD3<Double>(1.0, 0.9, 0.8)),
                    "ambientIntensity": .float(0.08),
                    "scatteringCoeff": .float(1.25),
                    "absorptionCoeff": .float(0.12),
                    "phaseG": .float(0.25),
                    "maxSteps": .float(96),
                    "shadowSteps": .float(6),
                    "stepSize": .float(0.09),
                    "emissionColorWarm": .vector3(SIMD3<Double>(1.0, 0.35, 0.12)),
                    "emissionColorCool": .vector3(SIMD3<Double>(0.10, 0.22, 0.85)),
                    "emissionIntensity": .float(1.15),
                    "hdrScale": .float(1.0),
                    "debugMode": .float(0.0)
                ]
            )
            let composite = RenderNode(
                name: "Composite",
                shader: "fx_volumetric_composite",
                inputs: ["scene": stars.id, "volumetric": nebula.id]
            )
            let odt = RenderNode(
                name: "ODT",
                shader: "odt_acescg_to_rec709",
                inputs: ["input": composite.id]
            )

            let graph = RenderGraph(nodes: [depth, stars, nebula, composite, odt], rootNodeID: odt.id)
            let quality = QualityProfile(name: "NebulaStars", fidelity: .high, resolutionHeight: options.height, colorDepth: 10)
            let req = RenderRequest(graph: graph, time: .zero, quality: quality)
            let result = try await engine.render(request: req)
            guard let data = result.imageBuffer else {
                throw NSError(domain: "MetaVisLab", code: 882, userInfo: [NSLocalizedDescriptionKey: "No imageBuffer from composite render"])
            }
            let outURL = options.outDirURL.appendingPathComponent("nebula_star_interaction.png")
            try writeRGBA16FloatAsPNG(floatRGBA: data, width: options.width, height: options.height, to: outURL)
            print("✅ Wrote: \(outURL.path)")
        }
        #endif
    }

    #if canImport(ImageIO) && canImport(CoreGraphics) && canImport(UniformTypeIdentifiers)
    private static func writeDensityHistogramPNG(floatRGBA data: Data, width: Int, height: Int, to url: URL) throws {
        let count = width * height * 4
        let floats: [Float] = data.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: Float.self)
            return Array(ptr.prefix(count))
        }

        let bins = 256
        var histPre = [Int](repeating: 0, count: bins)
        var histPost = [Int](repeating: 0, count: bins)
        for i in 0..<(width * height) {
            let pre = max(0.0, min(1.0, floats[i * 4 + 0]))
            let post = max(0.0, min(1.0, floats[i * 4 + 1]))
            let b0 = min(bins - 1, max(0, Int(pre * Float(bins - 1))))
            let b1 = min(bins - 1, max(0, Int(post * Float(bins - 1))))
            histPre[b0] += 1
            histPost[b1] += 1
        }

        let w = 512
        let h = 256
        var rgba = [UInt8](repeating: 0, count: w * h * 4)

        let maxCount = max(histPre.max() ?? 1, histPost.max() ?? 1)
        func yFor(_ c: Int) -> Int {
            let t = Double(c) / Double(maxCount)
            return max(0, min(h - 1, (h - 1) - Int(t * Double(h - 1) + 0.5)))
        }

        func setPixel(x: Int, y: Int, r: UInt8, g: UInt8, b: UInt8) {
            guard x >= 0 && x < w && y >= 0 && y < h else { return }
            let idx = (y * w + x) * 4
            rgba[idx + 0] = r
            rgba[idx + 1] = g
            rgba[idx + 2] = b
            rgba[idx + 3] = 255
        }

        for x in 0..<w {
            let bin = min(bins - 1, Int(Double(x) / Double(w - 1) * Double(bins - 1) + 0.5))
            setPixel(x: x, y: yFor(histPre[bin]), r: 255, g: 0, b: 0)
            setPixel(x: x, y: yFor(histPost[bin]), r: 0, g: 255, b: 0)
        }

        let cfData = Data(rgba) as CFData
        guard let provider = CGDataProvider(data: cfData) else {
            throw NSError(domain: "MetaVisLab", code: 887, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGDataProvider (histogram)"])
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let cgImage = CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw NSError(domain: "MetaVisLab", code: 888, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage (histogram)"])
        }

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "MetaVisLab", code: 889, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG destination (histogram)"])
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "MetaVisLab", code: 890, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize PNG write (histogram)"])
        }
    }

    private static func writeRGBA16FloatAsPNG(floatRGBA data: Data, width: Int, height: Int, to url: URL) throws {
        let count = width * height * 4
        let floats: [Float] = data.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: Float.self)
            return Array(ptr.prefix(count))
        }

        // Convert to 8-bit sRGB-ish for inspection.
        // Assumes input is already in display-referred space (ODT applied).
        var rgba8 = [UInt8](repeating: 0, count: count)
        for i in 0..<(width * height) {
            let r = max(0, floats[i * 4 + 0])
            let g = max(0, floats[i * 4 + 1])
            let b = max(0, floats[i * 4 + 2])
            let a = max(0, min(1, floats[i * 4 + 3]))

            func to8(_ x: Float) -> UInt8 {
                let y = max(0, min(1, x))
                return UInt8(y * 255.0 + 0.5)
            }

            rgba8[i * 4 + 0] = to8(r)
            rgba8[i * 4 + 1] = to8(g)
            rgba8[i * 4 + 2] = to8(b)
            rgba8[i * 4 + 3] = to8(a)
        }

        let cfData = Data(rgba8) as CFData
        guard let provider = CGDataProvider(data: cfData) else {
            throw NSError(domain: "MetaVisLab", code: 883, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGDataProvider"])
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
            throw NSError(domain: "MetaVisLab", code: 884, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
        }

        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "MetaVisLab", code: 885, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG destination"])
        }

        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw NSError(domain: "MetaVisLab", code: 886, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize PNG write"])
        }
    }
    #endif

    private static func parse(args: [String]) throws -> Options {
        func usage(_ message: String) -> NSError {
            NSError(domain: "MetaVisLab", code: 879, userInfo: [NSLocalizedDescriptionKey: "\(message)\n\n" + MetaVisLabHelp.text])
        }

        var outDir: String?
        var width: Int = 1280
        var height: Int = 720

        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--out":
                i += 1
                guard i < args.count else { throw usage("Missing value for --out") }
                outDir = args[i]
            case "--width":
                i += 1
                guard i < args.count else { throw usage("Missing value for --width") }
                width = Int(args[i]) ?? width
            case "--height":
                i += 1
                guard i < args.count else { throw usage("Missing value for --height") }
                height = Int(args[i]) ?? height
            default:
                if a.hasPrefix("-") {
                    throw usage("Unknown option: \(a)")
                }
            }
            i += 1
        }

        let outURL = URL(fileURLWithPath: outDir ?? "./test_outputs/_nebula_debug")
        return Options(outDirURL: outURL, width: width, height: height)
    }
}
