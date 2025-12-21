import Metal
import Foundation
import simd

public struct TextVisibilityAnalysis {
    public var averageLuminance: Float
    public var variance: Float
    public var minLuminance: Float
    public var maxLuminance: Float
    
    public static let zero = TextVisibilityAnalysis(averageLuminance: 0, variance: 0, minLuminance: 0, maxLuminance: 0)
}

public class TextVisibilityOptimizer {
    private let device: MTLDevice
    private let pipelineState: MTLComputePipelineState
    private let resultBuffer: MTLBuffer
    
    struct AnalysisResultGPU {
        var averageLuminance: Float
        var variance: Float
        var minLuminance: Float
        var maxLuminance: Float
    }
    
    public init(device: MTLDevice, library: MTLLibrary) throws {
        self.device = device
        
        guard let function = library.makeFunction(name: "analyze_text_background") else {
            throw RenderError.shaderNotFound("analyze_text_background")
        }
        
        self.pipelineState = try device.makeComputePipelineState(function: function)
        
        guard let buffer = device.makeBuffer(length: MemoryLayout<AnalysisResultGPU>.stride, options: .storageModeShared) else {
            throw RenderError.bufferAllocationFailed("AnalysisResult")
        }
        self.resultBuffer = buffer
    }
    
    public func analyze(background: MTLTexture, region: SIMD4<Float>, commandBuffer: MTLCommandBuffer) -> TextVisibilityAnalysis {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return .zero
        }
        
        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(background, index: 0)
        encoder.setBuffer(resultBuffer, offset: 0, index: 0)
        
        var regionData = region
        encoder.setBytes(&regionData, length: MemoryLayout<SIMD4<Float>>.stride, index: 1)
        
        // Dispatch single thread for now (as per shader implementation)
        encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
        
        encoder.endEncoding()
        
        // Wait for completion to read back (Synchronous for now)
        // Note: In a real-time system, we would use a completion handler or double buffering.
        // But for this renderer, we can block or use waitUntilCompleted on the buffer?
        // Actually, we can't block here if we are inside the main command buffer encoding flow.
        // But we are in `processText`, which builds the command buffer.
        // We can't read the result UNTIL the command buffer is executed.
        
        // CRITICAL ISSUE: We need the result NOW to decide text color.
        // But the analysis happens on GPU.
        // Solution: We must split the command buffer.
        // 1. Encode Analysis.
        // 2. Commit & Wait.
        // 3. Read Result.
        // 4. Encode Text.
        
        // This requires `GraphPipeline` to support splitting.
        // Or we use the CPU to sample the texture if it's accessible.
        // `background` is likely Private storage.
        // So we MUST use GPU.
        
        // For this implementation, we will assume `GraphPipeline` can handle the split or we accept the stall.
        // We will return a placeholder here, and the caller (GraphPipeline) must handle the execution.
        
        return .zero // Placeholder, actual logic needs to happen in GraphPipeline
    }
    
    // Helper to execute analysis immediately
    public func analyzeSynchronously(background: MTLTexture, region: SIMD4<Float>, commandQueue: MTLCommandQueue) -> TextVisibilityAnalysis {
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return .zero }
        
        _ = analyze(background: background, region: region, commandBuffer: commandBuffer)
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        
        let pointer = resultBuffer.contents().bindMemory(to: AnalysisResultGPU.self, capacity: 1)
        let result = pointer.pointee
        
        return TextVisibilityAnalysis(
            averageLuminance: result.averageLuminance,
            variance: result.variance,
            minLuminance: result.minLuminance,
            maxLuminance: result.maxLuminance
        )
    }
    
    public func optimize(command: TextDrawCommand, background: MTLTexture, commandBuffer: MTLCommandBuffer) -> TextDrawCommand {
        // We need a command queue to run the analysis synchronously.
        // Since we only have a commandBuffer here, we can try to get its queue.
        let queue = commandBuffer.commandQueue
        
        // Calculate Region
        // Assuming Metal coordinates (0,0 top-left) and TextPass uses pixel coordinates.
        // Width approximation: char count * fontSize * 0.5
        let charWidth = command.fontSize * 0.5
        let width = Float(command.text.count) * Float(charWidth)
        let height = Float(command.fontSize)
        
        // Y-flip check: If position.y is large (e.g. 1800 in 2160p), it's bottom.
        // If Metal texture is top-down, 1800 is bottom.
        // Region needs (x, y, w, h).
        let region = SIMD4<Float>(command.position.x, command.position.y, width, height)
        
        let analysis = analyzeSynchronously(background: background, region: region, commandQueue: queue)
        
        print("DEBUG: Text Analysis for '\(command.text)': Lum=\(analysis.averageLuminance), Var=\(analysis.variance)")
        
        var newCommand = command
        var newStyle = command.style
        
        // 1. Adaptive Text Coloring
        // Warm White: #F4F2EE (0.96, 0.95, 0.93)
        // Neutral Light Gray: #E8E8E8 (0.91, 0.91, 0.91)
        // Soft Ivory: #F0E9DB (0.94, 0.91, 0.86)
        
        if analysis.averageLuminance < 0.4 {
            // Dark Background -> Warm White
            newStyle.color = SIMD4<Float>(0.96, 0.95, 0.93, 1.0)
        } else {
            // Light Background -> Neutral Light Gray (to avoid blowout)
            newStyle.color = SIMD4<Float>(0.91, 0.91, 0.91, 1.0)
        }
        
        // 2. Micro-Shadow (Primary Method)
        // 1-2px shadow, 20-30% opacity
        // If bright background, increase opacity
        var shadowOpacity: Float = 0.3
        if analysis.averageLuminance > 0.6 {
            shadowOpacity = 0.6
        }
        
        newStyle.shadowColor = SIMD4<Float>(0, 0, 0, shadowOpacity)
        newStyle.shadowOffset = SIMD2<Float>(2.0, 2.0) // 2px
        newStyle.shadowBlur = 3.0 // Softness
        
        // 3. Ultra-Fine Outline (Fallback)
        // If busy (variance high) or very bright
        if analysis.variance > 0.05 || analysis.averageLuminance > 0.8 {
            newStyle.outlineWidth = 1.0
            newStyle.outlineColor = SIMD4<Float>(0, 0, 0, 0.4)
        }
        
        // 4. Micro-Backing (Optional)
        // Not implemented in TextDrawCommand yet, would need a separate draw call or style property.
        // For now, shadow and outline should suffice.
        
        // Update command
        // TextDrawCommand is immutable, so we create a new one
        return TextDrawCommand(
            text: command.text,
            position: command.position,
            fontSize: command.fontSize,
            style: newStyle,
            fontID: command.fontID,
            anchor: command.anchor,
            alignment: command.alignment,
            positionMode: command.positionMode
        )
    }
}
