// Sources/MetaVisRender/Ingestion/Grading/LookAnalysisEngine.swift
// Sprint 03: CDL extraction and look matching for color grading

import AVFoundation
import CoreImage
import Accelerate
import Foundation

// MARK: - Look Analysis Engine

/// Analyzes footage to extract color decision lists (CDL) and match looks between clips
public actor LookAnalysisEngine {
    
    // MARK: - Configuration
    
    public struct Config: Sendable {
        /// Number of frames to sample for analysis
        public let sampleFrameCount: Int
        /// Resolution to downsample frames for analysis
        public let analysisResolution: Int
        /// Minimum saturation to include in analysis
        public let minSaturation: Float
        /// Include skin tone protection in CDL
        public let protectSkinTones: Bool
        /// Target for white balance neutral
        public let whiteBalanceTarget: SIMD3<Float>
        
        public init(
            sampleFrameCount: Int = 24,
            analysisResolution: Int = 256,
            minSaturation: Float = 0.1,
            protectSkinTones: Bool = true,
            whiteBalanceTarget: SIMD3<Float> = SIMD3(1.0, 1.0, 1.0)
        ) {
            self.sampleFrameCount = sampleFrameCount
            self.analysisResolution = analysisResolution
            self.minSaturation = minSaturation
            self.protectSkinTones = protectSkinTones
            self.whiteBalanceTarget = whiteBalanceTarget
        }
        
        public static let `default` = Config()
        
        public static let fast = Config(
            sampleFrameCount: 8,
            analysisResolution: 128
        )
        
        public static let detailed = Config(
            sampleFrameCount: 48,
            analysisResolution: 512
        )
    }
    
    private let config: Config
    private let ciContext: CIContext
    
    public init(config: Config = .default) {
        self.config = config
        self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
    }
    
    // MARK: - Public API
    
    /// Extract CDL parameters from footage
    public func extractCDL(from url: URL) async throws -> ColorDecisionList {
        let frames = try await sampleFrames(from: url)
        guard !frames.isEmpty else {
            throw IngestionError.unsupportedFormat(url.pathExtension)
        }
        
        // Analyze color characteristics across frames
        let colorStats = analyzeColorDistribution(frames: frames)
        
        // Calculate CDL parameters
        let slope = calculateSlope(from: colorStats)
        let offset = calculateOffset(from: colorStats)
        let power = calculatePower(from: colorStats)
        let saturation = calculateSaturation(from: colorStats)
        
        return ColorDecisionList(
            slope: slope,
            offset: offset,
            power: power,
            saturation: saturation
        )
    }
    
    /// Extract look profile with full metadata
    public func extractLook(from url: URL) async throws -> LookProfile {
        let frames = try await sampleFrames(from: url)
        guard !frames.isEmpty else {
            throw IngestionError.unsupportedFormat(url.pathExtension)
        }
        
        let colorStats = analyzeColorDistribution(frames: frames)
        let cdl = ColorDecisionList(
            slope: calculateSlope(from: colorStats),
            offset: calculateOffset(from: colorStats),
            power: calculatePower(from: colorStats),
            saturation: calculateSaturation(from: colorStats)
        )
        
        return LookProfile(
            cdl: cdl,
            colorCast: detectColorCast(from: colorStats),
            contrast: colorStats.contrast,
            exposure: colorStats.exposureBias,
            whiteBalance: colorStats.whiteBalance,
            skinToneHue: config.protectSkinTones ? detectSkinToneHue(frames: frames) : nil,
            histogram: colorStats.histogram,
            sourceURL: url
        )
    }
    
    /// Compare looks between two clips and calculate similarity
    public func compareLooks(
        _ look1: LookProfile,
        _ look2: LookProfile
    ) -> LookComparison {
        let cdlSimilarity = compareCDL(look1.cdl, look2.cdl)
        let histogramSimilarity = compareHistograms(look1.histogram, look2.histogram)
        let contrastDiff = abs(look1.contrast - look2.contrast)
        let exposureDiff = abs(look1.exposure - look2.exposure)
        
        let overallScore = (cdlSimilarity * 0.4 + histogramSimilarity * 0.3 +
                           (1.0 - min(contrastDiff, 1.0)) * 0.15 +
                           (1.0 - min(exposureDiff, 1.0)) * 0.15)
        
        return LookComparison(
            similarity: overallScore,
            cdlSimilarity: cdlSimilarity,
            histogramSimilarity: histogramSimilarity,
            contrastDifference: contrastDiff,
            exposureDifference: exposureDiff,
            matchRecommendation: overallScore > 0.85 ? .goodMatch :
                                 overallScore > 0.6 ? .adjustable : .mismatch
        )
    }
    
    /// Generate CDL to match target look from source
    public func generateMatchingCDL(
        source: LookProfile,
        target: LookProfile
    ) -> ColorDecisionList {
        // Calculate the transformation needed
        let slopeDiff = target.cdl.slope / source.cdl.slope
        let offsetDiff = target.cdl.offset - source.cdl.offset
        let powerDiff = target.cdl.power / source.cdl.power
        let satDiff = target.cdl.saturation / max(source.cdl.saturation, 0.01)
        
        return ColorDecisionList(
            slope: slopeDiff,
            offset: offsetDiff,
            power: powerDiff,
            saturation: satDiff
        )
    }
    
    /// Load and analyze a LUT file
    public func analyzeLUT(at url: URL) async throws -> LookLUTAnalysis {
        let lutData = try await loadLUT(from: url)
        
        // Analyze LUT characteristics
        let contrast = analyzeLUTContrast(lutData)
        let saturationChange = analyzeLUTSaturation(lutData)
        let colorShift = analyzeLUTColorShift(lutData)
        let isIdentity = isNearIdentity(lutData)
        
        return LookLUTAnalysis(
            url: url,
            size: lutData.size,
            contrast: contrast,
            saturationChange: saturationChange,
            colorShift: colorShift,
            isNearIdentity: isIdentity,
            approximateCDL: approximateCDL(from: lutData)
        )
    }
    
    // MARK: - Frame Sampling
    
    private func sampleFrames(from url: URL) async throws -> [AnalysisFrame] {
        let asset = AVAsset(url: url)
        
        guard try await asset.load(.isReadable) else {
            throw IngestionError.unsupportedFormat(url.pathExtension)
        }
        
        let duration = try await asset.load(.duration).seconds
        guard duration > 0 else {
            throw IngestionError.corruptedFile("Invalid duration")
        }
        
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: config.analysisResolution, height: config.analysisResolution)
        
        let interval = duration / Double(config.sampleFrameCount + 1)
        var frames: [AnalysisFrame] = []
        
        for i in 1...config.sampleFrameCount {
            let time = CMTime(seconds: interval * Double(i), preferredTimescale: 600)
            
            do {
                let (cgImage, actualTime) = try await generator.image(at: time)
                let pixels = extractPixels(from: cgImage)
                
                frames.append(AnalysisFrame(
                    timestamp: actualTime.seconds,
                    pixels: pixels,
                    width: cgImage.width,
                    height: cgImage.height
                ))
            } catch {
                // Skip frames that fail to decode
                continue
            }
        }
        
        return frames
    }
    
    private func extractPixels(from image: CGImage) -> [SIMD3<Float>] {
        let width = image.width
        let height = image.height
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return []
        }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else {
            return []
        }
        
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var pixels: [SIMD3<Float>] = []
        pixels.reserveCapacity(width * height)
        
        for i in 0..<(width * height) {
            let r = Float(buffer[i * 4]) / 255.0
            let g = Float(buffer[i * 4 + 1]) / 255.0
            let b = Float(buffer[i * 4 + 2]) / 255.0
            pixels.append(SIMD3(r, g, b))
        }
        
        return pixels
    }
    
    // MARK: - Color Analysis
    
    private func analyzeColorDistribution(frames: [AnalysisFrame]) -> ColorStatistics {
        var allPixels: [SIMD3<Float>] = []
        
        for frame in frames {
            allPixels.append(contentsOf: frame.pixels)
        }
        
        guard !allPixels.isEmpty else {
            return ColorStatistics.neutral
        }
        
        // Calculate mean RGB
        var sum = SIMD3<Float>.zero
        for pixel in allPixels {
            sum += pixel
        }
        let mean = sum / Float(allPixels.count)
        
        // Calculate variance
        var variance = SIMD3<Float>.zero
        for pixel in allPixels {
            let diff = pixel - mean
            variance += diff * diff
        }
        variance /= Float(allPixels.count)
        let stdDev = SIMD3(sqrt(variance.x), sqrt(variance.y), sqrt(variance.z))
        
        // Calculate percentiles for shadows/mids/highlights
        let sorted = allPixels.sorted { luminance($0) < luminance($1) }
        let p5 = sorted[Int(Float(sorted.count) * 0.05)]
        let p50 = sorted[Int(Float(sorted.count) * 0.50)]
        let p95 = sorted[Int(Float(sorted.count) * 0.95)]
        
        // Calculate histogram
        var histogram = Array(repeating: Float(0), count: 256)
        for pixel in allPixels {
            let lum = Int(min(255, max(0, luminance(pixel) * 255)))
            histogram[lum] += 1
        }
        let maxHist = histogram.max() ?? 1.0
        histogram = histogram.map { $0 / maxHist }
        
        // Calculate contrast
        let contrast = luminance(p95) - luminance(p5)
        
        // Calculate exposure bias (0 = neutral, >0 = bright, <0 = dark)
        let exposureBias = (luminance(mean) - 0.18) / 0.18  // 0.18 is middle gray
        
        // Estimate white balance from highlights
        let whiteBalance = p95 / max(luminance(p95), 0.01)
        
        return ColorStatistics(
            mean: mean,
            stdDev: stdDev,
            shadows: p5,
            midtones: p50,
            highlights: p95,
            histogram: histogram,
            contrast: contrast,
            exposureBias: exposureBias,
            whiteBalance: whiteBalance
        )
    }
    
    private func luminance(_ rgb: SIMD3<Float>) -> Float {
        return 0.2126 * rgb.x + 0.7152 * rgb.y + 0.0722 * rgb.z
    }
    
    // MARK: - CDL Calculation
    
    private func calculateSlope(from stats: ColorStatistics) -> SIMD3<Float> {
        // Slope adjusts contrast/brightness multiplicatively
        // Higher values = more contrast
        let targetContrast: Float = 0.8  // Ideal contrast range
        let currentContrast = stats.contrast
        
        if currentContrast < 0.01 {
            return SIMD3(1.0, 1.0, 1.0)
        }
        
        let contrastRatio = targetContrast / currentContrast
        
        // Per-channel adjustment based on white balance
        let wb = stats.whiteBalance
        let avgWB = (wb.x + wb.y + wb.z) / 3.0
        
        return SIMD3(
            contrastRatio * (avgWB / max(wb.x, 0.01)),
            contrastRatio * (avgWB / max(wb.y, 0.01)),
            contrastRatio * (avgWB / max(wb.z, 0.01))
        ).clamped(lowerBound: SIMD3(0.5, 0.5, 0.5), upperBound: SIMD3(2.0, 2.0, 2.0))
    }
    
    private func calculateOffset(from stats: ColorStatistics) -> SIMD3<Float> {
        // Offset adjusts black level additively
        let shadows = stats.shadows
        let targetBlack: Float = 0.02  // Slight lift for video
        
        let avgShadow = (shadows.x + shadows.y + shadows.z) / 3.0
        let offsetNeeded = targetBlack - avgShadow
        
        return SIMD3(offsetNeeded, offsetNeeded, offsetNeeded)
            .clamped(lowerBound: SIMD3(-0.1, -0.1, -0.1), upperBound: SIMD3(0.1, 0.1, 0.1))
    }
    
    private func calculatePower(from stats: ColorStatistics) -> SIMD3<Float> {
        // Power adjusts gamma/midtones
        // Values > 1 darken midtones, < 1 brighten
        let midLum = luminance(stats.midtones)
        let targetMid: Float = 0.45  // Target midtone luminance
        
        if midLum < 0.01 {
            return SIMD3(1.0, 1.0, 1.0)
        }
        
        // Calculate gamma needed: targetMid = midLum^gamma
        // gamma = log(targetMid) / log(midLum)
        let gamma = log(targetMid) / log(midLum)
        let clampedGamma = max(0.5, min(2.0, gamma))
        
        return SIMD3(clampedGamma, clampedGamma, clampedGamma)
    }
    
    private func calculateSaturation(from stats: ColorStatistics) -> Float {
        // Estimate current saturation from color variance
        let meanLum = luminance(stats.mean)
        let colorDiff = abs(stats.mean.x - meanLum) + abs(stats.mean.y - meanLum) + abs(stats.mean.z - meanLum)
        
        // Target slightly higher saturation for video
        let targetSaturation: Float = 1.1
        let currentSaturation = colorDiff * 3.0  // Rough estimate
        
        if currentSaturation < 0.01 {
            return 1.0
        }
        
        return max(0.5, min(2.0, targetSaturation / currentSaturation))
    }
    
    // MARK: - Look Detection
    
    private func detectColorCast(from stats: ColorStatistics) -> ColorCast {
        let mean = stats.mean
        let avgLum = luminance(mean)
        
        if avgLum < 0.01 { return .neutral }
        
        // Normalize to remove luminance
        let normalized = mean / avgLum
        
        // Detect dominant color cast
        let rDiff = normalized.x - 1.0
        let gDiff = normalized.y - 1.0
        let bDiff = normalized.z - 1.0
        
        let threshold: Float = 0.1
        
        if abs(rDiff) < threshold && abs(gDiff) < threshold && abs(bDiff) < threshold {
            return .neutral
        }
        
        if rDiff > gDiff && rDiff > bDiff && rDiff > threshold {
            return bDiff < -threshold ? .warmOrange : .warmRed
        }
        
        if bDiff > rDiff && bDiff > gDiff && bDiff > threshold {
            return gDiff > threshold ? .coolCyan : .coolBlue
        }
        
        if gDiff > rDiff && gDiff > bDiff && gDiff > threshold {
            return rDiff > threshold ? .warmYellow : .coolGreen
        }
        
        if rDiff > threshold && bDiff > threshold {
            return .magenta
        }
        
        return .neutral
    }
    
    private func detectSkinToneHue(frames: [AnalysisFrame]) -> Float? {
        // Look for skin tone range in HSL space
        // Typical skin tones: H = 0-50 (red-orange-yellow), S = 0.2-0.6, L = 0.3-0.7
        var skinHues: [Float] = []
        
        for frame in frames {
            for pixel in frame.pixels {
                let hsl = rgbToHSL(pixel)
                
                // Check if in skin tone range
                if hsl.x < 50.0 / 360.0 || hsl.x > 350.0 / 360.0 {  // Hue in red-orange range
                    if hsl.y > 0.15 && hsl.y < 0.7 {  // Moderate saturation
                        if hsl.z > 0.2 && hsl.z < 0.8 {  // Not too dark or bright
                            skinHues.append(hsl.x)
                        }
                    }
                }
            }
        }
        
        guard !skinHues.isEmpty else { return nil }
        
        // Return average skin tone hue
        return skinHues.reduce(0, +) / Float(skinHues.count)
    }
    
    private func rgbToHSL(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        let maxC = max(rgb.x, max(rgb.y, rgb.z))
        let minC = min(rgb.x, min(rgb.y, rgb.z))
        let delta = maxC - minC
        
        let l = (maxC + minC) / 2.0
        
        if delta < 0.001 {
            return SIMD3(0, 0, l)
        }
        
        let s = delta / (1.0 - abs(2.0 * l - 1.0))
        
        var h: Float = 0
        if maxC == rgb.x {
            h = ((rgb.y - rgb.z) / delta).truncatingRemainder(dividingBy: 6.0)
        } else if maxC == rgb.y {
            h = (rgb.z - rgb.x) / delta + 2.0
        } else {
            h = (rgb.x - rgb.y) / delta + 4.0
        }
        
        h /= 6.0
        if h < 0 { h += 1.0 }
        
        return SIMD3(h, s, l)
    }
    
    // MARK: - Comparison
    
    private func compareCDL(_ a: ColorDecisionList, _ b: ColorDecisionList) -> Float {
        let slopeDiff = length(a.slope - b.slope)
        let offsetDiff = length(a.offset - b.offset)
        let powerDiff = length(a.power - b.power)
        let satDiff = abs(a.saturation - b.saturation)
        
        let maxDiff: Float = 3.0  // Maximum expected difference
        let totalDiff = slopeDiff + offsetDiff + powerDiff + satDiff
        
        return max(0, 1.0 - (totalDiff / maxDiff))
    }
    
    private func compareHistograms(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        
        // Bhattacharyya coefficient for histogram comparison
        var sum: Float = 0
        for i in a.indices {
            sum += sqrt(a[i] * b[i])
        }
        
        return sum / Float(a.count)
    }
    
    // MARK: - LUT Analysis
    
    private func loadLUT(from url: URL) async throws -> SimpleLUTData {
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var size = 0
        var entries: [SIMD3<Float>] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.components(separatedBy: .whitespaces)
                if parts.count >= 2, let s = Int(parts[1]) {
                    size = s
                }
                continue
            }
            
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("TITLE") ||
               trimmed.hasPrefix("DOMAIN") {
                continue
            }
            
            let values = trimmed.components(separatedBy: .whitespaces)
                .compactMap { Float($0) }
            
            if values.count >= 3 {
                entries.append(SIMD3(values[0], values[1], values[2]))
            }
        }
        
        return SimpleLUTData(size: size, entries: entries)
    }
    
    private func analyzeLUTContrast(_ lut: SimpleLUTData) -> Float {
        guard !lut.entries.isEmpty else { return 1.0 }
        
        // Compare input black/white to output
        let inputBlack = SIMD3<Float>.zero
        let inputWhite = SIMD3<Float>.one
        
        let outputBlack = lut.entries.first ?? inputBlack
        let outputWhite = lut.entries.last ?? inputWhite
        
        let inputRange = luminance(inputWhite) - luminance(inputBlack)
        let outputRange = luminance(outputWhite) - luminance(outputBlack)
        
        return outputRange / max(inputRange, 0.01)
    }
    
    private func analyzeLUTSaturation(_ lut: SimpleLUTData) -> Float {
        guard lut.size > 1 else { return 1.0 }
        
        // Sample saturated input colors and compare output saturation
        var inputSat: Float = 0
        var outputSat: Float = 0
        var samples = 0
        
        for entry in lut.entries {
            let maxC = max(entry.x, max(entry.y, entry.z))
            let minC = min(entry.x, min(entry.y, entry.z))
            outputSat += maxC - minC
            samples += 1
        }
        
        // Expected input saturation for a neutral grid
        inputSat = Float(samples) * 0.5
        
        return outputSat / max(inputSat, 0.01)
    }
    
    private func analyzeLUTColorShift(_ lut: SimpleLUTData) -> SIMD3<Float> {
        guard !lut.entries.isEmpty else { return .zero }
        
        // Check mid-gray transformation
        let midIndex = lut.entries.count / 2
        let midOutput = lut.entries[midIndex]
        
        // Expected mid-gray is 0.5, 0.5, 0.5
        return midOutput - SIMD3(0.5, 0.5, 0.5)
    }
    
    private func isNearIdentity(_ lut: SimpleLUTData) -> Bool {
        guard lut.size > 1, !lut.entries.isEmpty else { return false }
        
        let step = 1.0 / Float(lut.size - 1)
        var maxDiff: Float = 0
        var i = 0
        
        for b in 0..<lut.size {
            for g in 0..<lut.size {
                for r in 0..<lut.size {
                    if i >= lut.entries.count { break }
                    
                    let expected = SIMD3(Float(r) * step, Float(g) * step, Float(b) * step)
                    let actual = lut.entries[i]
                    let diff = length(expected - actual)
                    maxDiff = max(maxDiff, diff)
                    
                    i += 1
                }
            }
        }
        
        return maxDiff < 0.02
    }
    
    private func approximateCDL(from lut: SimpleLUTData) -> ColorDecisionList {
        guard !lut.entries.isEmpty else {
            return ColorDecisionList(
                slope: SIMD3(1, 1, 1),
                offset: SIMD3(0, 0, 0),
                power: SIMD3(1, 1, 1),
                saturation: 1.0
            )
        }
        
        // Sample key points to estimate CDL
        let black = lut.entries.first ?? .zero
        let white = lut.entries.last ?? .one
        let mid = lut.entries[lut.entries.count / 2]
        
        // Estimate slope from white point
        let slope = white
        
        // Estimate offset from black point
        let offset = black
        
        // Estimate power from midtones
        // Expected mid input: 0.5 after slope/offset
        // power = log(output) / log(input)
        let midInput: Float = 0.5
        let midLum = luminance(mid)
        let power = midLum > 0.01 && midInput > 0.01 ?
            log(midLum) / log(midInput) : 1.0
        
        return ColorDecisionList(
            slope: slope,
            offset: offset,
            power: SIMD3(power, power, power),
            saturation: analyzeLUTSaturation(lut)
        )
    }
}

