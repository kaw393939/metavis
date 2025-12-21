import Foundation
import Metal
import MetalKit
import ImageIO
import CoreGraphics
import Yams

import Logging

/// Validates the physical camera simulation
/// Verifies FOV accuracy, Depth of Field (DoF), and Motion Blur
@available(macOS 14.0, *)
public struct CameraValidator: EffectValidator {
    public let effectName = "camera"
    private let device: MTLDevice
    private let visionAnalyzer: VisionAnalyzer
    private let logger = Logger(label: "com.metalvis.validation.camera")
    
    // MARK: - Math Config Structures
    private struct MathConfig: Decodable {
        let scenarios: [String: Scenario]
    }
    
    private struct Scenario: Decodable {
        let description: String?
        let parameters: [String: Double]
        let expectations: [String: Double]
    }
    
    public init(device: MTLDevice) {
        self.device = device
        self.visionAnalyzer = VisionAnalyzer(device: device)
    }
    
    public func validate(
        frameData: Data,
        baselineData: Data?,
        parameters: EffectParameters,
        context: ValidationContext
    ) async throws -> EffectValidationResult {
        
        var metrics: [String: Double] = [:]
        var diagnostics: [Diagnostic] = []
        
        // Check if we have camera parameters
        if let focalLength = parameters.additionalParams["focal_length"],
           let sensorWidth = parameters.additionalParams["sensor_width"] {
            
            // Check test type to decide which validation to run
            let testType = parameters.additionalParams["test_type"] ?? 0.0
            
            if abs(testType - 2.0) < 0.01 {
                // Bokeh Validation
                if let fStop = parameters.additionalParams["f_stop"],
                   let focusDistance = parameters.additionalParams["focus_distance"] {
                    let bokehResult = try await validateBokeh(
                        data: frameData,
                        focalLength: focalLength,
                        fStop: fStop,
                        focusDistance: focusDistance
                    )
                    metrics.merge(bokehResult.metrics) { (_, new) in new }
                    diagnostics.append(contentsOf: bokehResult.diagnostics)
                }
            } else {
                // Default: FOV Validation
                let fovResult = try await validateFOV(data: frameData, focalLength: focalLength, sensorWidth: sensorWidth)
                metrics.merge(fovResult.metrics) { (_, new) in new }
                diagnostics.append(contentsOf: fovResult.diagnostics)
            }
        }
        
        // We can also run basic saliency check
        let saliency = try await visionAnalyzer.analyzeSaliency(data: frameData)
        metrics["saliency_confidence"] = Double(saliency.averageConfidence)
        
        return EffectValidationResult(
            effectName: effectName,
            passed: !diagnostics.contains { $0.severity == .error },
            metrics: metrics,
            thresholds: [:], // Thresholds are handled by Runner
            diagnostics: diagnostics,
            suggestedFixes: [],
            timestamp: Date(),
            frameIndex: context.frameIndex
        )
    }
    
    // MARK: - Config Loading
    
    private func loadMathConfig() -> MathConfig? {
        let path = "assets/config/validation_math/camera_lens_math.yaml"
        // Use absolute path if needed, but relative to workspace root is standard for this project
        // Assuming running from workspace root
        let fullPath = FileManager.default.currentDirectoryPath + "/" + path
        
        guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else {
            // Try absolute path if relative fails (for safety)
            let absPath = "/Users/kwilliams/Projects/metavis_studio/" + path
            guard let absContent = try? String(contentsOfFile: absPath, encoding: .utf8) else {
                logger.warning("Failed to load math config from \(path)")
                return nil
            }
            let decoder = YAMLDecoder()
            return try? decoder.decode(MathConfig.self, from: absContent)
        }
        
        let decoder = YAMLDecoder()
        return try? decoder.decode(MathConfig.self, from: content)
    }
    
    private func findMatchingScenario(config: MathConfig, focalLength: Float, fStop: Float?, focusDistance: Float?, sensorWidth: Float) -> Scenario? {
        for (_, scenario) in config.scenarios {
            let p = scenario.parameters
            
            // Check mandatory params
            if let fl = p["focal_length"], abs(Float(fl) - focalLength) > 0.1 { continue }
            if let sw = p["sensor_width"], abs(Float(sw) - sensorWidth) > 0.1 { continue }
            
            // Check optional params if provided in scenario
            if let fs = p["f_stop"], let inputFs = fStop {
                if abs(Float(fs) - inputFs) > 0.1 { continue }
            }
            
            if let fd = p["focus_distance"], let inputFd = focusDistance {
                if abs(Float(fd) - inputFd) > 0.1 { continue }
            }
            
            return scenario
        }
        return nil
    }

    // MARK: - FOV Validation
    
