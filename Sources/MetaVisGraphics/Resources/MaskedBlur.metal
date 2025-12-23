#include <metal_stdlib>
using namespace metal;

// MARK: - Masked Blur

kernel void fx_masked_blur(
    texture2d<float, access::sample> sharpTexture [[texture(0)]],
    texture2d<float, access::sample> blurryTexture [[texture(1)]],
    texture2d<float, access::sample> maskTexture [[texture(2)]],
    texture2d<float, access::write> outputTexture [[texture(3)]],
    constant float &blurRadius [[buffer(0)]],
    constant float &maskThreshold [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    constexpr sampler s(filter::linear, mip_filter::linear, address::clamp_to_edge, coord::normalized);
    float2 outSize = float2(outputTexture.get_width(), outputTexture.get_height());
    float2 uv = (float2(gid) + 0.5) / outSize;
    
    float maskValue = maskTexture.sample(s, uv).r;
    
    // Fast path: if mask is 0 (Sharp), just sample the sharp texture (LOD 0) and exit.
    // This avoids sampling the blurry texture entirely in sharp regions.
    if (maskValue < maskThreshold) {
        outputTexture.write(sharpTexture.sample(s, uv), gid);
        return;
    }

    // Normalize mask
    float denom = max(1.0 - maskThreshold, 0.000001);
    float m = clamp((maskValue - maskThreshold) / denom, 0.0, 1.0);
    
    // 1. Sample Sharp (High Res)
    float4 sharp = sharpTexture.sample(s, uv);
    
    // 2. Sample Blurry (Low Res Mipmapped)
    // We expect blurryTexture to be downsampled (e.g. half res) and have mips.
    // The blurRadius is relative to the *output* size.
    // Since blurryTexture is smaller, we might need to adjust LOD bias if we wanted perfect matching,
    // but standard trilinear mix works well aesthetically.
    float maxAvailLod = float(max(0u, blurryTexture.get_num_mip_levels() - 1u));
    float desiredMaxLod = clamp(log2(max(blurRadius, 1.0)), 0.0, maxAvailLod);
    float lod = m * desiredMaxLod;
    
    float4 blurred = blurryTexture.sample(s, uv, level(lod));
    
    // 3. Mix
    // When m is low (near sharp), lod is low.
    // But blurryTexture itself is already downsampled!
    // So 'level(0)' of blurryTexture is already 1/2 or 1/4 res.
    // We must mix between 'sharp' and 'blurred' based on m logic,
    // OR we relies on the fact that for small radius, we might want sharp.
    
    // Standard approach: Use the blurry sample, but if m is small, we mix with sharp?
    // The O(1) loop logic was purely Sample(LOD).
    // Now Sample(LOD) happens on a lower-res texture.
    // So if LOD=0, we get the downsampled image (not ideal for sharp).
    // So we should Mix(Sharp, BlurredSample, m).
    
    float4 result = mix(sharp, blurred, m);
    outputTexture.write(result, gid);
}
