#include <metal_stdlib>
using namespace metal;

struct RegionStats {
    float averageLuminance;
    float variance;
    float minLuminance;
    float maxLuminance;
};

kernel void analyze_region_luminance(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    device RegionStats* stats [[buffer(0)]],
    constant uint4& region [[buffer(1)]], // x, y, width, height
    uint2 gid [[thread_position_in_grid]]
) {
    // Simple parallel reduction would be better, but for a small region (text box),
    // a single thread or small group iterating might be acceptable, 
    // OR we launch threads for the region and use atomics.
    
    // For simplicity in this "Preview" agent, let's assume we launch a grid covering the region
    // and use threadgroup memory for reduction.
    
    // Actually, to keep it very simple and robust without complex reduction logic in this step:
    // We will just sample a grid of points in the region on the CPU or 
    // use a compute shader that runs on a fixed small grid (e.g. 16x16) and samples the underlying texture.
    
    // Let's try a different approach:
    // The CPU will ask for stats. We launch a kernel with 1 threadgroup.
    // The threadgroup size is fixed (e.g. 16x16 = 256 threads).
    // Each thread samples a portion of the region.
    
    // ... On second thought, writing a robust reduction shader from scratch is error-prone.
    // I will use a simpler approach: 
    // Just sample 100 random points in the rect? No, that's noisy.
    // I'll implement a simple "gather" kernel that runs on a single thread (inefficient but safe) 
    // or just use MPSImageStatistics if available in the swift code.
    // Since I can't easily check for MPS availability/linking, I'll write a simple kernel.
}

// A simple kernel that computes stats for a defined rectangle.
// Intended to be dispatched with a single threadgroup of size (1,1,1) for simplicity (very slow)
// OR better: Dispatch (Width/8, Height/8) and output to a texture, then downsample?
//
// Let's go with: "Analyze a specific rect"
// We will launch (1,1,1) and loop. It's bad for GPU parallelism but fine for a few text labels.
kernel void analyze_text_region(
    texture2d<float, access::read> input [[texture(0)]],
    device RegionStats* output [[buffer(0)]],
    constant float4& rect [[buffer(1)]], // x, y, width, height (normalized or pixels)
    uint id [[thread_position_in_grid]]
) {
    if (id > 0) return; // Only thread 0 runs
    
    float sumLum = 0.0;
    float sumSqLum = 0.0;
    float minLum = 1.0;
    float maxLum = 0.0;
    
    uint startX = uint(rect.x);
    uint startY = uint(rect.y);
    uint width = uint(rect.z);
    uint height = uint(rect.w);
    
    // Clamp to texture bounds
    uint texW = input.get_width();
    uint texH = input.get_height();
    
    if (startX >= texW || startY >= texH) {
        return;
    }
    
    uint endX = min(startX + width, texW);
    uint endY = min(startY + height, texH);
    
    // Stride to avoid checking every pixel if large
    uint stride = 4; 
    uint count = 0;
    
    for (uint y = startY; y < endY; y += stride) {
        for (uint x = startX; x < endX; x += stride) {
            float4 color = input.read(uint2(x, y));
            // Rec.709 luminance
            float lum = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
            
            sumLum += lum;
            sumSqLum += lum * lum;
            minLum = min(minLum, lum);
            maxLum = max(maxLum, lum);
            count++;
        }
    }
    
    if (count > 0) {
        output->averageLuminance = sumLum / float(count);
        output->variance = (sumSqLum / float(count)) - (output->averageLuminance * output->averageLuminance);
        
        // DEBUG: Overwrite min/max with debug info
        output->minLuminance = float(count);
        
        // Sample center pixel to verify texture has content
        float4 center = input.read(uint2(texW/2, texH/2));
        output->maxLuminance = center.g; // Green channel of center pixel
    } else {
        output->averageLuminance = 0.5;
        output->variance = 0.0;
        output->minLuminance = -1.0; // Flag for count=0
        output->maxLuminance = -1.0;
    }
}
