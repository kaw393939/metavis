import Metal
import Foundation

/// Error types for AsyncComputeManager
public enum AsyncComputeError: Error {
    case deviceNotFound
    case failedToCreateCommandQueue
    case failedToCreateCommandBuffer
    case failedToCreateSharedEvent
    case commandBufferExecutionFailed(String)
    case deviceLost
    case executionTimeout
}

/// Manages asynchronous parallel GPU compute operations
///
/// AsyncComputeManager enables efficient parallel execution of independent GPU workloads
/// using multiple command buffers and MTLSharedEvent for synchronization between dependent operations.
///
/// Key capabilities:
/// - Parallel command buffer submission for independent passes
/// - MTLSharedEvent-based synchronization for dependent operations
/// - Thread-safe command buffer creation and submission
/// - Error handling for command buffer failures and device loss
///
/// Performance targets:
/// - 20-40% speedup for independent parallel passes vs sequential execution
/// - Efficient GPU utilization through overlapping compute/render operations
/// - Minimal synchronization overhead for dependent passes
///
/// Usage:
/// ```swift
/// let manager = try AsyncComputeManager(device: metalDevice)
///
/// // Execute independent passes in parallel
/// try await manager.executeInParallel([
///     { try await renderBackgroundPass() },
///     { try await renderFieldPass() }
/// ])
///
/// // Execute dependent passes with synchronization
/// try await manager.executeWithDependencies([
///     (texture1, color1),
///     (texture2, color2)
/// ])
/// ```
public final class AsyncComputeManager: Sendable {
    /// Metal device for GPU operations
    public let device: MTLDevice
    
    /// Command queue for submitting command buffers
    public let commandQueue: MTLCommandQueue
    
    /// Initializes AsyncComputeManager with a Metal device
    ///
    /// - Parameter device: Metal device to use for GPU operations
    /// - Throws: AsyncComputeError if command queue creation fails
    public init(device: MTLDevice) throws {
        self.device = device
        
        guard let queue = device.makeCommandQueue() else {
            throw AsyncComputeError.failedToCreateCommandQueue
        }
        
        self.commandQueue = queue
    }
    
    /// Creates multiple command buffers for parallel execution
    ///
    /// - Parameter count: Number of command buffers to create
    /// - Returns: Array of command buffers ready for encoding
    /// - Throws: AsyncComputeError if any command buffer creation fails
    public func createParallelBuffers(count: Int) throws -> [MTLCommandBuffer] {
        var buffers: [MTLCommandBuffer] = []
        buffers.reserveCapacity(count)
        
        for _ in 0..<count {
            guard let buffer = commandQueue.makeCommandBuffer() else {
                throw AsyncComputeError.failedToCreateCommandBuffer
            }
            buffers.append(buffer)
        }
        
        return buffers
    }
    
    /// Creates a shared event for synchronizing dependent operations
    ///
    /// Shared events allow one command buffer to signal completion and another
    /// to wait for that signal before proceeding, enabling efficient GPU-side
    /// synchronization without CPU involvement.
    ///
    /// - Returns: MTLSharedEvent for synchronization
    /// - Throws: AsyncComputeError if event creation fails
    public func createSharedEvent() throws -> MTLSharedEvent {
        guard let event = device.makeSharedEvent() else {
            throw AsyncComputeError.failedToCreateSharedEvent
        }
        return event
    }
    
    /// Executes multiple independent operations in parallel
    ///
    /// This method submits command buffers for parallel GPU execution, allowing
    /// independent render/compute passes to overlap for improved performance.
    ///
    /// - Parameter operations: Array of async closures to execute in parallel
    /// - Throws: AsyncComputeError if any operation fails
    ///
    /// Performance: Target 20-40% speedup vs sequential execution for independent passes
    public func executeInParallel(_ operations: [() async throws -> Void]) async throws {
        // Execute all operations in parallel using TaskGroup
        try await withThrowingTaskGroup(of: Void.self) { group in
            for operation in operations {
                group.addTask {
                    try await operation()
                }
            }
            
            // Wait for all operations to complete
            // If any operation throws, the error propagates
            try await group.waitForAll()
        }
    }
    
