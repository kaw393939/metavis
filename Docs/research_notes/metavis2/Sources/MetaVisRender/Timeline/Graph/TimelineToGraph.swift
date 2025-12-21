import Foundation
import simd

public class TimelineToGraph {
    public static func buildGraph(from timeline: TimelineModel, at time: Double) -> NodeGraph {
        var nodes: [GraphNode] = []
        var connections: [NodeConnection] = []
        
        var activeClipNodeId: String?
        
        // Iterate tracks bottom-up (Track 0 is bottom)
        for track in timeline.videoTracks {
            guard !track.isMuted else { continue }
            
            // Find active clip at current time
            // Calculate duration based on speed
            if let clip = track.clips.first(where: { clip in
                let duration = (clip.sourceOut - clip.sourceIn) / clip.speed
                return time >= clip.timelineIn && time < (clip.timelineIn + duration)
            }) {
                // Create Input Node
                let nodeId = "clip_\(clip.id.rawValue)"
                let inputNode = GraphNode(
                    id: nodeId,
                    type: .input,
                    name: "Clip \(clip.id.rawValue)",
                    properties: [
                        "assetId": .string(clip.source)
                    ]
                )
                nodes.append(inputNode)
                
                if let previousNodeId = activeClipNodeId {
                    // Composite with previous
                    let compositeId = "comp_\(nodeId)"
                    let compositeNode = GraphNode(
                        id: compositeId,
                        type: .composite,
                        name: "Composite",
                        properties: [
                            "blendMode": .enumValue(track.blendMode.rawValue),
                            "opacity": .float(Float(track.opacity))
                        ]
                    )
                    nodes.append(compositeNode)
                    
                    // Connect Previous -> Background
                    connections.append(NodeConnection(fromNodeId: previousNodeId, fromPinId: "output", toNodeId: compositeId, toPinId: "background"))
                    
                    // Connect Current -> Foreground
                    connections.append(NodeConnection(fromNodeId: nodeId, fromPinId: "output", toNodeId: compositeId, toPinId: "foreground"))
                    
                    activeClipNodeId = compositeId
                } else {
                    activeClipNodeId = nodeId
                }
            }
        }
        
        // If no video, use background from scene or default black
        if activeClipNodeId == nil {
            let bgId = "background"
            var bgProperties: [String: NodeValue] = [
                "type": .enumValue("solid"),
                "color": .color(SIMD3<Float>(0, 0, 0))
            ]
            
            if let proceduralBg = timeline.scene?.proceduralBackground {
                switch proceduralBg {
                case .solid(let solid):
                    bgProperties = [
                        "type": .enumValue("solid"),
                        "color": .color(solid.color)
                    ]
                case .gradient(let gradient):
                    // Simple 2-stop gradient support for now
                    let start = gradient.gradient.first?.color ?? SIMD3<Float>(0,0,0)
                    let end = gradient.gradient.last?.color ?? SIMD3<Float>(1,1,1)
                    bgProperties = [
                        "type": .enumValue("gradient"),
                        "colorStart": .color(start),
                        "colorEnd": .color(end),
                        "angle": .float(gradient.angle)
                    ]
                default:
                    // Fallback to black for unsupported types
                    break
                }
            }
            
            let bgNode = GraphNode(
                id: bgId,
                type: .generator,
                name: "Background",
                properties: bgProperties
            )
            nodes.append(bgNode)
            activeClipNodeId = bgId
        }
        
        // Process Graphics Tracks (Text)
        for track in timeline.graphicsTracks {
            guard !track.isMuted else { continue }
            
            for element in track.elements {
                if case .text(let textElement) = element {
                    // Check timing
                    let startTime = Double(textElement.startTime)
                    let duration = Double(textElement.duration)
                    let endTime = duration > 0 ? startTime + duration : Double.infinity
                    
                    if time >= startTime && time < endTime {
                        // Create Text Node
                        let textNodeId = "text_\(UUID().uuidString)"
                        var properties: [String: NodeValue] = [
                            "text": .string(textElement.content),
                            "fontSize": .float(textElement.fontSize),
                            "color": .vector4(textElement.color),
                            "position": .vector3(textElement.position),
                            "fontName": .string(textElement.fontName)
                        ]
                        
                        let textNode = GraphNode(
                            id: textNodeId,
                            type: .text,
                            name: "Text",
                            properties: properties
                        )
                        nodes.append(textNode)
                        
                        if let previousNodeId = activeClipNodeId {
                            // Connect Previous -> Text Node Reference (for visibility analysis)
                            connections.append(NodeConnection(fromNodeId: previousNodeId, fromPinId: "output", toNodeId: textNodeId, toPinId: "reference"))
                            
                            // Composite Text over Previous
                            let compositeId = "comp_\(textNodeId)"
                            let compositeNode = GraphNode(
                                id: compositeId,
                                type: .composite,
                                name: "Composite Text",
                                properties: [
                                    "blendMode": .enumValue("normal"), // Text usually normal blend
                                    "opacity": .float(1.0)
                                ]
                            )
                            nodes.append(compositeNode)
                            
                            // Connect Previous -> Background
                            connections.append(NodeConnection(fromNodeId: previousNodeId, fromPinId: "output", toNodeId: compositeId, toPinId: "background"))
                            
                            // Connect Text -> Foreground
                            connections.append(NodeConnection(fromNodeId: textNodeId, fromPinId: "output", toNodeId: compositeId, toPinId: "foreground"))
                            
                            activeClipNodeId = compositeId
                        } else {
                            activeClipNodeId = textNodeId
                        }
                    }
                }
            }
        }
        
        // Create Output Node
        let outputId = "output"
        let outputNode = GraphNode(
            id: outputId,
            type: .output,
            name: "Output"
        )
        nodes.append(outputNode)
        
        if let rootId = activeClipNodeId {
            connections.append(NodeConnection(fromNodeId: rootId, fromPinId: "output", toNodeId: outputId, toPinId: "input"))
        }
        
        return NodeGraph(nodes: nodes, connections: connections, rootNodeId: outputId)
    }
}
