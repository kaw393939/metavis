#include <metal_stdlib>
using namespace metal;

#ifndef CORE_COLOR_METAL
#define CORE_COLOR_METAL

namespace Core {
namespace Color {

    // MARK: - Constants
    
    // Rec.709 Luma Coefficients (Standard sRGB/HDTV)
    constant float3 LumaRec709 = float3(0.2126, 0.7152, 0.0722);
    
    // ACEScg (AP1) Luma Coefficients
    constant float3 LumaACEScg = float3(0.2722287168, 0.6740817658, 0.0536895174);
    
    // MARK: - Color Space Matrices
    // NOTE: Metal uses COLUMN-major storage for float3x3.
    // When constructing with float3x3(float3, float3, float3), each float3 is a COLUMN.
    // For matrix * vector multiplication to work correctly, these matrices are TRANSPOSED
    // from the standard row-major color science notation.
    
    // ACEScg -> Rec.709 (Linear) - TRANSPOSED for Metal column-major storage
    // Standard row-major form: [[1.705, -0.622, -0.083], [-0.130, 1.141, -0.011], [-0.024, -0.129, 1.153]]
    constant float3x3 ACEScg_to_Rec709 = float3x3(
        float3( 1.7050509310, -0.1302564950, -0.0240033570),  // Column 0
        float3(-0.6217921210,  1.1408047740, -0.1289689740),  // Column 1
        float3(-0.0832588100, -0.0105482790,  1.1529723310)   // Column 2
    );

    // ACEScg -> Rec.2020 (Linear) - TRANSPOSED for Metal column-major storage
    // Standard row-major: [[0.6132, 0.3395, 0.0474], [0.0742, 0.9167, 0.0091], [0.0206, 0.1061, 0.8733]]
    constant float3x3 ACEScg_to_Rec2020 = float3x3(
        float3(0.6132, 0.0742, 0.0206),  // Column 0
        float3(0.3395, 0.9167, 0.1061),  // Column 1
        float3(0.0474, 0.0091, 0.8733)   // Column 2
    );

    // MARK: - Utilities
    
    inline float luminance(float3 color, float3 weights = LumaACEScg) {
        return dot(color, weights);
    }

    inline half luminance(half3 color) {
        return dot(color, half3(LumaACEScg));
    }

    // MARK: - Tone Mapping Curves
    
    // Narkowicz ACES Fitted Curve
    // Input: Linear Color (Rec.709 primaries expected for this specific curve fit,
    // but often applied to others for "look")
    inline half3 TonemapACES_Narkowicz(half3 x) {
        half a = 2.51h;
        half b = 0.03h;
        half c = 2.43h;
        half d = 0.59h;
        half e = 0.14h;
        return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0h, 1.0h);
    }
    
    // Overload for float3 compatibility
    inline float3 TonemapACES_Narkowicz(float3 x) {
        return float3(TonemapACES_Narkowicz(half3(x)));
    }


    // ST.2084 (PQ) EOTF Inverse (Linear -> PQ)
    // Input: Linear normalized to 0-1 range (where 1.0 = 10000 nits)
    // NOTE: For canonical PQ encoding, use Core::ColorSpace::LinearNitsToPQ
    inline half3 LinearToPQ(half3 linearColor) {
        half m1 = 2610.0h / 4096.0h * 0.25h;
        half m2 = 2523.0h / 4096.0h * 128.0h;
        half c1 = 3424.0h / 4096.0h;
        half c2 = 2413.0h / 4096.0h * 32.0h;
        half c3 = 2392.0h / 4096.0h * 32.0h;
        
        half3 Y = pow(max(linearColor, 0.0h), m1);
        half3 L = pow((c1 + c2 * Y) / (1.0h + c3 * Y), m2);
        return L;
    }
    
    // Overload for float3 compatibility
    inline float3 LinearToPQ(float3 linearColor) {
        return float3(LinearToPQ(half3(linearColor)));
    }
    
    // MARK: - RGB <-> HSL Conversion
    
