import Foundation
import MetaVisCore

/// Registers the standard engine nodes with the Core registry.
/// This allows the UI and Agents to discover the engine's capabilities.
public struct EngineNodeRegistration {
    
    public static func registerAll() async {
        let registry = NodeRegistry.shared
        
        // 1. Color Management (ACES)
        await registry.register(NodeDefinition(
            type: "core.color.aces_transform",
            displayName: "ACES Transform",
            category: "Color",
            description: "Converts between color spaces using ACES (Academy Color Encoding System).",
            inputs: [
                NodePort(id: "input", name: "Input", type: .image),
                NodePort(id: "input_space", name: "Input Space", type: .string), // e.g. "Rec709", "SLog3"
                NodePort(id: "output_space", name: "Output Space", type: .string) // e.g. "ACEScg"
            ],
            outputs: [
                NodePort(id: "output", name: "Output", type: .image)
            ],
            tags: ["color", "grade", "lut", "transform"]
        ))
        
        // 2. Blur
        await registry.register(NodeDefinition(
            type: "core.filter.blur",
            displayName: "Gaussian Blur",
            category: "Filter",
            description: "Applies a Gaussian blur to the image.",
            inputs: [
                NodePort(id: "input", name: "Input", type: .image),
                NodePort(id: "radius", name: "Radius", type: .float)
            ],
            outputs: [
                NodePort(id: "output", name: "Output", type: .image)
            ],
            tags: ["blur", "soften", "defocus"]
        ))
        
        // 3. Composite (Over)
        await registry.register(NodeDefinition(
            type: "core.composite.over",
            displayName: "Composite (Over)",
            category: "Compositing",
            description: "Layers the foreground over the background using alpha blending.",
            inputs: [
                NodePort(id: "background", name: "Background", type: .image),
                NodePort(id: "foreground", name: "Foreground", type: .image),
                NodePort(id: "opacity", name: "Opacity", type: .float)
            ],
            outputs: [
                NodePort(id: "output", name: "Output", type: .image)
            ],
            tags: ["layer", "merge", "blend"]
        ))
        
        // 4. Text
        await registry.register(NodeDefinition(
            type: "core.source.text",
            displayName: "Text Source",
            category: "Source",
            description: "Generates text with configurable font and style.",
            inputs: [
                NodePort(id: "text", name: "Text", type: .string),
                NodePort(id: "font", name: "Font", type: .string),
                NodePort(id: "size", name: "Size", type: .float),
                NodePort(id: "color", name: "Color", type: .vector3)
            ],
            outputs: [
                NodePort(id: "output", name: "Output", type: .image)
            ],
            tags: ["title", "typography", "generator"]
        ))
        
        // 5. LiDAR Depth (New!)
        await registry.register(NodeDefinition(
            type: "core.spatial.depth_composite",
            displayName: "Depth Composite",
            category: "Spatial",
            description: "Composites layers based on Z-depth from LiDAR or depth maps.",
            inputs: [
                NodePort(id: "background", name: "Background", type: .image),
                NodePort(id: "bg_depth", name: "BG Depth", type: .depth),
                NodePort(id: "foreground", name: "Foreground", type: .image),
                NodePort(id: "fg_depth", name: "FG Depth", type: .depth)
            ],
            outputs: [
                NodePort(id: "output", name: "Output", type: .image)
            ],
            tags: ["lidar", "z-buffer", "occlusion", "ar"]
        ))
    }
}
