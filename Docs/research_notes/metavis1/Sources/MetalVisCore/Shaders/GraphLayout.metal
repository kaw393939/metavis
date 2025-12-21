#include <metal_stdlib>
using namespace metal;

// Match Swift LayoutNode structure
struct LayoutNode {
    float2 position;
    float2 velocity;
    float mass;
    uint id;
};

// Match Swift QuadTreeNode structure
struct QuadTreeNode {
    float2 centerOfMass;
    float totalMass;
    float2 boundsMin;
    float2 boundsMax;
    uint childIndices[4];  // 0 = no child
    bool isLeaf;
    char padding[3];  // Align to 16 bytes
};

// Match Swift LayoutParams structure
struct LayoutParams {
    float repulsionStrength;
    float attractionStrength;
    float theta;
    float damping;
    float timeStep;
    float4 bounds;  // min_x, min_y, max_x, max_y
    uint maxIterations;
    float convergenceThreshold;
};

/// Compute repulsive forces using Barnes-Hut approximation
/// MBE Chapter 13: Compute kernel fundamentals
kernel void compute_repulsion(
    device LayoutNode *nodes [[buffer(0)]],
    constant QuadTreeNode *tree [[buffer(1)]],
    constant LayoutParams &params [[buffer(2)]],
    device float2 *forces [[buffer(3)]],
    constant uint &nodeCount [[buffer(4)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= nodeCount) return;
    
    LayoutNode node = nodes[gid];
    float2 force = float2(0, 0);
    
    // Traverse quadtree recursively (stack-based)
    // Stack size of 32 allows for deep trees
    uint stack[32];
    int stackPtr = 0;
    stack[stackPtr++] = 0;  // Start with root node
    
    while (stackPtr > 0) {
        uint treeIdx = stack[--stackPtr];
        QuadTreeNode treeNode = tree[treeIdx];
        
        float2 delta = treeNode.centerOfMass - node.position;
        float dist = length(delta);
        
        // Avoid singularity when nodes overlap
        if (dist < 0.01) continue;
        
        // Barnes-Hut criterion: s/d < theta
        // s = size of region, d = distance to center of mass
        float2 size = treeNode.boundsMax - treeNode.boundsMin;
        float s = max(size.x, size.y);
        
        if (treeNode.isLeaf || (s / dist) < params.theta) {
            // Treat as single body (Coulomb's law)
            // F = k * (m1 * m2) / r²
            // delta points from node to centerOfMass
            // Repulsion pushes node away, so force opposes delta
            float forceMag = params.repulsionStrength * 
                           (node.mass * treeNode.totalMass) / (dist * dist);
            force += normalize(delta) * -forceMag;  // Push away from mass
        } else {
            // Recurse into children (push onto stack)
            for (int i = 0; i < 4; i++) {
                if (treeNode.childIndices[i] != 0) {
                    stack[stackPtr++] = treeNode.childIndices[i];
                }
            }
        }
    }
    
    forces[gid] = force;
}

/// Compute attractive forces from edges (Hooke's law)
/// Each thread processes one edge and atomically updates both nodes
kernel void compute_attraction(
    constant LayoutNode *nodes [[buffer(0)]],
    constant uint2 *edges [[buffer(1)]],
    constant LayoutParams &params [[buffer(2)]],
    device atomic_float *forces [[buffer(3)]],  // Interleaved [x0, y0, x1, y1, ...]
    constant uint &edgeCount [[buffer(4)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= edgeCount) return;
    
    uint2 edge = edges[gid];
    LayoutNode source = nodes[edge.x];
    LayoutNode target = nodes[edge.y];
    
    float2 delta = target.position - source.position;
    float dist = length(delta);
    
    // Avoid singularity
    if (dist < 0.01) return;
    
    // Hooke's law: F = k * x (spring force)
    float forceMag = params.attractionStrength * dist;
    float2 force = normalize(delta) * forceMag;
    
    // Atomic add to force accumulator (source pulled toward target)
    atomic_fetch_add_explicit(&forces[edge.x * 2 + 0], force.x, memory_order_relaxed);
    atomic_fetch_add_explicit(&forces[edge.x * 2 + 1], force.y, memory_order_relaxed);
    
    // Target pulled toward source (Newton's 3rd law)
    atomic_fetch_add_explicit(&forces[edge.y * 2 + 0], -force.x, memory_order_relaxed);
    atomic_fetch_add_explicit(&forces[edge.y * 2 + 1], -force.y, memory_order_relaxed);
}

/// Update node positions using velocity Verlet integration
/// MBE Chapter 13: Parallel position updates
kernel void update_positions(
    device LayoutNode *nodes [[buffer(0)]],
    constant float2 *forces [[buffer(1)]],
    constant LayoutParams &params [[buffer(2)]],
    constant uint &nodeCount [[buffer(3)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= nodeCount) return;
    
    LayoutNode node = nodes[gid];
    
    // Acceleration: a = F / m
    float2 acceleration = forces[gid] / node.mass;
    
    // Velocity Verlet integration
    // v(t+dt) = v(t) + a(t) * dt
    node.velocity += acceleration * params.timeStep;
    
    // Apply damping to simulate friction
    node.velocity *= params.damping;
    
    // Update position: x(t+dt) = x(t) + v(t+dt) * dt
    node.position += node.velocity * params.timeStep;
    
    // Clamp to bounds
    node.position.x = clamp(node.position.x, params.bounds.x, params.bounds.z);
    node.position.y = clamp(node.position.y, params.bounds.y, params.bounds.w);
    
    // Write back
    nodes[gid] = node;
}

/// Compute kinetic energy for convergence detection
/// Sum of 0.5 * m * v²
kernel void compute_kinetic_energy(
    constant LayoutNode *nodes [[buffer(0)]],
    device atomic_float *totalEnergy [[buffer(1)]],
    constant uint &nodeCount [[buffer(2)]],
    uint gid [[thread_position_in_grid]]
) {
    if (gid >= nodeCount) return;
    
    LayoutNode node = nodes[gid];
    float speedSquared = dot(node.velocity, node.velocity);
    float energy = 0.5 * node.mass * speedSquared;
    
    atomic_fetch_add_explicit(totalEnergy, energy, memory_order_relaxed);
}
