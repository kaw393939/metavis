import CoreVideo
import Foundation
import Metal

final class MetalQCFingerprint {
    static let shared = MetalQCFingerprint()

    struct Error: Swift.Error, LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    // Layout mirror of `QCFingerprintAccum` storage in `QCFingerprint.metal`.
    // Note: Metal side uses atomics; we only rely on size/layout for zeroing.
    private struct AccumRaw {
        var count: UInt32
        var sumR: UInt32
        var sumG: UInt32
        var sumB: UInt32
        var sumR2: UInt64
        var sumG2: UInt64
        var sumB2: UInt64
    }

    // Packed 16-byte result written by `qc_fingerprint_finalize_16`.
    private struct Out16 {
        var meanR: UInt16
        var meanG: UInt16
        var meanB: UInt16
        var stdR: UInt16
        var stdG: UInt16
        var stdB: UInt16
        var pad0: UInt16
        var pad1: UInt16
    }

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let accumulatePSO: MTLComputePipelineState
    private let finalizePSO: MTLComputePipelineState
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

        guard let fnAcc = library.makeFunction(name: "qc_fingerprint_accumulate_bgra8") else {
            return nil
        }

        guard let fnFin = library.makeFunction(name: "qc_fingerprint_finalize_16") else {
            return nil
        }

        do {
            accumulatePSO = try device.makeComputePipelineState(function: fnAcc)
            finalizePSO = try device.makeComputePipelineState(function: fnFin)
        } catch {
            return nil
        }

        self.device = device
        self.queue = queue

        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
    }

    func fingerprint(pixelBuffer: CVPixelBuffer) throws -> VideoContentQC.Fingerprint {
        guard let textureCache else {
            throw Error(message: "Missing CVMetalTextureCache")
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)

        guard format == kCVPixelFormatType_32BGRA else {
            throw Error(message: "Unsupported pixel format: \(format)")
        }

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

        guard let accumBuffer = device.makeBuffer(length: MemoryLayout<AccumRaw>.stride, options: [.storageModeShared]) else {
            throw Error(message: "Failed to allocate accum buffer")
        }
        memset(accumBuffer.contents(), 0, accumBuffer.length)

        guard let outBuffer = device.makeBuffer(length: MemoryLayout<Out16>.stride, options: [.storageModeShared]) else {
            throw Error(message: "Failed to allocate output buffer")
        }
        memset(outBuffer.contents(), 0, outBuffer.length)

        guard let enc1 = cmd.makeComputeCommandEncoder() else {
            throw Error(message: "Failed to create compute encoder")
        }

        enc1.setComputePipelineState(accumulatePSO)
        enc1.setTexture(srcTex, index: 0)
        enc1.setBuffer(accumBuffer, offset: 0, index: 0)

        let grid1 = MTLSize(width: 64, height: 36, depth: 1)
        let tg1 = MTLSize(width: 8, height: 8, depth: 1)
        enc1.dispatchThreads(grid1, threadsPerThreadgroup: tg1)
        enc1.endEncoding()

        guard let enc2 = cmd.makeComputeCommandEncoder() else {
            throw Error(message: "Failed to create compute encoder")
        }

        enc2.setComputePipelineState(finalizePSO)
        enc2.setBuffer(accumBuffer, offset: 0, index: 0)
        enc2.setBuffer(outBuffer, offset: 0, index: 1)

        let grid2 = MTLSize(width: 1, height: 1, depth: 1)
        let tg2 = MTLSize(width: 1, height: 1, depth: 1)
        enc2.dispatchThreads(grid2, threadsPerThreadgroup: tg2)
        enc2.endEncoding()

        cmd.commit()
        cmd.waitUntilCompleted()

        let out = outBuffer.contents().assumingMemoryBound(to: Out16.self).pointee
        let inv = 1.0 / 65535.0

        let meanR = Double(out.meanR) * inv
        let meanG = Double(out.meanG) * inv
        let meanB = Double(out.meanB) * inv
        let stdR = Double(out.stdR) * inv
        let stdG = Double(out.stdG) * inv
        let stdB = Double(out.stdB) * inv

        return VideoContentQC.Fingerprint(meanR: meanR, meanG: meanG, meanB: meanB, stdR: stdR, stdG: stdG, stdB: stdB)
    }
}
