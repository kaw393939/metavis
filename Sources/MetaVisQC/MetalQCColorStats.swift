import CoreVideo
import Foundation
import Metal

final class MetalQCColorStats {
    static let shared = MetalQCColorStats()

    struct Error: Swift.Error, LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    // Mirror of `QCColorStatsAccum` in `QCFingerprint.metal`.
    private struct Accum {
        var count: UInt32
        var sumR: UInt32
        var sumG: UInt32
        var sumB: UInt32
    }

    struct Result {
        var meanRGB: SIMD3<Float>
        var histogram: [Float] // normalized 256-bin
        var peakBin: Int
    }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLComputePipelineState
    private var textureCache: CVMetalTextureCache?

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return nil
        }
        guard let queue = device.makeCommandQueue() else {
            return nil
        }

        let library: MTLLibrary
        do {
            library = try device.makeDefaultLibrary(bundle: Bundle.module)
        } catch {
            return nil
        }

        guard let fn = library.makeFunction(name: "qc_colorstats_accumulate_bgra8") else {
            return nil
        }

        do {
            pipeline = try device.makeComputePipelineState(function: fn)
        } catch {
            return nil
        }

        self.device = device
        self.queue = queue

        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    func colorStats(pixelBuffer: CVPixelBuffer, maxDimension: Int) throws -> Result {
        guard let textureCache else {
            throw Error(message: "Missing CVMetalTextureCache")
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)

        guard format == kCVPixelFormatType_32BGRA else {
            throw Error(message: "Unsupported pixel format: \(format)")
        }

        let targetW = UInt32(min(max(1, maxDimension), width))
        let targetH = UInt32(min(max(1, maxDimension), height))

        var cvTex: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTex
        )
        guard status == kCVReturnSuccess, let cvTex, let srcTex = CVMetalTextureGetTexture(cvTex) else {
            throw Error(message: "Failed to create CVMetalTexture (\(status))")
        }

        guard let cmd = queue.makeCommandBuffer() else {
            throw Error(message: "Failed to create command buffer")
        }

        guard let accumBuffer = device.makeBuffer(length: MemoryLayout<Accum>.stride, options: [.storageModeShared]) else {
            throw Error(message: "Failed to allocate accum buffer")
        }
        memset(accumBuffer.contents(), 0, accumBuffer.length)

        let histCount = 256
        guard let histogramBuffer = device.makeBuffer(length: histCount * MemoryLayout<UInt32>.stride, options: [.storageModeShared]) else {
            throw Error(message: "Failed to allocate histogram buffer")
        }
        memset(histogramBuffer.contents(), 0, histogramBuffer.length)

        var tw = targetW
        var th = targetH

        guard let enc = cmd.makeComputeCommandEncoder() else {
            throw Error(message: "Failed to create compute encoder")
        }

        enc.setComputePipelineState(pipeline)
        enc.setTexture(srcTex, index: 0)
        enc.setBuffer(accumBuffer, offset: 0, index: 0)
        enc.setBuffer(histogramBuffer, offset: 0, index: 1)
        enc.setBytes(&tw, length: MemoryLayout<UInt32>.stride, index: 2)
        enc.setBytes(&th, length: MemoryLayout<UInt32>.stride, index: 3)

        let grid = MTLSize(width: Int(targetW), height: Int(targetH), depth: 1)
        let tg = MTLSize(width: 16, height: 16, depth: 1)
        enc.dispatchThreads(grid, threadsPerThreadgroup: tg)
        enc.endEncoding()

        cmd.commit()
        cmd.waitUntilCompleted()

        let accum = accumBuffer.contents().assumingMemoryBound(to: Accum.self).pointee
        let n = max(1, Int(accum.count))

        let invCount = 1.0 / Float(n)
        let inv255: Float = 1.0 / 255.0

        let meanR = (Float(accum.sumR) * invCount) * inv255
        let meanG = (Float(accum.sumG) * invCount) * inv255
        let meanB = (Float(accum.sumB) * invCount) * inv255

        let counts = histogramBuffer.contents().assumingMemoryBound(to: UInt32.self)
        var histogram = Array<Float>(repeating: 0, count: histCount)
        histogram.withUnsafeMutableBufferPointer { out in
            for i in 0..<histCount {
                out[i] = Float(counts[i]) * invCount
            }
        }

        var peakBin = 0
        var peakCount: UInt32 = 0
        for i in 0..<histCount {
            let c = counts[i]
            if c > peakCount {
                peakCount = c
                peakBin = i
            }
        }

        return Result(meanRGB: SIMD3<Float>(meanR, meanG, meanB), histogram: histogram, peakBin: peakBin)
    }
}
