import Foundation
import MetaVisCore

/// A Tool is a stateless unit of work that operates on a Project using Devices.
public protocol Tool {
    var name: String { get }
    var description: String { get }
    
    /// Executes the tool's primary function.
    /// - Parameters:
    ///   - project: The project context (can be mutated).
    ///   - devices: The available devices to perform the work.
    func run(project: inout Project, devices: [any VirtualDevice]) async throws
}