    /// Convert RGB to HSL
    /// Input: RGB in 0-1 range
    /// Output: HSL where H is 0-1, S is 0-1, L is 0-1
    inline float3 rgbToHsl(float3 rgb) {
        float maxC = max(rgb.r, max(rgb.g, rgb.b));
        float minC = min(rgb.r, min(rgb.g, rgb.b));
        float delta = maxC - minC;
        
        float3 hsl;
        
        // Lightness
        hsl.z = (maxC + minC) * 0.5;
        
        if (delta < 0.00001) {
            // Achromatic
            hsl.x = 0.0;
            hsl.y = 0.0;
        } else {
            // Saturation
            if (hsl.z < 0.5) {
                hsl.y = delta / (maxC + minC);
            } else {
                hsl.y = delta / (2.0 - maxC - minC);
            }
            
            // Hue
            float3 deltas = (((maxC - rgb) / 6.0) + (delta / 2.0)) / delta;
            
            if (rgb.r == maxC) {
                hsl.x = deltas.b - deltas.g;
            } else if (rgb.g == maxC) {
                hsl.x = (1.0 / 3.0) + deltas.r - deltas.b;
            } else {
                hsl.x = (2.0 / 3.0) + deltas.g - deltas.r;
            }
            
            // Wrap hue to 0-1
            if (hsl.x < 0.0) hsl.x += 1.0;
            if (hsl.x > 1.0) hsl.x -= 1.0;
        }
        
        return hsl;
    }
    
    /// Helper for HSL to RGB conversion
    inline float hueToRgb(float p, float q, float t) {
        if (t < 0.0) t += 1.0;
        if (t > 1.0) t -= 1.0;
        if (t < 1.0 / 6.0) return p + (q - p) * 6.0 * t;
        if (t < 1.0 / 2.0) return q;
        if (t < 2.0 / 3.0) return p + (q - p) * (2.0 / 3.0 - t) * 6.0;
        return p;
    }
    
    /// Convert HSL to RGB
    /// Input: HSL where H is 0-1, S is 0-1, L is 0-1
    /// Output: RGB in 0-1 range
    inline float3 hslToRgb(float3 hsl) {
        float3 rgb;
        
        if (hsl.y < 0.00001) {
            // Achromatic
            rgb = float3(hsl.z);
        } else {
            float q = hsl.z < 0.5 ? hsl.z * (1.0 + hsl.y) : hsl.z + hsl.y - hsl.z * hsl.y;
            float p = 2.0 * hsl.z - q;
            
            rgb.r = hueToRgb(p, q, hsl.x + 1.0 / 3.0);
            rgb.g = hueToRgb(p, q, hsl.x);
            rgb.b = hueToRgb(p, q, hsl.x - 1.0 / 3.0);
        }
        
        return rgb;
    }
    
    // MARK: - RGB <-> HSV Conversion
    
    /// Convert RGB to HSV
    /// Input: RGB in 0-1 range
    /// Output: HSV where H is 0-1, S is 0-1, V is 0-1
    inline float3 rgbToHsv(float3 rgb) {
        float maxC = max(rgb.r, max(rgb.g, rgb.b));
        float minC = min(rgb.r, min(rgb.g, rgb.b));
        float delta = maxC - minC;
        
        float3 hsv;
        hsv.z = maxC;  // Value
        
        if (delta < 0.00001) {
            hsv.x = 0.0;
            hsv.y = 0.0;
        } else {
            hsv.y = delta / maxC;  // Saturation
            
            // Hue
            if (rgb.r == maxC) {
                hsv.x = (rgb.g - rgb.b) / delta;
            } else if (rgb.g == maxC) {
                hsv.x = 2.0 + (rgb.b - rgb.r) / delta;
            } else {
                hsv.x = 4.0 + (rgb.r - rgb.g) / delta;
            }
            
            hsv.x /= 6.0;
            if (hsv.x < 0.0) hsv.x += 1.0;
        }
        
        return hsv;
    }
    
    /// Convert HSV to RGB
    /// Input: HSV where H is 0-1, S is 0-1, V is 0-1
    /// Output: RGB in 0-1 range
    inline float3 hsvToRgb(float3 hsv) {
        if (hsv.y < 0.00001) {
            return float3(hsv.z);
        }
        
        float h = hsv.x * 6.0;
        int i = int(floor(h));
        float f = h - float(i);
        float p = hsv.z * (1.0 - hsv.y);
        float q = hsv.z * (1.0 - hsv.y * f);
        float t = hsv.z * (1.0 - hsv.y * (1.0 - f));
        
        switch (i % 6) {
            case 0: return float3(hsv.z, t, p);
            case 1: return float3(q, hsv.z, p);
            case 2: return float3(p, hsv.z, t);
            case 3: return float3(p, q, hsv.z);
            case 4: return float3(t, p, hsv.z);
            default: return float3(hsv.z, p, q);
        }
    }

} // namespace Color
} // namespace Core

#endif // CORE_COLOR_METAL
