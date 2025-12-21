// PropertyDriver.swift
// MetaVisRender
//
// Created for Sprint 05: Timeline & Animation
// Drives property animations from keyframes and expressions

import Foundation
import simd

// MARK: - PropertyDriver

/// Drives animations for manifest properties.
/// Manages keyframe tracks, expressions, and semantic animations.
public actor PropertyDriver {
    
    // MARK: - Types
    
    /// Error types for property driving
    public enum Error: Swift.Error, Equatable {
        case propertyNotFound(String)
        case invalidPropertyType(String)
        case circularDependency
    }
    
    /// A driven property with its animation source
    public struct DrivenProperty: Sendable {
        public let path: PropertyPath
        public let animation: PropertyAnimation
        
        public init(path: PropertyPath, animation: PropertyAnimation) {
            self.path = path
            self.animation = animation
        }
    }
    
    /// Types of property animation
    public enum PropertyAnimation: Sendable {
        /// Animated with keyframes
        case keyframes(KeyframeTrack<Double>)
        
        /// Animated with expression
        case expression(String)
        
        /// Driven by semantic data (e.g., track_speaker)
        case semantic(SemanticDriver)
        
        /// Linked to another property
        case linked(PropertyPath, offset: Double)
    }
    
    /// Semantic animation drivers
    public enum SemanticDriver: String, Codable, Sendable {
        /// Follow the active speaker's face
        case trackSpeaker = "track_speaker"
        
        /// Follow a specific face
        case trackFace = "track_face"
        
        /// Pan through salient regions
        case panSaliency = "pan_saliency"
        
        /// Zoom based on emotional intensity
        case zoomEmotion = "zoom_emotion"
        
        /// Auto-frame subjects
        case autoFrame = "auto_frame"
        
        /// Follow motion
        case followMotion = "follow_motion"
    }
    
    // MARK: - Properties
    
    /// Registered property drivers
    private var drivers: [PropertyPath: DrivenProperty] = [:]
    
    /// Expression evaluator
    private let expressionEvaluator: ExpressionEvaluator
    
    /// Timeline resolver
    private let resolver: TimelineResolver
    
    // MARK: - Initialization
    
    public init(resolver: TimelineResolver? = nil) {
        self.expressionEvaluator = ExpressionEvaluator()
        self.resolver = resolver ?? TimelineResolver()
    }
    
    // MARK: - Registration
    
    /// Register a keyframe-driven property
    public func registerKeyframes(
        path: String,
        track: KeyframeTrack<Double>
    ) {
        let propertyPath = PropertyPath(path)
        let driven = DrivenProperty(
            path: propertyPath,
            animation: .keyframes(track)
        )
        drivers[propertyPath] = driven
    }
    
    /// Register an expression-driven property
    public func registerExpression(
        path: String,
        expression: String
    ) {
        let propertyPath = PropertyPath(path)
        let driven = DrivenProperty(
            path: propertyPath,
            animation: .expression(expression)
        )
        drivers[propertyPath] = driven
    }
    
    /// Register a semantic-driven property
    public func registerSemantic(
        path: String,
        driver: SemanticDriver
    ) {
        let propertyPath = PropertyPath(path)
        let driven = DrivenProperty(
            path: propertyPath,
            animation: .semantic(driver)
        )
        drivers[propertyPath] = driven
    }
    
    /// Register a linked property (follows another property)
    public func registerLinked(
        path: String,
        sourcePath: String,
        offset: Double = 0
    ) {
        let propertyPath = PropertyPath(path)
        let driven = DrivenProperty(
            path: propertyPath,
            animation: .linked(PropertyPath(sourcePath), offset: offset)
        )
        drivers[propertyPath] = driven
    }
    
    /// Unregister a property driver
    public func unregister(path: String) {
        let propertyPath = PropertyPath(path)
        drivers.removeValue(forKey: propertyPath)
    }
    
    /// Clear all drivers
    public func clearAll() {
        drivers.removeAll()
    }
    
    // MARK: - Evaluation
    
    /// Evaluate a property at a given time
    public func evaluate(
        path: String,
        context: TimelineResolver.Context
    ) throws -> Double {
        let propertyPath = PropertyPath(path)
        
        guard let driven = drivers[propertyPath] else {
            throw Error.propertyNotFound(path)
        }
        
        return try evaluateAnimation(driven.animation, context: context)
    }
    
    /// Evaluate all driven properties
    public func evaluateAll(
        context: TimelineResolver.Context
    ) throws -> [PropertyPath: Double] {
        var results: [PropertyPath: Double] = [:]
        
        for (path, driven) in drivers {
            results[path] = try evaluateAnimation(driven.animation, context: context)
        }
        
        return results
    }
    
    /// Evaluate a specific animation
    private func evaluateAnimation(
        _ animation: PropertyAnimation,
        context: TimelineResolver.Context,
        visited: Set<PropertyPath> = []
    ) throws -> Double {
        switch animation {
        case .keyframes(let track):
            return track.evaluate(at: context.time)
            
        case .expression(let expr):
            return try expressionEvaluator.evaluate(expr, context: context)
            
        case .semantic(let driver):
            return try evaluateSemantic(driver, context: context)
            
        case .linked(let sourcePath, let offset):
            // Check for circular dependency
            guard !visited.contains(sourcePath) else {
                throw Error.circularDependency
            }
            
            guard let sourceDriver = drivers[sourcePath] else {
                throw Error.propertyNotFound(sourcePath.path)
            }
            
            var newVisited = visited
            newVisited.insert(sourcePath)
            
            let sourceValue = try evaluateAnimation(
                sourceDriver.animation,
                context: context,
                visited: newVisited
            )
            
            return sourceValue + offset
        }
    }
    
    /// Evaluate a semantic driver
    private func evaluateSemantic(
        _ driver: SemanticDriver,
        context: TimelineResolver.Context
    ) throws -> Double {
        // Semantic drivers require access to FootageIndexRecord data
        // which will be connected when we integrate with Sprint 06
        // For now, return placeholder values
        
        switch driver {
        case .trackSpeaker:
            // Would query speaker position from FootageIndexRecord
            return 0.5  // Center
            
        case .trackFace:
            // Would query face position
            return 0.5
            
        case .panSaliency:
            // Would use saliency map
            let time = context.time
            return sin(time * 0.1) * 0.3 + 0.5
            
        case .zoomEmotion:
            // Would use emotion intensity
            return 1.0
            
        case .autoFrame:
            // Would compute optimal framing
            return 0.5
            
        case .followMotion:
            // Would track motion vectors
            return 0.5
        }
    }
    
    // MARK: - Queries
    
    /// Get all registered property paths
    public var registeredPaths: [PropertyPath] {
        Array(drivers.keys)
    }
    
    /// Check if a property is driven
    public func isDriven(path: String) -> Bool {
        drivers[PropertyPath(path)] != nil
    }
    
    /// Get the animation type for a property
    public func animationType(path: String) -> PropertyAnimation? {
        drivers[PropertyPath(path)]?.animation
    }
}

