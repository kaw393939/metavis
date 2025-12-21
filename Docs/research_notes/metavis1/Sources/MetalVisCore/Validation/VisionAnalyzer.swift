import Foundation
import Metal
import Vision
import CoreImage
import Accelerate
import Logging

/// Vision-based image analysis for effect validation
/// Uses Apple Vision framework for saliency, edge detection, and quality metrics
@available(macOS 14.0, *)
public final class VisionAnalyzer: @unchecked Sendable {
    private let device: MTLDevice
    private let ciContext: CIContext
    private let logger = Logger(label: "com.metalvis.validation.vision")
    
    public init(device: MTLDevice) {
        self.device = device
        self.ciContext = CIContext(mtlDevice: device)
    }
    
    // MARK: - Saliency Analysis
    
    /// Analyze attention saliency to detect where visual focus is drawn
    public func analyzeSaliency(texture: MTLTexture) async throws -> SaliencyResult {
        let cgImage = try await textureToCGImage(texture)
        return try await analyzeSaliency(cgImage: cgImage)
    }
    
    public func analyzeSaliency(data: Data) async throws -> SaliencyResult {
        let cgImage = try cgImage(from: data)
        return try await analyzeSaliency(cgImage: cgImage)
    }
    
    private func analyzeSaliency(cgImage: CGImage) async throws -> SaliencyResult {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        try handler.perform([request])
        
        guard let observation = request.results?.first as? VNSaliencyImageObservation else {
            throw VisionAnalyzerError.saliencyFailed("No saliency observation returned")
        }
        
        // Extract saliency map
        let saliencyMap = observation.salientObjects ?? []
        let hotspots = saliencyMap.map { rect -> SaliencyHotspot in
            SaliencyHotspot(
                center: CGPoint(x: rect.boundingBox.midX, y: rect.boundingBox.midY),
                boundingBox: rect.boundingBox,
                confidence: Float(rect.confidence)
            )
        }
        
        // Calculate overall saliency concentration
        let totalConfidence = hotspots.reduce(0) { $0 + $1.confidence }
        let averageConfidence = hotspots.isEmpty ? 0 : totalConfidence / Float(hotspots.count)
        
        return SaliencyResult(
            hotspots: hotspots,
            totalSalientArea: calculateTotalArea(hotspots),
            averageConfidence: averageConfidence,
            distributionScore: calculateDistributionScore(hotspots)
        )
    }
    
    // MARK: - Depth Analysis
    
    public func analyzeDepthSeparation(texture: MTLTexture) async throws -> DepthSeparationResult {
        let cgImage = try await textureToCGImage(texture)
        return try await analyzeDepthSeparation(cgImage: cgImage)
    }
    
    public func analyzeDepthSeparation(data: Data) async throws -> DepthSeparationResult {
        let cgImage = try cgImage(from: data)
        return try await analyzeDepthSeparation(cgImage: cgImage)
    }
    
    private func analyzeDepthSeparation(cgImage: CGImage) async throws -> DepthSeparationResult {
        // Use person segmentation as proxy for depth layers
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        try handler.perform([request])
        
        guard let observation = request.results?.first else {
            // No foreground detected - return default result
            return DepthSeparationResult(
                foregroundPercentage: 0,
                backgroundPercentage: 100,
                separationConfidence: 0,
                layerCount: 1
            )
        }
        
        // Calculate mask coverage
        let maskPixelBuffer = try observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler)
        let maskCoverage = try calculateMaskCoverage(maskPixelBuffer)
        
