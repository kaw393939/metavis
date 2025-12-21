import Foundation
import ArgumentParser
import MetaVisTimeline
import MetaVisCore
import MetaVisSimulation
import MetaVisScheduler
import MetaVisIngest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct GenerateCompositeCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "generate-composite",
        abstract: "Generates a composite video using JWST FITS data (v46 Data-Driven)."
    )
    
    @Option(name: .shortAndLong, help: "Output path (optional). Defaults to ./renders/jwst_composite.mov")
    var output: String?

    @Flag(name: .shortAndLong, help: "Force regeneration of intermediate maps")
    var force: Bool = false

    @Option(name: .long, help: "Timeline duration in seconds (default: 30)")
    var durationSeconds: Int = 30

    @Option(name: .long, help: "Output width (default: 3840)")
    var width: Int = 3840

    @Option(name: .long, help: "Output height (default: 2160)")
    var height: Int = 2160
    
    func run() async throws {
        print("🔭 Starting JWST Composite Generation (v46 Data-Driven)...")
        
        let tempDir = FileManager.default.temporaryDirectory
        let densityURL = tempDir.appendingPathComponent("v46_density.tiff")
        let colorURL = tempDir.appendingPathComponent("v46_color.tiff")
        let starsURL = tempDir.appendingPathComponent("v46_stars.json")
        
        print("   🔍 Checking cache at: \(tempDir.path)")
        print("      Density: \(FileManager.default.fileExists(atPath: densityURL.path) ? "✅" : "❌")")
        print("      Color:   \(FileManager.default.fileExists(atPath: colorURL.path) ? "✅" : "❌")")
        print("      Stars:   \(FileManager.default.fileExists(atPath: starsURL.path) ? "✅" : "❌")")
        print("      Force:   \(force)")

        let inputWidth: Int
        let inputHeight: Int
        let starData: [StarData]
        
        let cacheExists = FileManager.default.fileExists(atPath: densityURL.path) &&
                          FileManager.default.fileExists(atPath: colorURL.path) &&
                          FileManager.default.fileExists(atPath: starsURL.path)
                          
        if cacheExists && !force {
            print("   ♻️ Found cached intermediate maps. Using cache...")
            
            guard let source = CGImageSourceCreateWithURL(densityURL as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
                  let w = props[kCGImagePropertyPixelWidth as String] as? Int,
                  let h = props[kCGImagePropertyPixelHeight as String] as? Int else {
                print("❌ Failed to read dimensions from cached density map.")
                return
            }
                        inputWidth = w
                        inputHeight = h
            
            let data = try Data(contentsOf: starsURL)
            starData = try JSONDecoder().decode([StarData].self, from: data)
            
        } else {
            // 1. Load FITS Files
            let assetsDir = URL(fileURLWithPath: "/Users/kwilliams/Projects/metavis_render_two/assets")
            let reader = FITSReader()
            let preprocessor = FITSPreprocessor()
            
            // Map roles to filenames (MIRI mapping)
            // F090W -> F770W
            // F200W -> F1130W
            // F335M -> F1280W
            // F444W -> F1800W
            let filterMap: [String: String] = [
                "F090W": "hlsp_jwst-ero_jwst_miri_carina_f770w_v1_i2d.fits",
                "F200W": "hlsp_jwst-ero_jwst_miri_carina_f1130w_v1_i2d.fits",
                "F335M": "hlsp_jwst-ero_jwst_miri_carina_f1280w_v1_i2d.fits",
                "F444W": "hlsp_jwst-ero_jwst_miri_carina_f1800w_v1_i2d.fits"
            ]
            
            var processedBuffers: [String: FITSPreprocessor.ProcessedBuffer] = [:]
            
            // Asinh Alphas from Spec
            let alphas: [String: Float] = [
                "F090W": 12,
                "F200W": 10,
                "F335M": 8,
                "F444W": 6
            ]
            
            for (role, filename) in filterMap {
                let url = assetsDir.appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: url.path) {
                    print("   📂 Loading \(role) (\(filename))...")
                    let asset = try reader.read(url: url)
                    let buffer = preprocessor.process(asset: asset, asinhAlpha: alphas[role] ?? 10)
                    processedBuffers[role] = buffer
                } else {
                    print("   ⚠️ Missing \(role) (\(filename))")
                }
            }
            
            guard let refBuffer = processedBuffers.values.first else {
                print("❌ No data loaded.")
                return
            }
            
            inputWidth = refBuffer.width
            inputHeight = refBuffer.height
            let pixelCount = inputWidth * inputHeight
            
            // 2. Derive Nebula Density D(x,y)
            // D_raw = 0.4*V_F200W + 0.3*V_F335M + 0.3*V_F444W
            print("   ☁️ Generating Nebula Density Map...")
            var density = [Float](repeating: 0, count: pixelCount)
            
            let vF200W = processedBuffers["F200W"]?.data ?? [Float](repeating: 0, count: pixelCount)
            let vF335M = processedBuffers["F335M"]?.data ?? [Float](repeating: 0, count: pixelCount)
            let vF444W = processedBuffers["F444W"]?.data ?? [Float](repeating: 0, count: pixelCount)
            
            for i in 0..<pixelCount {
                let dRaw = 0.4 * vF200W[i] + 0.3 * vF335M[i] + 0.3 * vF444W[i]
                density[i] = min(max(dRaw, 0), 1)
            }
            
            // Normalize by P95
            let p95 = computePercentile(data: density, p: 0.95)
            let invP95 = p95 > 0 ? 1.0 / p95 : 1.0
            
            for i in 0..<pixelCount {
                var d = density[i] * invP95
                d = min(max(d, 0), 1)
                density[i] = pow(d, 0.8) // Contrast boost
            }
            
            // 3. Derive Emissive Color C_rgb(x,y)
            print("   🎨 Generating Emissive Color Map...")
            var r = [Float](repeating: 0, count: pixelCount)
            var g = [Float](repeating: 0, count: pixelCount)
            var b = [Float](repeating: 0, count: pixelCount)
            
            let vF090W = processedBuffers["F090W"]?.data ?? [Float](repeating: 0, count: pixelCount)
            
            // Weights
            // F444W: 1.00, 0.15, 0.00
            // F335M: 0.25, 0.80, 0.05
            // F200W: 0.15, 0.30, 0.25
            // F090W: 0.00, 0.10, 0.80
            
            for i in 0..<pixelCount {
                r[i] = 1.00 * vF444W[i] + 0.25 * vF335M[i] + 0.15 * vF200W[i] + 0.00 * vF090W[i]
                g[i] = 0.15 * vF444W[i] + 0.80 * vF335M[i] + 0.30 * vF200W[i] + 0.10 * vF090W[i]
                b[i] = 0.00 * vF444W[i] + 0.05 * vF335M[i] + 0.25 * vF200W[i] + 0.80 * vF090W[i]
                
                let maxRGB = max(r[i], max(g[i], b[i]))
                if maxRGB > 1.0 {
                    r[i] /= maxRGB
                    g[i] /= maxRGB
                    b[i] /= maxRGB
                }
            }
            
            // 4. Star Detection
            print("   ✨ Detecting Stars...")
            let detector = StarDetector()
            // Use F090W (mapped to F770W) for detection
            let detectionBuffer = processedBuffers["F090W"] ?? refBuffer
            
            let stars = detector.detect(buffer: detectionBuffer, threshold: 0.7) { uv in
                // Sample color from our generated maps
                let x = Int(uv.x * Float(inputWidth))
                let y = Int(uv.y * Float(inputHeight))
                let idx = min(max(y * inputWidth + x, 0), pixelCount - 1)
                return SIMD3<Float>(r[idx], g[idx], b[idx])
            }
            
            starData = stars.map { StarData(u: $0.position.x, v: $0.position.y, mag: $0.magnitude, r: $0.color.x, g: $0.color.y, b: $0.color.z) }
            
            // 5. Save Intermediate Maps
            try saveGrayImage(data: density, width: inputWidth, height: inputHeight, url: densityURL)
            try saveRGBImage(r: r, g: g, b: b, width: inputWidth, height: inputHeight, url: colorURL)
            
            let starJSON = try JSONEncoder().encode(starData)
            try starJSON.write(to: starsURL)
            
            print("   💾 Saved intermediate maps to \(tempDir.path)")
        }
        
        // 6. Create Timeline
        var timeline = Timeline(name: "JWST v46 Composite")
        let duration = RationalTime(value: Int64(durationSeconds), timescale: 1)
        let range = TimeRange(start: .zero, duration: duration)
        
        // Track 1: Density
        let densityAsset = Asset(id: UUID(), name: "Density Map", status: .ready, url: densityURL, type: .image, duration: .zero)
        var track1 = Track(name: "Density", type: .video)
        try track1.add(Clip(name: "Density", assetId: densityAsset.id, range: range, sourceStartTime: .zero))
        timeline.addTrack(track1)
        
        // Track 2: Color
        let colorAsset = Asset(id: UUID(), name: "Color Map", status: .ready, url: colorURL, type: .image, duration: .zero)
        var track2 = Track(name: "Color", type: .video)
        try track2.add(Clip(name: "Color", assetId: colorAsset.id, range: range, sourceStartTime: .zero))
        timeline.addTrack(track2)
        
        // 7. Render
        let outputURL = URL(fileURLWithPath: output ?? "./renders/jwst_composite_v46.mov")
        let outputDirectory = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        
        // Default grade tuned for a more "space" look (deeper mids, slightly richer color).
        let config = MetaVisScheduler.ConfigData(
            exposure: 1.10,
            saturation: 1.08,
            contrast: 1.18,
            lift: -0.03,
            gamma: 1.05,
            gain: 1.04
        )
        
        let payload = RenderJobPayload(
            timeline: timeline,
            outputPath: outputURL.path,
            width: width,
            height: height,
            assets: [
                AssetInfo(id: densityAsset.id, name: densityAsset.name, url: densityAsset.url!, type: .image),
                AssetInfo(id: colorAsset.id, name: colorAsset.name, url: colorAsset.url!, type: .image)
            ],
            stars: starData,
            config: config
        )
        
        let job = Job(
            id: UUID(),
            type: .render,
            status: .pending,
            priority: 10,
            payload: try JSONEncoder().encode(payload)
        )
        
        let worker = RenderWorker()
        print("🚀 Starting Render...")
        _ = try await worker.execute(job: job) { progress in
            print("   Render Progress: \(Int(progress.progress * 100))% - \(progress.message)")
        }
        print("✅ Render Complete: \(outputURL.path)")
        
        // 6. Feedback
        print("\nTo verify the output with AI feedback, run:")
        print("swift run metavis feedback --input \(outputURL.path)")
    }
    
    func computePercentile(data: [Float], p: Float) -> Float {
        // Sample
        let sampleCount = min(data.count, 10000)
        let stride = data.count / sampleCount
        var samples: [Float] = []
        samples.reserveCapacity(sampleCount)
        for i in 0..<sampleCount {
            samples.append(data[i * stride])
        }
        samples.sort()
        let idx = Int(Float(samples.count) * p)
        return samples[min(idx, samples.count - 1)]
    }
    
    func saveGrayImage(data: [Float], width: Int, height: Int, url: URL) throws {
        var bytes = [UInt8](repeating: 0, count: width * height)
        for i in 0..<data.count {
            bytes[i] = UInt8(min(max(data[i] * 255.0, 0.0), 255.0))
        }
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
        guard let image = context.makeImage() else { return }
        
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
    
    func saveRGBImage(r: [Float], g: [Float], b: [Float], width: Int, height: Int, url: URL) throws {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<width*height {
            bytes[i*4 + 0] = UInt8(min(max(r[i] * 255.0, 0.0), 255.0))
            bytes[i*4 + 1] = UInt8(min(max(g[i] * 255.0, 0.0), 255.0))
            bytes[i*4 + 2] = UInt8(min(max(b[i] * 255.0, 0.0), 255.0))
            bytes[i*4 + 3] = 255
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        guard let image = context.makeImage() else { return }
        
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