// MARK: - Supporting Types

/// Color Decision List parameters
public struct ColorDecisionList: Codable, Sendable, Equatable {
    /// Multiplicative gain (slope) per channel
    public let slope: SIMD3<Float>
    /// Additive offset per channel
    public let offset: SIMD3<Float>
    /// Gamma/power per channel
    public let power: SIMD3<Float>
    /// Global saturation multiplier
    public let saturation: Float
    
    public init(slope: SIMD3<Float>, offset: SIMD3<Float>, power: SIMD3<Float>, saturation: Float) {
        self.slope = slope
        self.offset = offset
        self.power = power
        self.saturation = saturation
    }
    
    /// Identity CDL (no change)
    public static let identity = ColorDecisionList(
        slope: SIMD3(1, 1, 1),
        offset: SIMD3(0, 0, 0),
        power: SIMD3(1, 1, 1),
        saturation: 1.0
    )
    
    /// Apply CDL to a color value
    public func apply(to color: SIMD3<Float>) -> SIMD3<Float> {
        // Standard CDL formula: out = (in * slope + offset) ^ power
        var result = color * slope + offset
        result = SIMD3(
            pow(max(0, result.x), power.x),
            pow(max(0, result.y), power.y),
            pow(max(0, result.z), power.z)
        )
        
        // Apply saturation
        if saturation != 1.0 {
            let lum = 0.2126 * result.x + 0.7152 * result.y + 0.0722 * result.z
            result = SIMD3(
                lum + saturation * (result.x - lum),
                lum + saturation * (result.y - lum),
                lum + saturation * (result.z - lum)
            )
        }
        
        return result
    }
}