        return DepthSeparationResult(
            foregroundPercentage: maskCoverage * 100,
            backgroundPercentage: (1 - maskCoverage) * 100,
            separationConfidence: Float(observation.allInstances.count > 0 ? 0.9 : 0.1),
            layerCount: observation.allInstances.count + 1
        )
    }
    
    // MARK: - Color Analysis
    
    public func analyzeColorDistribution(texture: MTLTexture) async throws -> ColorDistributionResult {
        let cgImage = try await textureToCGImage(texture)
        return try analyzeColorDistribution(cgImage: cgImage)
    }
    
    public func analyzeColorDistribution(data: Data) async throws -> ColorDistributionResult {
        let cgImage = try cgImage(from: data)
        return try analyzeColorDistribution(cgImage: cgImage)
    }
    
    private func analyzeColorDistribution(cgImage: CGImage) throws -> ColorDistributionResult {
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            throw VisionAnalyzerError.colorAnalysisFailed("Could not extract pixel data")
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        
        var redHistogram = [Int](repeating: 0, count: 256)
        var greenHistogram = [Int](repeating: 0, count: 256)
        var blueHistogram = [Int](repeating: 0, count: 256)
        
        var totalR: Float = 0
        var totalG: Float = 0
        var totalB: Float = 0
        var pixelCount = 0
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Int(bytes[offset])
                let g = Int(bytes[offset + 1])
                let b = Int(bytes[offset + 2])
                
                redHistogram[r] += 1
                greenHistogram[g] += 1
                blueHistogram[b] += 1
                
                totalR += Float(r)
                totalG += Float(g)
                totalB += Float(b)
                pixelCount += 1
            }
        }
        
        let avgR = totalR / Float(pixelCount)
        let avgG = totalG / Float(pixelCount)
        let avgB = totalB / Float(pixelCount)
        
        return ColorDistributionResult(
            redHistogram: redHistogram,
            greenHistogram: greenHistogram,
            blueHistogram: blueHistogram,
            averageColor: SIMD3<Float>(avgR / 255, avgG / 255, avgB / 255),
            dominantColors: extractDominantColors(redHistogram, greenHistogram, blueHistogram)
        )
    }
    
    public func analyzeRegionColor(data: Data, region: CGRect) async throws -> SIMD3<Float> {
        let cgImage = try cgImage(from: data)

        guard let dataProvider = cgImage.dataProvider,
              let dataRef = dataProvider.data,
              let bytes = CFDataGetBytePtr(dataRef) else {
            throw VisionAnalyzerError.colorAnalysisFailed("Could not extract pixel data")
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8

        // Convert normalized rect to pixel coordinates
        let startX = Int(region.minX * CGFloat(width))
        let startY = Int(region.minY * CGFloat(height))
        let endX = Int(region.maxX * CGFloat(width))
        let endY = Int(region.maxY * CGFloat(height))
        
        // Clamp to image bounds
        let safeStartX = max(0, startX)
        let safeStartY = max(0, startY)
        let safeEndX = min(width, endX)
        let safeEndY = min(height, endY)

        var totalR: Float = 0
        var totalG: Float = 0
        var totalB: Float = 0
        var pixelCount = 0

        for y in safeStartY..<safeEndY {
            for x in safeStartX..<safeEndX {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Float(bytes[offset])
                let g = Float(bytes[offset + 1])
                let b = Float(bytes[offset + 2])

                totalR += r
                totalG += g
                totalB += b
                pixelCount += 1
            }
        }
        
        guard pixelCount > 0 else {
            return SIMD3<Float>(0, 0, 0)
        }

        let avgR = totalR / Float(pixelCount) / 255.0
        let avgG = totalG / Float(pixelCount) / 255.0
        let avgB = totalB / Float(pixelCount) / 255.0

        return SIMD3<Float>(avgR, avgG, avgB)
    }

    public func analyzeCenterRegionColor(data: Data, regionRadius: Float = 0.1) async throws -> SIMD3<Float> {
        let cgImage = try cgImage(from: data)

        guard let dataProvider = cgImage.dataProvider,
              let dataRef = dataProvider.data,
              let bytes = CFDataGetBytePtr(dataRef) else {
            throw VisionAnalyzerError.colorAnalysisFailed("Could not extract pixel data")
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8

        let centerX = Float(width) / 2.0
        let centerY = Float(height) / 2.0
        let maxRadius = Float(min(width, height)) * regionRadius

        var totalR: Float = 0
        var totalG: Float = 0
        var totalB: Float = 0
        var pixelCount = 0

        for y in 0..<height {
            for x in 0..<width {
                let dx = Float(x) - centerX
                let dy = Float(y) - centerY
                let dist = sqrt(dx * dx + dy * dy)
                
                if dist <= maxRadius {
                    let offset = y * bytesPerRow + x * bytesPerPixel
                    let r = Float(bytes[offset])
                    let g = Float(bytes[offset + 1])
                    let b = Float(bytes[offset + 2])

                    totalR += r
                    totalG += g
                    totalB += b
                    pixelCount += 1
                }
            }
        }
        
        guard pixelCount > 0 else {
            return SIMD3<Float>(0, 0, 0)
        }

        let avgR = totalR / Float(pixelCount) / 255.0
        let avgG = totalG / Float(pixelCount) / 255.0
        let avgB = totalB / Float(pixelCount) / 255.0

        return SIMD3<Float>(avgR, avgG, avgB)
    }
    
    // MARK: - Luminance Analysis
    
    public func analyzeLuminanceProfile(texture: MTLTexture, regions: Int = 5) async throws -> LuminanceProfile {
        let cgImage = try await textureToCGImage(texture)
        return try analyzeLuminanceProfile(cgImage: cgImage, regions: regions)
    }
    
    public func analyzeLuminanceProfile(data: Data, regions: Int = 5, linearize: Bool = false) async throws -> LuminanceProfile {
        let cgImage = try cgImage(from: data)
        return try analyzeLuminanceProfile(cgImage: cgImage, regions: regions, linearize: linearize)
    }
    
    private func analyzeLuminanceProfile(cgImage: CGImage, regions: Int, linearize: Bool = false) throws -> LuminanceProfile {
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            throw VisionAnalyzerError.colorAnalysisFailed("Could not extract pixel data")
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        
        let centerX = width / 2
        let centerY = height / 2
        // Use diagonal radius to cover corners
        let maxRadius = sqrt(Float(width * width + height * height)) / 2.0
        
        var ringLuminance = [Float](repeating: 0, count: regions)
        var ringCounts = [Int](repeating: 0, count: regions)
        
        for y in 0..<height {
            for x in 0..<width {
                let dx = Float(x - centerX)
                let dy = Float(y - centerY)
                let radius = sqrt(dx * dx + dy * dy)
                let normalizedRadius = radius / maxRadius
                
                let ring = min(Int(normalizedRadius * Float(regions)), regions - 1)
                
                let offset = y * bytesPerRow + x * bytesPerPixel
                var r = Float(bytes[offset]) / 255.0
                var g = Float(bytes[offset + 1]) / 255.0
                var b = Float(bytes[offset + 2]) / 255.0
                
                if linearize {
                    r = srgbToLinear(r)
                    g = srgbToLinear(g)
                    b = srgbToLinear(b)
                }
                
                let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
                
                ringLuminance[ring] += luminance
                ringCounts[ring] += 1
            }
        }
        
        let averageLuminance = zip(ringLuminance, ringCounts).map { (sum, cnt) -> Float in
            cnt > 0 ? (sum / Float(cnt)) : 0
        }
        
        let centerLum = averageLuminance.first ?? 0
        let edgeLum = averageLuminance.last ?? 1
        let falloffRatio = edgeLum > 0 ? centerLum / edgeLum : 0
        
        return LuminanceProfile(
            ringLuminance: averageLuminance,
            centerLuminance: centerLum,
            edgeLuminance: edgeLum,
            falloffRatio: falloffRatio
        )
    }
    
    // MARK: - Radial Channel Analysis
    
    public func analyzeRadialChannelProfiles(data: Data, regions: Int = 10) async throws -> (red: [Float], green: [Float], blue: [Float]) {
        let cgImage = try cgImage(from: data)
        
        guard let dataProvider = cgImage.dataProvider,
              let dataRef = dataProvider.data,
              let bytes = CFDataGetBytePtr(dataRef) else {
            throw VisionAnalyzerError.colorAnalysisFailed("Could not extract pixel data")
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        
        let centerX = width / 2
        let centerY = height / 2
        let maxRadius = Float(min(width, height) / 2)
        
        var rProfile = [Float](repeating: 0, count: regions)
        var gProfile = [Float](repeating: 0, count: regions)
        var bProfile = [Float](repeating: 0, count: regions)
        var counts = [Int](repeating: 0, count: regions)
        
        for y in 0..<height {
            for x in 0..<width {
                let dx = Float(x - centerX)
                let dy = Float(y - centerY)
                let radius = sqrt(dx * dx + dy * dy)
                let normalizedRadius = radius / maxRadius
                
                if normalizedRadius > 1.0 { continue }
                
                let ring = min(Int(normalizedRadius * Float(regions)), regions - 1)
                
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Float(bytes[offset])
                let g = Float(bytes[offset + 1])
                let b = Float(bytes[offset + 2])
                
                rProfile[ring] += r
                gProfile[ring] += g
                bProfile[ring] += b
                counts[ring] += 1
            }
        }
        
        for i in 0..<regions {
            if counts[i] > 0 {
                rProfile[i] /= Float(counts[i])
                gProfile[i] /= Float(counts[i])
                bProfile[i] /= Float(counts[i])
            }
        }
        
        return (rProfile, gProfile, bProfile)
    }
    
    // MARK: - Edge Detection
    
    public func analyzeEdges(texture: MTLTexture) async throws -> EdgeAnalysisResult {
        let cgImage = try await textureToCGImage(texture)
        return try await analyzeEdges(cgImage: cgImage)
    }
    
    public func analyzeEdges(data: Data) async throws -> EdgeAnalysisResult {
        let cgImage = try cgImage(from: data)
        return try await analyzeEdges(cgImage: cgImage)
    }
    
    private func analyzeEdges(cgImage: CGImage) async throws -> EdgeAnalysisResult {
        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 1.0
        request.detectsDarkOnLight = true
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        
        guard let observation = request.results?.first else {
            return EdgeAnalysisResult(
                edgeCount: 0,
                totalEdgeLength: 0,
                averageEdgeStrength: 0,
                edgeDensity: 0
            )
        }
        
        let contourCount = observation.contourCount
        var totalLength: Float = 0
        
        for i in 0..<contourCount {
            if let contour = try? observation.contour(at: i) {
                totalLength += Float(contour.pointCount)
            }
        }
        
        let imageArea = Float(cgImage.width * cgImage.height)
        let edgeDensity = totalLength / imageArea
        
        return EdgeAnalysisResult(
            edgeCount: contourCount,
            totalEdgeLength: totalLength,
            averageEdgeStrength: contourCount > 0 ? 1.0 : 0.0,
            edgeDensity: edgeDensity
        )
    }
    
    // MARK: - SSIM & Energy
    
    public func calculateSSIM(original: MTLTexture, modified: MTLTexture) async throws -> SSIMResult {
        let originalImage = try await textureToCGImage(original)
        let modifiedImage = try await textureToCGImage(modified)
        return try calculateSSIM(original: originalImage, modified: modifiedImage)
    }
    
    public func calculateSSIM(originalData: Data, modifiedData: Data) async throws -> SSIMResult {
        let originalImage = try cgImage(from: originalData)
        let modifiedImage = try cgImage(from: modifiedData)
        return try calculateSSIM(original: originalImage, modified: modifiedImage)
    }
    
    private func calculateSSIM(original: CGImage, modified: CGImage) throws -> SSIMResult {
        guard let origData = original.dataProvider?.data,
              let origBytes = CFDataGetBytePtr(origData),
              let modData = modified.dataProvider?.data,
              let modBytes = CFDataGetBytePtr(modData) else {
            throw VisionAnalyzerError.ssimFailed("Could not extract pixel data")
        }
        
        let width = min(original.width, modified.width)
        let height = min(original.height, modified.height)
        let bytesPerRow = original.bytesPerRow
        let bytesPerPixel = original.bitsPerPixel / 8
        
        var sumOriginal: Float = 0
        var sumModified: Float = 0
        var sumOriginalSq: Float = 0
        var sumModifiedSq: Float = 0
        var sumCross: Float = 0
        var count: Float = 0
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                
                let origLum = 0.2126 * Float(origBytes[offset]) +
                              0.7152 * Float(origBytes[offset + 1]) +
                              0.0722 * Float(origBytes[offset + 2])
                
                let modLum = 0.2126 * Float(modBytes[offset]) +
                             0.7152 * Float(modBytes[offset + 1]) +
                             0.0722 * Float(modBytes[offset + 2])
                
                sumOriginal += origLum
                sumModified += modLum
                sumOriginalSq += origLum * origLum
                sumModifiedSq += modLum * modLum
                sumCross += origLum * modLum
                count += 1
            }
        }
        
        let meanOrig = sumOriginal / count
        let meanMod = sumModified / count
        let varOrig = (sumOriginalSq / count) - (meanOrig * meanOrig)
        let varMod = (sumModifiedSq / count) - (meanMod * meanMod)
        let covar = (sumCross / count) - (meanOrig * meanMod)
        
        let c1: Float = 6.5025
        let c2: Float = 58.5225
        
        let ssim = ((2 * meanOrig * meanMod + c1) * (2 * covar + c2)) /
                   ((meanOrig * meanOrig + meanMod * meanMod + c1) * (varOrig + varMod + c2))
        
        return SSIMResult(
            overall: ssim,
            luminanceComponent: (2 * meanOrig * meanMod + c1) / (meanOrig * meanOrig + meanMod * meanMod + c1),
            contrastComponent: (2 * sqrt(varOrig) * sqrt(varMod) + c2) / (varOrig + varMod + c2),
            structureComponent: covar > 0 ? (covar + c2/2) / (sqrt(varOrig) * sqrt(varMod) + c2/2) : 0
        )
    }
    
    public func calculateEnergy(texture: MTLTexture) async throws -> Float {
        let cgImage = try await textureToCGImage(texture)
        return try calculateEnergy(cgImage: cgImage)
    }
    
    public func calculateEnergy(data: Data, linearize: Bool = false) async throws -> Float {
        let cgImage = try cgImage(from: data)
        return try calculateEnergy(cgImage: cgImage, linearize: linearize)
    }
    
    private func calculateEnergy(cgImage: CGImage, linearize: Bool = false) throws -> Float {
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            throw VisionAnalyzerError.energyCalculationFailed("Could not extract pixel data")
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let isFloat = (cgImage.bitmapInfo.rawValue & CGBitmapInfo.floatComponents.rawValue) != 0
        let is32Bit = cgImage.bitsPerComponent == 32
        
        var totalEnergy: Float = 0
        let rawBytes = UnsafeRawPointer(bytes)
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                var r: Float
                var g: Float
                var b: Float
                
                if isFloat && is32Bit {
                    r = rawBytes.load(fromByteOffset: offset, as: Float.self)
                    g = rawBytes.load(fromByteOffset: offset + 4, as: Float.self)
                    b = rawBytes.load(fromByteOffset: offset + 8, as: Float.self)
                } else {
                    r = Float(bytes[offset]) / 255.0
                    g = Float(bytes[offset + 1]) / 255.0
                    b = Float(bytes[offset + 2]) / 255.0
                }
                
                if linearize {
                    r = srgbToLinear(r)
                    g = srgbToLinear(g)
                    b = srgbToLinear(b)
                }
                
                let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
                totalEnergy += luminance
            }
        }
        
        return totalEnergy
    }
    
    // MARK: - Min/Max Analysis
    
    public func getMinMaxLuminance(data: Data) async throws -> (min: Float, max: Float) {
        let cgImage = try cgImage(from: data)
        
        guard let dataProvider = cgImage.dataProvider,
              let dataRef = dataProvider.data,
              let bytes = CFDataGetBytePtr(dataRef) else {
            throw VisionAnalyzerError.colorAnalysisFailed("Could not extract pixel data")
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        
        var minLum: Float = 1.0
        var maxLum: Float = 0.0
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Float(bytes[offset]) / 255.0
                let g = Float(bytes[offset + 1]) / 255.0
                let b = Float(bytes[offset + 2]) / 255.0
                
                let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
                
                if luminance < minLum { minLum = luminance }
                if luminance > maxLum { maxLum = luminance }
            }
        }
        
        return (minLum, maxLum)
    }
    
    // MARK: - Helpers
    
    /// Convert sRGB (0-1) to Linear (0-1)
    public func srgbToLinear(_ v: Float) -> Float {
        return (v > 0.04045) ? pow((v + 0.055) / 1.055, 2.4) : (v / 12.92)
    }
    
    private func textureToCGImage(_ texture: MTLTexture) async throws -> CGImage {
        let ciImage = CIImage(mtlTexture: texture, options: nil)
        guard let image = ciImage else {
            throw VisionAnalyzerError.textureConversionFailed("Could not create CIImage from texture")
        }
        
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            throw VisionAnalyzerError.textureConversionFailed("Could not create CGImage from CIImage")
        }
        
        return cgImage
    }
    
    private func cgImage(from data: Data) throws -> CGImage {
        // Check for "RAWF" Magic Header (0x52415746)
        if data.count > 16 {
            let magic = data.withUnsafeBytes { $0.load(as: UInt32.self) }
            if magic == 0x52415746 {
                return try createCGImageFromRawFloat(data)
            }
        }
        
        // Fallback to standard image parsing (PNG/JPEG)
        let cfData = data as CFData
        guard let source = CGImageSourceCreateWithData(cfData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw VisionAnalyzerError.textureConversionFailed("Could not create CGImage from Data")
        }
        return image
    }
    
    private func createCGImageFromRawFloat(_ data: Data) throws -> CGImage {
        // Parse Header
        let width = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: Int32.self) })
        let height = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: Int32.self) })
        let channels = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 12, as: Int32.self) })
        
        let headerSize = 16
        let payloadSize = data.count - headerSize
        let expectedSize = width * height * channels * MemoryLayout<Float>.size
        
        guard payloadSize >= expectedSize else {
            throw VisionAnalyzerError.textureConversionFailed("Raw float data truncated")
        }
        
        // Create CGImage from Float32 data
        // We use a Linear sRGB Color Space to preserve physical values
        let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGBitmapInfo.floatComponents.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
        
        // Create Data Provider
        // We need to pass the payload part of the Data
        let payloadData = data.subdata(in: headerSize..<data.count) as CFData
        guard let provider = CGDataProvider(data: payloadData) else {
            throw VisionAnalyzerError.textureConversionFailed("Failed to create data provider")
        }
        
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 32, // Float32
            bitsPerPixel: 128,    // 4 * 32
            bytesPerRow: width * 16,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw VisionAnalyzerError.textureConversionFailed("Failed to create Float32 CGImage")
        }
        
        return image
    }
    
    private func calculateTotalArea(_ hotspots: [SaliencyHotspot]) -> Float {
        return hotspots.reduce(0) { $0 + Float($1.boundingBox.width * $1.boundingBox.height) }
    }
    
    private func calculateDistributionScore(_ hotspots: [SaliencyHotspot]) -> Float {
        // Simple distribution metric: average distance from center
        guard !hotspots.isEmpty else { return 0 }
        let totalDist = hotspots.reduce(Float(0)) { sum, spot in
            let dx = spot.center.x - 0.5
            let dy = spot.center.y - 0.5
            return sum + Float(sqrt(dx*dx + dy*dy))
        }
        return totalDist / Float(hotspots.count)
    }
    
    private func calculateMaskCoverage(_ buffer: CVPixelBuffer) throws -> Float {
        // Simplified coverage calculation
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return 0 }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        
        var totalPixels = 0
        var maskPixels = 0
        
        let bufferPtr = baseAddress.bindMemory(to: UInt8.self, capacity: height * bytesPerRow)
        
        for y in 0..<height {
            for x in 0..<width {
                if bufferPtr[y * bytesPerRow + x] > 128 {
                    maskPixels += 1
                }
                totalPixels += 1
            }
        }
        
        return totalPixels > 0 ? Float(maskPixels) / Float(totalPixels) : 0
    }
    
    private func extractDominantColors(_ r: [Int], _ g: [Int], _ b: [Int]) -> [SIMD3<Float>] {
        // Simplified dominant color extraction
        // Just returns the peak of each histogram for now
        let maxR = r.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        let maxG = g.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        let maxB = b.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        
        return [SIMD3<Float>(Float(maxR)/255, Float(maxG)/255, Float(maxB)/255)]
    }
    
    // MARK: - Clipping Analysis
    
    public func analyzeClipping(texture: MTLTexture, threshold: Float = 0.99) async throws -> Float {
        let cgImage = try await textureToCGImage(texture)
        return try analyzeClipping(cgImage: cgImage, threshold: threshold)
    }
    
    public func analyzeClipping(data: Data, threshold: Float = 0.99) async throws -> Float {
        let cgImage = try cgImage(from: data)
        return try analyzeClipping(cgImage: cgImage, threshold: threshold)
    }
    
    private func analyzeClipping(cgImage: CGImage, threshold: Float) throws -> Float {
        guard let dataProvider = cgImage.dataProvider,
              let dataRef = dataProvider.data,
              let bytes = CFDataGetBytePtr(dataRef) else {
            throw VisionAnalyzerError.colorAnalysisFailed("Could not extract pixel data")
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        
        var clippedCount = 0
        let totalPixels = width * height
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Float(bytes[offset]) / 255.0
                let g = Float(bytes[offset + 1]) / 255.0
                let b = Float(bytes[offset + 2]) / 255.0
                
                let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
                
                if luminance >= threshold {
                    clippedCount += 1
                }
            }
        }
        
        return Float(clippedCount) / Float(totalPixels)
    }
    
    // MARK: - Variance Analysis
    
    public func analyzeLocalVariance(texture: MTLTexture, regions: Int = 5) async throws -> [Float] {
        let cgImage = try await textureToCGImage(texture)
        return try analyzeLocalVariance(cgImage: cgImage, regions: regions)
    }
    
    public func analyzeLocalVariance(data: Data, regions: Int = 5) async throws -> [Float] {
        let cgImage = try cgImage(from: data)
        return try analyzeLocalVariance(cgImage: cgImage, regions: regions)
    }
    
    private func analyzeLocalVariance(cgImage: CGImage, regions: Int) throws -> [Float] {
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            throw VisionAnalyzerError.colorAnalysisFailed("Could not extract pixel data")
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        
        let centerX = width / 2
        let centerY = height / 2
        let maxRadius = Float(min(width, height) / 2)
        
        var ringSum = [Float](repeating: 0, count: regions)
        var ringSqSum = [Float](repeating: 0, count: regions)
        var ringCounts = [Int](repeating: 0, count: regions)
        
        for y in 0..<height {
            for x in 0..<width {
                let dx = Float(x - centerX)
                let dy = Float(y - centerY)
                let radius = sqrt(dx * dx + dy * dy)
                let normalizedRadius = radius / maxRadius
                
                let ring = min(Int(normalizedRadius * Float(regions)), regions - 1)
                
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Float(bytes[offset]) / 255.0
                let g = Float(bytes[offset + 1]) / 255.0
                let b = Float(bytes[offset + 2]) / 255.0
                
                let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
                
                ringSum[ring] += luminance
                ringSqSum[ring] += luminance * luminance
                ringCounts[ring] += 1
            }
        }
        
        return zip(zip(ringSum, ringSqSum), ringCounts).map { (sums, cnt) -> Float in
            guard cnt > 0 else { return 0 }
            let mean = sums.0 / Float(cnt)
            let meanSq = sums.1 / Float(cnt)
            return max(0, meanSq - mean * mean) // Variance
        }
    }
    
    public func analyzeVerticalVariance(data: Data, slices: Int = 5) async throws -> [Float] {
        let cgImage = try cgImage(from: data)
        return try analyzeVerticalVariance(cgImage: cgImage, slices: slices)
    }
    
    private func analyzeVerticalVariance(cgImage: CGImage, slices: Int) throws -> [Float] {
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            throw VisionAnalyzerError.colorAnalysisFailed("Could not extract pixel data")
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        
        var sliceSum = [Float](repeating: 0, count: slices)
        var sliceSqSum = [Float](repeating: 0, count: slices)
        var sliceCounts = [Int](repeating: 0, count: slices)
        
        for y in 0..<height {
            let normalizedY = Float(y) / Float(height)
            let slice = min(Int(normalizedY * Float(slices)), slices - 1)
            
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = Float(bytes[offset]) / 255.0
                let g = Float(bytes[offset + 1]) / 255.0
                let b = Float(bytes[offset + 2]) / 255.0
                
                let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
                
                sliceSum[slice] += luminance
                sliceSqSum[slice] += luminance * luminance
                sliceCounts[slice] += 1
            }
        }
        
        return zip(zip(sliceSum, sliceSqSum), sliceCounts).map { (sums, cnt) -> Float in
            guard cnt > 0 else { return 0 }
            let mean = sums.0 / Float(cnt)
            let meanSq = sums.1 / Float(cnt)
            return max(0, meanSq - mean * mean)
        }
    }

    // MARK: - Text Analysis
    
    public func analyzeText(texture: MTLTexture) async throws -> TextAnalysisResult {
        let cgImage = try await textureToCGImage(texture)
        return try await analyzeText(cgImage: cgImage)
    }
    
    public func analyzeText(data: Data) async throws -> TextAnalysisResult {
        let cgImage = try cgImage(from: data)
        return try await analyzeText(cgImage: cgImage)
    }
    
    private func analyzeText(cgImage: CGImage) async throws -> TextAnalysisResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        
        guard let observations = request.results else {
            return TextAnalysisResult(observations: [], fullText: "")
        }
        
        let textObservations = observations.compactMap { observation -> TextObservation? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return TextObservation(
                text: candidate.string,
                confidence: candidate.confidence,
                boundingBox: observation.boundingBox
            )
        }
        
        let fullText = textObservations.map { $0.text }.joined(separator: "\n")
        
        return TextAnalysisResult(
            observations: textObservations,
            fullText: fullText
        )
    }
    
    // MARK: - Motion Analysis
    
    public func analyzeMotion(previous: MTLTexture, current: MTLTexture) async throws -> MotionResult {
        let prevImage = try await textureToCGImage(previous)
        let currImage = try await textureToCGImage(current)
        return try await analyzeMotion(previous: prevImage, current: currImage)
    }
    
    public func analyzeMotion(previousData: Data, currentData: Data) async throws -> MotionResult {
        let prevImage = try cgImage(from: previousData)
        let currImage = try cgImage(from: currentData)
        return try await analyzeMotion(previous: prevImage, current: currImage)
    }
    
    private func analyzeMotion(previous: CGImage, current: CGImage) async throws -> MotionResult {
        let request = VNGenerateOpticalFlowRequest(targetedCGImage: current, options: [:])
        request.computationAccuracy = .veryHigh
        
        let handler = VNImageRequestHandler(cgImage: previous, options: [:])
        try handler.perform([request])
        
        guard let observation = request.results?.first else {
             throw VisionAnalyzerError.motionAnalysisFailed("No optical flow observation")
        }
        
        let flowBuffer = observation.pixelBuffer
        let motionStats = try calculateMotionStatistics(flowBuffer)
        
        return MotionResult(
            averageMagnitude: motionStats.average,
            maxMagnitude: motionStats.max,
            stabilityScore: 1.0 / (1.0 + motionStats.average)
        )
    }
    
    private func calculateMotionStatistics(_ buffer: CVPixelBuffer) throws -> (average: Float, max: Float) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return (0, 0) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(buffer)
        
        // Optical flow usually returns 32-bit float per component (2 components) -> 64 bit per pixel?
        // Or 16-bit float?
        // VNGenerateOpticalFlowRequest output format is kCVPixelFormatType_TwoComponent32Float (2C32Float) usually.
        
        var totalMag: Float = 0
        var maxMag: Float = 0
        var count: Int = 0
        
        if pixelFormat == kCVPixelFormatType_TwoComponent32Float {
            let bufferPtr = baseAddress.bindMemory(to: Float.self, capacity: height * bytesPerRow / 4)
            
            for y in 0..<height {
                for x in 0..<width {
                    // 2 floats per pixel
                    let offset = (y * bytesPerRow / 4) + (x * 2)
                    let dx = bufferPtr[offset]
                    let dy = bufferPtr[offset + 1]
                    
                    let mag = sqrt(dx*dx + dy*dy)
                    totalMag += mag
                    if mag > maxMag { maxMag = mag }
                    count += 1
                }
            }
        } else {
            // Fallback or error
            // For now return 0
            return (0, 0)
        }
        
        return (count > 0 ? totalMag / Float(count) : 0, maxMag)
    }
    
    // MARK: - Shape Analysis
    
    public func analyzeHotspotCircularity(data: Data, center: CGPoint, radius: Float) async throws -> Float {
        let cgImage = try cgImage(from: data)
        
        guard let dataProvider = cgImage.dataProvider,
              let dataRef = dataProvider.data,
              let bytes = CFDataGetBytePtr(dataRef) else {
            throw VisionAnalyzerError.colorAnalysisFailed("Could not extract pixel data")
        }

        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        let isFloat = (cgImage.bitmapInfo.rawValue & CGBitmapInfo.floatComponents.rawValue) != 0
        let is32Bit = cgImage.bitsPerComponent == 32
        let rawBytes = UnsafeRawPointer(bytes)

        // Fix radius scaling: if > 1.0, treat as pixels, else normalized
        let maxRadiusPixels = radius > 1.0 ? radius : Float(min(width, height)) * radius
        
        let centerX = Float(center.x) * Float(width)
        let centerY = Float(center.y) * Float(height)
        
        // First pass: Collect all bright pixels to find centroid and area
        var brightPixels: [SIMD2<Float>] = []
        var sumX: Float = 0
        var sumY: Float = 0
        
        // Optimization: Only search within bounding box of maxRadius
        let startX = max(0, Int(centerX - maxRadiusPixels))
        let endX = min(width, Int(centerX + maxRadiusPixels))
        let startY = max(0, Int(centerY - maxRadiusPixels))
        let endY = min(height, Int(centerY + maxRadiusPixels))
        
        for y in startY..<endY {
            for x in startX..<endX {
                let dx = Float(x) - centerX
                let dy = Float(y) - centerY
                if dx*dx + dy*dy > maxRadiusPixels*maxRadiusPixels { continue }
                
                let offset = y * bytesPerRow + x * bytesPerPixel
                var r: Float, g: Float, b: Float
                
                if isFloat && is32Bit {
                    r = rawBytes.load(fromByteOffset: offset, as: Float.self)
                    g = rawBytes.load(fromByteOffset: offset + 4, as: Float.self)
                    b = rawBytes.load(fromByteOffset: offset + 8, as: Float.self)
                } else {
                    r = Float(bytes[offset]) / 255.0
                    g = Float(bytes[offset + 1]) / 255.0
                    b = Float(bytes[offset + 2]) / 255.0
                }
                
                let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
                
                if luminance > 0.5 {
                    let p = SIMD2<Float>(Float(x), Float(y))
                    brightPixels.append(p)
                    sumX += p.x
                    sumY += p.y
                }
            }
        }
        
        guard !brightPixels.isEmpty else { return 0 }
        
        let centroid = SIMD2<Float>(sumX / Float(brightPixels.count), sumY / Float(brightPixels.count))
        
        // Calculate Max Radius from Centroid
        var maxDistSq: Float = 0
        for p in brightPixels {
            let d = p - centroid
            let dSq = d.x*d.x + d.y*d.y
            if dSq > maxDistSq { maxDistSq = dSq }
        }
        
        let area = Float(brightPixels.count)
        let circumscribedArea = Float.pi * maxDistSq
        
        // Circularity = Area / Area of Circumscribed Circle
        // 1.0 for perfect circle, < 1.0 for other shapes
        let circularity = area / max(circumscribedArea, 0.001)
        
        return min(circularity, 1.0)
    }
    
    // MARK: - Object Detection (Contours)
    
    public func findObjectBounds(texture: MTLTexture) async throws -> [CGRect] {
        let cgImage = try await textureToCGImage(texture)
        return try await findObjectBounds(cgImage: cgImage)
    }
    
    public func findObjectBounds(data: Data) async throws -> [CGRect] {
        let cgImage = try cgImage(from: data)
        return try await findObjectBounds(cgImage: cgImage)
    }
    
    private func findObjectBounds(cgImage: CGImage) async throws -> [CGRect] {
        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 2.0 // High contrast to find objects against black
        request.detectsDarkOnLight = false // We have light objects on dark background
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        
        guard let observation = request.results?.first else {
            return []
        }
        
        var bounds: [CGRect] = []
        let contourCount = observation.contourCount
        
        // We only care about top-level contours (outer shapes)
        for contour in observation.topLevelContours {
            // Filter out small noise
            if contour.pointCount > 50 {
                // The path is in normalized coordinates
                let path = contour.normalizedPath
                bounds.append(path.boundingBox)
            }
        }
        
        return bounds
    }
}

