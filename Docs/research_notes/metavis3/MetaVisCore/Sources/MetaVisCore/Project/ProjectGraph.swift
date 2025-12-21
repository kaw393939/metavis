import Foundation

/// Defines a directed graph of projects to manage dependencies and detect cycles.
public struct ProjectGraph {
    
    /// Map of Project ID to the Project object.
    private var projects: [UUID: Project] = [:]
    
    public init() {}
    
    public mutating func add(_ project: Project) {
        projects[project.id] = project
    }
    
    /// Checks if adding a dependency `importedId` to `targetId` would create a cycle.
    /// Returns true if a cycle is detected.
    public func wouldCreateCycle(targetId: UUID, importedId: UUID) -> Bool {
        // DFS to check if targetId is reachable from importedId
        var visited = Set<UUID>()
        var stack = [importedId]
        
        while let current = stack.popLast() {
            if current == targetId {
                return true // Cycle detected: imported leads back to target
            }
            
            if !visited.contains(current) {
                visited.insert(current)
                
                if let project = projects[current] {
                    // Add all children of current to stack
                    for imp in project.imports {
                        stack.append(imp.projectId)
                    }
                }
            }
        }
        
        return false
    }
    
    /// generic topological check, throws if cycle exists currently
    public func validateGraph() throws {
        // Implementation for full graph validation if needed
    }
}
