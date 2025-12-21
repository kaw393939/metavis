// TimelineResolver.swift
// MetaVisRender
//
// Created for Sprint 05: Timeline & Animation
// Resolves animated properties at a specific time

import Foundation
import simd

// MARK: - TimelineResolver

/// Resolves all animated properties in a manifest at a specific time.
/// Takes a manifest with keyframes and returns a "flattened" manifest
/// where all values are resolved to their interpolated state.
public actor TimelineResolver {
    
    // MARK: - Types
    
    /// Errors that can occur during timeline resolution
    public enum Error: Swift.Error, Equatable {
        case invalidTimeRange
        case circularDependency
        case expressionError(String)
        case unknownProperty(String)
    }
    
    /// Resolution context passed during evaluation
    public struct Context {
        /// Current time in seconds
        public let time: Double
        
        /// Current frame number
        public let frame: Int
        
        /// Total duration of the timeline
        public let duration: Double
        
        /// Progress through timeline (0-1)
        public var progress: Double {
            duration > 0 ? time / duration : 0
        }
        
        /// Frames per second
        public let fps: Double
        
        public init(time: Double, frame: Int, duration: Double, fps: Double) {
            self.time = time
            self.frame = frame
            self.duration = duration
            self.fps = fps
        }
        
        /// Create context from time and fps
        public static func at(time: Double, duration: Double, fps: Double = 30) -> Context {
            Context(
                time: time,
                frame: Int(time * fps),
                duration: duration,
                fps: fps
            )
        }
    }
    
    // MARK: - Properties
    
    /// Cache of resolved values for performance
    private var cache: [String: Any] = [:]
    
    /// Last resolved time
    private var lastResolvedTime: Double?
    
    /// Cache invalidation threshold (in seconds)
    private let cacheThreshold: Double = 0.001
    
    /// Expression evaluator for dynamic expressions
    private let expressionEvaluator: ExpressionEvaluator
    
    // MARK: - Initialization
    
    public init() {
        self.expressionEvaluator = ExpressionEvaluator()
    }
    
    // MARK: - Resolution
    
    /// Resolve a single animated value at a given time
    public func resolve<T: Interpolatable & Codable>(
        _ animatedValue: AnimatedValue<T>,
        at time: Double
    ) -> T {
        animatedValue.evaluate(at: time)
    }
    
    /// Resolve a keyframe track at a given time
    public func resolve<T: Interpolatable>(
        track: KeyframeTrack<T>,
        at time: Double
    ) -> T {
        track.evaluate(at: time)
    }
    
    /// Resolve an expression string at a given context
    public func resolveExpression(
        _ expression: String,
        context: Context
    ) throws -> Double {
        try expressionEvaluator.evaluate(expression, context: context)
    }
    
    /// Resolve camera position from animated values
    public func resolveCamera(
        position: AnimatedValue<SIMD3<Float>>,
        target: AnimatedValue<SIMD3<Float>>,
        fov: AnimatedValue<Float>,
        at time: Double
    ) -> ResolvedCamera {
        ResolvedCamera(
            position: position.evaluate(at: time),
            target: target.evaluate(at: time),
            fov: fov.evaluate(at: time)
        )
    }
    
    /// Resolve transform from animated values
    public func resolveTransform(
        position: AnimatedValue<SIMD3<Float>>,
        rotation: AnimatedValue<SIMD3<Float>>,
        scale: AnimatedValue<SIMD3<Float>>,
        at time: Double
    ) -> ResolvedTransform {
        ResolvedTransform(
            position: position.evaluate(at: time),
            rotation: rotation.evaluate(at: time),
            scale: scale.evaluate(at: time)
        )
    }
    
    /// Resolve opacity with optional expression
    public func resolveOpacity(
        _ opacity: AnimatedValue<Float>?,
        expression: String?,
        context: Context
    ) throws -> Float {
        if let expr = expression {
            return Float(try resolveExpression(expr, context: context))
        }
        return opacity?.evaluate(at: context.time) ?? 1.0
    }
    
    /// Clear the resolution cache
    public func clearCache() {
        cache.removeAll()
        lastResolvedTime = nil
    }
    
    /// Check if cache is valid for given time
    private func isCacheValid(for time: Double) -> Bool {
        guard let lastTime = lastResolvedTime else { return false }
        return abs(time - lastTime) < cacheThreshold
    }
}

// MARK: - Resolved Types

/// Resolved camera state at a specific time
public struct ResolvedCamera: Sendable, Equatable {
    public let position: SIMD3<Float>
    public let target: SIMD3<Float>
    public let fov: Float
    
    public init(position: SIMD3<Float>, target: SIMD3<Float>, fov: Float) {
        self.position = position
        self.target = target
        self.fov = fov
    }
}