// MARK: - Types

public enum VisionAnalyzerError: Error {
    case textureConversionFailed(String)
    case saliencyFailed(String)
    case colorAnalysisFailed(String)
    case ssimFailed(String)
    case energyCalculationFailed(String)
    case motionAnalysisFailed(String)
}

public struct SaliencyResult: Sendable {
    public let hotspots: [SaliencyHotspot]
    public let totalSalientArea: Float
    public let averageConfidence: Float
    public let distributionScore: Float
}

public struct SaliencyHotspot: Sendable {
    public let center: CGPoint
    public let boundingBox: CGRect
    public let confidence: Float
    
    public var area: Float { Float(boundingBox.width * boundingBox.height) }
}

public struct DepthSeparationResult: Sendable {
    public let foregroundPercentage: Float
    public let backgroundPercentage: Float
    public let separationConfidence: Float
    public let layerCount: Int
}

public struct ColorDistributionResult: Sendable {
    public let redHistogram: [Int]
    public let greenHistogram: [Int]
    public let blueHistogram: [Int]
    public let averageColor: SIMD3<Float>
    public let dominantColors: [SIMD3<Float>]
}

public struct LuminanceProfile: Sendable {
    public let ringLuminance: [Float]
    public let centerLuminance: Float
    public let edgeLuminance: Float
    public let falloffRatio: Float
}

