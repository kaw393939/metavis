#include <metal_stdlib>
using namespace metal;

struct AnalysisResult {
    float averageLuminance;
    float variance;
    float minLuminance;
    float maxLuminance;
};

// Simple luminance calculation
float get_luminance(float3 color) {
    return dot(color, float3(0.2126, 0.7152, 0.0722));
}

kernel void analyze_text_background(
    texture2d<float, access::read> background [[texture(0)]],
    device AnalysisResult* result [[buffer(0)]],
    constant float4& region [[buffer(1)]], // x, y, width, height (normalized or pixel?)
    uint2 gid [[thread_position_in_grid]]
) {
    // We'll use a simple parallel reduction or just atomic adds for now?
    // Atomic float is hard in Metal.
    // Better approach: One threadgroup per region, or just one thread that loops?
    // Since the region is small (text box), one thread might be too slow, but a small grid is fine.
    
    // For simplicity in this prototype, let's just sample a grid of points in the region.
    // We'll launch a kernel with fixed size (e.g. 16x16) and sample the region.
    
    // Actually, let's make it simpler:
    // The host code will dispatch (1, 1, 1) and this single thread will loop over the region.
    // It's not efficient for large regions, but for text boxes (e.g. 500x100) it's okay-ish, or we can optimize later.
    // Optimization: Dispatch 8x8 threads, each samples a sub-block, then write to shared memory?
    // Let's stick to a single thread for safety and simplicity first.
    
    if (gid.x > 0 || gid.y > 0) return;
    
    float startX = region.x;
    float startY = region.y;
    float width = region.z;
    float height = region.w;
    
    float sumLum = 0.0;
    float sumSqLum = 0.0;
    float minLum = 1.0;
    float maxLum = 0.0;
    
    int samples = 0;
    
    // Stride for performance (don't sample every pixel)
    int stride = 4;
    
    for (float y = 0; y < height; y += stride) {
        for (float x = 0; x < width; x += stride) {
            uint2 pos = uint2(startX + x, startY + y);
            
            if (pos.x >= background.get_width() || pos.y >= background.get_height()) continue;
            
            float4 color = background.read(pos);
            float lum = get_luminance(color.rgb);
            
            sumLum += lum;
            sumSqLum += lum * lum;
            minLum = min(minLum, lum);
            maxLum = max(maxLum, lum);
            samples++;
        }
    }
    
    if (samples > 0) {
        float avg = sumLum / float(samples);
        float variance = (sumSqLum / float(samples)) - (avg * avg);
        
        result->averageLuminance = avg;
        result->variance = variance;
        result->minLuminance = minLum;
        result->maxLuminance = maxLum;
    } else {
        result->averageLuminance = 0.5;
        result->variance = 0.0;
        result->minLuminance = 0.0;
        result->maxLuminance = 1.0;
    }
}