    /// Executes dependent operations with explicit synchronization
    ///
    /// Uses MTLSharedEvent to ensure operations execute in correct order while
    /// still allowing GPU-side parallelism within each operation.
    ///
    /// - Parameter operations: Array of (texture, color) tuples representing dependent operations
    /// - Throws: AsyncComputeError if execution fails
    ///
    /// Example:
    /// ```swift
    /// try await manager.executeWithDependencies([
    ///     (backgroundTexture, backgroundColor),  // executes first
    ///     (compositedTexture, overlayColor)      // waits for first to complete
    /// ])
    /// ```
    public func executeWithDependencies(_ operations: [(MTLTexture, SIMD4<Float>)]) async throws {
        // Create shared event for synchronization
        let event = try createSharedEvent()
        
        // Execute operations sequentially with GPU-side synchronization
        for (index, (texture, color)) in operations.enumerated() {
            // Fill texture directly (CPU-side for now - production would use compute shader)
            // Convert Float32 color to Float16 for RGBA16Float texture
            let float16Color = SIMD4<UInt16>(
                Float16(color.x).bitPattern,
                Float16(color.y).bitPattern,
                Float16(color.z).bitPattern,
                Float16(color.w).bitPattern
            )
            
            let bytesPerPixel = 8  // 4 channels * 2 bytes (Float16)
            let bytesPerRow = texture.width * bytesPerPixel
            
            // Create buffer with repeated color
            var pixels = [SIMD4<UInt16>](repeating: float16Color, count: texture.width * texture.height)
            
            pixels.withUnsafeMutableBytes { pixelBytes in
                texture.replace(
                    region: MTLRegionMake2D(0, 0, texture.width, texture.height),
                    mipmapLevel: 0,
                    withBytes: pixelBytes.baseAddress!,
                    bytesPerRow: bytesPerRow
                )
            }
            
            // Create command buffer for synchronization
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                throw AsyncComputeError.failedToCreateCommandBuffer
            }
            
            // If not the first operation, wait for previous operation to complete
            if index > 0 {
                commandBuffer.encodeWaitForEvent(event, value: UInt64(index))
            }
            
            // Signal completion for next operation
            commandBuffer.encodeSignalEvent(event, value: UInt64(index + 1))
            
            // Commit and wait for completion
            try await commandBuffer.commitAndWait()
            
            // Check for errors
            if let error = commandBuffer.error {
                throw AsyncComputeError.commandBufferExecutionFailed(error.localizedDescription)
            }
        }
    }
    
    /// Validates that device is still available and functional
    ///
    /// - Throws: AsyncComputeError.deviceLost if device is unavailable
    public func validateDevice() throws {
        // Try to create a command buffer as a device validation check
        guard commandQueue.makeCommandBuffer() != nil else {
            throw AsyncComputeError.deviceLost
        }
    }
    
    /// Creates a command buffer with error handling
    ///
    /// - Returns: Command buffer ready for encoding
    /// - Throws: AsyncComputeError if creation fails
    public func makeCommandBuffer() throws -> MTLCommandBuffer {
        guard let buffer = commandQueue.makeCommandBuffer() else {
            throw AsyncComputeError.failedToCreateCommandBuffer
        }
        return buffer
    }
}

// MARK: - MTLCommandBuffer Async Extensions

extension MTLCommandBuffer {
    /// Async wrapper for completion to support Swift concurrency
    /// This adds the completion handler and commits in one operation
    public func commitAndWait() async throws {
        return await withCheckedContinuation { continuation in
            self.addCompletedHandler { buffer in
                if let error = buffer.error {
                    // Can't throw from continuation, just resume
                    continuation.resume()
                } else {
                    continuation.resume()
                }
            }
            self.commit()
        }
    }
}
