import Foundation
import simd

/// Converts a TimelineModel into a NodeGraph for the GraphPipeline.
public struct TimelineToGraphConverter {
    
    public static func convert(_ timeline: TimelineModel) -> NodeGraph {
        var nodes: [GraphNode] = []
        var connections: [NodeConnection] = []
        
        // 1. Create Output Node
        let outputNode = GraphNode(
            id: "output",
            type: .output,
            name: "Final Output",
            position: SIMD2(1000, 0)
        )
        nodes.append(outputNode)
        
        var lastNodeId: String? = nil
        
        // 2. Handle Background
        if let scene = timeline.scene {
            if let procBg = scene.proceduralBackground {
                // Procedural Background Node
                let bgNodeId = "background"
                var bgNode = GraphNode(
                    id: bgNodeId,
                    type: .generator,
                    name: "Background",
                    position: SIMD2(-500, 0)
                )
                
                switch procBg {
                case .solid(let solid):
                    bgNode.properties["type"] = .enumValue("solid")
                    bgNode.properties["color"] = .color(solid.color)
                case .gradient(let gradient):
                    bgNode.properties["type"] = .enumValue("gradient")
                    // Serialize gradient stops if needed, or simplify
                case .starfield:
                    bgNode.properties["type"] = .enumValue("starfield")
                case .procedural:
                    bgNode.properties["type"] = .enumValue("procedural")
                }
                
                nodes.append(bgNode)
                lastNodeId = bgNodeId
            } else if scene.background != "transparent" {
                // Solid Color Background from Hex
                // (Assuming we parsed it or handle it in the node)
                let bgNodeId = "background_solid"
                var bgNode = GraphNode(
                    id: bgNodeId,
                    type: .generator,
                    name: "Solid Background",
                    position: SIMD2(-500, 0)
                )
                bgNode.properties["type"] = .enumValue("solid")
                // Parse hex or pass as string if node supports it
                bgNode.properties["colorHex"] = .string(scene.background) 
                
                nodes.append(bgNode)
                lastNodeId = bgNodeId
            }
        }
        
        // 3. Handle Graphics Tracks (Text)
        // For now, we'll just create a Text Node for each text element and composite them
        // In a real graph, we might merge them or have a "Text Layer" node.
        
        for track in timeline.graphicsTracks {
            for element in track.elements {
                if case .text(let textElement) = element {
                    let textNodeId = "text_\(UUID().uuidString)"
                    var textNode = GraphNode(
                        id: textNodeId,
                        type: .text,
                        name: "Text: \(textElement.content.prefix(10))",
                        position: SIMD2(0, 0)
                    )
                    
                    // Map properties
                    textNode.properties["content"] = .string(textElement.content)
                    textNode.properties["fontSize"] = .float(textElement.fontSize)
                    textNode.properties["position"] = .vector3(textElement.position)
                    textNode.properties["color"] = .vector4(textElement.color)
                    textNode.properties["duration"] = .float(textElement.duration)
                    
                    if let rotation = textElement.rotation {
                        textNode.properties["rotation"] = .vector3(rotation)
                    }
                    if let scale = textElement.scale {
                        textNode.properties["scale"] = .vector3(scale)
                    }
                    
                    // Animation
                    if let anim = textElement.animation {
                        // Serialize animation config to node properties
                        if let data = try? JSONEncoder().encode(anim),
                           let jsonString = String(data: data, encoding: .utf8) {
                            textNode.properties["animation"] = .string(jsonString)
                        }
                    }
                    
                    nodes.append(textNode)
                    
                    // Composite over previous
                    if let prevId = lastNodeId {
                        let compNodeId = "comp_\(UUID().uuidString)"
                        let compNode = GraphNode(
                            id: compNodeId,
                            type: .composite,
                            name: "Composite",
                            position: SIMD2(500, 0)
                        )
                        nodes.append(compNode)
                        
                        // Connect Background (B) and Text (A)
                        connections.append(NodeConnection(fromNodeId: prevId, fromPinId: "output", toNodeId: compNodeId, toPinId: "background"))
                        connections.append(NodeConnection(fromNodeId: textNodeId, fromPinId: "output", toNodeId: compNodeId, toPinId: "foreground"))
                        
                        lastNodeId = compNodeId
                    } else {
                        lastNodeId = textNodeId
                    }
                }
            }
        }
        
        // 4. Connect to Output
        if let finalId = lastNodeId {
            connections.append(NodeConnection(fromNodeId: finalId, fromPinId: "output", toNodeId: "output", toPinId: "input"))
        }
        
        return NodeGraph(nodes: nodes, connections: connections, rootNodeId: "output")
    }
}
