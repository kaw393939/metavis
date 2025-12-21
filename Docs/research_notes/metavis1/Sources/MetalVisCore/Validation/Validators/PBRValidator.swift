import Foundation
import Metal
import Vision

@available(macOS 14.0, *)
public final class PBRValidator: EffectValidator {
    public let effectName = "pbr_validation"
    private let analyzer: VisionAnalyzer
    
    public init(device: MTLDevice) {
        self.analyzer = VisionAnalyzer(device: device)
    }
    
    public func validate(
        frameData: Data,
        baselineData: Data?,
        parameters: EffectParameters,
        context: ValidationContext
    ) async throws -> EffectValidationResult {
        var metrics: [String: Double] = [:]
        var diagnostics: [Diagnostic] = []
        var passed = true
        
        // 1. Analyze Saliency (Find the objects)
        var saliency = try await analyzer.analyzeSaliency(data: frameData)
        
        // Fallback to Contour Detection if Saliency fails to find 2 objects
        if saliency.hotspots.count < 2 {
            let contourBounds = try await analyzer.findObjectBounds(data: frameData)
            
            if contourBounds.count >= 2 {
                // Create synthetic hotspots from contours
                let newHotspots = contourBounds.map { rect in
                    SaliencyHotspot(
                        center: CGPoint(x: rect.midX, y: rect.midY),
                        boundingBox: rect,
                        confidence: 1.0
                    )
                }
                // Replace saliency result
                saliency = SaliencyResult(
                    hotspots: newHotspots,
                    totalSalientArea: saliency.totalSalientArea,
                    averageConfidence: 1.0,
                    distributionScore: saliency.distributionScore
                )
            }
        }

        metrics["saliency_count"] = Double(saliency.hotspots.count)
        
        // We expect at least 2 hotspots (Sphere and Quad)
        if saliency.hotspots.count < 2 {
            passed = false
            diagnostics.append(Diagnostic(
                severity: .error,
                code: "PBR_MISSING_OBJECTS",
                message: "Expected at least 2 salient objects (Sphere and Quad), found \(saliency.hotspots.count)"
            ))
        }
        
        // 2. Analyze Objects
        // Sort hotspots by X position (Left = Sphere, Right = Quad)
        let sortedHotspots = saliency.hotspots.sorted { $0.center.x < $1.center.x }
        
        if let leftObj = sortedHotspots.first {
            // --- Left Object (Sphere) Analysis ---
            metrics["left_obj_x"] = Double(leftObj.center.x)
            metrics["left_obj_circularity"] = 0.0 // Placeholder
            
            // Check Cutoff (Margin check)
            // Bounding box is normalized (0-1)
            let margin: CGFloat = 0.02
            if leftObj.boundingBox.minX < margin {
                passed = false
                diagnostics.append(Diagnostic(
                    severity: .error,
                    code: "PBR_SPHERE_CUTOFF",
                    message: "Left object (Sphere) is too close to the left edge (minX: \(leftObj.boundingBox.minX))"
                ))
            }
            
            // Check Circularity
            // We can use the analyzer's circularity check if we had the raw data, 
            // but here we can approximate with bounding box aspect ratio for now
            let aspect = leftObj.boundingBox.width / leftObj.boundingBox.height
            // Note: Bounding box aspect depends on image aspect ratio. 
            // Assuming 16:9 image, a square/circle would have aspect 9/16 = 0.5625 in normalized coords?
            // No, Vision bounding boxes are normalized. 
            // If image is 1920x1080, a 100x100 box is (100/1920) x (100/1080) = 0.052 x 0.092.
            // So aspect in normalized coords = (w/1920) / (h/1080) = (w/h) * (1080/1920).
            // For a circle (w=h), normalized aspect should be 1080/1920 = 0.5625.
            
            let imageAspect = 1920.0 / 1080.0 // Assuming HD
            let correctedAspect = aspect * imageAspect
            metrics["left_obj_aspect"] = Double(correctedAspect)
            
            if abs(correctedAspect - 1.0) > 0.2 {
                // Not a circle?
                // diagnostics.append(Diagnostic(severity: .warning, code: "PBR_SHAPE_MISMATCH", message: "Left object aspect ratio \(correctedAspect) is not circular"))
            }
            
            // Use VisionAnalyzer's circularity check
            // We need to pass the center and radius (approx from bbox)
            let radius = Float(max(leftObj.boundingBox.width, leftObj.boundingBox.height) / 2.0)
            let circularity = try await analyzer.analyzeHotspotCircularity(data: frameData, center: leftObj.center, radius: radius)
            metrics["left_obj_circularity"] = Double(circularity)
            
            if circularity < 0.6 {
                 passed = false
                 diagnostics.append(Diagnostic(
                    severity: .error,
                    code: "PBR_SPHERE_SHAPE",
                    message: "Left object does not look like a sphere (circularity: \(circularity))"
                 ))
            }
        }
        
        if let rightObj = sortedHotspots.last, sortedHotspots.count > 1 {
            // --- Right Object (Quad) Analysis ---
            metrics["right_obj_x"] = Double(rightObj.center.x)
            
            // Check Cutoff
            let margin: CGFloat = 0.02
            if rightObj.boundingBox.maxX > (1.0 - margin) {
                passed = false
                diagnostics.append(Diagnostic(
                    severity: .error,
                    code: "PBR_QUAD_CUTOFF",
                    message: "Right object (Quad) is too close to the right edge (maxX: \(rightObj.boundingBox.maxX))"
                ))
            }
            
            // Check Color (Gold)
            // Analyze color in the hotspot region
            let color = try await analyzer.analyzeRegionColor(data: frameData, region: rightObj.boundingBox)
            metrics["right_obj_r"] = Double(color.x)
            metrics["right_obj_g"] = Double(color.y)
            metrics["right_obj_b"] = Double(color.z)
            
            // Gold is roughly (1.0, 0.84, 0.0)
            // Allow some variance due to lighting
            if color.x < 0.5 || color.y < 0.3 { // Basic check for "yellow-ish/gold"
                 passed = false
                 diagnostics.append(Diagnostic(
                    severity: .error,
                    code: "PBR_QUAD_COLOR",
                    message: "Right object color \(color) does not look like Gold"
                 ))
            }
            
            // Check Brightness (it was too dark before)
            let brightness = (color.x + color.y + color.z) / 3.0
            metrics["right_obj_brightness"] = Double(brightness)
            
            if brightness < 0.1 {
                passed = false
                diagnostics.append(Diagnostic(
                    severity: .error,
                    code: "PBR_QUAD_DARK",
                    message: "Right object is too dark (\(brightness)), lighting might be insufficient"
                ))
            }
        }
        
        return EffectValidationResult(
            effectName: effectName,
            passed: passed,
            metrics: metrics,
            thresholds: [:],
            diagnostics: diagnostics,
            suggestedFixes: passed ? [] : ["Adjust camera position (z-axis)", "Increase light intensity", "Check PBR shader implementation"],
            debugArtifacts: [:],
            frameIndex: context.frameIndex
        )
    }
}
