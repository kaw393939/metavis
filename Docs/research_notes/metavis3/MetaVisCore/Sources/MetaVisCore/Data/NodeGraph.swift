import Foundation

// MARK: - Graph Definition

public struct NodeGraph: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var nodes: [UUID: Node]
    public var edges: [Edge]
    
    public init(id: UUID = UUID(), name: String = "Untitled Graph") {
        self.id = id
        self.name = name
        self.nodes = [:]
        self.edges = []
    }
    
    public mutating func add(node: Node) {
        nodes[node.id] = node
        Log.graph.debug("Added node: \(node.name) (\(node.id))")
    }
    
    public mutating func remove(nodeId: UUID) {
        if let node = nodes[nodeId] {
            nodes.removeValue(forKey: nodeId)
            // Also remove connected edges
            let removedEdges = edges.filter { $0.fromNode == nodeId || $0.toNode == nodeId }
            edges.removeAll { $0.fromNode == nodeId || $0.toNode == nodeId }
            
            Log.graph.debug("Removed node: \(node.name) and \(removedEdges.count) edges")
        }
    }
    
    public mutating func connect(fromNode: UUID, fromPort: PortID, toNode: UUID, toPort: PortID) throws {
        // Basic validation: Nodes must exist
        guard let sourceNode = nodes[fromNode] else {
            Log.graph.error("Connect failed: Source node \(fromNode) not found")
            throw GraphError.nodeNotFound(fromNode)
        }
        guard let targetNode = nodes[toNode] else {
            Log.graph.error("Connect failed: Target node \(toNode) not found")
            throw GraphError.nodeNotFound(toNode)
        }
        
        // Prevent self-connections
        if fromNode == toNode {
            Log.graph.error("Connect failed: Self-connection attempted on \(fromNode)")
            throw GraphError.selfConnection
        }
        
        // Validate Ports
        guard let sourcePort = sourceNode.outputs.first(where: { $0.id == fromPort }) else {
            Log.graph.error("Connect failed: Source port \(fromPort) not found on \(sourceNode.name)")
            throw GraphError.portNotFound(fromPort)
        }
        guard let targetPort = targetNode.inputs.first(where: { $0.id == toPort }) else {
            Log.graph.error("Connect failed: Target port \(toPort) not found on \(targetNode.name)")
            throw GraphError.portNotFound(toPort)
        }
        
        // Validate Types
        if sourcePort.type != targetPort.type {
            Log.graph.error("Connect failed: Type mismatch \(sourcePort.type.rawValue) -> \(targetPort.type.rawValue)")
            throw GraphError.portTypeMismatch(from: sourcePort.type, to: targetPort.type)
        }
        
        let edge = Edge(fromNode: fromNode, fromPort: fromPort, toNode: toNode, toPort: toPort)
        
        // Check for duplicates
        if edges.contains(edge) {
            Log.graph.warning("Connect ignored: Duplicate edge")
            throw GraphError.duplicateEdge
        }
        
        // Check for cycles BEFORE adding the edge
        // Optimization: Only check if 'fromNode' is reachable from 'toNode'
        if createsCycle(from: fromNode, to: toNode) {
            Log.graph.error("Connect failed: Cycle detected")
            throw GraphError.cycleDetected
        }
        
        edges.append(edge)
        Log.graph.info("Connected \(sourceNode.name):\(sourcePort.name) -> \(targetNode.name):\(targetPort.name)")
    }
    
    /// Checks if adding an edge from `source` to `target` would create a cycle.
    /// This is done by checking if `source` is reachable from `target` in the current graph.
    private func createsCycle(from source: UUID, to target: UUID) -> Bool {
        // If they are the same, it's a self-cycle
        if source == target { return true }
        
        // Build adjacency list for traversal
        // We only care about the connected component starting from 'target'
        var adjacency: [UUID: [UUID]] = [:]
        for edge in edges {
            adjacency[edge.fromNode, default: []].append(edge.toNode)
        }
        
        // BFS to find if `source` is reachable from `target`
        var queue: [UUID] = [target]
        var visited: Set<UUID> = [target]
        
        while !queue.isEmpty {
            let current = queue.removeFirst()
            
            if current == source {
                return true // Found a path from target back to source
            }
            
            if let neighbors = adjacency[current] {
                for neighbor in neighbors {
                    if !visited.contains(neighbor) {
                        visited.insert(neighbor)
                        queue.append(neighbor)
                    }
                }
            }
        }
        
        return false
    }
    
    /// Checks if the graph contains any cycles using Iterative DFS.
    /// This avoids stack overflow on deep graphs.
    public func hasCycle() -> Bool {
        // Build adjacency list for faster lookup
        var adjacency: [UUID: [UUID]] = [:]
        for edge in edges {
            adjacency[edge.fromNode, default: []].append(edge.toNode)
        }
        
        var visited: Set<UUID> = [] // Nodes fully processed
        var recursionStack: Set<UUID> = [] // Nodes currently in the traversal path
        
        for startNode in nodes.keys {
            if visited.contains(startNode) { continue }
            
            // Stack stores: (node, nextNeighborIndex)
            // We look up neighbors from adjacency map to avoid copying arrays into the stack
            var stack: [(UUID, Int)] = []
            
            stack.append((startNode, 0))
            recursionStack.insert(startNode)
            
            while !stack.isEmpty {
                // Peek at the top
                let (currentNode, index) = stack.last!
                let neighbors = adjacency[currentNode] ?? []
                
                if index < neighbors.count {
                    // Process the next neighbor
                    let neighbor = neighbors[index]
                    
                    // Advance the index for the current node
                    stack[stack.count - 1].1 += 1
                    
                    if recursionStack.contains(neighbor) {
                        return true // Cycle detected (Back edge)
                    }
                    
                    if !visited.contains(neighbor) {
                        // Push neighbor onto stack to visit it
                        stack.append((neighbor, 0))
                        recursionStack.insert(neighbor)
                    }
                } else {
                    // All neighbors visited, pop the node
                    stack.removeLast()
                    recursionStack.remove(currentNode)
                    visited.insert(currentNode)
                }
            }
        }
        
        return false
    }
}

public enum GraphError: MetaVisErrorProtocol, Equatable {
    case nodeNotFound(UUID)
    case portNotFound(PortID)
    case portTypeMismatch(from: PortType, to: PortType)
    case duplicateEdge
    case selfConnection
    case cycleDetected
    
    public var code: Int {
        switch self {
        case .nodeNotFound: return 2001
        case .portNotFound: return 2002
        case .portTypeMismatch: return 2003
        case .duplicateEdge: return 2004
        case .selfConnection: return 2005
        case .cycleDetected: return 2006
        }
    }
    
    public var title: String {
        switch self {
        case .nodeNotFound: return "Node Not Found"
        case .portNotFound: return "Port Not Found"
        case .portTypeMismatch: return "Port Type Mismatch"
        case .duplicateEdge: return "Duplicate Edge"
        case .selfConnection: return "Self Connection"
        case .cycleDetected: return "Cycle Detected"
        }
    }
    
    public var debugDescription: String {
        switch self {
        case .nodeNotFound(let id): return "Node with ID \(id) does not exist in the graph."
        case .portNotFound(let id): return "Port with ID \(id) does not exist on the node."
        case .portTypeMismatch(let from, let to): return "Cannot connect port of type \(from) to \(to)."
        case .duplicateEdge: return "This connection already exists."
        case .selfConnection: return "A node cannot be connected to itself."
        case .cycleDetected: return "This connection would create an infinite loop."
        }
    }
}