/// Full look profile with metadata
public struct LookProfile: Sendable {
    public let cdl: ColorDecisionList
    public let colorCast: ColorCast
    public let contrast: Float
    public let exposure: Float
    public let whiteBalance: SIMD3<Float>
    public let skinToneHue: Float?
    public let histogram: [Float]
    public let sourceURL: URL?
    
    public init(
        cdl: ColorDecisionList,
        colorCast: ColorCast,
        contrast: Float,
        exposure: Float,
        whiteBalance: SIMD3<Float>,
        skinToneHue: Float?,
        histogram: [Float],
        sourceURL: URL?
    ) {
        self.cdl = cdl
        self.colorCast = colorCast
        self.contrast = contrast
        self.exposure = exposure
        self.whiteBalance = whiteBalance
        self.skinToneHue = skinToneHue
        self.histogram = histogram
        self.sourceURL = sourceURL
    }
}

/// Detected color cast
public enum ColorCast: String, Codable, Sendable {
    case neutral
    case warmRed
    case warmOrange
    case warmYellow
    case coolGreen
    case coolCyan
    case coolBlue
    case magenta
}

/// Comparison result between two looks
public struct LookComparison: Sendable {
    public let similarity: Float  // 0-1, 1 = identical
    public let cdlSimilarity: Float
    public let histogramSimilarity: Float
    public let contrastDifference: Float
    public let exposureDifference: Float
    public let matchRecommendation: MatchRecommendation
}

