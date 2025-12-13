import Foundation
import CoreML
import MetaVisCore

/// Manages the configuration and context for Neural Engine (ANE) operations.
/// Ensures optimal use of Apple Silicon hardware.
public final class NeuralEngineContext: Sendable {
    
    public static let shared = NeuralEngineContext()
    
    private init() {}
    
    /// Returns the optimal configuration for a CoreML model.
    /// - Parameter useANE: If true, explicitly requests all compute units (CPU+GPU+ANE).
    public func makeConfiguration(useANE: Bool = true) -> MLModelConfiguration {
        let config = MLModelConfiguration()
        
        if useANE {
            // "all" is generally the best way to hit the ANE.
            // .cpuAndNeuralEngine might be used if GPU is busy with rendering,
            // but CoreML Scheduler is usually smarter than us.
            config.computeUnits = .all
        } else {
            config.computeUnits = .cpuOnly
        }
        
        return config
    }
    
    /// Maps our generic AIComputeUnit to CoreML's compute units.
    public func mapComputeUnit(_ unit: AIComputeUnit) -> MLComputeUnits {
        switch unit {
        case .all: return .all
        case .cpuOnly: return .cpuOnly
        case .cpuAndGPU: return .cpuAndGPU
        case .neuralEngineOnly: return .all // CoreML doesn't strictly support "ANE ONLY", fallback to all
        }
    }
}