// MARK: - Vector Property Driver

/// Drives vector properties (position, rotation, scale, color)
public actor VectorPropertyDriver {
    
    // MARK: - Types
    
    /// A driven vector property
    public struct DrivenVector3: Sendable {
        public let path: PropertyPath
        public let x: PropertyDriver.PropertyAnimation?
        public let y: PropertyDriver.PropertyAnimation?
        public let z: PropertyDriver.PropertyAnimation?
        public let combined: KeyframeTrack<SIMD3<Float>>?
        
        public init(
            path: PropertyPath,
            x: PropertyDriver.PropertyAnimation? = nil,
            y: PropertyDriver.PropertyAnimation? = nil,
            z: PropertyDriver.PropertyAnimation? = nil,
            combined: KeyframeTrack<SIMD3<Float>>? = nil
        ) {
            self.path = path
            self.x = x
            self.y = y
            self.z = z
            self.combined = combined
        }
    }
    
    // MARK: - Properties
    
    private var drivers: [PropertyPath: DrivenVector3] = [:]
    private let expressionEvaluator: ExpressionEvaluator
    
    // MARK: - Initialization
    
    public init() {
        self.expressionEvaluator = ExpressionEvaluator()
    }
    
    // MARK: - Registration
    
    /// Register a vector property with combined keyframes
    public func register(
        path: String,
        track: KeyframeTrack<SIMD3<Float>>
    ) {
        let propertyPath = PropertyPath(path)
        let driven = DrivenVector3(path: propertyPath, combined: track)
        drivers[propertyPath] = driven
    }
    
    /// Register a vector property with per-component animations
    public func register(
        path: String,
        x: PropertyDriver.PropertyAnimation? = nil,
        y: PropertyDriver.PropertyAnimation? = nil,
        z: PropertyDriver.PropertyAnimation? = nil
    ) {
        let propertyPath = PropertyPath(path)
        let driven = DrivenVector3(path: propertyPath, x: x, y: y, z: z)
        drivers[propertyPath] = driven
    }
    
    // MARK: - Evaluation
    
    /// Evaluate a vector property at a given time
    public func evaluate(
        path: String,
        context: TimelineResolver.Context
    ) throws -> SIMD3<Float> {
        let propertyPath = PropertyPath(path)
        
        guard let driven = drivers[propertyPath] else {
            throw PropertyDriver.Error.propertyNotFound(path)
        }
        
        // Use combined track if available
        if let combined = driven.combined {
            return combined.evaluate(at: context.time)
        }
        
        // Evaluate per-component
        let xValue = try evaluateComponent(driven.x, context: context)
        let yValue = try evaluateComponent(driven.y, context: context)
        let zValue = try evaluateComponent(driven.z, context: context)
        
        return SIMD3<Float>(Float(xValue), Float(yValue), Float(zValue))
    }
    
    private func evaluateComponent(
        _ animation: PropertyDriver.PropertyAnimation?,
        context: TimelineResolver.Context
    ) throws -> Double {
        guard let anim = animation else { return 0 }
        
        switch anim {
        case .keyframes(let track):
            return track.evaluate(at: context.time)
        case .expression(let expr):
            return try expressionEvaluator.evaluate(expr, context: context)
        case .semantic, .linked:
            // These require PropertyDriver for full evaluation
            return 0
        }
    }
}

