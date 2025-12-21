#include <metal_stdlib>
#include "../Core/Procedural.metal"

using namespace metal;
using namespace Procedural;

// =============================================================================
// FUTURE ROADMAP: Advanced Rendering Features
// =============================================================================
//
// VOLUMETRIC RAYMARCHING (Priority: High)
// ----------------------------------------
// Replace layered media_plane approach with true volumetric rendering:
// - Implement raymarching compute kernel with adaptive step size
// - Use G-buffer for depth-aware integration
// - Add self-shadowing via shadow ray marching
// - Support density fields from FBM with extinction coefficients
// - Target: 64-128 samples per ray for cinematic quality
//
// Example signature:
//   kernel void fx_volumetric_nebula(
//       texture3d<float> densityVolume,
//       texture2d<float> depthBuffer,
//       constant VolumetricParams& params,
//       ...)
//
// SPECTRAL LIGHT MODEL (Priority: Medium)
// ----------------------------------------
// For physically accurate astronomical effects:
// - Transition from RGB to spectral basis (e.g., 8-16 wavelength bins)
// - Implement wavelength-dependent scattering (Rayleigh, Mie)
// - Blackbody radiation with proper Planck distribution
// - Emission line spectra for nebula gas (H-alpha, O-III, etc.)
// - Convert to XYZ/ACEScg at final compositing stage
//
// =============================================================================

// MARK: - Field Parameters
// This struct matches the Swift ProceduralFieldDefinition (simplified for Phase 1)

struct FieldParams {
    int fieldType;         // 0=Perlin, 1=Simplex, 2=Worley, 3=FBM_Perlin
    float frequency;
    int octaves;
    float lacunarity;
    float gain;
    
    int domainWarp;        // Changed from bool to int for alignment with Swift Int32
    float warpStrength;
    
    // Domain transform
    float2 scale;
    float2 offset;
    float rotation;
    
    // Color mapping
    int colorCount;
    int loopGradient;      // Changed from bool to int for alignment with Swift Int32
    
    float time;
    float padding;
};

// MARK: - Graph Interpreter (Phase 2)

enum OpCode {
    OP_CONSTANT = 0,
    OP_COORD = 1,
    OP_ADD = 2,
    OP_SUB = 3,
    OP_MUL = 4,
    OP_DIV = 5,
    OP_SIN = 6,
    OP_COS = 7,
    OP_ABS = 8,
    OP_MIN = 9,
    OP_MAX = 10,
    OP_MIX = 11,
    OP_POW = 12,
    OP_EXP = 13,
    OP_NORMALIZE = 14,
    
    OP_PERLIN = 20,
    OP_SIMPLEX = 21,
    OP_WORLEY = 22,
    OP_FBM = 23,
    
    OP_DOMAIN_WARP = 30,
    OP_DOMAIN_ROTATE = 31,
    OP_DOMAIN_SCALE = 32,
    OP_DOMAIN_OFFSET = 33
};

struct GraphNode {
    int op;
    int inputs[4]; // Indices of input nodes (or registers)
    float params[4]; // Parameters (freq, octaves, etc.)
};

// MARK: - Generic Field Kernel

