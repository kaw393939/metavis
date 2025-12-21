import Metal
import CoreText
import Foundation
import simd

/// A text event with timing information for timeline-aware rendering
public struct TimedTextEvent {
    public let content: VisualContent
    public let startTime: Double
    public let duration: Double
    public let animation: AnimationDefinition?
    
    public init(content: VisualContent, startTime: Double, duration: Double, animation: AnimationDefinition? = nil) {
        self.content = content
        self.startTime = startTime
        self.duration = duration
        self.animation = animation
    }
    
    /// Check if this event is active at the given time
    public func isActive(at time: Double) -> Bool {
        return time >= startTime && time < startTime + duration
    }
}

public class TextPass: RenderPass {
    public let label = "Text Overlay"
    public var inputs: [String] = ["main_buffer"]
    public var outputs: [String] = ["main_buffer"] // Renders in place (overlay)
    
    private let device: MTLDevice
    private let textRenderer: SDFTextRenderer
    
    // Store text events with timing for timeline-aware rendering
    public var timedTextEvents: [TimedTextEvent] = []
    
    // Legacy property for backward compatibility (deprecated)
    @available(*, deprecated, message: "Use timedTextEvents instead for timeline-aware rendering")
    public var textEvents: [VisualContent] {
        get { timedTextEvents.map { $0.content } }
        set { 
            // Legacy: assume all events start at 0 with infinite duration
            timedTextEvents = newValue.map { TimedTextEvent(content: $0, startTime: 0, duration: Double.infinity) }
        }
    }
    
    public init(device: MTLDevice, textRenderer: SDFTextRenderer) {
        self.device = device
        self.textRenderer = textRenderer
    }
    
