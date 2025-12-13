#include <metal_stdlib>
using namespace metal;

// Standard SMPTE Colors (75% Bars) - Linear Light Values (ACEScg)
// These are scene-linear values representing 75% reflectance
// Will be converted to display via ODT (ACEScg→Rec.709 + gamma)
constant float3 kSMPTE_White = float3(0.75, 0.75, 0.75);     // 75% linear light
constant float3 kSMPTE_Yellow = float3(0.75, 0.75, 0.0);     // 75% linear yellow
constant float3 kSMPTE_Cyan = float3(0.0, 0.75, 0.75);       // 75% linear cyan
constant float3 kSMPTE_Green = float3(0.0, 0.75, 0.0);       // 75% linear green
constant float3 kSMPTE_Magenta = float3(0.75, 0.0, 0.75);    // 75% linear magenta
constant float3 kSMPTE_Red = float3(0.75, 0.0, 0.0);         // 75% linear red
constant float3 kSMPTE_Blue = float3(0.0, 0.0, 0.75);        // 75% linear blue

kernel void fx_smpte_bars(
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) return;
    
    float2 uv = float2(gid) / float2(output.get_width(), output.get_height());
    
    float3 color = float3(0.0);
    
    // Top 2/3: Standard Colors
    if (uv.y < 0.67) {
        if (uv.x < 1.0/7.0) color = kSMPTE_White;
        else if (uv.x < 2.0/7.0) color = kSMPTE_Yellow;
        else if (uv.x < 3.0/7.0) color = kSMPTE_Cyan;
        else if (uv.x < 4.0/7.0) color = kSMPTE_Green;
        else if (uv.x < 5.0/7.0) color = kSMPTE_Magenta;
        else if (uv.x < 6.0/7.0) color = kSMPTE_Red;
        else color = kSMPTE_Blue;
    } 
    // Middle Band: Reverse Blue Bars / Castellation (Simplified)
    else if (uv.y < 0.75) {
        if (uv.x < 1.0/7.0) color = kSMPTE_Blue;
        else if (uv.x < 2.0/7.0) color = float3(0.07); // I-Signal (Approx blackish)
        else if (uv.x < 3.0/7.0) color = kSMPTE_Magenta;
        else if (uv.x < 4.0/7.0) color = float3(0.07);
        else if (uv.x < 5.0/7.0) color = kSMPTE_Cyan;
        else if (uv.x < 6.0/7.0) color = float3(0.07);
        else color = kSMPTE_White;
    }
    // Bottom: Pluge (Simplified)
    else {
        // PLUGE pattern usually in 2nd block
         if (uv.x < 1.0/6.0) color = float3(0.03, 0.1, 0.16); // -I
         else if (uv.x < 2.0/6.0) color = float3(1.0); // 100% White
         else if (uv.x < 3.0/6.0) color = float3(0.2, 0.0, 0.4); // +Q
         else if (uv.x < 4.0/6.0) color = float3(0.05); // Super Black
         else if (uv.x < 5.0/6.0) color = float3(0.0); // Black 0
         else color = float3(0.05); // Super Black
    }
    
    // Output Linear ACEScg (will be converted to display via ODT)
    output.write(float4(color, 1.0), gid);
}