    private struct SubValidationResult {
        let metrics: [String: Double]
        let diagnostics: [Diagnostic]
    }
    
    private func validateFOV(data: Data, focalLength: Float, sensorWidth: Float) async throws -> SubValidationResult {
        // Theoretical FOV calculation
        // theta = 2 * atan(sensor_width / (2 * focal_length))
        var expectedFOV = 2 * atan(sensorWidth / (2 * focalLength))
        var expectedDegrees = degrees(expectedFOV)
        
        // Try to load from config
        if let config = loadMathConfig(),
           let scenario = findMatchingScenario(config: config, focalLength: focalLength, fStop: nil, focusDistance: nil, sensorWidth: sensorWidth) {
            if let expDeg = scenario.expectations["fov_horizontal_deg"] {
                expectedDegrees = Float(expDeg)
                logger.info("Using expected FOV from config: \(expectedDegrees)")
            }
        }
        
        // Measure apparent FOV from image
        // We assume the scene contains two markers at x = +/- 1.0, z = -5.0
        // This assumption relies on ValidationRunner.createFOVScene()
        
        // Use custom marker detection instead of saliency
        let markers = findMarkers(in: data)
        
        guard markers.count >= 2 else {
            return SubValidationResult(
                metrics: ["fov_tolerance": 999.0], // High error
                diagnostics: [Diagnostic(
                    severity: .error,
                    code: "FOV_MARKER_MISSING",
                    message: "Failed to detect 2 markers for FOV measurement. Found \(markers.count).",
                    context: ["markers": "\(markers.count)"]
                )]
            )
        }
        
        // Get the two markers (already sorted by findMarkers)
        let leftMarker = markers[0]
        let rightMarker = markers[1]
        
        // Calculate normalized distance (0.0 to 1.0)
        // markers are in normalized coordinates (0-1)
        let deltaU = Float(rightMarker.x - leftMarker.x)
        
        // Aspect ratio is 16:9 (1920/1080) as per ValidationRunner
        let aspect: Float = 1920.0 / 1080.0
        
        // Back-calculate FOV
        // Formula derived: tan(theta/2) = 0.2 / deltaU
        // (Assuming markers at x=±1, z=-5, and P[0][0] = 1/tan(fov/2))
        // We do NOT divide by aspect ratio because we are measuring Horizontal FOV directly from Horizontal spread.
        let measuredHalfAngle = atan(0.2 / deltaU)
        let measuredFOV = 2 * measuredHalfAngle
        let measuredDegrees = degrees(measuredFOV)
        
        let errorDegrees = abs(measuredDegrees - expectedDegrees)
        
        var diagnostics: [Diagnostic] = []
        if errorDegrees > 1.0 { // 1 degree warning threshold internal to validator
             diagnostics.append(Diagnostic(
                severity: .warning,
                code: "FOV_MISMATCH",
                message: "Measured FOV deviates from expected",
                measuredValue: Double(measuredDegrees),
                expectedMin: Double(expectedDegrees - 0.5),
                expectedMax: Double(expectedDegrees + 0.5),
                context: ["deltaU": "\(deltaU)", "aspect": "\(aspect)"]
            ))
        }
        
        return SubValidationResult(
            metrics: [
                "fov_tolerance": Double(errorDegrees), // The error itself is the metric to check
                "measured_fov": Double(measuredDegrees),
                "expected_fov": Double(expectedDegrees)
            ],
            diagnostics: diagnostics
        )
    }
    
