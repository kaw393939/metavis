import Foundation
import CoreImage
import Vision
import AVFoundation
import Accelerate

/// Analyzes image/video quality using PSNR, SSIM, sharpness, and noise metrics
public class QualityAnalyzer {
    private let ciContext: CIContext
    
    public init() {
        self.ciContext = CIContext(options: [.workingColorSpace: NSNull()])
    }
    
    // MARK: - Main Analysis
    
    /// Comprehensive quality analysis of a video
    public func analyzeQuality(videoURL: URL) async throws -> QualityAnalysisResult {
        
        // Extract sample frames
        let frames = try await extractSampleFrames(videoURL, count: 10)
        
        var sharpnessScores: [Double] = []
        var noiseScores: [Double] = []
        var contrastScores: [Double] = []
        
        for frame in frames {
            sharpnessScores.append(measureSharpness(frame))
            noiseScores.append(measureNoise(frame))
            contrastScores.append(measureContrast(frame))
        }
        
        let avgSharpness = sharpnessScores.reduce(0, +) / Double(sharpnessScores.count)
        let avgNoise = noiseScores.reduce(0, +) / Double(noiseScores.count)
        let avgContrast = contrastScores.reduce(0, +) / Double(contrastScores.count)
        
        let overallScore = calculateOverallScore(
            sharpness: avgSharpness,
            noise: avgNoise,
            contrast: avgContrast
        )
        
        return QualityAnalysisResult(
            sharpness: avgSharpness,
            noise: avgNoise,
            contrast: avgContrast,
            overallScore: overallScore
        )
    }
    
    // MARK: - Sharpness Measurement
    
    /// Measure image sharpness using Laplacian variance
    public func measureSharpness(_ image: CIImage) -> Double {
        // Convert to grayscale
        guard let grayscale = CIFilter(name: "CIPhotoEffectMono") else {
            return 0.0
        }
        grayscale.setValue(image, forKey: kCIInputImageKey)
        
        guard let grayImage = grayscale.outputImage else {
            return 0.0
        }
        
        // Apply Laplacian filter (edge detection)
        guard let convolution = CIFilter(name: "CIConvolution3X3") else {
            return 0.0
        }
        
        // Laplacian kernel
        let laplacianKernel = CIVector(values: [
            0, -1, 0,
            -1, 4, -1,
            0, -1, 0
        ], count: 9)
        
        convolution.setValue(grayImage, forKey: kCIInputImageKey)
        convolution.setValue(laplacianKernel, forKey: "inputWeights")
        
        guard let laplacian = convolution.outputImage else {
            return 0.0
        }
        
        // Calculate variance of Laplacian (higher = sharper)
        let variance = calculateVariance(laplacian)
        
        // Normalize to 0-1 range
        return min(variance / 1000.0, 1.0)
    }
    
    private func calculateVariance(_ image: CIImage) -> Double {
        // Sample pixels and calculate variance
        let extent = image.extent
        let width = Int(extent.width)
        let height = Int(extent.height)
        
        // Downsample for performance
        let sampleWidth = min(width, 256)
        let sampleHeight = min(height, 256)
        
        let scale = CGAffineTransform(
            scaleX: CGFloat(sampleWidth) / extent.width,
            y: CGFloat(sampleHeight) / extent.height
        )
        let scaledImage = image.transformed(by: scale)
        
        var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        
        ciContext.render(
            scaledImage,
            toBitmap: &pixels,
            rowBytes: sampleWidth * 4,
            bounds: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        
        // Calculate variance of grayscale values
        var sum: Double = 0
        var sumSquares: Double = 0
        var count = 0
        
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let gray = Double(pixels[i])  // R channel (grayscale)
            sum += gray
            sumSquares += gray * gray
            count += 1
        }
        
        let mean = sum / Double(count)
        let variance = (sumSquares / Double(count)) - (mean * mean)
        
        return variance
    }
    
    // MARK: - Noise Measurement
    
