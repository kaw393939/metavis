#include <metal_stdlib>
using namespace metal;

// Macbeth ColorChecker 24 patches (Linear sRGB)
constant float3 patches[24] = {
    float3(0.11, 0.08, 0.06), // Dark Skin
    float3(0.48, 0.36, 0.31), // Light Skin
    float3(0.19, 0.28, 0.45), // Blue Sky
    float3(0.13, 0.17, 0.08), // Foliage
    float3(0.26, 0.25, 0.46), // Blue Flower
    float3(0.26, 0.53, 0.44), // Bluish Green
    float3(0.62, 0.31, 0.06), // Orange
    float3(0.15, 0.17, 0.41), // Purplish Blue
    float3(0.53, 0.12, 0.14), // Moderate Red
    float3(0.18, 0.07, 0.20), // Purple
    float3(0.44, 0.58, 0.10), // Yellow Green
    float3(0.67, 0.48, 0.08), // Orange Yellow
    float3(0.06, 0.08, 0.36), // Blue
    float3(0.14, 0.36, 0.10), // Green
    float3(0.43, 0.06, 0.06), // Red
    float3(0.78, 0.69, 0.08), // Yellow
    float3(0.53, 0.11, 0.34), // Magenta
    float3(0.05, 0.32, 0.46), // Cyan
    float3(0.95, 0.95, 0.95), // White
    float3(0.78, 0.78, 0.78), // Neutral 8
    float3(0.57, 0.57, 0.57), // Neutral 6.5
    float3(0.36, 0.36, 0.36), // Neutral 5
    float3(0.19, 0.19, 0.19), // Neutral 3.5
    float3(0.05, 0.05, 0.05)  // Black
};

kernel void macbeth_generator(
    texture2d<float, access::write> output [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    
    float width = float(output.get_width());
    float height = float(output.get_height());
    
    // 6 columns, 4 rows
    // Calculate UV
    float u = float(gid.x) / width;
    float v = float(gid.y) / height; 
    
    int col = int(u * 6.0);
    int row = int(v * 4.0);
    
    // Clamp
    col = clamp(col, 0, 5);
    row = clamp(row, 0, 3);
    
    int index = row * 6 + col;
    
    float3 color = patches[index];
    
    // Add a black border around patches
    float cellW = width / 6.0;
    float cellH = height / 4.0;
    float localX = float(gid.x) - float(col) * cellW;
    float localY = float(gid.y) - float(row) * cellH;
    
    float border = 10.0; // pixels
    if (localX < border || localX > cellW - border || localY < border || localY > cellH - border) {
        color = float3(0.05, 0.05, 0.05); // Dark gray background
    }
    
    output.write(float4(color, 1.0), gid);
}
