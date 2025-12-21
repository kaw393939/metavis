import Foundation
import MetaVisCore

/// Builds a NodeGraph from a TimelineSegment, supporting multi-track compositing.
public class CompositeGraphBuilder {
    
    public init() {}
    
    public func build(from segment: TimelineSegment, assetTypeLookup: ((UUID) -> String?)? = nil) throws -> NodeGraph {
        var graph = NodeGraph(name: "Composite Graph")
        
        // 1. Create Output Node
        let outputNode = Node(
            name: "Output",
            type: NodeType.output,
            inputs: [NodePort(id: "input", name: "Input", type: .image)]
        )
        graph.add(node: outputNode)
        
        // 2. Create Source Nodes for all active clips
        var sourceNodes: [UUID: Node] = [:]
        
        // Group by Track
        let clipsByTrack = Dictionary(grouping: segment.activeClips, by: { $0.trackIndex })
        let sortedTracks = clipsByTrack.keys.sorted()
        
        // We will chain blend nodes:
        // Track 0 -> [Blend] -> Track 1 -> [Blend] -> Track 2 ...
        
        var previousOutputNodeID: UUID? = nil
        
        for trackIndex in sortedTracks {
            guard let clips = clipsByTrack[trackIndex] else { continue }
            
            // For this demo, we assume one clip per track per segment (no transitions on same track)
            guard let clip = clips.first else { continue }
            
            // Determine Node Type
            var nodeType = NodeType.source
            if let lookup = assetTypeLookup, let type = lookup(clip.assetId) {
                if type == "video" { nodeType = NodeType.videoSource }
                else if type == "fits" { nodeType = NodeType.fitsSource }
            }
            
            // Extract Color Property from Clip Metadata (if present)
            // We need a way to pass properties from Clip to Node.
            // The TimelineSegment doesn't carry arbitrary properties easily.
            // But we can look up the Asset? No, the color is a per-instance property.
            // For now, we will rely on the Command to set up the NodeGraph manually,
            // OR we can hack the properties into the Node here if we had access.
            // Since this is a specialized builder, let's assume we can get properties later?
            // No, let's just build the graph.
            
            // Wait, the standard TimelineGraphBuilder doesn't support custom properties per clip.
            // We might need to subclass or just build the graph manually in the Command.
            // Building manually in the Command is safer for this specific "Finest Visualization" task.
            
            // Let's just return an empty graph here and do the work in the Command.
            // Actually, let's make this builder useful.
            
            let sourceNode = Node(
                name: "Source Track \(trackIndex)",
                type: nodeType,
                properties: [
                    "assetId": .string(clip.assetId.uuidString),
                    "sourceStart": .float(clip.sourceRange.start.seconds),
                    "duration": .float(clip.sourceRange.duration.seconds)
                    // We will inject "color" later if needed, or rely on defaults.
                ],
                outputs: [NodePort(id: "output", name: "Output", type: .image)]
            )
            graph.add(node: sourceNode)
            
            if let prevID = previousOutputNodeID {
                // Create Blend Node (Add)
                let blendNode = Node(
                    name: "Blend Track \(trackIndex)",
                    type: "com.metavis.effect.blend", // We need to ensure this exists or use a generator
                    properties: ["mode": .string("add")],
                    inputs: [
                        NodePort(id: "background", name: "BG", type: .image),
                        NodePort(id: "foreground", name: "FG", type: .image)
                    ],
                    outputs: [NodePort(id: "output", name: "Output", type: .image)]
                )
                graph.add(node: blendNode)
                
                try graph.connect(fromNode: prevID, fromPort: "output", toNode: blendNode.id, toPort: "background")
                try graph.connect(fromNode: sourceNode.id, fromPort: "output", toNode: blendNode.id, toPort: "foreground")
                
                previousOutputNodeID = blendNode.id
            } else {
                previousOutputNodeID = sourceNode.id
            }
        }
        
        if let finalID = previousOutputNodeID {
            try graph.connect(fromNode: finalID, fromPort: "output", toNode: outputNode.id, toPort: "input")
        }
        
        return graph
    }
}
