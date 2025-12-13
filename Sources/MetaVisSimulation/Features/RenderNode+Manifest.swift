import Foundation
import MetaVisCore
import simd

extension RenderNode {
    
    /// Initialize a RenderNode from a FeatureManifest.
    /// - Parameters:
    ///   - manifest: The feature manifest defining the node.
    ///   - id: Optional UUID for the node instance.
    public init(manifest: FeatureManifest, id: UUID = UUID()) {
        let initialParameters = manifest.defaultNodeParameters()
        
        // Map inputs to UUIDs? No, RenderNode inputs are [PortName: NodeID].
        // At initialization from manifest, we don't have connections yet.
        // So inputs starts empty.
        
        self.init(
            id: id,
            name: manifest.name,
            shader: manifest.kernelName,
            inputs: [:], // Connections are made later
            parameters: initialParameters,
            timing: nil
        )
    }
}