kernel void fx_procedural_graph(
    texture2d<float, access::write> output [[texture(0)]],
    constant GraphNode* nodes [[buffer(0)]],
    constant int& nodeCount [[buffer(1)]],
    constant GradientStop* gradient [[buffer(2)]],
    constant int& gradientCount [[buffer(3)]],
    constant float& time [[buffer(4)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    float2 resolution = float2(output.get_width(), output.get_height());
    float2 uv = float2(gid) / resolution;
    
    // Register file for node outputs
    // Max 64 nodes supported for now
    float results[64];
    float2 vectorResults[64]; // For vector ops (like domain warp)
    
    // Initialize vector results with UV for coordinate nodes
    // But coordinate nodes usually output scalar components or modify the UV context?
    // In this graph model, nodes output values.
    // Domain operations transform the coordinate for *subsequent* nodes?
    // Or do they output a transformed coordinate?
    // Let's assume nodes output values (scalar or vector).
    // But most procedural noise takes a coordinate as input.
    // Where does that coordinate come from?
    // It usually comes from the "current domain".
    // In a graph, "Coordinate" node outputs the current UV.
    // "Domain Warp" takes a coordinate and outputs a warped coordinate.
    // "Perlin" takes a coordinate input.
    
    // Let's refine the model:
    // Nodes output float (scalar) or float2 (vector).
    // We'll store both, or use a tagged union (not possible in Metal).
    // We'll assume most ops are scalar, but some are vector.
    
    // Default coordinate
    float2 currentUV = uv;
    
    for (int i = 0; i < nodeCount; i++) {
        GraphNode node = nodes[i];
        float val = 0.0;
        float2 vecVal = float2(0.0);
        
        // Fetch inputs (scalar)
        float in0 = (node.inputs[0] >= 0 && node.inputs[0] < 64) ? results[node.inputs[0]] : 0.0;
        float in1 = (node.inputs[1] >= 0 && node.inputs[1] < 64) ? results[node.inputs[1]] : 0.0;
        float in2 = (node.inputs[2] >= 0 && node.inputs[2] < 64) ? results[node.inputs[2]] : 0.0;
        
        // Fetch inputs (vector)
        float2 vIn0 = (node.inputs[0] >= 0 && node.inputs[0] < 64) ? vectorResults[node.inputs[0]] : float2(0.0);
        
        switch (node.op) {
            case OP_CONSTANT:
                val = node.params[0];
                break;
                
            case OP_COORD:
                // params[0]: 0=x, 1=y, 2=uv (vector)
                if (node.params[0] < 0.5) val = currentUV.x;
                else if (node.params[0] < 1.5) val = currentUV.y;
                else vecVal = currentUV;
                break;
                
            case OP_ADD: val = in0 + in1; break;
            case OP_SUB: val = in0 - in1; break;
            case OP_MUL: val = in0 * in1; break;
            case OP_DIV: val = (in1 != 0.0) ? in0 / in1 : 0.0; break;
            case OP_SIN: val = sin(in0); break;
            case OP_COS: val = cos(in0); break;
            case OP_ABS: val = abs(in0); break;
            case OP_MIN: val = min(in0, in1); break;
            case OP_MAX: val = max(in0, in1); break;
            case OP_MIX: val = mix(in0, in1, node.params[0]); break; // params[0] is mix factor if constant, or use in2?
            case OP_POW: val = pow(in0, in1); break;
            
            // Noise Generators
            // These usually take a coordinate input.
            // If input[0] is connected, use it as coordinate (vector).
            // Else use currentUV.
            case OP_PERLIN: {
                float2 p = (node.inputs[0] >= 0) ? vIn0 : currentUV;
                float freq = node.params[0] > 0.0 ? node.params[0] : 1.0;
                val = perlin(p * freq);
                val = val * 0.5 + 0.5; // Remap [-1, 1] -> [0, 1]
                break;
            }
            case OP_SIMPLEX: {
                float2 p = (node.inputs[0] >= 0) ? vIn0 : currentUV;
                float freq = node.params[0] > 0.0 ? node.params[0] : 1.0;
                val = simplex(p * freq);
                val = val * 0.5 + 0.5;
                break;
            }
            case OP_WORLEY: {
                float2 p = (node.inputs[0] >= 0) ? vIn0 : currentUV;
                float freq = node.params[0] > 0.0 ? node.params[0] : 1.0;
                val = worley(p * freq);
                break;
            }
            case OP_FBM: {
                float2 p = (node.inputs[0] >= 0) ? vIn0 : currentUV;
                float freq = node.params[0] > 0.0 ? node.params[0] : 1.0;
                int octaves = int(node.params[1]);
                float lacunarity = node.params[2];
                float gain = node.params[3];
                val = fbm(p * freq, octaves, lacunarity, gain);
                val = val * 0.5 + 0.5;
                break;
            }
            
            // Domain Operators
            // These output a VECTOR (float2)
            case OP_DOMAIN_OFFSET: {
                float2 p = (node.inputs[0] >= 0) ? vIn0 : currentUV;
                vecVal = p + float2(node.params[0], node.params[1]);
                break;
            }
            case OP_DOMAIN_SCALE: {
                float2 p = (node.inputs[0] >= 0) ? vIn0 : currentUV;
                vecVal = p * float2(node.params[0], node.params[1]);
                break;
            }
            case OP_DOMAIN_ROTATE: {
                float2 p = (node.inputs[0] >= 0) ? vIn0 : currentUV;
                vecVal = domainRotate(p, node.params[0]);
                break;
            }
            case OP_DOMAIN_WARP: {
                float2 p = (node.inputs[0] >= 0) ? vIn0 : currentUV;
                // Input 1 is the warp field (scalar or vector?)
                // Usually warp field is vector. But if scalar, we can use it for both axes?
                // Let's assume input 1 is a vector field (e.g. from another noise node that outputs vector?)
                // But our noise nodes output scalar.
                // We can construct a vector from two scalars?
                // For now, let's use a simple warp where we sample noise internally or use scalar input as strength?
                // Spec says: x' = x + strength * F(x)
                // If input[1] is connected, it's F(x).
                // If F(x) is scalar, we displace along gradient? Or just (val, val)?
                float warpVal = (node.inputs[1] >= 0) ? results[node.inputs[1]] : 0.0;
                vecVal = p + float2(warpVal, warpVal) * node.params[0];
                break;
            }
        }
        
        results[i] = val;
        vectorResults[i] = vecVal;
    }
    
    // Map final result to color
    // Assume last node is scalar output
    float finalVal = results[nodeCount - 1];
    float3 color = mapToGradient(finalVal, gradient, gradientCount, true); // Loop gradient by default?
    
    output.write(float4(color, 1.0), gid);
}

kernel void fx_procedural_field(
    texture2d<float, access::write> output [[texture(0)]],
    constant FieldParams& params [[buffer(0)]],
    constant GradientStop* gradient [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    float2 resolution = float2(output.get_width(), output.get_height());
    float2 uv = float2(gid) / resolution;
    
    // 1. Domain Operations
    float2 p = uv;
    
    // Scale & Offset
    p = p * params.scale + params.offset;
    
    // Rotation
    if (params.rotation != 0.0) {
        p = domainRotate(p, params.rotation);
    }
    
    // Frequency
    p *= params.frequency;
    
    // Domain Warp
    if (params.domainWarp != 0) {
        // Use low-freq noise for warp
        float2 warpField = float2(
            perlin(p + float2(0.0, 0.0) + params.time * 0.1),
            perlin(p + float2(5.2, 1.3) + params.time * 0.1)
        );
        p = domainWarp(p, params.warpStrength, warpField);
    }
    
    // 2. Field Evaluation
    float value = 0.0;
    
    // SAFETY: Check for NaNs in input coordinates
    if (isnan(p.x) || isnan(p.y) || isinf(p.x) || isinf(p.y)) {
        p = float2(0.0);
    }
    
    switch (params.fieldType) {
        case 0: // Perlin
            value = perlin(p);
            // Remap [-1, 1] -> [0, 1]
            value = value * 0.5 + 0.5;
            break;
        case 1: // Simplex
            value = simplex(p);
            // Remap [-1, 1] -> [0, 1]
            value = value * 0.5 + 0.5;
            break;
        case 2: // Worley
            value = worley(p);
            // Already [0, 1]
            break;
        case 3: // FBM
            value = fbm(p, params.octaves, params.lacunarity, params.gain);
            // Remap [-1, 1] -> [0, 1]
            value = value * 0.5 + 0.5;
            break;
        case 4: // Fire
            {
                // Custom Fire Logic
                // 1. Upward movement & Scale
                float2 fireP = p * float2(1.0, 0.5); // Stretch vertically
                fireP.y -= params.time * 2.5; // Move up faster
                
                // 2. FBM Noise
                float f = fbm(fireP, params.octaves, params.lacunarity, params.gain);
                
                // 3. Shape (Triangle/Flame shape)
                // We need original UV for shaping, but p is transformed.
                // Let's approximate shape using the transformed p if we assume standard domain.
                // Or better, use the 'uv' variable which is available in scope.
                
                float xOffset = uv.x - 0.5;
                float shape = 1.0 - abs(xOffset) * 2.0; // Wider base
                shape = clamp(shape, 0.0, 1.0);
                
                // Fade top
                float fade = smoothstep(1.0, 0.1, uv.y);
                
                // Combine
                value = (f * 0.5 + 0.5) * shape * fade;
                
                // Threshold/Contrast
                value = smoothstep(0.1, 0.8, value);
                value = pow(value, 0.8); // Gamma
            }
            break;
        default:
            value = 0.5;
    }
    
    // SAFETY: Clamp value to valid range to prevent NaNs/Inf propagation
    if (isnan(value) || isinf(value)) {
        value = 0.0;
    }
    value = clamp(value, 0.0, 1.0);
    
    // 3. Color Mapping
    float3 color = mapToGradient(value, gradient, params.colorCount, params.loopGradient != 0);
    
    // Use value as alpha for transparency (Fire/Clouds)
    // For standard noise, this makes dark areas transparent.
    float alpha = value;
    if (params.fieldType == 4) {
        // Fire: use noise value as alpha
        alpha = value;
    } else if (params.fieldType == 3) {
        // FBM Nebula: dark areas (value < 0.3) become transparent to show stars
        alpha = smoothstep(0.0, 0.4, value);
    } else {
        // Other types: fully opaque
        alpha = 1.0;
    }
    
    output.write(float4(color, alpha), gid);
}
