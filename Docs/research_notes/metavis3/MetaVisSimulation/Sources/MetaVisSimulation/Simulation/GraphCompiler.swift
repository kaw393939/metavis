import Foundation
import MetaVisCore
import Metal

public enum CompilerError: Error {
    case unknownNode(String)
    case disconnectedGraph
    case missingInput(String)
    case missingProperty(String)
}

/// Compiles a MetaVisCore.NodeGraph into a Metal RenderPass.
public class GraphCompiler {
    private let device: MTLDevice
    
    public init(device: MTLDevice) {
        self.device = device
    }
    
    /// Compiles the graph into a renderable pass.
    /// - Parameter graph: The source NodeGraph.
    /// - Returns: A RenderPass object containing the execution plan.
    public func compile(graph: NodeGraph) throws -> RenderPass {
        // 1. Validate Graph
        guard !graph.nodes.isEmpty else {
            return RenderPass(commands: [])
        }
        
        // 2. Topological Sort (Simplified for now: just find Output and walk back)
        // Find Output Node
        guard let outputNode = graph.nodes.values.first(where: { $0.type == NodeType.output }) else {
            throw CompilerError.disconnectedGraph // Or missing output
        }
        
        var commands: [RenderCommand] = []
        
        // 3. Generate Commands
        // We traverse from Output backwards to find the active source chain.
        // For this MVP, we support: Source -> [Transition] -> Output
        
        // Find what is connected to Output.input
        guard let outputConnection = graph.edges.first(where: { $0.toNode == outputNode.id && $0.toPort == "input" }) else {
             // If output is not connected, we render black/clear
             return RenderPass(commands: [])
        }
        
        let finalNodeId = outputConnection.fromNode
        guard let finalNode = graph.nodes[finalNodeId] else {
            throw CompilerError.disconnectedGraph
        }
        
        try processNode(finalNode, graph: graph, commands: &commands)
        
        // Finally, present the result of the last operation
        commands.append(.present(finalNodeId))
        
        return RenderPass(commands: commands)
    }
    