public struct EdgeAnalysisResult: Sendable {
    public let edgeCount: Int
    public let totalEdgeLength: Float
    public let averageEdgeStrength: Float
    public let edgeDensity: Float
}

public struct SSIMResult: Sendable {
    public let overall: Float
    public let luminanceComponent: Float
    public let contrastComponent: Float
    public let structureComponent: Float
}

public struct TextAnalysisResult: Sendable {
    public let observations: [TextObservation]
    public let fullText: String
}

public struct TextObservation: Sendable {
    public let text: String
    public let confidence: VNConfidence
    public let boundingBox: CGRect
}

public struct MotionResult: Sendable {
    public let averageMagnitude: Float
    public let maxMagnitude: Float
    public let stabilityScore: Float
}

extension LuminanceProfile {
    /// Checks if the luminance profile matches the Cos^4 law of illumination falloff
    /// - Parameters:
    ///   - tolerance: Maximum allowed deviation (e.g. 0.15 for 15%)
    ///   - intensity: The intensity of the vignette effect (0.0-1.0)
    ///   - maxAngle: The maximum angle (in radians) at the edge of the analyzed region (normalized radius = 1.0)
    /// - Returns: Tuple of (matches, maxDeviation)
    public func matchesCos4LawWithDeviation(tolerance: Float, intensity: Float, maxAngle: Float = 30.0 * (.pi / 180.0)) -> (matches: Bool, deviation: Float) {
        // Cos^4 law: L(θ) = L(0) * cos^4(θ)
        // We approximate θ based on ring index (radius)
        
        var maxDeviation: Float = 0.0
        
        for (i, luminance) in ringLuminance.enumerated() {
            let normalizedRadius = Float(i) / Float(ringLuminance.count - 1)
            // Use exact geometry: theta = atan(r/f)
            // We know maxAngle corresponds to r=1.0
            // So tan(maxAngle) = R_max / f
            // For normalized radius r':
            // theta' = atan(normalizedRadius * tan(maxAngle))
            let angle = atan(normalizedRadius * tan(maxAngle))
            let cosTheta = cos(angle)
            let cos4 = cosTheta * cosTheta * cosTheta * cosTheta
            
            // The effect blends between 1.0 (no vignette) and cos4 based on intensity
            // L_expected = L_center * mix(1.0, cos4, intensity)
            let expectedFactor = 1.0 * (1.0 - intensity) + cos4 * intensity
            let expectedLuminance = centerLuminance * expectedFactor
            
            // Avoid division by zero
            if expectedLuminance > 0.001 {
                let deviation = abs(luminance - expectedLuminance) / expectedLuminance
                maxDeviation = max(maxDeviation, deviation)
            }
        }
        
        return (maxDeviation <= tolerance, maxDeviation)
    }
}

// MARK: - Convenience Helpers for Validators
    
extension VisionAnalyzer {
    
    public func calculateHistogram(data: Data) async throws -> [Int] {
        // Return Green channel as proxy for luminance histogram since we don't compute full luminance histogram yet
        let dist = try await analyzeColorDistribution(data: data)
        return dist.greenHistogram
    }
    
    public func calculateEdgeDensity(data: Data) async throws -> Float {
        let result = try await analyzeEdges(data: data)
        return result.edgeDensity
    }
    
    public func calculateAverageLuminance(data: Data) async throws -> Float {
        let dist = try await analyzeColorDistribution(data: data)
        let c = dist.averageColor
        return 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
    }
    
    public func calculateContrast(data: Data) async throws -> Float {
        let (minLum, maxLum) = try await getMinMaxLuminance(data: data)
        return (maxLum - minLum) / (maxLum + minLum + 0.001)
    }
    
    public func calculateLuminanceVariance(data: Data) async throws -> Float {
        // Use single region to get global variance
        let varianceProfile = try await analyzeLocalVariance(data: data, regions: 1)
        return varianceProfile.first ?? 0.0
    }
}
