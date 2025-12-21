import Metal
import Foundation

public enum ResolverError: Error {
    case unsupportedElementType(String)
    case resourceLoadingFailed(String)
}

public class ManifestResolver {
    public static func resolve(manifest: RenderManifest, device: MTLDevice) throws -> (RenderPipeline, Scene) {
        // 1. Create Scene
        let scene = Scene()
        scene.setCamera(manifest.camera)
        
        // Set procedural background if specified
        if let procBackground = manifest.scene.proceduralBackground {
            scene.proceduralBackground = procBackground
        }
        
        // 0. Handle Node Graph (FUTURE)
        if let graph = manifest.graph {
            print("Using node-based rendering system")
            let pipeline = try GraphPipeline(device: device, graph: graph)
            return (pipeline, scene)
        }

        // 3. Handle layer-based system (NEW)
        if manifest.usesLayers {
            print("Using layer-based rendering system")
            let pipeline = try LayeredPipeline(device: device)
            if let layers = manifest.layers {
                scene.layers = layers
                
                for layer in layers {
                    // Check if layer is enabled
                    let isEnabled: Bool
                    switch layer {
                    case .graphics(let l): isEnabled = l.base.enabled
                    case .procedural(let l): isEnabled = l.base.enabled
                    case .solid(let l): isEnabled = l.base.enabled
                    case .adjustment(let l): isEnabled = l.base.enabled
                    case .video(let l): isEnabled = l.base.enabled
                    }
                    
                    if !isEnabled { continue }
                    
                    // Extract text elements from graphics layers for scene inspection/legacy support
                    if case .graphics(let graphicsLayer) = layer {
                        for element in graphicsLayer.elements {
                            if case .text(let textElement) = element {
                                scene.textElements.append(textElement)
                            }
                        }
                    }
                    
                    // Extract procedural background from first enabled procedural layer
                    if case .procedural(let procLayer) = layer {
                        if scene.proceduralBackground == nil {
                            scene.proceduralBackground = procLayer.background
                        }
                    }
                }
            }
            return (pipeline, scene)
        }
        
        // 2. Create Pipeline
        let pipeline = try StandardPipeline(device: device)
        
        // 4. Handle legacy element system (DEPRECATED)
        if let elements = manifest.elements {
            for element in elements {
                switch element {
                case .text(let textElement):
                    scene.textElements.append(textElement)
                    
                case .model(let modelElement):
                    // Resolve material if present
                    if let materialDef = modelElement.material {
                        let material = MaterialResolver.resolve(materialDef)
                        print("Resolved material for model \(modelElement.path): \(material)")
                    }
                    break
                }
            }
        }
        
        return (pipeline, scene)
    }
}