    private func processNode(_ node: Node, graph: NodeGraph, commands: inout [RenderCommand]) throws {
        switch node.type {
        case NodeType.source:
            // Extract Asset ID
            guard let assetIdValue = node.properties["assetId"],
                  case .string(let assetIdString) = assetIdValue,
                  let assetId = UUID(uuidString: assetIdString) else {
                throw CompilerError.missingProperty("assetId on Source Node")
            }
            
            // Extract Color Space Info (Default to sRGB/Rec.709)
            let tf = Int(node.properties["transferFunction"]?.floatValue ?? 1)
            let prim = Int(node.properties["primaries"]?.floatValue ?? 2)
            
            commands.append(.loadTexture(node.id, assetId, false, tf, prim))
            
        case NodeType.videoSource:
            // Extract Asset ID
            guard let assetIdValue = node.properties["assetId"],
                  case .string(let assetIdString) = assetIdValue,
                  let assetId = UUID(uuidString: assetIdString) else {
                throw CompilerError.missingProperty("assetId on Video Source Node")
            }
            
            // Extract Color Space Info (Default to sRGB/Rec.709)
            let tf = Int(node.properties["transferFunction"]?.floatValue ?? 1)
            let prim = Int(node.properties["primaries"]?.floatValue ?? 2)
            
            commands.append(.loadTexture(node.id, assetId, true, tf, prim))
            
        case NodeType.fitsSource:
            guard let assetIdValue = node.properties["assetId"],
                  case .string(let assetIdString) = assetIdValue,
                  let assetId = UUID(uuidString: assetIdString) else {
                throw CompilerError.missingProperty("assetId on FITS Source Node")
            }
            
            commands.append(.loadFITS(node.id, assetId))

        case NodeType.Effect.toneMap:
            guard let inputEdge = graph.edges.first(where: { $0.toNode == node.id && $0.toPort == "input" }),
                  let inputNode = graph.nodes[inputEdge.fromNode] else {
                throw CompilerError.missingInput("ToneMap requires input")
            }
            
            try processNode(inputNode, graph: graph, commands: &commands)
            
            commands.append(.process(node.id, "toneMapKernel", [inputNode.id], node.properties))

        case NodeType.Effect.acesOutput:
            guard let inputEdge = graph.edges.first(where: { $0.toNode == node.id && $0.toPort == "input" }),
                  let inputNode = graph.nodes[inputEdge.fromNode] else {
                throw CompilerError.missingInput("ACES Output requires input")
            }
            
            try processNode(inputNode, graph: graph, commands: &commands)
            
            commands.append(.process(node.id, "acesOutputKernel", [inputNode.id], node.properties))


        case NodeType.Effect.jwstComposite:
            print("✅ [GraphCompiler] Compiling JWST Composite Node: \(node.id)")
            // Check for v46 Data-Driven Ports (Density, Color)
            let v46Ports = ["density", "color"]
            var inputIds: [UUID] = []
            var isV46 = false
            
            // Check if any v46 ports are connected
            for port in v46Ports {
                if graph.edges.contains(where: { $0.toNode == node.id && $0.toPort == port }) {
                    isV46 = true
                    break
                }
            }
            
            if isV46 {
                // v46 Data-Driven Path
                for port in v46Ports {
                    if let edge = graph.edges.first(where: { $0.toNode == node.id && $0.toPort == port }),
                       let inputNode = graph.nodes[edge.fromNode] {
                        try processNode(inputNode, graph: graph, commands: &commands)
                        inputIds.append(inputNode.id)
                    } else {
                        inputIds.append(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
                    }
                }
            } else {
                // Legacy v45 Path (4-Channel FITS)
                let ports = ["f770w", "f1130w", "f1280w", "f1800w"]
                
                for port in ports {
                    if let edge = graph.edges.first(where: { $0.toNode == node.id && $0.toPort == port }) {
                       if let inputNode = graph.nodes[edge.fromNode] {
                            try processNode(inputNode, graph: graph, commands: &commands)
                            inputIds.append(inputNode.id)
                       } else {
                           inputIds.append(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
                       }
                    } else {
                        // Append Empty UUID to maintain slot order
                        inputIds.append(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
                    }
                }
            }
            
            // Pass properties like exposure/gamma for each channel if they exist on the composite node?
            // Or maybe the composite node just takes the textures and does a weighted sum.
            // Let's assume properties are passed through.
            commands.append(.process(node.id, "jwst_composite", inputIds, node.properties))
            
        case NodeType.text:
            guard let textVal = node.properties["text"], case .string(let text) = textVal else {
                throw CompilerError.missingProperty("text")
            }
            let font = (node.properties["font"]?.stringValue) ?? "Helvetica"
            let size = (node.properties["size"]?.floatValue) ?? 64.0
            
            commands.append(.generateText(node.id, text, font, size))
            
        case NodeType.generator:
            let type = (node.properties["type"]?.stringValue) ?? "checkerboard"
            commands.append(.process(node.id, type, [], node.properties))
            
        case NodeType.audioWaveform:
            var color = SIMD4<Float>(1,1,1,1)
            if let c = node.properties["color"], case .color(let v) = c {
                color = v
            }
            commands.append(.generateWaveform(node.id, color))
            
        case NodeType.Transition.dissolve:
            // Recursive: Process Inputs A and B first
            guard let edgeA = graph.edges.first(where: { $0.toNode == node.id && $0.toPort == "inputA" }),
                  let edgeB = graph.edges.first(where: { $0.toNode == node.id && $0.toPort == "inputB" }),
                  let nodeA = graph.nodes[edgeA.fromNode],
                  let nodeB = graph.nodes[edgeB.fromNode] else {
                throw CompilerError.missingInput("Dissolve requires inputA and inputB")
            }
            
            try processNode(nodeA, graph: graph, commands: &commands)
            try processNode(nodeB, graph: graph, commands: &commands)
            
            // Get Mix Factor (default 0.5 if missing, though Timeline should set it)
            var mix = 0.5
            if let m = node.properties["mix"], case .float(let v) = m {
                mix = v
            }
            
            commands.append(.process(node.id, "dissolve", [nodeA.id, nodeB.id], ["mix": .float(mix)]))
            
        case "com.metavis.effect.blend":
            // Recursive: Process Inputs
            guard let edgeBG = graph.edges.first(where: { $0.toNode == node.id && ($0.toPort == "background" || $0.toPort == "input0") }),
                  let edgeFG = graph.edges.first(where: { $0.toNode == node.id && ($0.toPort == "foreground" || $0.toPort == "input1") }),
                  let nodeBG = graph.nodes[edgeBG.fromNode],
                  let nodeFG = graph.nodes[edgeFG.fromNode] else {
                throw CompilerError.missingInput("Blend requires background and foreground")
            }
            
            try processNode(nodeBG, graph: graph, commands: &commands)
            try processNode(nodeFG, graph: graph, commands: &commands)
            
            let mode = node.properties["mode"]?.stringValue ?? "normal"
            commands.append(.process(node.id, "blend", [nodeBG.id, nodeFG.id], ["mode": .string(mode)]))
            
        case NodeType.Effect.postProcess:
            guard let inputEdge = graph.edges.first(where: { $0.toNode == node.id && $0.toPort == "input" }),
                  let inputNode = graph.nodes[inputEdge.fromNode] else {
                throw CompilerError.missingInput("PostProcess requires input")
            }
            
            try processNode(inputNode, graph: graph, commands: &commands)
            
            commands.append(.process(node.id, "final_composite", [inputNode.id], node.properties))
            
        default:
            throw CompilerError.unknownNode(node.type)
        }
    }
}

/// A compiled set of instructions for the Engine.
public struct RenderPass {
    public let commands: [RenderCommand]
}

public enum RenderCommand {
    case loadTexture(UUID, UUID, Bool, Int, Int) // NodeID, AssetID, isVideo, TransferFn, Primaries
    case loadFITS(UUID, UUID) // NodeID, AssetID (Raw Data)
    case generateText(UUID, String, String, Float) // NodeID, Text, Font, Size
    case generateWaveform(UUID, SIMD4<Float>) // NodeID, Color
    case process(UUID, String, [UUID], [String: NodeValue]) // NodeID, KernelName, InputNodeIDs, Parameters
    case present(UUID) // NodeID to display
}
