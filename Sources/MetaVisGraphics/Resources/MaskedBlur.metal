#include <metal_stdlib>
using namespace metal;

// MARK: - Masked Blur

kernel void fx_masked_blur(
    texture2d<float, access::sample> inputTexture [[texture(0)]],
    texture2d<float, access::sample> maskTexture [[texture(1)]],
    texture2d<float, access::write> outputTexture [[texture(2)]],
    constant float &blurRadius [[buffer(0)]],
    constant float &maskThreshold [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    float2 texelSize = 1.0 / float2(outputTexture.get_width(), outputTexture.get_height());
    float2 uv = (float2(gid) + 0.5) * texelSize;
    
    float maskValue = maskTexture.sample(s, uv).r;
    
    // If mask > threshold, we blur. Otherwise pass through.
    if (maskValue < maskThreshold) {
        outputTexture.write(inputTexture.sample(s, uv), gid);
        return;
    }
    
    float effectiveRadius = blurRadius * maskValue;
    
    if (effectiveRadius < 1.0) {
       outputTexture.write(inputTexture.sample(s, uv), gid);
       return; 
    }
    
    // Box blur 
    float4 result = float4(0.0);
    float totalWeight = 0.0;
    
    int r = int(ceil(effectiveRadius));
    r = min(r, 64); // Safety limit
    
    for (int y = -r; y <= r; y+=2) { // Step 2 for optimization
        for (int x = -r; x <= r; x+=2) {
            float2 offset = float2(x, y) * texelSize;
            float weight = 1.0; 
            
            // Circular check
            if (length(float2(x,y)) <= effectiveRadius) {
                 result += inputTexture.sample(s, uv + offset) * weight;
                 totalWeight += weight;
            }
        }
    }
    
    if (totalWeight > 0.0) {
        result /= totalWeight;
    }
    
    outputTexture.write(result, gid);
}
