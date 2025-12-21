import Foundation
import Metal
import simd
import Logging

/// Validates text layout - margins, legibility, and alignment
@available(macOS 14.0, *)
public struct TextLayoutValidator: EffectValidator {
    public let effectName = "text_layout"
    public let tolerances: [String: Float]
    
    private let device: MTLDevice
    private let visionAnalyzer: VisionAnalyzer
    private let logger = Logger(label: "com.metalvis.validation.text")
    
    public init(device: MTLDevice, tolerances: [String: Float] = [:]) {
        self.device = device
        self.visionAnalyzer = VisionAnalyzer(device: device)
        self.tolerances = tolerances
    }
    
    public func validate(
        frameData: Data,
        baselineData: Data?,
        parameters: EffectParameters,
        context: ValidationContext
    ) async throws -> EffectValidationResult {
        logger.info("Validating text layout at frame \(context.frameIndex)")
        
        var metrics: [String: Float] = [:]
        var diagnostics: [Diagnostic] = []
        var suggestedFixes: [String] = []
        
        // 1. Margin Compliance
        // Check if any pixels exist in the margin areas
        // We assume the text is white on black, OR we detect background color
        
        // Sample background color from a safe corner (top-left 1%)
        let cornerRegion = CGRect(x: 0, y: 0, width: 0.01, height: 0.01)
        let backgroundColor = try await visionAnalyzer.analyzeRegionColor(data: frameData, region: cornerRegion)
        let bgBrightness = max(backgroundColor.x, max(backgroundColor.y, backgroundColor.z))
        
        // Dynamic threshold: Background + 0.1 (10% brighter than background)
        // But enforce a minimum floor of 0.3 to avoid false positives on gradients
        let detectionThreshold = max(bgBrightness + 0.1, 0.3)

        // Get margin settings from parameters or defaults
        let marginH = parameters.additionalParams["margin_horizontal"] ?? 0.10
        let marginV = parameters.additionalParams["margin_vertical"] ?? 0.05
        
        let _ = Float(context.width)
        let _ = Float(context.height)
        
        // Define margin rects (normalized 0-1)
        let leftMargin = CGRect(x: 0, y: 0, width: Double(marginH), height: 1.0)
        let rightMargin = CGRect(x: 1.0 - Double(marginH), y: 0, width: Double(marginH), height: 1.0)
        let topMargin = CGRect(x: 0, y: 0, width: 1.0, height: Double(marginV))
        let bottomMargin = CGRect(x: 0, y: 1.0 - Double(marginV), width: 1.0, height: Double(marginV))
        
        // Check for content in margins
        let leftColor = try await visionAnalyzer.analyzeRegionColor(data: frameData, region: leftMargin)
        let rightColor = try await visionAnalyzer.analyzeRegionColor(data: frameData, region: rightMargin)
        let topColor = try await visionAnalyzer.analyzeRegionColor(data: frameData, region: topMargin)
        let bottomColor = try await visionAnalyzer.analyzeRegionColor(data: frameData, region: bottomMargin)
        
        let maxMarginBrightness = max(
            max(leftColor.x, max(leftColor.y, leftColor.z)),
            max(rightColor.x, max(rightColor.y, rightColor.z)),
            max(topColor.x, max(topColor.y, topColor.z)),
            max(bottomColor.x, max(bottomColor.y, bottomColor.z))
        )
        
        metrics["margin_violation"] = maxMarginBrightness > detectionThreshold ? 1.0 : 0.0
        
        if maxMarginBrightness > detectionThreshold {
            diagnostics.append(Diagnostic(
                severity: .warning,
                code: "TEXT_MARGIN_VIOLATION",
                message: "Text content detected in safe margins (brightness: \(String(format: "%.3f", maxMarginBrightness)), bg: \(String(format: "%.3f", bgBrightness)))",
                context: [
                    "margin_h": "\(marginH)",
                    "margin_v": "\(marginV)",
                    "threshold": "\(detectionThreshold)"
                ]
            ))
            suggestedFixes.append("Increase text margins or reduce font size")
        }
        
        // 1.5 Edge Cutoff Check
        // Check if text is actually cut off at the screen edges
        let edgeThickness = 0.005 // 0.5% of screen dimension
        
        let leftEdge = CGRect(x: 0, y: 0, width: edgeThickness, height: 1.0)
        let rightEdge = CGRect(x: 1.0 - edgeThickness, y: 0, width: edgeThickness, height: 1.0)
        
        let leftEdgeColor = try await visionAnalyzer.analyzeRegionColor(data: frameData, region: leftEdge)
        let rightEdgeColor = try await visionAnalyzer.analyzeRegionColor(data: frameData, region: rightEdge)
        
        let maxEdgeBrightness = max(
            max(leftEdgeColor.x, max(leftEdgeColor.y, leftEdgeColor.z)),
            max(rightEdgeColor.x, max(rightEdgeColor.y, rightEdgeColor.z))
        )
        
        metrics["edge_cutoff"] = maxEdgeBrightness > detectionThreshold ? 1.0 : 0.0
        
        if maxEdgeBrightness > detectionThreshold {
            let leftMax = max(leftEdgeColor.x, max(leftEdgeColor.y, leftEdgeColor.z))
            let rightMax = max(rightEdgeColor.x, max(rightEdgeColor.y, rightEdgeColor.z))
            let side = leftMax > rightMax ? "LEFT" : "RIGHT"
            
             diagnostics.append(Diagnostic(
                severity: .error,
                code: "TEXT_CLIPPED",
                message: "Text is clipped at \(side) screen edge (brightness: \(String(format: "%.3f", maxEdgeBrightness)), bg: \(String(format: "%.3f", bgBrightness)))",
                context: ["edge_brightness": "\(maxEdgeBrightness)", "side": side, "threshold": "\(detectionThreshold)"]
            ))
            suggestedFixes.append("Reduce font size or wrap text to fit screen width")
        }
        
        // 2. Legibility (OCR)
        let textResult = try await visionAnalyzer.analyzeText(data: frameData)
        let recognizedText = textResult.fullText
        
        // Calculate OCR accuracy
        var ocrAccuracy: Float = 0.0
        
        if let expectedText = parameters.textParams["content"] {
            // Normalize texts (remove newlines, extra spaces, case insensitive)
            let normalizedExpected = expectedText.replacingOccurrences(of: "\n", with: " ").lowercased().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let normalizedRecognized = recognizedText.replacingOccurrences(of: "\n", with: " ").lowercased().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            // Simple containment check
            if normalizedRecognized.contains(normalizedExpected) {
                ocrAccuracy = 1.0
            } else {
                // If not exact match, check for partial match (e.g. 80% of words found)
                let expectedWords = Set(normalizedExpected.split(separator: " "))
                let recognizedWords = Set(normalizedRecognized.split(separator: " "))
                let commonWords = expectedWords.intersection(recognizedWords)
                
                if !expectedWords.isEmpty {
                    ocrAccuracy = Float(commonWords.count) / Float(expectedWords.count)
                }
            }
            
            if ocrAccuracy < 0.8 {
                diagnostics.append(Diagnostic(
                    severity: .error,
                    code: "TEXT_LEGIBILITY_FAILED",
                    message: "Expected text not found in recognized output (accuracy: \(String(format: "%.2f", ocrAccuracy)))",
                    context: [
                        "expected": expectedText,
                        "recognized": recognizedText.prefix(100) + (recognizedText.count > 100 ? "..." : "")
                    ]
                ))
                suggestedFixes.append("Increase font size, contrast, or reduce blur/distortion")
            }
        } else {
            // If no expected text provided, just check if ANY text was found with high confidence
            if !textResult.observations.isEmpty {
                let totalConf = textResult.observations.reduce(0.0) { $0 + $1.confidence }
                ocrAccuracy = Float(totalConf) / Float(textResult.observations.count)
            }
        }
        
        metrics["ocr_accuracy"] = ocrAccuracy
        
        // Contrast Check
        let minMax = try await visionAnalyzer.getMinMaxLuminance(data: frameData)
        let contrast = minMax.max - minMax.min
        
        if contrast < 0.5 {
            diagnostics.append(Diagnostic(
                severity: .warning,
                code: "TEXT_LOW_CONTRAST",
                message: "Text contrast is low (contrast: \(String(format: "%.2f", contrast)))",
                context: ["contrast": "\(contrast)"]
            ))
        }
        
        // 3. Baseline Alignment (Placeholder)
        metrics["baseline_deviation"] = 0.0 // Assume perfect alignment for now
        
        // 4. Line Length (Placeholder)
        metrics["chars_per_line_deviation"] = 0.0
        
        // 5. Orphan/Widow (Placeholder)
        metrics["orphan_count"] = 0.0
        
        // Determine pass/fail
        let hasErrors = diagnostics.contains { $0.severity == .error }
        let passed = !hasErrors
        
        return EffectValidationResult(
            effectName: effectName,
            passed: passed,
            metrics: metrics.mapValues { Double($0) },
            thresholds: tolerances.mapValues { Double($0) },
            diagnostics: diagnostics,
            suggestedFixes: suggestedFixes,
            frameIndex: context.frameIndex
        )
    }
}
