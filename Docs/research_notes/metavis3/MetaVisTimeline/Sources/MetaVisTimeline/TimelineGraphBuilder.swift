import Foundation
import MetaVisCore

/// Builds a NodeGraph from a TimelineSegment.
public class TimelineGraphBuilder {
    
    public enum CompositionMode {
        case sequence // Standard timeline behavior (cuts/transitions)
        case stack // Composite behavior (blend all active clips)
        case jwstComposite // JWST Composite behavior (specialized kernel)
    }
    
    public var mode: CompositionMode = .sequence
    
    public init() {}
    
    public func build(from segment: TimelineSegment, assetLookup: ((UUID) -> Asset?)? = nil) async throws -> NodeGraph {
        var graph = NodeGraph(name: "Segment Graph")
        
        // 1. Create Output Node
        let outputNode = Node(
            name: "Output",
            type: NodeType.output,
            inputs: [NodePort(id: "input", name: "Input", type: .image)]
        )
        graph.add(node: outputNode)
        
        // 2. Create Source Nodes for all active clips
        var sourceNodes: [UUID: Node] = [:]
        var toneMapNodes: [UUID: Node] = [:] // Map clip ID to ToneMap node (for FITS)
        
        for resolvedClip in segment.activeClips {
            // Determine Node Type based on Asset Type
            var nodeType = NodeType.source
            var properties: [String: NodeValue] = [
                "assetId": .string(resolvedClip.assetId.uuidString),
                "sourceStart": .float(resolvedClip.sourceRange.start.seconds),
                "duration": .float(resolvedClip.sourceRange.duration.seconds)
            ]
            
            var isFITS = false
            var fitsStats: FITSStatistics? = nil
            var fitsName: String = ""
            
            if let lookup = assetLookup, let asset = lookup(resolvedClip.assetId) {
                if asset.type == .video {
                    nodeType = NodeType.videoSource
                } else if asset.type == .fits {
                    nodeType = NodeType.fitsSource
                    isFITS = true
                    fitsName = asset.name.lowercased()
                    
                    if let url = asset.url {
                        if let fitsAsset = try? await FITSAssetRegistry.shared.load(url: url) {
                            fitsStats = fitsAsset.statistics
                        }
                    }
                }
            }
            
            let sourceNode = Node(
                name: "Source \(resolvedClip.trackIndex)",
                type: nodeType,
                properties: properties,
                outputs: [NodePort(id: "output", name: "Output", type: .image)]
            )
            graph.add(node: sourceNode)
            sourceNodes[resolvedClip.id] = sourceNode
            
            // If FITS, create ToneMap Node immediately after
            if isFITS {
                var whitePoint: Float = 100.0
                var blackPoint: Float = 0.0
                
                if let stats = fitsStats {
                    // --- NASA / STScI Style Normalization ---
                    
                    // 1. Black Point: Set to Median * 8.0 (Black Hole Option).
                    // We want "inky blacks" (0.0) for anything that isn't structure.
                    let median = stats.median ?? stats.min
                    blackPoint = median * 8.0
                    
                    // 2. White Point: Use 99th percentile if available.
                    // Set to 8.0 to recover highlight detail (fix "blown out" look) while keeping brightness.
                    if let p99 = stats.percentiles[99] {
                        whitePoint = p99 * 8.0 
                    } else {
                        whitePoint = stats.max
                    }
                    
                    // Safety check
                    if whitePoint <= blackPoint {
                        whitePoint = blackPoint + 1.0
                    }
                }
                
                let toneMapNode = Node(
                    name: "ToneMap \(resolvedClip.trackIndex)",
                    type: NodeType.Effect.toneMap,
                    properties: [
                        "blackPoint": .float(Double(blackPoint)),
                        "whitePoint": .float(Double(whitePoint)),
                        "gamma": .float(2.8) // Aggressive Gamma 2.8 for "Inky Blacks" and separation
                    ],
                    inputs: [NodePort(id: "input", name: "Input", type: .image)],
                    outputs: [NodePort(id: "output", name: "Output", type: .image)]
                )
                graph.add(node: toneMapNode)
                
                // Connect Source -> ToneMap
                try graph.connect(fromNode: sourceNode.id, fromPort: "output", toNode: toneMapNode.id, toPort: "input")
                
                toneMapNodes[resolvedClip.id] = toneMapNode
            }
        }
        
        // 3. Handle Transition or Direct Connection
        
        if mode == .stack {
            // Check for v46 Data-Driven Composite (Density + Color)
            var hasDensity = false
            var hasColor = false
            
            if let lookup = assetLookup {
                hasDensity = segment.activeClips.contains { clip in
                    guard let asset = lookup(clip.assetId) else { return false }
                    return asset.name.contains("Density")
                }
                hasColor = segment.activeClips.contains { clip in
                    guard let asset = lookup(clip.assetId) else { return false }
                    return asset.name.contains("Color")
                }
            }
            
            if hasDensity && hasColor {
                // Create v46 Volumetric Composite Node
                let compositeNode = Node(
                    name: "JWST Volumetric Composite",
                    type: NodeType.Effect.jwstComposite,
                    inputs: [
                        NodePort(id: "density", name: "Density", type: .image),
                        NodePort(id: "color", name: "Color", type: .image)
                    ],
                    outputs: [NodePort(id: "output", name: "Output", type: .image)]
                )
                graph.add(node: compositeNode)
                
                // Connect Sources
                for clip in segment.activeClips {
                    let sourceID = toneMapNodes[clip.id]?.id ?? sourceNodes[clip.id]?.id
                    guard let finalSourceID = sourceID else { continue }
                    
                    if let lookup = assetLookup, let asset = lookup(clip.assetId) {
                        if asset.name.contains("Density") {
                            try graph.connect(fromNode: finalSourceID, fromPort: "output", toNode: compositeNode.id, toPort: "density")
                        } else if asset.name.contains("Color") {
                            try graph.connect(fromNode: finalSourceID, fromPort: "output", toNode: compositeNode.id, toPort: "color")
                        }
                    }
                }
                
                // Connect Composite -> Output
                try graph.connect(fromNode: compositeNode.id, fromPort: "output", toNode: outputNode.id, toPort: "input")
                
            } else {
                // Check if we should use JWST Composite Node (Legacy v45 FITS)
                let isJWST = segment.activeClips.contains { clip in
                    if let lookup = assetLookup, let asset = lookup(clip.assetId) {
                        return asset.type == .fits
                    }
                    return false
                }
            
                if isJWST {
                // Create JWST Composite Node
                // We need to pass colors here now, or rely on the Composite Kernel to have defaults/lookups
                // For now, we'll assume the Composite Node logic (in Compiler) handles the coloring based on input port
                // or we pass them as properties.
                
                let compositeNode = Node(
                    name: "JWST Composite",
                    type: NodeType.Effect.jwstComposite,
                    properties: [
                        // Artistic Palette (NASA/STScI Style)
                        // F770W (Shortest): Blue/Violet - Structure
                        "color_f770w": .color(SIMD4<Float>(0.1, 0.1, 1.0, 1.0)),
                        // F1130W (Medium): Cyan/Teal - Oxygen/Gas
                        "color_f1130w": .color(SIMD4<Float>(0.0, 0.8, 0.8, 1.0)),
                        // F1280W (Medium-Long): Orange/Gold - Dust/Hydrocarbons
                        "color_f1280w": .color(SIMD4<Float>(1.0, 0.7, 0.0, 1.0)),
                        // F1800W (Longest): Deep Red - Background Dust
                        "color_f1800w": .color(SIMD4<Float>(1.0, 0.0, 0.0, 1.0))
                    ],
                    inputs: [
                        NodePort(id: "f770w", name: "Blue", type: .image),
                        NodePort(id: "f1130w", name: "Green", type: .image),
                        NodePort(id: "f1280w", name: "Orange", type: .image),
                        NodePort(id: "f1800w", name: "Red", type: .image)
                    ],
                    outputs: [NodePort(id: "output", name: "Output", type: .image)]
                )
                graph.add(node: compositeNode)
                
                // Create ACES Output Node
                let acesNode = Node(
                    name: "ACES Output",
                    type: NodeType.Effect.acesOutput,
                    inputs: [NodePort(id: "input", name: "Input", type: .image)],
                    outputs: [NodePort(id: "output", name: "Output", type: .image)]
                )
                graph.add(node: acesNode)
                
                // Connect Sources (via ToneMap) to Composite Ports
                for clip in segment.activeClips {
                    // Use ToneMap node if available, else Source node
                    let sourceID = toneMapNodes[clip.id]?.id ?? sourceNodes[clip.id]?.id
                    guard let finalSourceID = sourceID else { continue }
                    
                    // Determine Port based on Asset Name
                    if let lookup = assetLookup, let asset = lookup(clip.assetId) {
                        let name = asset.name.lowercased()
                        var portId: String? = nil
                        
                        if name.contains("f770w") { portId = "f770w" }
                        else if name.contains("f1130w") { portId = "f1130w" }
                        else if name.contains("f1280w") { portId = "f1280w" }
                        else if name.contains("f1800w") { portId = "f1800w" }
                        
                        if let port = portId {
                            try graph.connect(fromNode: finalSourceID, fromPort: "output", toNode: compositeNode.id, toPort: port)
                        }
                    }
                }
                
                // Connect Composite -> ACES -> Output
                try graph.connect(fromNode: compositeNode.id, fromPort: "output", toNode: acesNode.id, toPort: "input")
                try graph.connect(fromNode: acesNode.id, fromPort: "output", toNode: outputNode.id, toPort: "input")
                
            } else {
                // Generic Stack Mode: Blend all clips together (Additive)
                // We chain them: Clip 0 + Clip 1 -> Mix 1 + Clip 2 -> Mix 2 ...
                
                let sortedClips = segment.activeClips.sorted(by: { $0.trackIndex < $1.trackIndex })
                var currentOutputNodeID: UUID? = nil
                
                for (index, clip) in sortedClips.enumerated() {
                    // Use ToneMap node if available
                    let sourceID = toneMapNodes[clip.id]?.id ?? sourceNodes[clip.id]?.id
                    guard let finalSourceID = sourceID else { continue }
                    
                    if index == 0 {
                        currentOutputNodeID = finalSourceID
                    } else {
                        // Create Blend Node (Add)
                        let blendNode = Node(
                            name: "Blend \(index)",
                            type: NodeType.Effect.blend,
                            properties: ["mode": .string("add")],
                            inputs: [
                                NodePort(id: "input0", name: "Background", type: .image),
                                NodePort(id: "input1", name: "Foreground", type: .image)
                            ],
                            outputs: [NodePort(id: "output", name: "Output", type: .image)]
                        )
                        graph.add(node: blendNode)
                        
                        // Connect Previous -> Input 0
                        if let prevID = currentOutputNodeID {
                            try graph.connect(fromNode: prevID, fromPort: "output", toNode: blendNode.id, toPort: "input0")
                        }
                        
                        // Connect Current -> Input 1
                        try graph.connect(fromNode: finalSourceID, fromPort: "output", toNode: blendNode.id, toPort: "input1")
                        
                        currentOutputNodeID = blendNode.id
                    }
                }
                
                if let finalID = currentOutputNodeID {
                    try graph.connect(fromNode: finalID, fromPort: "output", toNode: outputNode.id, toPort: "input")
                }
            }
            }
        } else {
            // Sequence Mode (Original Logic)
            
            // Group clips by track
            let clipsByTrack = Dictionary(grouping: segment.activeClips, by: { $0.trackIndex })
            
            // Find the track that is transitioning (has > 1 clip)
            // If multiple tracks are transitioning, we only support one for now (the highest one).
            let transitioningTrackIndex = clipsByTrack.keys.filter { clipsByTrack[$0]!.count > 1 }.max()
            
            if let trackIndex = transitioningTrackIndex, let clips = clipsByTrack[trackIndex], let transition = segment.transition {
                // Transition Logic
                
                // Handle Cascading Transitions (Multiple Overlaps)
                // If we have > 2 clips, we need to chain transitions.
                // A -> B -> C
                // (A mix B) mix C
                
                // Sort clips by their appearance in the track (which corresponds to the array order from Resolver)
                // The Resolver appends them in order of start time / track index.
                // For a single track, they should be in timeline order.
                
                var currentOutputNodeID: UUID? = nil
                
                // We iterate through pairs.
                // But wait, we only have ONE transition definition in the segment (segment.transition).
                // This is a limitation of the current TimelineSegment struct.
                // It assumes the segment is dominated by one transition.
                // In a triple overlap, we technically have 2 transitions active (A->B and B->C).
                // But we only have access to one `segment.transition`.
                
                // Ideally, we should fix TimelineSegment to support multiple transitions.
                // But for now, let's try to make a best-effort render graph.
                // We will chain them using the SAME transition type for all steps in this segment.
                
                for i in 0..<(clips.count - 1) {
                    let clipA = clips[i]
                    let clipB = clips[i+1]
                    
                    let nodeA_ID = toneMapNodes[clipA.id]?.id ?? sourceNodes[clipA.id]?.id
                    let nodeB_ID = toneMapNodes[clipB.id]?.id ?? sourceNodes[clipB.id]?.id
                    
                    guard let idA = nodeA_ID, let idB = nodeB_ID else { continue }
                    
                    let transitionType: String
                    switch transition.type {
                    case .dissolve: transitionType = NodeType.Transition.dissolve
                    case .wipe: transitionType = NodeType.Transition.wipe
                    }
                    
                    let transitionNode = Node(
                        name: "Transition \(i)",
                        type: transitionType,
                        inputs: [
                            NodePort(id: "inputA", name: "A", type: .image),
                            NodePort(id: "inputB", name: "B", type: .image)
                        ],
                        outputs: [NodePort(id: "output", name: "Output", type: .image)]
                    )
                    graph.add(node: transitionNode)
                    
                    // Input A: Either the previous transition result OR the source clip
                    if let prevID = currentOutputNodeID {
                        try graph.connect(fromNode: prevID, fromPort: "output", toNode: transitionNode.id, toPort: "inputA")
                    } else {
                        try graph.connect(fromNode: idA, fromPort: "output", toNode: transitionNode.id, toPort: "inputA")
                    }
                    
                    // Input B: The next clip
                    try graph.connect(fromNode: idB, fromPort: "output", toNode: transitionNode.id, toPort: "inputB")
                    
                    currentOutputNodeID = transitionNode.id
                }
                
                // Connect Final Transition -> Output
                if let finalID = currentOutputNodeID {
                    try graph.connect(fromNode: finalID, fromPort: "output", toNode: outputNode.id, toPort: "input")
                }
                
            } else {
                // Cut Logic (No Transition on any single track)
                // Connect the top-most clip (highest track index) to output
                
                if let topClip = segment.activeClips.max(by: { $0.trackIndex < $1.trackIndex }) {
                    let sourceID = toneMapNodes[topClip.id]?.id ?? sourceNodes[topClip.id]?.id
                    if let finalID = sourceID {
                        try graph.connect(fromNode: finalID, fromPort: "output", toNode: outputNode.id, toPort: "input")
                    }
                }
            }
        }
        
        return graph
    }
}
