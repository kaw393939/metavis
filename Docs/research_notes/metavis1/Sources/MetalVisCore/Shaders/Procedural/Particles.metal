#include <metal_stdlib>
#include "../Core/Noise.metal"

using namespace metal;

// MARK: - Particle System Shaders
// Implements dynamic particle behavior (Turbulence, Buoyancy) in the Vertex Shader
// and physical shading (Blackbody) in the Fragment Shader.

struct ParticleUniforms {
    float4x4 viewProjectionMatrix;
    float4x4 modelMatrix;
    float time;
    float turbulence;      // V6.3
    float temperature;     // V6.3 (Kelvin)
    float emissionRate;    // Used for density/brightness scaling
    float lifetime;
    uint flags;            // Bit 0: Blackbody Enabled
};

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float2 uv       [[attribute(2)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float life; // 0.0 to 1.0
};

// Simple Blackbody Approximation (Kelvin to RGB)
// Valid for 1000K to 10000K
inline float3 blackbody(float temp) {
    float3 color = float3(255.0, 255.0, 255.0);
    float t = temp / 100.0;
    
    // Red
    if (t <= 66.0) {
        color.r = 255.0;
    } else {
        color.r = t - 60.0;
        color.r = 329.698727446 * pow(color.r, -0.1332047592);
    }
    
    // Green
    if (t <= 66.0) {
        color.g = t;
        color.g = 99.4708025861 * log(color.g) - 161.1195681661;
    } else {
        color.g = t - 60.0;
        color.g = 288.1221695283 * pow(color.g, -0.0755148492);
    }
    
    // Blue
    if (t >= 66.0) {
        color.b = 255.0;
    } else {
        if (t <= 19.0) {
            color.b = 0.0;
        } else {
            color.b = t - 10.0;
            color.b = 138.5177312231 * log(color.b) - 305.0447927307;
        }
    }
    
    return clamp(color / 255.0, 0.0, 1.0);
}

vertex VertexOut particle_vertex(
    VertexIn in [[stage_in]],
    constant ParticleUniforms &uniforms [[buffer(1)]],
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]]
) {
    VertexOut out;
    
    float3 pos = in.position;
    
    // 1. Calculate Particle Life/Phase based on ID and Time
    // Each particle has a random offset based on its ID (or position)
    float randomOffset = Core::Noise::hash12(float2(float(vertexID % 1000), 0.0));
    float loopTime = 3.0; // Loop every 3 seconds
    float phase = fmod(uniforms.time + randomOffset * loopTime, loopTime) / loopTime; // 0.0 to 1.0
    
    out.life = phase;
    
    // 2. Apply Buoyancy (Rise up)
    float riseSpeed = 2.0;
    pos.y += phase * riseSpeed;
    
    // 3. Apply Turbulence (Curl Noise)
    // Scale position for noise frequency
    float3 noisePos = pos * 0.5 + float3(0, uniforms.time * 0.5, 0);
    float3 curl = float3(
        Core::Noise::simplex(noisePos.xy),
        0.0, // Keep Y mostly driven by buoyancy
        Core::Noise::simplex(noisePos.yz)
    );
    
    pos += curl * uniforms.turbulence * phase; // Turbulence increases with age
    
    // 4. Transform
    float4 worldPos = uniforms.modelMatrix * float4(pos, 1.0);
    out.position = uniforms.viewProjectionMatrix * worldPos;
    out.uv = in.uv;
    
    // 5. Color Calculation
    float3 baseColor = float3(1.0, 0.8, 0.2); // Default Orange
    
    if ((uniforms.flags & 1) != 0) {
        // Blackbody
        // Cool down as it ages
        float currentTemp = mix(uniforms.temperature, 500.0, phase * phase); // Decay to red/black
        baseColor = blackbody(currentTemp);
    }
    
    // Fade in and out
    float alpha = 1.0;
    // Fade in
    alpha *= smoothstep(0.0, 0.2, phase);
    // Fade out
    alpha *= (1.0 - smoothstep(0.5, 1.0, phase));
    
    out.color = float4(baseColor, alpha);
    
    return out;
}

fragment float4 particle_fragment(
    VertexOut in [[stage_in]],
    texture2d<float> spriteTexture [[texture(0)]]
) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 texColor = spriteTexture.sample(s, in.uv);
    
    // Multiply texture alpha with vertex color alpha
    float alpha = texColor.a * in.color.a;
    
    // Premultiplied Alpha for additive blending usually?
    // Or standard blending. Let's output standard.
    
    return float4(in.color.rgb * texColor.rgb, alpha);
}
