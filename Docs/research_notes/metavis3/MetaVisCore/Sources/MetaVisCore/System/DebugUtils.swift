import Foundation

/// Utilities for debugging complex data structures.
public struct DebugUtils {
    
    /// Generates a text-based visualization of a NodeGraph.
    /// Useful for printing to console during development.
    public static func dumpGraph(_ graph: NodeGraph) -> String {
        var output = "Graph: \(graph.name) (\(graph.id))\n"
        output += "Nodes: \(graph.nodes.count)\n"
        
        for node in graph.nodes.values.sorted(by: { $0.name < $1.name }) {
            output += "  - [\(node.name)] (\(node.type))\n"
            output += "    Inputs:\n"
            for port in node.inputs {
                output += "      - \(port.name) (\(port.type))\n"
            }
            output += "    Outputs:\n"
            for port in node.outputs {
                output += "      - \(port.name) (\(port.type))\n"
            }
        }
        
        output += "Edges: \(graph.edges.count)\n"
        for edge in graph.edges {
            let fromName = graph.nodes[edge.fromNode]?.name ?? "?"
            let toName = graph.nodes[edge.toNode]?.name ?? "?"
            output += "  - \(fromName):\(edge.fromPort) -> \(toName):\(edge.toPort)\n"
        }
        
        return output
    }
}
