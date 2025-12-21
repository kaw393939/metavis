#include <metal_stdlib>
using namespace metal;

// Include Core Color System
#include "Shaders/ColorSpace.metal"
#include "Shaders/PostProcessing.metal"

struct VertexIn {
    float4 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut video_plane_vertex(VertexIn in [[stage_in]],
                                  constant float4x4 &modelViewProjection [[buffer(1)]]) {
    VertexOut out;
    out.position = modelViewProjection * in.position;
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 video_plane_fragment(VertexOut in [[stage_in]],
                                   texture2d<float> texture [[texture(0)]],
                                   constant float &opacity [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float4 color = texture.sample(s, in.texCoord);
    return float4(color.rgb, color.a * opacity);
}

struct VolumeVertexOut {
    float4 position [[position]];
    float3 localPosition;
};

vertex VolumeVertexOut volume_vertex(VertexIn in [[stage_in]],
                                     constant float4x4 &modelViewProjection [[buffer(1)]]) {
    VolumeVertexOut out;
    out.position = modelViewProjection * in.position;
    out.localPosition = in.position.xyz + 0.5; // Map -0.5...0.5 to 0.0...1.0
    return out;
}

fragment float4 volume_fragment(VolumeVertexOut in [[stage_in]],
                                texture3d<float> densityTexture [[texture(0)]],
                                constant float &densityScale [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    
    // Simple visualization: Sample the volume at the surface of the cube
    // In a real raymarcher, we would march through the volume.
    float density = densityTexture.sample(s, in.localPosition).r;
    
    // Map density to a color (e.g., orange fire)
    float3 color = float3(1.0, 0.5, 0.1) * density * densityScale;
    return float4(color, density);
}

// --- Diagnostic Kernels ---

// Helper for atomic float min/max
void atomic_min_float(device atomic_uint* atom, float val) {
    uint old = atomic_load_explicit(atom, memory_order_relaxed);
    while (true) {
        float oldVal = as_type<float>(old);
        if (val >= oldVal) break;
        if (atomic_compare_exchange_weak_explicit(atom, &old, as_type<uint>(val), memory_order_relaxed, memory_order_relaxed)) break;
    }
}

void atomic_max_float(device atomic_uint* atom, float val) {
    uint old = atomic_load_explicit(atom, memory_order_relaxed);
    while (true) {
        float oldVal = as_type<float>(old);
        if (val <= oldVal) break;
        if (atomic_compare_exchange_weak_explicit(atom, &old, as_type<uint>(val), memory_order_relaxed, memory_order_relaxed)) break;
    }
}

kernel void FITSMinMaxKernel(texture2d<float, access::read> inTexture [[texture(0)]],
                             device atomic_uint *outMinMax [[buffer(0)]], // [Min, Max]
                             uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= inTexture.get_width() || gid.y >= inTexture.get_height()) return;
    
    float val = inTexture.read(gid).r;
    
    // Skip NaNs for min/max
    if (isnan(val)) return;
    
    atomic_min_float(&outMinMax[0], val);
    atomic_max_float(&outMinMax[1], val);
}

kernel void CompositeMinMaxKernel(texture2d<float, access::read> inTexture [[texture(0)]],
                                  device atomic_uint *outMinMax [[buffer(0)]], // [Min, Max]
                                  uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= inTexture.get_width() || gid.y >= inTexture.get_height()) return;
    
    float4 val4 = inTexture.read(gid);
    // Check max of RGB
    float val = max(max(val4.r, val4.g), val4.b);
    float minV = min(min(val4.r, val4.g), val4.b);
    
    if (isnan(val)) return; 
    
    atomic_min_float(&outMinMax[0], minV);
    atomic_max_float(&outMinMax[1], val);
}

// MARK: - FITS Processing

kernel void fitsToneMap(texture2d<float, access::read> inTexture [[texture(0)]],
                        texture2d<float, access::write> outTexture [[texture(1)]],
                        constant float &gain [[buffer(0)]],
                        constant float &offset [[buffer(1)]],
                        constant float &exposure [[buffer(2)]],
                        uint2 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) { return; }
    
    float4 inColor = inTexture.read(gid);
    float val = inColor.r;
    
    // Simple Asinh Stretch
    // y = asinh( (x - offset) * gain ) / asinh(gain) * exposure
    
    float norm = (val - offset) * gain;
    float stretched = asinh(norm); 
    // Normalize roughly to 0-1 range for a specific gain context, or just keep HDR
    // For visualization, we output the stretched value directly to RGB
    
    // Apply exposure
    val = stretched * exposure;
    
    outTexture.write(float4(val, val, val, 1.0), gid);
}

kernel void fitsComposite(texture2d<float, access::read> redTex [[texture(0)]],
                          texture2d<float, access::read> greenTex [[texture(1)]],
                          texture2d<float, access::read> blueTex [[texture(2)]],
                          texture2d<float, access::write> outTexture [[texture(3)]],
                          constant float &sat [[buffer(0)]],
                          uint2 gid [[thread_position_in_grid]]) {
    
    if (gid.x >= outTexture.get_width() || gid.y >= outTexture.get_height()) { return; }
    
    float r = redTex.read(gid).r;
    float g = greenTex.read(gid).r;
    float b = blueTex.read(gid).r;
    
    // Basic RGB mapping
    float3 color = float3(r, g, b);
    
    // Saturation boos could happen here, keeping it linear for now
    
    outTexture.write(float4(color, 1.0), gid);
}

