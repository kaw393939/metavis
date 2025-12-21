import Metal
import simd

/// GPU-accelerated graph layout engine using force-directed algorithm
/// Implements Barnes-Hut approximation for O(N log N) performance
/// MBE Reference: Chapter 13-14 (Compute Shaders)
public actor GraphLayoutEngine {
    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary

    // Compute pipelines
    private let repulsionPipeline: MTLComputePipelineState
    private let attractionPipeline: MTLComputePipelineState
    private let updatePipeline: MTLComputePipelineState
    private let energyPipeline: MTLComputePipelineState

    // Thread configuration (MBE page 121)
    private let threadsPerThreadgroup: MTLSize
    private let threadExecutionWidth: Int

    public init(device: MTLDevice) throws {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            throw LayoutError.failedToCreateCommandQueue
        }
        commandQueue = queue

        // Load shader library - compile from source for SPM compatibility
        let library: MTLLibrary
        if let bundlePath = Bundle.module.path(forResource: "GraphLayout", ofType: "metal"),
           let shaderSource = try? String(contentsOfFile: bundlePath) {
            library = try device.makeLibrary(source: shaderSource, options: nil)
        } else if let defaultLibrary = device.makeDefaultLibrary() {
            library = defaultLibrary
        } else {
            throw LayoutError.failedToLoadLibrary
        }
        self.library = library

        // Create compute pipelines
        guard let repulsionFunc = library.makeFunction(name: "compute_repulsion") else {
            print("❌ Failed to find compute_repulsion function")
            print("Available functions: \(library.functionNames)")
            throw LayoutError.failedToLoadShaderFunctions
        }
        guard let attractionFunc = library.makeFunction(name: "compute_attraction") else {
            print("❌ Failed to find compute_attraction function")
            throw LayoutError.failedToLoadShaderFunctions
        }
        guard let updateFunc = library.makeFunction(name: "update_positions") else {
            print("❌ Failed to find update_positions function")
            throw LayoutError.failedToLoadShaderFunctions
        }
        guard let energyFunc = library.makeFunction(name: "compute_kinetic_energy") else {
            print("❌ Failed to find compute_kinetic_energy function")
            throw LayoutError.failedToLoadShaderFunctions
        }

        repulsionPipeline = try device.makeComputePipelineState(function: repulsionFunc)
        attractionPipeline = try device.makeComputePipelineState(function: attractionFunc)
        updatePipeline = try device.makeComputePipelineState(function: updateFunc)
        energyPipeline = try device.makeComputePipelineState(function: energyFunc)

        // Configure thread groups (MBE page 121: optimal is 64 threads)
        threadExecutionWidth = repulsionPipeline.threadExecutionWidth
        threadsPerThreadgroup = MTLSize(width: 64, height: 1, depth: 1)
    }

    // MARK: - Public API

    /// Compute repulsion forces between all nodes using Barnes-Hut approximation
    public func computeRepulsionForces(
        nodes: inout [LayoutNode],
        params: LayoutParams
    ) async throws -> [SIMD2<Float>] {
        // Build Barnes-Hut quadtree for spatial partitioning
        let tree = try await buildQuadTree(nodes: nodes)

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw LayoutError.failedToCreateCommandBuffer
        }

        // Create buffers
        let nodeBuffer = device.makeBuffer(
            bytes: &nodes,
            length: MemoryLayout<LayoutNode>.stride * nodes.count,
            options: .storageModeShared
        )!

        var treeArray = tree
        let treeBuffer = device.makeBuffer(
            bytes: &treeArray,
            length: MemoryLayout<QuadTreeNode>.stride * tree.count,
            options: .storageModeShared
        )!

        var params = params
        let paramsBuffer = device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<LayoutParams>.stride,
            options: .storageModeShared
        )!

        var forces = [SIMD2<Float>](repeating: .zero, count: nodes.count)
        let forcesBuffer = device.makeBuffer(
            bytes: &forces,
            length: MemoryLayout<SIMD2<Float>>.stride * nodes.count,
            options: .storageModeShared
        )!

        var nodeCount = UInt32(nodes.count)
        let nodeCountBuffer = device.makeBuffer(
            bytes: &nodeCount,
            length: MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        )!

        // Encode compute command
        encoder.setComputePipelineState(repulsionPipeline)
        encoder.setBuffer(nodeBuffer, offset: 0, index: 0)
        encoder.setBuffer(treeBuffer, offset: 0, index: 1)
        encoder.setBuffer(paramsBuffer, offset: 0, index: 2)
        encoder.setBuffer(forcesBuffer, offset: 0, index: 3)
        encoder.setBuffer(nodeCountBuffer, offset: 0, index: 4)

        // Dispatch threads (MBE page 121)
        let threadgroups = MTLSize(
            width: (nodes.count + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: 1,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()

        await waitForCompletion(commandBuffer)

        // Read back results
        let forcesPointer = forcesBuffer.contents().bindMemory(
            to: SIMD2<Float>.self,
            capacity: nodes.count
        )
        return Array(UnsafeBufferPointer(start: forcesPointer, count: nodes.count))
    }

    /// Compute attraction forces along edges
    public func computeAttractionForces(
        nodes: [LayoutNode],
        edges: [SIMD2<UInt32>],
        params: LayoutParams
    ) async throws -> [SIMD2<Float>] {
        guard !edges.isEmpty else {
            return [SIMD2<Float>](repeating: .zero, count: nodes.count)
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw LayoutError.failedToCreateCommandBuffer
        }

        // Create buffers
        var nodes = nodes
        let nodeBuffer = device.makeBuffer(
            bytes: &nodes,
            length: MemoryLayout<LayoutNode>.stride * nodes.count,
            options: .storageModeShared
        )!

        var edges = edges
        let edgeBuffer = device.makeBuffer(
            bytes: &edges,
            length: MemoryLayout<SIMD2<UInt32>>.stride * edges.count,
            options: .storageModeShared
        )!

        var params = params
        let paramsBuffer = device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<LayoutParams>.stride,
            options: .storageModeShared
        )!

        // Forces buffer (interleaved floats for atomic operations)
        var forces = [Float](repeating: 0, count: nodes.count * 2)
        let forcesBuffer = device.makeBuffer(
            bytes: &forces,
            length: MemoryLayout<Float>.stride * forces.count,
            options: .storageModeShared
        )!

        var edgeCount = UInt32(edges.count)
        let edgeCountBuffer = device.makeBuffer(
            bytes: &edgeCount,
            length: MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        )!

        // Encode compute command
        encoder.setComputePipelineState(attractionPipeline)
        encoder.setBuffer(nodeBuffer, offset: 0, index: 0)
        encoder.setBuffer(edgeBuffer, offset: 0, index: 1)
        encoder.setBuffer(paramsBuffer, offset: 0, index: 2)
        encoder.setBuffer(forcesBuffer, offset: 0, index: 3)
        encoder.setBuffer(edgeCountBuffer, offset: 0, index: 4)

        let threadgroups = MTLSize(
            width: (edges.count + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: 1,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()

        await waitForCompletion(commandBuffer)

        // Read back and convert from interleaved floats to SIMD2
        let forcesPointer = forcesBuffer.contents().bindMemory(to: Float.self, capacity: forces.count)
        let forcesArray = Array(UnsafeBufferPointer(start: forcesPointer, count: forces.count))

        return (0 ..< nodes.count).map { i in
            SIMD2<Float>(forcesArray[i * 2], forcesArray[i * 2 + 1])
        }
    }

    /// Update node positions using velocity Verlet integration
    public func updatePositions(
        nodes: inout [LayoutNode],
        forces: [SIMD2<Float>],
        params: LayoutParams
    ) async throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw LayoutError.failedToCreateCommandBuffer
        }

        // Create buffers
        let nodeBuffer = device.makeBuffer(
            bytes: &nodes,
            length: MemoryLayout<LayoutNode>.stride * nodes.count,
            options: .storageModeShared
        )!

        var forces = forces
        let forcesBuffer = device.makeBuffer(
            bytes: &forces,
            length: MemoryLayout<SIMD2<Float>>.stride * forces.count,
            options: .storageModeShared
        )!

        var params = params
        let paramsBuffer = device.makeBuffer(
            bytes: &params,
            length: MemoryLayout<LayoutParams>.stride,
            options: .storageModeShared
        )!

        var nodeCount = UInt32(nodes.count)
        let nodeCountBuffer = device.makeBuffer(
            bytes: &nodeCount,
            length: MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        )!

        // Encode compute command
        encoder.setComputePipelineState(updatePipeline)
        encoder.setBuffer(nodeBuffer, offset: 0, index: 0)
        encoder.setBuffer(forcesBuffer, offset: 0, index: 1)
        encoder.setBuffer(paramsBuffer, offset: 0, index: 2)
        encoder.setBuffer(nodeCountBuffer, offset: 0, index: 3)

        let threadgroups = MTLSize(
            width: (nodes.count + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width,
            height: 1,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()

        await waitForCompletion(commandBuffer)

        // Read back results
        let nodesPointer = nodeBuffer.contents().bindMemory(
            to: LayoutNode.self,
            capacity: nodes.count
        )
        nodes = Array(UnsafeBufferPointer(start: nodesPointer, count: nodes.count))
    }

    /// Perform one complete layout iteration (forces + position update)
    public func layoutIteration(
        nodes: inout [LayoutNode],
        edges: [SIMD2<UInt32>],
        params: LayoutParams
    ) async throws {
        // Compute all forces
        let repulsion = try await computeRepulsionForces(nodes: &nodes, params: params)
        let attraction = try await computeAttractionForces(nodes: nodes, edges: edges, params: params)

        // Combine forces
        let totalForces = zip(repulsion, attraction).map { $0 + $1 }

        // Update positions
        try await updatePositions(nodes: &nodes, forces: totalForces, params: params)
    }

    /// Run layout algorithm until convergence
    public func layout(
        nodes: inout [LayoutNode],
        edges: [SIMD2<UInt32>],
        params: LayoutParams
    ) async throws -> Int {
        var iteration = 0
        while iteration < params.maxIterations {
            try await layoutIteration(nodes: &nodes, edges: edges, params: params)
            iteration += 1

            if hasConverged(nodes: nodes, threshold: params.convergenceThreshold) {
                break
            }
        }

        return iteration
    }

    /// Check if layout has converged (velocities below threshold)
    public nonisolated func hasConverged(nodes: [LayoutNode], threshold: Float) -> Bool {
        let maxSpeed = nodes.map { simd_length($0.velocity) }.max() ?? 0
        return maxSpeed < threshold
    }

    // MARK: - Barnes-Hut Tree Construction

    /// Build quadtree for Barnes-Hut force approximation (CPU for now)
    public func buildQuadTree(nodes: [LayoutNode]) async throws -> [QuadTreeNode] {
        guard !nodes.isEmpty else {
            return []
        }

        // Compute bounds
        let positions = nodes.map { $0.position }
        let minX = positions.map { $0.x }.min()!
        let minY = positions.map { $0.y }.min()!
        let maxX = positions.map { $0.x }.max()!
        let maxY = positions.map { $0.y }.max()!
        let bounds = (min: SIMD2<Float>(minX, minY), max: SIMD2<Float>(maxX, maxY))

        var tree: [QuadTreeNode] = []
        _ = buildQuadTreeRecursive(nodes: nodes, bounds: bounds, tree: &tree)
        return tree
    }

    private func buildQuadTreeRecursive(
        nodes: [LayoutNode],
        bounds: (min: SIMD2<Float>, max: SIMD2<Float>),
        tree: inout [QuadTreeNode],
        depth: Int = 0
    ) -> Int {
        // Guard against empty nodes or excessive depth
        guard !nodes.isEmpty, depth < 20 else {
            return 0 // Return invalid index
        }

        // Compute center of mass
        var totalMass: Float = 0
        var comX: Float = 0
        var comY: Float = 0
        for node in nodes {
            totalMass += node.mass
            comX += node.position.x * node.mass
            comY += node.position.y * node.mass
        }
        comX /= totalMass
        comY /= totalMass

        // Single node or very small bounds - create leaf
        let size = max(bounds.max.x - bounds.min.x, bounds.max.y - bounds.min.y)
        if nodes.count == 1 || size < 0.001 {
            let nodeIndex = tree.count
            tree.append(QuadTreeNode(
                centerOfMass: SIMD2<Float>(comX, comY),
                totalMass: totalMass,
                boundsMin: bounds.min,
                boundsMax: bounds.max,
                childIndices: (0, 0, 0, 0),
                isLeaf: true
            ))
            return nodeIndex
        }

        // Multiple nodes - subdivide
        let center = SIMD2<Float>(
            (bounds.min.x + bounds.max.x) / 2,
            (bounds.min.y + bounds.max.y) / 2
        )

        // Partition nodes into quadrants
        var nw: [LayoutNode] = []
        var ne: [LayoutNode] = []
        var sw: [LayoutNode] = []
        var se: [LayoutNode] = []

        for node in nodes {
            if node.position.x < center.x {
                if node.position.y < center.y {
                    sw.append(node)
                } else {
                    nw.append(node)
                }
            } else {
                if node.position.y < center.y {
                    se.append(node)
                } else {
                    ne.append(node)
                }
            }
        }

        // Reserve slot for this internal node
        let nodeIndex = tree.count
        tree.append(QuadTreeNode(
            centerOfMass: .zero,
            totalMass: 0,
            boundsMin: .zero,
            boundsMax: .zero,
            childIndices: (0, 0, 0, 0),
            isLeaf: false
        ))

        // Recursively build children
        var childIndices: (UInt32, UInt32, UInt32, UInt32) = (0, 0, 0, 0)

        if !nw.isEmpty {
            let nwBounds = (min: SIMD2<Float>(bounds.min.x, center.y), max: SIMD2<Float>(center.x, bounds.max.y))
            childIndices.0 = UInt32(buildQuadTreeRecursive(nodes: nw, bounds: nwBounds, tree: &tree, depth: depth + 1))
        }
        if !ne.isEmpty {
            let neBounds = (min: SIMD2<Float>(center.x, center.y), max: bounds.max)
            childIndices.1 = UInt32(buildQuadTreeRecursive(nodes: ne, bounds: neBounds, tree: &tree, depth: depth + 1))
        }
        if !sw.isEmpty {
            let swBounds = (min: bounds.min, max: center)
            childIndices.2 = UInt32(buildQuadTreeRecursive(nodes: sw, bounds: swBounds, tree: &tree, depth: depth + 1))
        }
        if !se.isEmpty {
            let seBounds = (min: SIMD2<Float>(center.x, bounds.min.y), max: SIMD2<Float>(bounds.max.x, center.y))
            childIndices.3 = UInt32(buildQuadTreeRecursive(nodes: se, bounds: seBounds, tree: &tree, depth: depth + 1))
        }

        // Update internal node
        tree[nodeIndex] = QuadTreeNode(
            centerOfMass: SIMD2<Float>(comX, comY),
            totalMass: totalMass,
            boundsMin: bounds.min,
            boundsMax: bounds.max,
            childIndices: childIndices,
            isLeaf: false
        )

        return nodeIndex
    }

    // MARK: - Private Helpers

    /// Wait for Metal command buffer to complete (Swift 6 concurrency safe)
    private func waitForCompletion(_ commandBuffer: MTLCommandBuffer) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            commandBuffer.addCompletedHandler { _ in
                continuation.resume()
            }
            commandBuffer.commit()
        }
    }
}

// MARK: - Error Types

public enum LayoutError: Error {
    case failedToCreateCommandQueue
    case failedToLoadLibrary
    case failedToLoadShaderFunctions
    case failedToCreateCommandBuffer
}