/// Resolved transform at a specific time
public struct ResolvedTransform: Sendable, Equatable {
    public let position: SIMD3<Float>
    public let rotation: SIMD3<Float>  // Euler angles in radians
    public let scale: SIMD3<Float>
    
    public init(position: SIMD3<Float>, rotation: SIMD3<Float>, scale: SIMD3<Float>) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }
    
    /// Identity transform
    public static let identity = ResolvedTransform(
        position: .zero,
        rotation: .zero,
        scale: SIMD3<Float>(1, 1, 1)
    )
    
    /// Create a 4x4 transformation matrix
    public var matrix: simd_float4x4 {
        let translationMatrix = simd_float4x4(translation: position)
        let rotationMatrix = simd_float4x4(rotation: rotation)
        let scaleMatrix = simd_float4x4(scale: scale)
        return translationMatrix * rotationMatrix * scaleMatrix
    }
}

// MARK: - Matrix Helpers

extension simd_float4x4 {
    init(translation: SIMD3<Float>) {
        self.init(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(translation.x, translation.y, translation.z, 1)
        )
    }
    
    init(scale: SIMD3<Float>) {
        self.init(
            SIMD4<Float>(scale.x, 0, 0, 0),
            SIMD4<Float>(0, scale.y, 0, 0),
            SIMD4<Float>(0, 0, scale.z, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }
    
    init(rotation: SIMD3<Float>) {
        // Euler angles to rotation matrix (XYZ order)
        let cx = cos(rotation.x)
        let sx = sin(rotation.x)
        let cy = cos(rotation.y)
        let sy = sin(rotation.y)
        let cz = cos(rotation.z)
        let sz = sin(rotation.z)
        
        self.init(
            SIMD4<Float>(cy * cz, cy * sz, -sy, 0),
            SIMD4<Float>(sx * sy * cz - cx * sz, sx * sy * sz + cx * cz, sx * cy, 0),
            SIMD4<Float>(cx * sy * cz + sx * sz, cx * sy * sz - sx * cz, cx * cy, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }
}

// MARK: - Timeline State

/// Complete timeline state for batch resolution
public struct TimelineState: Sendable {
    /// Current time
    public let time: Double
    
    /// Current frame
    public let frame: Int
    
    /// Total duration
    public let duration: Double
    
    /// FPS
    public let fps: Double
    
    /// Resolved camera (if present)
    public var camera: ResolvedCamera?
    
    /// Resolved element transforms by element ID
    public var elementTransforms: [String: ResolvedTransform]
    
    /// Resolved effect parameters by effect ID
    public var effectParameters: [String: [String: Double]]
    
    public init(
        time: Double,
        frame: Int,
        duration: Double,
        fps: Double,
        camera: ResolvedCamera? = nil,
        elementTransforms: [String: ResolvedTransform] = [:],
        effectParameters: [String: [String: Double]] = [:]
    ) {
        self.time = time
        self.frame = frame
        self.duration = duration
        self.fps = fps
        self.camera = camera
        self.elementTransforms = elementTransforms
        self.effectParameters = effectParameters
    }
}

// MARK: - PropertyPath

/// Path to a property in the manifest for animation
public struct PropertyPath: Hashable, Sendable {
    /// Path components (e.g., ["camera", "position", "x"])
    public let components: [String]
    
    /// Full path string
    public var path: String {
        components.joined(separator: ".")
    }
    
    public init(_ path: String) {
        self.components = path.split(separator: ".").map(String.init)
    }
    
    public init(components: [String]) {
        self.components = components
    }
    
    /// Get the parent path
    public var parent: PropertyPath? {
        guard components.count > 1 else { return nil }
        return PropertyPath(components: Array(components.dropLast()))
    }
    
    /// Get the property name (last component)
    public var propertyName: String? {
        components.last
    }
}

// MARK: - Convenience Extensions

extension TimelineResolver {
    /// Create a timeline for a specific duration and evaluate a closure at each frame
    public func evaluateTimeline(
        duration: Double,
        fps: Double = 30,
        evaluator: (Context) async throws -> Void
    ) async throws {
        let frameCount = Int(duration * fps)
        
        for frame in 0..<frameCount {
            let time = Double(frame) / fps
            let context = Context(time: time, frame: frame, duration: duration, fps: fps)
            try await evaluator(context)
        }
    }
    
    /// Sample a keyframe track at regular intervals
    public func sample<T: Interpolatable>(
        track: KeyframeTrack<T>,
        from startTime: Double,
        to endTime: Double,
        samples: Int
    ) -> [T] {
        guard samples > 1 else { return [track.evaluate(at: startTime)] }
        
        var results: [T] = []
        let step = (endTime - startTime) / Double(samples - 1)
        
        for i in 0..<samples {
            let time = startTime + Double(i) * step
            results.append(track.evaluate(at: time))
        }
        
        return results
    }
}
