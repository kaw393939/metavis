#include <metal_stdlib>
using namespace metal;

struct WaveformParams {
    float4 color;
    uint sampleCount;
    float thickness;
    float amplitude;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Fragment Shader
fragment float4 waveform_fragment(
    VertexOut in [[stage_in]],
    constant float* samples [[buffer(0)]],
    constant WaveformParams& params [[buffer(1)]]
) {
    float2 uv = in.texCoord;
    
    // Map UV.x to sample index
    uint index = uint(uv.x * float(params.sampleCount));
    index = min(index, params.sampleCount - 1);
    
    float sample = samples[index] * params.amplitude;
    
    // Map UV.y (-1 to 1 space relative to center)
    // Assuming UV is 0..1. Center is 0.5.
    float y = (uv.y - 0.5) * 2.0;
    
    // Distance to waveform value
    // We want to draw a vertical bar from 0 to sample
    // Or a line connecting samples (more complex in frag shader)
    // Let's do vertical bars (oscilloscope style)
    
    float intensity = 0.0;
    
    // Check if y is between 0 and sample
    if (sample >= 0) {
        if (y >= 0 && y <= sample) intensity = 1.0;
    } else {
        if (y <= 0 && y >= sample) intensity = 1.0;
    }
    
    return params.color * intensity;
}
