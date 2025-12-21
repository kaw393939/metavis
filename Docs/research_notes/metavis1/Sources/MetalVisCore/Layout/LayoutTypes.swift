import Metal
import simd

/// Node in the graph layout system
public struct LayoutNode: Sendable {
    public var position: SIMD2<Float>
    public var velocity: SIMD2<Float>
    public var mass: Float
    public var id: UInt32

    public init(position: SIMD2<Float>, velocity: SIMD2<Float>, mass: Float, id: UInt32) {
        self.position = position
        self.velocity = velocity
        self.mass = mass
        self.id = id
    }
}

/// Parameters for force-directed layout
public struct LayoutParams: Sendable {
    public var repulsionStrength: Float
    public var attractionStrength: Float
    public var theta: Float // Barnes-Hut approximation threshold
    public var damping: Float
    public var timeStep: Float
    public var bounds: SIMD4<Float> // min_x, min_y, max_x, max_y
    public var maxIterations: Int
    public var convergenceThreshold: Float

    public init(
        repulsionStrength: Float = 100.0,
        attractionStrength: Float = 0.1,
        theta: Float = 0.5,
        damping: Float = 0.9,
        timeStep: Float = 0.1,
        bounds: SIMD4<Float> = SIMD4<Float>(-100, -100, 100, 100),
        maxIterations: Int = 500,
        convergenceThreshold: Float = 0.01
    ) {
        self.repulsionStrength = repulsionStrength
        self.attractionStrength = attractionStrength
        self.theta = theta
        self.damping = damping
        self.timeStep = timeStep
        self.bounds = bounds
        self.maxIterations = maxIterations
        self.convergenceThreshold = convergenceThreshold
    }
}

/// Node in the Barnes-Hut quadtree
public struct QuadTreeNode: Sendable {
    public var centerOfMass: SIMD2<Float>
    public var totalMass: Float
    public var boundsMin: SIMD2<Float>
    public var boundsMax: SIMD2<Float>
    public var childIndices: (UInt32, UInt32, UInt32, UInt32) // 0 = no child
    public var isLeaf: Bool

    public init(
        centerOfMass: SIMD2<Float> = .zero,
        totalMass: Float = 0,
        boundsMin: SIMD2<Float> = .zero,
        boundsMax: SIMD2<Float> = .zero,
        childIndices: (UInt32, UInt32, UInt32, UInt32) = (0, 0, 0, 0),
        isLeaf: Bool = true
    ) {
        self.centerOfMass = centerOfMass
        self.totalMass = totalMass
        self.boundsMin = boundsMin
        self.boundsMax = boundsMax
        self.childIndices = childIndices
        self.isLeaf = isLeaf
    }
}