// MARK: - Convenience Extensions

extension PropertyDriver {
    /// Create common camera animations
    public func setupCameraPan(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        duration: Double,
        curve: InterpolationType = .easeInOut
    ) {
        let positionTrack = KeyframeTrack<Double>(
            keyframes: [
                Keyframe(time: 0, value: 0),
                Keyframe(time: duration, value: 1)
            ],
            interpolation: curve
        )
        
        registerKeyframes(path: "camera.position.progress", track: positionTrack)
    }
    
    /// Create a breathing/pulsing animation
    public func setupBreathing(
        path: String,
        min: Double,
        max: Double,
        frequency: Double = 1.0
    ) {
        let expr = ExpressionEvaluator.Preset.breathe(
            frequency: frequency,
            min: min,
            max: max
        ).expression
        
        registerExpression(path: path, expression: expr)
    }
    
    /// Create a fade in animation
    public func setupFadeIn(
        path: String,
        duration: Double
    ) {
        let expr = ExpressionEvaluator.Preset.fadeIn(duration: duration).expression
        registerExpression(path: path, expression: expr)
    }
    
    /// Create a fade out animation
    public func setupFadeOut(
        path: String,
        startTime: Double,
        duration: Double
    ) {
        let expr = ExpressionEvaluator.Preset.fadeOut(startTime: startTime, duration: duration).expression
        registerExpression(path: path, expression: expr)
    }
}