    /// Measure noise level using median filter difference
    public func measureNoise(_ image: CIImage) -> Double {
        // Apply median filter (removes noise)
        guard let median = CIFilter(name: "CIMedianFilter") else {
            return 0.0
        }
        median.setValue(image, forKey: kCIInputImageKey)
        
        guard let filtered = median.outputImage else {
            return 0.0
        }
        
        // Difference between original and filtered = noise
        guard let difference = CIFilter(name: "CIDifferenceBlendMode") else {
            return 0.0
        }
        difference.setValue(image, forKey: kCIInputImageKey)
        difference.setValue(filtered, forKey: kCIInputBackgroundImageKey)
        
        guard let noiseImage = difference.outputImage else {
            return 0.0
        }
        
        // Calculate mean of difference
        let noiseMean = calculateMean(noiseImage)
        
        // Normalize to 0-1 range (lower = less noise)
        return min(noiseMean * 10.0, 1.0)
    }
    
    private func calculateMean(_ image: CIImage) -> Double {
        let extent = image.extent
        let width = Int(extent.width)
        let height = Int(extent.height)
        
        // Downsample for performance
        let sampleWidth = min(width, 256)
        let sampleHeight = min(height, 256)
        
        let scale = CGAffineTransform(
            scaleX: CGFloat(sampleWidth) / extent.width,
            y: CGFloat(sampleHeight) / extent.height
        )
        let scaledImage = image.transformed(by: scale)
        
        var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        
        ciContext.render(
            scaledImage,
            toBitmap: &pixels,
            rowBytes: sampleWidth * 4,
            bounds: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        
        var sum: Double = 0
        var count = 0
        
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i])
            let g = Double(pixels[i + 1])
            let b = Double(pixels[i + 2])
            sum += (r + g + b) / 3.0
            count += 1
        }
        
        return (sum / Double(count)) / 255.0
    }
    
    // MARK: - Contrast Measurement
    
    /// Measure image contrast
    public func measureContrast(_ image: CIImage) -> Double {
        let extent = image.extent
        let width = Int(extent.width)
        let height = Int(extent.height)
        
        // Downsample for performance
        let sampleWidth = min(width, 256)
        let sampleHeight = min(height, 256)
        
        let scale = CGAffineTransform(
            scaleX: CGFloat(sampleWidth) / extent.width,
            y: CGFloat(sampleHeight) / extent.height
        )
        let scaledImage = image.transformed(by: scale)
        
        var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        
        ciContext.render(
            scaledImage,
            toBitmap: &pixels,
            rowBytes: sampleWidth * 4,
            bounds: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        
        // Calculate min and max luminance
        var minLum: Double = 255
        var maxLum: Double = 0
        
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i])
            let g = Double(pixels[i + 1])
            let b = Double(pixels[i + 2])
            let lum = (r + g + b) / 3.0
            minLum = min(minLum, lum)
            maxLum = max(maxLum, lum)
        }
        
        // Michelson contrast
        let contrast = (maxLum - minLum) / (maxLum + minLum + 1.0)
        
        return contrast
    }
    
    // MARK: - PSNR Calculation
    
    /// Calculate Peak Signal-to-Noise Ratio between two images
    public func calculatePSNR(_ image1: CIImage, _ image2: CIImage) -> Double {
        let mse = calculateMSE(image1, image2)
        
        if mse == 0 { return Double.infinity }
        
        let maxPixelValue = 255.0
        let psnr = 20 * log10(maxPixelValue / sqrt(mse))
        
        return psnr
    }
    
    private func calculateMSE(_ image1: CIImage, _ image2: CIImage) -> Double {
        let extent = image1.extent
        let width = Int(extent.width)
        let height = Int(extent.height)
        
        // Ensure same size
        guard extent == image2.extent else { return Double.infinity }
        
        // Downsample for performance
        let sampleWidth = min(width, 512)
        let sampleHeight = min(height, 512)
        
        let scale = CGAffineTransform(
            scaleX: CGFloat(sampleWidth) / extent.width,
            y: CGFloat(sampleHeight) / extent.height
        )
        
        let scaled1 = image1.transformed(by: scale)
        let scaled2 = image2.transformed(by: scale)
        
        var pixels1 = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        var pixels2 = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        
        let bounds = CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        ciContext.render(scaled1, toBitmap: &pixels1, rowBytes: sampleWidth * 4,
                        bounds: bounds, format: .RGBA8, colorSpace: colorSpace)
        ciContext.render(scaled2, toBitmap: &pixels2, rowBytes: sampleWidth * 4,
                        bounds: bounds, format: .RGBA8, colorSpace: colorSpace)
        
        var sumSquaredDiff: Double = 0
        
        for i in 0..<pixels1.count {
            let diff = Double(pixels1[i]) - Double(pixels2[i])
            sumSquaredDiff += diff * diff
        }
        
        return sumSquaredDiff / Double(pixels1.count)
    }
    
    // MARK: - SSIM Calculation
    
    /// Calculate Structural Similarity Index between two images
    public func calculateSSIM(_ image1: CIImage, _ image2: CIImage) -> Double {
        // Simplified SSIM calculation
        let stats1 = calculateImageStatistics(image1)
        let stats2 = calculateImageStatistics(image2)
        
        let c1 = 0.01 * 0.01 * 255 * 255
        let c2 = 0.03 * 0.03 * 255 * 255
        
        let luminance = (2 * stats1.mean * stats2.mean + c1) /
                       (stats1.mean * stats1.mean + stats2.mean * stats2.mean + c1)
        
        let contrast = (2 * stats1.stdDev * stats2.stdDev + c2) /
                      (stats1.stdDev * stats1.stdDev + stats2.stdDev * stats2.stdDev + c2)
        
        // For simplicity, assume structure term is 1.0
        // Full SSIM would need covariance calculation
        let structure = 1.0
        
        return luminance * contrast * structure
    }
    
    private func calculateImageStatistics(_ image: CIImage) -> ImageStatistics {
        let extent = image.extent
        let width = Int(extent.width)
        let height = Int(extent.height)
        
        let sampleWidth = min(width, 256)
        let sampleHeight = min(height, 256)
        
        let scale = CGAffineTransform(
            scaleX: CGFloat(sampleWidth) / extent.width,
            y: CGFloat(sampleHeight) / extent.height
        )
        let scaledImage = image.transformed(by: scale)
        
        var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        
        ciContext.render(
            scaledImage,
            toBitmap: &pixels,
            rowBytes: sampleWidth * 4,
            bounds: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        
        var sum: Double = 0
        var count = 0
        
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let gray = (Double(pixels[i]) + Double(pixels[i+1]) + Double(pixels[i+2])) / 3.0
            sum += gray
            count += 1
        }
        
        let mean = sum / Double(count)
        
        var sumSquaredDiff: Double = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let gray = (Double(pixels[i]) + Double(pixels[i+1]) + Double(pixels[i+2])) / 3.0
            sumSquaredDiff += pow(gray - mean, 2)
        }
        
        let variance = sumSquaredDiff / Double(count)
        let stdDev = sqrt(variance)
        
        return ImageStatistics(mean: mean, stdDev: stdDev)
    }
    
    // MARK: - Overall Scoring
    
    private func calculateOverallScore(
        sharpness: Double,
        noise: Double,
        contrast: Double
    ) -> Double {
        // Weight factors
        let sharpnessWeight = 0.4
        let noiseWeight = 0.3
        let contrastWeight = 0.3
        
        // Noise should be low (invert score)
        let noiseScore = 1.0 - noise
        
        return (sharpness * sharpnessWeight +
                noiseScore * noiseWeight +
                contrast * contrastWeight)
    }
    
    // MARK: - Frame Extraction
    
    private func extractSampleFrames(_ videoURL: URL, count: Int) async throws -> [CIImage] {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else {
            throw QualityAnalysisError.noVideoTrack
        }
        
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        var frames: [CIImage] = []
        
        for i in 0..<count {
            let time = CMTime(
                seconds: durationSeconds * Double(i) / Double(count - 1),
                preferredTimescale: 600
            )
            
            let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
            frames.append(CIImage(cgImage: cgImage))
        }
        
        return frames
    }
}

// MARK: - Result Types

public struct QualityAnalysisResult: Codable {
    public let sharpness: Double  // 0.0 - 1.0 (higher = sharper)
    public let noise: Double  // 0.0 - 1.0 (lower = less noise)
    public let contrast: Double  // 0.0 - 1.0 (higher = more contrast)
    public let overallScore: Double  // 0.0 - 1.0
    
    /// Human-readable grade
    public var grade: String {
        switch overallScore {
        case 0.95...1.0: return "A+"
        case 0.90..<0.95: return "A"
        case 0.80..<0.90: return "B"
        case 0.70..<0.80: return "C"
        default: return "F"
        }
    }
}

struct ImageStatistics {
    let mean: Double
    let stdDev: Double
}

// MARK: - Errors

public enum QualityAnalysisError: Error {
    case noVideoTrack
}