public enum MatchRecommendation: String, Sendable {
    case goodMatch      // Looks similar enough for intercutting
    case adjustable     // Can be matched with minor grading
    case mismatch       // Significant difference, may need heavy grading
}

/// LUT analysis results for look matching
public struct LookLUTAnalysis: Sendable {
    public let url: URL
    public let size: Int
    public let contrast: Float
    public let saturationChange: Float
    public let colorShift: SIMD3<Float>
    public let isNearIdentity: Bool
    public let approximateCDL: ColorDecisionList
}

// MARK: - Private Types

private struct AnalysisFrame: Sendable {
    let timestamp: Double
    let pixels: [SIMD3<Float>]
    let width: Int
    let height: Int
}

private struct ColorStatistics {
    let mean: SIMD3<Float>
    let stdDev: SIMD3<Float>
    let shadows: SIMD3<Float>
    let midtones: SIMD3<Float>
    let highlights: SIMD3<Float>
    let histogram: [Float]
    let contrast: Float
    let exposureBias: Float
    let whiteBalance: SIMD3<Float>
    
    static let neutral = ColorStatistics(
        mean: SIMD3(0.5, 0.5, 0.5),
        stdDev: SIMD3(0.2, 0.2, 0.2),
        shadows: SIMD3(0.05, 0.05, 0.05),
        midtones: SIMD3(0.5, 0.5, 0.5),
        highlights: SIMD3(0.95, 0.95, 0.95),
        histogram: Array(repeating: 1.0 / 256.0, count: 256),
        contrast: 0.9,
        exposureBias: 0.0,
        whiteBalance: SIMD3(1, 1, 1)
    )
}

private struct SimpleLUTData {
    let size: Int
    let entries: [SIMD3<Float>]
}

// MARK: - SIMD Extensions

extension SIMD3 where Scalar == Float {
    func clamped(lowerBound: SIMD3<Float>, upperBound: SIMD3<Float>) -> SIMD3<Float> {
        return SIMD3(
            Swift.min(Swift.max(self.x, lowerBound.x), upperBound.x),
            Swift.min(Swift.max(self.y, lowerBound.y), upperBound.y),
            Swift.min(Swift.max(self.z, lowerBound.z), upperBound.z)
        )
    }
}
