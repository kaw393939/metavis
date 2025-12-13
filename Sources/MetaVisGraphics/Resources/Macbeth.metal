#include <metal_stdlib>
using namespace metal;

// Macbeth ColorChecker Classic (24 patches)
// Values are Linear Reflectance (scene-linear, ACEScg working space)
// Based on actual measured reflectance values from X-Rite/BabelColor
// These will be converted to display via ODT (ACEScg→Rec.709 + gamma)
constant float3 kMacbethColors[24] = {
    float3(0.092, 0.058, 0.042),  // 1. Dark Skin
    float3(0.360, 0.237, 0.187),  // 2. Light Skin
    float3(0.095, 0.132, 0.254),  // 3. Blue Sky
    float3(0.080, 0.119, 0.043),  // 4. Foliage
    float3(0.179, 0.164, 0.353),  // 5. Blue Flower
    float3(0.102, 0.368, 0.301),  // 6. Bluish Green
    float3(0.547, 0.178, 0.032),  // 7. Orange
    float3(0.055, 0.077, 0.245),  // 8. Purplish Blue
    float3(0.392, 0.081, 0.099),  // 9. Moderate Red
    float3(0.081, 0.037, 0.121),  // 10. Purple
    float3(0.360, 0.403, 0.043),  // 11. Yellow Green
    float3(0.624, 0.312, 0.017),  // 12. Orange Yellow
    float3(0.023, 0.036, 0.208),  // 13. Blue
    float3(0.041, 0.231, 0.057),  // 14. Green
    float3(0.310, 0.031, 0.033),  // 15. Red
    float3(0.656, 0.527, 0.022),  // 16. Yellow
    float3(0.372, 0.073, 0.228),  // 17. Magenta
    float3(0.063, 0.271, 0.455),  // 18. Cyan
    float3(0.889, 0.889, 0.889),  // 19. White (90% reflectance)
    float3(0.566, 0.566, 0.566),  // 20. Neutral 8 (59.1%)
    float3(0.351, 0.351, 0.351),  // 21. Neutral 6.5 (36.2%)
    float3(0.187, 0.187, 0.187),  // 22. Neutral 5 (19.8%)
    float3(0.085, 0.085, 0.085),  // 23. Neutral 3.5 (9.0%)
    float3(0.030, 0.030, 0.030)   // 24. Black (3.1%)
};

kernel void fx_macbeth(
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    
    float2 uv = float2(gid) / float2(output.get_width(), output.get_height());
    
    // Grid: 6 columns x 4 rows (standard Macbeth layout)
    int col = int(uv.x * 6.0);
    int row = int(uv.y * 4.0);
    
    // Clamp to valid range
    col = clamp(col, 0, 5);
    row = clamp(row, 0, 3);
    
    int index = row * 6 + col;
    if (index >= 24) index = 23;
    
    float3 color = kMacbethColors[index];
    
    // Add inter-patch border (simulates physical chart)
    float2 uvInCell = fract(float2(uv.x * 6.0, uv.y * 4.0));
    float borderWidth = 0.05;
    if (uvInCell.x < borderWidth || uvInCell.x > (1.0 - borderWidth) ||
        uvInCell.y < borderWidth || uvInCell.y > (1.0 - borderWidth)) {
        color = float3(0.02); // Near-black border (neutral background)
    }
    
    // Output Linear ACEScg (will be converted to display via ODT)
    output.write(float4(color, 1.0), gid);
}