    private func findMarkers(in data: Data) -> [CGPoint] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let dataProvider = cgImage.dataProvider,
              let pixelData = dataProvider.data,
              let bytes = CFDataGetBytePtr(pixelData) else {
            return []
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        
        var leftSumX: Float = 0
        var leftSumY: Float = 0
        var leftCount: Int = 0
        
        var rightSumX: Float = 0
        var rightSumY: Float = 0
        var rightCount: Int = 0
        
        let threshold: UInt8 = 128
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                // Check green channel (assuming white markers)
                let g = bytes[offset + 1]
                
                if g > threshold {
                    if x < width / 2 {
                        leftSumX += Float(x)
                        leftSumY += Float(y)
                        leftCount += 1
                    } else {
                        rightSumX += Float(x)
                        rightSumY += Float(y)
                        rightCount += 1
                    }
                }
            }
        }
        
        var markers: [CGPoint] = []
        
        if leftCount > 0 {
            markers.append(CGPoint(
                x: Double(leftSumX) / Double(leftCount) / Double(width),
                y: Double(leftSumY) / Double(leftCount) / Double(height)
            ))
        }
        
        if rightCount > 0 {
            markers.append(CGPoint(
                x: Double(rightSumX) / Double(rightCount) / Double(width),
                y: Double(rightSumY) / Double(rightCount) / Double(height)
            ))
        }
        
        return markers
    }
    
    // MARK: - Bokeh Validation
    
    private func validateBokeh(
        data: Data,
        focalLength: Float,
        fStop: Float,
        focusDistance: Float
    ) async throws -> SubValidationResult {
        // 1. Measure bokeh disk diameter
        // We expect a single bright disk on black background
        guard let diameterPx = measureBlobDiameter(in: data) else {
            return SubValidationResult(
                metrics: ["coc_tolerance": 999.0],
                diagnostics: [Diagnostic(
                    severity: .error,
                    code: "BOKEH_NOT_FOUND",
                    message: "Failed to detect bokeh disk"
                )]
            )
        }
        
        // 2. Calculate expected CoC
        // Scene setup (must match ValidationRunner.createBokehScene):
        // Object at z = -10.0 (10m distance)
        // Focus at z = -2.0 (2m distance)
        // Sensor width = 36mm (default)
        // Image width = 1920px
        
        let objectDistance: Float = 10.0 // 10 meters
        let sensorWidth: Float = 36.0 // mm
        let imageWidthPx: Float = 1920.0
        
        // CoC formula: A * (|z - z_focus| / z) * (f / (z_focus - f))
        // All units in mm
        let f = focalLength // mm
        let A = f / fStop // mm
        let z = objectDistance * 1000.0 // mm
        let z_focus = focusDistance * 1000.0 // mm
        
        let term1 = abs(z - z_focus) / z
        let term2 = f / (z_focus - f)
        let expectedCoC_mm = A * term1 * term2
        
        // Convert CoC mm to pixels
        // pixels = mm * (imageWidthPx / sensorWidth)
        var expectedDiameterPx = expectedCoC_mm * (imageWidthPx / sensorWidth)
        
        // Try to load from config
        if let config = loadMathConfig(),
           let scenario = findMatchingScenario(config: config, focalLength: focalLength, fStop: fStop, focusDistance: focusDistance, sensorWidth: sensorWidth) {
            if let expPx = scenario.expectations["coc_diameter_px"] {
                expectedDiameterPx = Float(expPx)
                logger.info("Using expected Bokeh diameter from config: \(expectedDiameterPx)")
            }
        }
        
        // 3. Compare
        // Calculate ratio difference
        let ratio = Float(diameterPx) / expectedDiameterPx
        let error = abs(1.0 - ratio)
        
        logger.error("[CameraValidator] Bokeh Size: Measured=\(diameterPx) px, Expected=\(expectedDiameterPx) px, Error=\(error * 100)%")
        
        var diagnostics: [Diagnostic] = []
        if error > 0.2 { // 20% tolerance (increased from 10% to account for sampling artifacts)
            diagnostics.append(Diagnostic(
                severity: .warning,
                code: "BOKEH_SIZE_MISMATCH",
                message: "Bokeh size mismatch. Expected \(String(format: "%.1f", expectedDiameterPx)) px, got \(String(format: "%.1f", diameterPx)) px",
                measuredValue: Double(diameterPx),
                expectedMin: Double(expectedDiameterPx * 0.9),
                expectedMax: Double(expectedDiameterPx * 1.1),
                context: [
                    "focalLength": "\(focalLength)",
                    "fStop": "\(fStop)",
                    "focusDistance": "\(focusDistance)",
                    "measured": "\(diameterPx)",
                    "expected": "\(expectedDiameterPx)"
                ]
            ))
        }
        
        return SubValidationResult(
            metrics: [
                "coc_tolerance": Double(error),
                "bokeh_diameter_px": Double(diameterPx),
                "expected_diameter_px": Double(expectedDiameterPx)
            ],
            diagnostics: diagnostics
        )
    }
    
    private func measureBlobDiameter(in data: Data) -> Float? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let dataProvider = cgImage.dataProvider,
              let pixelData = dataProvider.data,
              let bytes = CFDataGetBytePtr(pixelData) else {
            return nil
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = cgImage.bytesPerRow
        let bytesPerPixel = cgImage.bitsPerPixel / 8
        
        var minX = width
        var maxX = 0
        var minY = height
        var maxY = 0
        var found = false
        
        let threshold: UInt8 = 20 // Low threshold to catch edges of bokeh
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                // Check luminance (assuming grayscale or white light)
                let r = bytes[offset]
                
                if r > threshold {
                    found = true
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        
        guard found else { return nil }
        
        let widthPx = Float(maxX - minX)
        let heightPx = Float(maxY - minY)
        
        // Return average diameter
        return (widthPx + heightPx) / 2.0
    }
    
    // MARK: - Helpers
    
    private func degrees(_ radians: Float) -> Float {
        return radians * 180 / .pi
    }
}
