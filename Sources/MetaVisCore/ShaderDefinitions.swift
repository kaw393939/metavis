import Foundation
import simd

/// "The Muscle" - Definitions for Core Shaders.
/// These structs bridge the Timeline parameters to the RenderGraph.

public enum ShaderNames {
    public static let exposure = "exposure_adjust"
    public static let contrast = "contrast_adjust"
    public static let saturation = "saturation_adjust"
    public static let tonemap = "aces_tonemap"
}

// MARK: - Node Factories

public struct ExposureNode {
    public static func create(inputID: UUID, ev: Float) -> RenderNode {
        return RenderNode(
            name: "Exposure",
            shader: ShaderNames.exposure,
            inputs: ["input": inputID],
            parameters: ["ev": .float(Double(ev))]
        )
    }
}

public struct ContrastNode {
    public static func create(inputID: UUID, factor: Float, pivot: Float = 0.18) -> RenderNode {
        return RenderNode(
            name: "Contrast",
            shader: ShaderNames.contrast,
            inputs: ["input": inputID],
            parameters: [
                "factor": .float(Double(factor)),
                "pivot": .float(Double(pivot))
            ]
        )
    }
}

public struct TonemapNode {
    public static func create(inputID: UUID) -> RenderNode {
        return RenderNode(
            name: "ACES Tonemap",
            shader: ShaderNames.tonemap,
            inputs: ["input": inputID],
            parameters: [:]
        )
    }
}

public struct CDLNode {
    public static func create(
        inputID: UUID,
        slope: SIMD3<Double> = SIMD3(1,1,1),
        offset: SIMD3<Double> = SIMD3(0,0,0),
        power: SIMD3<Double> = SIMD3(1,1,1),
        saturation: Double = 1.0
    ) -> RenderNode {
        return RenderNode(
            name: "ASC CDL",
            shader: "cdl_correct",
            inputs: ["input": inputID],
            parameters: [
                "slope": .vector3(slope),
                "offset": .vector3(offset),
                "power": .vector3(power),
                "saturation": .float(saturation)
            ]
        )
    }
}

public struct WaveformNode {
    public static func create(inputID: UUID) -> RenderNode {
        return RenderNode(
            name: "Waveform Monitor",
            shader: "waveform_monitor",
            inputs: ["input": inputID],
            parameters: [:]
        )
    }
}
