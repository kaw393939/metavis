import Metal
import simd

/// Handles the normalization of input media to Linear ACEScg
public final class InputProcessor: Sendable {
    public let device: MTLDevice
    private let idtPipeline: MTLComputePipelineState

    public init(device: MTLDevice) throws {
        self.device = device

        // Load shaders
        let bundle = Bundle.module
        var shaderSource = ""

        // We need ColorSpace.metal and InputProcessing.metal
        if let colorSpacePath = bundle.path(forResource: "ColorSpace", ofType: "metal"),
           let colorSpaceSource = try? String(contentsOfFile: colorSpacePath) {
            shaderSource += colorSpaceSource + "\n"
        }

        if let inputProcPath = bundle.path(forResource: "InputProcessing", ofType: "metal"),
           let inputProcSource = try? String(contentsOfFile: inputProcPath) {
            shaderSource += inputProcSource
        }

        let library: MTLLibrary
        if !shaderSource.isEmpty {
            library = try device.makeLibrary(source: shaderSource, options: nil)
        } else if let defaultLibrary = device.makeDefaultLibrary() {
            library = defaultLibrary
        } else {
            throw PostProcessingError.cannotLoadShaders
        }

        guard let function = library.makeFunction(name: "apply_idt") else {
            throw PostProcessingError.cannotLoadShaders
        }
        idtPipeline = try device.makeComputePipelineState(function: function)
    }

    /// Normalize input texture to Linear ACEScg based on the Media Profile
    public func process(
        inputTexture: MTLTexture,
        profile: MediaProfile,
        commandBuffer: MTLCommandBuffer
    ) throws -> MTLTexture {
        // 1. Create Output Texture (Linear ACEScg - Float16)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: inputTexture.width,
            height: inputTexture.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]

        guard let outputTexture = device.makeTexture(descriptor: descriptor) else {
            throw PostProcessingError.cannotCreateTexture
        }

        // 2. Encode IDT Kernel
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw PostProcessingError.cannotCreateCommandBuffer
        }

        encoder.setComputePipelineState(idtPipeline)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(outputTexture, index: 1)

        // Map IDT enum to shader constant
        var idtType: UInt32 = 0
        switch profile.idt {
        case .srgb_to_acescg: idtType = 0
        case .rec709_to_acescg: idtType = 1
        case .appleLog_to_acescg: idtType = 2
        case .p3d65_to_acescg: idtType = 3
        case .passthrough: idtType = 4
        }

        encoder.setBytes(&idtType, length: MemoryLayout<UInt32>.stride, index: 0)

        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (inputTexture.width + 15) / 16,
            height: (inputTexture.height + 15) / 16,
            depth: 1
        )

        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()

        return outputTexture
    }
}
