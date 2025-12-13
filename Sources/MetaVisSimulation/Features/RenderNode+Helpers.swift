import Foundation
import MetaVisCore

extension RenderNode {
    
    /// Helper to safely extract a float parameter.
    public func float(_ name: String, default val: Float = 0.0) -> Float {
        if let p = self.parameters[name] {
            switch p {
            case .float(let v): return Float(v)
            // case .int: NodeValue doesn't support Int yet
            default: return val
            }
        }
        return val
    }
    
    /// Helper to safely extract a vector3 parameter.
    public func vector3(_ name: String, default val: SIMD3<Float> = SIMD3<Float>(0,0,0)) -> SIMD3<Float> {
        if let p = self.parameters[name], case .vector3(let v) = p {
            return SIMD3<Float>(Float(v.x), Float(v.y), Float(v.z))
        }
        return val
    }
}