    public func execute(context: RenderContext,
                        inputTextures: [String: MTLTexture],
                        outputTextures: [String: MTLTexture]) throws {
        
        // Use the first input as the target
        guard let inputName = inputs.first,
              let targetTexture = inputTextures[inputName] else {
            print("TextPass: No input texture found")
            return
        }
        
        // Create a render pass descriptor to render directly into the target texture
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = targetTexture
        descriptor.colorAttachments[0].loadAction = .load // Keep existing content
        descriptor.colorAttachments[0].storeAction = .store
        
        guard let encoder = context.commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        
        encoder.label = "Text Pass Encoder"
        
        // Fix: Explicitly set viewport to match target texture
        encoder.setViewport(MTLViewport(
            originX: 0,
            originY: 0,
            width: Double(targetTexture.width),
            height: Double(targetTexture.height),
            znear: 0,
            zfar: 1
        ))
        
        // Get current time from render context
        let currentTime = Double(context.time)
        
        // Filter to only active text events based on current time
        let activeEvents = timedTextEvents.filter { $0.isActive(at: currentTime) }
        
        // Convert active VisualContent to LabelRequest
        var labels: [SDFTextRenderer.LabelRequest] = []
        
        print("TextPass: Time=\(String(format: "%.2f", currentTime))s, Active events: \(activeEvents.count) of \(timedTextEvents.count)")
        
        for timedEvent in activeEvents {
            let event = timedEvent.content
            let elapsed = currentTime - timedEvent.startTime
            let duration = timedEvent.duration
            
            // Simple mapping for now
            if let text = event.text {
                // print("TextPass: Found text event: \(text)")
                let fontSize = Float((event.size ?? 1.0) * 100.0) // Scale 1.0 -> 100px
                
                let colorHex = event.color ?? "#FFFFFF"
                var color = hexToSIMD4(colorHex)
                
                // Advanced Properties
                let outlineWidth = Float(event.outlineWidth ?? 0.0)
                let outlineColorHex = event.outlineColor ?? "#000000"
                let outlineColor = hexToSIMD4(outlineColorHex)
                let softness = Float(event.softness ?? 0.0)
                let weight = Float(event.weight ?? 0.5)
                
                let fadeStart = event.fadeStart ?? 0.0
                let fadeEnd = event.fadeEnd ?? 0.0
                
                // Animation Logic
                var tracking: Float = event.tracking ?? 0.0
                var yOffsetAnim: CGFloat = 0.0
                var currentPosition3D: SIMD3<Float>? = nil
                
                if let anim = timedEvent.animation {
                    if anim.type == "TRACKING_IN" {
                        // Tracking from 0.5 to 0.0 over 3 seconds (or duration)
                        let animDuration = min(duration, 3.0)
                        let t = min(Float(elapsed) / Float(animDuration), 1.0)
                        // Ease out cubic
                        let ease = 1.0 - pow(1.0 - t, 3.0)
                        
                        tracking += 0.2 * (1.0 - ease) // Start loose, go to base tracking
                        color.w *= ease // Fade in
                    } else if anim.type == "FADE_IN_UP" {
                        let animDuration = min(duration, 2.0)
                        let t = min(Float(elapsed) / Float(animDuration), 1.0)
                        let ease = 1.0 - pow(1.0 - t, 3.0)
                        
                        yOffsetAnim = CGFloat(50.0 * (1.0 - ease)) // Move up
                        color.w *= ease
                    } else if anim.type == "LINEAR_TRANSLATE" {
                        if let startPos = anim.startPosition, let endPos = anim.endPosition {
                            let t = Float(elapsed) / Float(anim.end - anim.start)
                            // Linear interpolation
                            let p0 = SIMD3<Float>(startPos[0], startPos[1], startPos[2])
                            let p1 = SIMD3<Float>(endPos[0], endPos[1], endPos[2])
                            currentPosition3D = mix(p0, p1, t: t)
                        }
                    }
                }
                
                // Position: Center by default
                // For vertical video, we need to adjust this logic or parse layout
                // For now, we'll just center it based on the texture size
                let centerX = CGFloat(targetTexture.width) / 2.0
                let centerY = CGFloat(targetTexture.height) / 2.0
                
                // Calculate Max Width
                var maxWidth: Float? = nil
                if let mw = event.maxWidth {
                    if mw <= 1.0 {
                        // Percentage
                        maxWidth = mw * Float(targetTexture.width)
                    } else {
                        // Pixels
                        maxWidth = mw
                    }
                } else {
                    // Default to 80% of screen width if not specified (Safe Default)
                    maxWidth = Float(targetTexture.width) * 0.8
                    // print("TextPass: Applied default maxWidth: \(maxWidth!) for text: \(text)")
                }
                
                // print("TextPass: Layout Debug - Text: '\(text.prefix(20))...', TargetWidth: \(targetTexture.width), MaxWidth: \(maxWidth ?? 0)")

                // Simple vertical stacking for multiple labels
                // This is a hack for the demo suite until full layout engine is integrated
                let index = labels.count
                let yOffset = CGFloat(index) * 150.0
                let position = CGPoint(x: centerX, y: centerY + yOffset - 100.0 + yOffsetAnim)
                
                let label = SDFTextRenderer.LabelRequest(
                    text: text,
                    position: position,
                    color: color,
                    fontSize: fontSize,
                    weight: weight,
                    softness: softness,
                    alignment: .center,
                    outlineColor: outlineColor,
                    outlineWidth: outlineWidth,
                    tracking: tracking,
                    maxWidth: maxWidth
                )
                labels.append(label)
                
                // 3D Rendering Logic (If applicable)
                if let pos3D = currentPosition3D {
                    // We need to render this label with a custom MVP matrix
                    // But SDFTextRenderer.render(labels: ...) batches everything with one MVP (Ortho).
                    // We need to break the batch or handle it differently.
                    // For now, let's just render this single label immediately using the single-label render method?
                    // No, TextPass structure builds a list of labels.
                    
                    // Hack: If we have 3D text, we can't use the batch list 'labels'.
                    // We should render it separately.
                    // But 'labels' are rendered at the end of the loop.
                    
                    // Let's remove it from 'labels' and render it manually here.
                    labels.removeLast()
                    
                    // Calculate MVP
                    let camera = context.scene.camera
                    let aspectRatio = Float(targetTexture.width) / Float(targetTexture.height)
                    let uniforms = camera.getUniforms(aspectRatio: aspectRatio)
                    let vp = uniforms.viewProjectionMatrix
                    
                    // Model Matrix
                    // Scale: Convert pixels to meters. Let's say 100px = 1m.
                    // And apply user scale.
                    let pixelToMeter: Float = 0.01
                    let userScale = Float(event.size ?? 1.0) // This was used for fontSize, but also implies scale
                    // Flip Y to match World Y-Up (Text is Y-Down)
                    // We use (-s, -s, s) to flip X and Y.
                    // Flip X: Because text generation is L->R, but in 3D space with this projection it appears mirrored.
                    // Flip Y: Because Metal is Y-Up, Text is Y-Down.
                    let s = pixelToMeter * userScale
                    let scaleMat = matrix_float4x4(diagonal: SIMD4<Float>(-s, -s, s, 1))
                    
                    // Rotation
                    var rotationMat = matrix_identity_float4x4
                    if let rot = event.rotation {
                        print("TextPass: Applying rotation \(rot) to text '\(text.prefix(10))...'")
                        let radX = rot[0] * .pi / 180.0
                        let radY = rot[1] * .pi / 180.0
                        let radZ = rot[2] * .pi / 180.0
                        
                        // X-axis rotation
                        let rotX = matrix_float4x4(rows: [
                            SIMD4<Float>(1, 0, 0, 0),
                            SIMD4<Float>(0, cos(radX), -sin(radX), 0),
                            SIMD4<Float>(0, sin(radX), cos(radX), 0),
                            SIMD4<Float>(0, 0, 0, 1)
                        ])
                        
                        // Y-axis rotation
                        let rotY = matrix_float4x4(rows: [
                            SIMD4<Float>(cos(radY), 0, sin(radY), 0),
                            SIMD4<Float>(0, 1, 0, 0),
                            SIMD4<Float>(-sin(radY), 0, cos(radY), 0),
                            SIMD4<Float>(0, 0, 0, 1)
                        ])
                        
                        // Z-axis rotation
                        let rotZ = matrix_float4x4(rows: [
                            SIMD4<Float>(cos(radZ), -sin(radZ), 0, 0),
                            SIMD4<Float>(sin(radZ), cos(radZ), 0, 0),
                            SIMD4<Float>(0, 0, 1, 0),
                            SIMD4<Float>(0, 0, 0, 1)
                        ])
                        
                        // Combine rotations: Z * Y * X (standard Euler angle order)
                        rotationMat = rotZ * rotY * rotX
                    } else {
                        print("TextPass: No rotation found for text '\(text.prefix(10))...'")
                    }
                    
                    // Translation
                    var translationMat = matrix_identity_float4x4
                    translationMat.columns.3 = SIMD4<Float>(pos3D.x, pos3D.y, pos3D.z, 1)
                    
                    // Center the text geometry before transforming
                    // The renderer generates text starting at (0,0) or (x,y).
                    // If we want to rotate around center, we need to offset.
                    // But we don't know the text size here easily without measuring.
                    // SDFTextRenderer.measure() is async/actor isolated? No, it's nonisolated.
                    // But we are in a synchronous function.
                    
                    // For Star Wars crawl, text is centered.
                    // Let's assume the renderer handles alignment (it does).
                    // If alignment is .center, vertices are generated centered around 'position'.
                    // In 3D, 'position' should be (0,0) relative to the Model Matrix.
                    
                    let label3D = SDFTextRenderer.LabelRequest(
                        text: text,
                        position: CGPoint(x: 0, y: 0), // Centered in Model Space
                        color: color,
                        fontSize: fontSize,
                        weight: weight,
                        softness: softness,
                        alignment: .center,
                        outlineColor: outlineColor,
                        outlineWidth: outlineWidth,
                        tracking: tracking,
                        maxWidth: maxWidth
                    )
                    
                    let model = translationMat * rotationMat * scaleMat
                    let mvp = vp * model
                    
                    // Render immediately
                    try? textRenderer.render(
                        labels: [label3D],
                        encoder: encoder,
                        screenSize: SIMD2(Float(targetTexture.width), Float(targetTexture.height)),
                        mvpMatrix: mvp,
                        fadeStart: fadeStart,
                        fadeEnd: fadeEnd
                    )
                }
            }
        }
        
        if !labels.isEmpty {
            print("TextPass: Rendering \(labels.count) 2D labels")
            let screenSize = SIMD2<Float>(Float(targetTexture.width), Float(targetTexture.height))
            try textRenderer.render(labels: labels, encoder: encoder, screenSize: screenSize)
        } else {
            print("TextPass: No 2D labels to render")
        }
        
        encoder.endEncoding()
    }
    
    private func hexToSIMD4(_ hex: String) -> SIMD4<Float> {
        var cString: String = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if (cString.hasPrefix("#")) {
            cString.remove(at: cString.startIndex)
        }

        if ((cString.count) != 6) {
            return SIMD4<Float>(1, 1, 1, 1)
        }

        var rgbValue: UInt64 = 0
        Scanner(string: cString).scanHexInt64(&rgbValue)

        return SIMD4<Float>(
            Float((rgbValue & 0xFF0000) >> 16) / 255.0,
            Float((rgbValue & 0x00FF00) >> 8) / 255.0,
            Float(rgbValue & 0x0000FF) / 255.0,
            1.0
        )
    }
}
