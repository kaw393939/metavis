import Foundation
import MetaVisCore
import simd

/// Protocol for types that can be converted to a NodeValue.
public protocol NodeValueConvertible {
    var asNodeValue: NodeValue { get }
}

// MARK: - Conformance

extension Double: NodeValueConvertible {
    public var asNodeValue: NodeValue { .float(self) }
}

extension Float: NodeValueConvertible {
    public var asNodeValue: NodeValue { .float(Double(self)) }
}

extension Int: NodeValueConvertible {
    public var asNodeValue: NodeValue { .int(self) }
}

extension Bool: NodeValueConvertible {
    public var asNodeValue: NodeValue { .bool(self) }
}

extension String: NodeValueConvertible {
    public var asNodeValue: NodeValue { .string(self) }
}

extension SIMD2<Float>: NodeValueConvertible {
    public var asNodeValue: NodeValue { .vector2(self) }
}

extension SIMD3<Float>: NodeValueConvertible {
    public var asNodeValue: NodeValue { .vector3(self) }
}

extension SIMD4<Float>: NodeValueConvertible {
    public var asNodeValue: NodeValue { .color(self) }
}

/// A type-erased protocol for tracks, allowing them to be stored in a heterogeneous collection.
public protocol TrackProtocol {
    /// Evaluate the track at the given time and return a NodeValue.
    func evaluate(at time: RationalTime) throws -> NodeValue
}

// MARK: - KeyframeTrack Conformance

extension KeyframeTrack: TrackProtocol where T: NodeValueConvertible {
    public func evaluate(at time: RationalTime) throws -> NodeValue {
        // Explicitly type the variable to force calling the struct method returning T
        let value: T = try self.evaluate(at: time)
        return value.asNodeValue
    }
}
