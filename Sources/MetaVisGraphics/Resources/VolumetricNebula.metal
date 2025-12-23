#include <metal_stdlib>
#include "Procedural.metal"
#include "Noise.metal"

using namespace metal;
using namespace Procedural;

// =============================================================================
// VOLUMETRIC NEBULA RAYMARCHER
// =============================================================================

// MARK: - Uniform Structures

struct VolumetricNebulaParams {
    // Camera (each float3 + padding = 16 bytes)
    float3 cameraPosition;
    float _pad0;
    float3 cameraForward;
    float _pad1;
    float3 cameraUp;
    float _pad2;
    float3 cameraRight;
    float _pad3;
    float fov;
    float aspectRatio;
    float _pad4[2]; // Align to 16 bytes
    
    // Volume Bounds (AABB)
    float3 volumeMin;
    float _pad5;
    float3 volumeMax;
    float _pad6;
    
    // Density Field
    float baseFrequency;
    int octaves;
    float lacunarity;
    float gain;
    float densityScale;
    float densityOffset;
    float _pad7[2]; // Align to 16 bytes
    
    // Animation
    float time;
    float _pad8[3]; // Align to 16 bytes
    float3 windVelocity;
    float _pad9;
    
    // Lighting
    float3 lightDirection;
    float _pad10;
    float3 lightColor;
    float ambientIntensity;
    
    // Scattering
    float scatteringCoeff;   // σ_s
    float absorptionCoeff;   // σ_a (extinction = σ_s + σ_a)
    float phaseG;            // Henyey-Greenstein asymmetry (-1 to 1)
    float _pad11;
    
    // Quality
    int maxSteps;
    int shadowSteps;
    float stepSize;
    float _pad12;
    
    // Color
    float3 emissionColorWarm;  // Hot regions (high density)
    float _pad13;
    float3 emissionColorCool;  // Cool regions (low density)
    float _pad14;
    float emissionIntensity;
    float hdrScale;
    float debugMode; // 0=beauty, 1=blue ratio (pre/post), 2=edge width, 3=density pre/post
    float _pad15[2]; // Final alignment
};

struct GradientStop3D {
    float3 color;
    float position;
};

// MARK: - 3D-ish Noise Helpers (built from existing 2D simplex/fbm)

inline float smooth01(float t) {
    // Smoothstep polynomial without explicit threshold parameters.
    t = saturate(t);
    return t * t * (3.0 - 2.0 * t);
}

inline float fbm3(float3 p, int octaves, float lacunarity, float gain) {
    // Combine 2D FBM on three planes with decorrelated offsets.
    float a = Procedural::fbm(p.xy + float2(11.7, -3.1), octaves, lacunarity, gain);
    float b = Procedural::fbm(p.yz + float2(-7.2, 19.4), octaves, lacunarity, gain);
    float c = Procedural::fbm(p.zx + float2(5.9, -13.8), octaves, lacunarity, gain);
    return (a + b + c) * (1.0 / 3.0);
}

inline float3 warp3(float3 p, int octaves, float lacunarity, float gain) {
    // Vector-valued warp from decorrelated FBM samples.
    float wx = fbm3(p + float3(17.0, 3.0, -5.0), octaves, lacunarity, gain);
    float wy = fbm3(p + float3(-2.0, 13.0, 7.0), octaves, lacunarity, gain);
    float wz = fbm3(p + float3(9.0, -11.0, 1.0), octaves, lacunarity, gain);
    return float3(wx, wy, wz);
}

inline float pillarFieldDensity(float3 pos, float cellSize) {
    // Procedural pillar centers in the XZ plane. Deterministic and stable.
    float2 uv = pos.xz / cellSize;
    float2 cell = floor(uv);

    float best = 0.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float2 c = cell + float2(float(i), float(j));
            float2 r2 = Procedural::hash22(c) * 2.0 - 1.0;
            float  r1 = Procedural::hash12(c + float2(7.3, -2.1));

            float2 centerXZ = (c + 0.5 + r2 * 0.35) * cellSize;
            float2 d = pos.xz - centerXZ;
            float dist = length(d);

            // Radius varies per cell; taper upward (pillar silhouette).
            float radius0 = mix(1.1, 2.8, r1);
            float yBase = -7.5;
            float yTop = 5.5;
            float v = saturate((pos.y - yBase) / max(1e-3, (yTop - yBase)));
            float vertical = smooth01(1.0 - v); // strong at base, fades toward top
            float taper = mix(1.0, 0.40, v);
            float radius = radius0 * taper;

            float core = smooth01(1.0 - dist / max(radius, 1e-3));
            float s = core * vertical;

            // Keep the strongest pillar contribution.
            best = max(best, s);
        }
    }
    return best;
}

inline float pillarFieldDensityFast(float3 pos, float cellSize) {
    // Cheaper 2x2 neighborhood approximation (used for gradient estimation).
    float2 uv = pos.xz / cellSize;
    float2 cell = floor(uv);

    float best = 0.0;
    for (int j = 0; j <= 1; j++) {
        for (int i = 0; i <= 1; i++) {
            float2 c = cell + float2(float(i), float(j));
            float2 r2 = Procedural::hash22(c) * 2.0 - 1.0;
            float  r1 = Procedural::hash12(c + float2(7.3, -2.1));

            float2 centerXZ = (c + 0.5 + r2 * 0.30) * cellSize;
            float2 d = pos.xz - centerXZ;
            float dist = length(d);

            float radius0 = mix(1.1, 2.6, r1);
            float yBase = -7.5;
            float yTop = 5.5;
            float v = saturate((pos.y - yBase) / max(1e-3, (yTop - yBase)));
            float vertical = smooth01(1.0 - v);
            float taper = mix(1.0, 0.45, v);
            float radius = radius0 * taper;

            float core = smooth01(1.0 - dist / max(radius, 1e-3));
            best = max(best, core * vertical);
        }
    }
    return best;
}

inline float sampleDensityForGradient(float3 pos, constant VolumetricNebulaParams& params) {
    // A cheaper proxy field for ∇density to avoid GPU stalls (sampleDensity is too expensive for 6x calls/step).
    float3 p = pos * (0.18 * params.baseFrequency);
    float bg = fbm3(p, 3, 2.0, 0.55);
    bg = 0.5 + 0.5 * bg;
    float background = smooth01(bg) * 0.18;

    float pillars = pillarFieldDensityFast(pos, 6.0);
    return (background + pillars);
}

// MARK: - Ray-Box Intersection

// Returns (tNear, tFar) or (-1, -1) if no hit
float2 intersectAABB(float3 rayOrigin, float3 rayDir, float3 boxMin, float3 boxMax) {
    float3 invDir = 1.0 / rayDir;
    float3 t0 = (boxMin - rayOrigin) * invDir;
    float3 t1 = (boxMax - rayOrigin) * invDir;
    
    float3 tmin = min(t0, t1);
    float3 tmax = max(t0, t1);
    
    float tNear = max(max(tmin.x, tmin.y), tmin.z);
    float tFar = min(min(tmax.x, tmax.y), tmax.z);
    
    if (tNear > tFar || tFar < 0.0) {
        return float2(-1.0);
    }
    
    return float2(max(tNear, 0.0), tFar);
}

// MARK: - Density Field

// Helper: Smooth blob falloff
float blobDensity(float3 pos, float3 center, float radius) {
    float d = length(pos - center) / radius;
    if (d > 1.0) return 0.0;
    // Smooth falloff
    float t = 1.0 - d;
    return t * t * (3.0 - 2.0 * t); // smoothstep-like
}

// Sample the nebula density at a world-space position
float sampleDensity(float3 pos, constant VolumetricNebulaParams& params) {
    float3 volumeCenter = (params.volumeMin + params.volumeMax) * 0.5;
    float3 volumeSize = params.volumeMax - params.volumeMin;
    
    // Apply wind animation
    float3 animatedPos = pos + params.windVelocity * params.time;
    
    // === PILLARS-OF-CREATION-LIKE STRUCTURE ===
    // Broad background fog + vertical pillars in XZ with turbulent carving.

    float3 p0 = animatedPos * (0.22 * params.baseFrequency);
    float3 w0 = warp3(p0 + float3(0.0, 0.0, params.time * 0.05), 3, 2.0, 0.55);
    float3 warped0 = animatedPos + (w0 * 2.0 - 1.0) * 0.95;

    // Background: very low frequency “nebula field” so the frame isn't empty.
    float bg = fbm3(warped0 * (0.18 * params.baseFrequency), 4, 2.05, 0.55);
    bg = 0.5 + 0.5 * bg; // [0,1]
    // Keep background present but not filling the whole frame.
    float background = smooth01(bg) * 0.08;

    // Pillars: column field in XZ, tapered with Y.
    float pillars = pillarFieldDensity(warped0, 6.0);

    // Add filament breakup on pillars so they read as dusty sheets.
    float3 p1 = warped0 * (0.95 * params.baseFrequency);
    float n1 = fbm3(p1, 4, params.lacunarity, params.gain);
    float ridge = 1.0 - fabs(n1);
    ridge = ridge * ridge;

    // Carve cavities (holes) into pillars.
    float carve = fbm3(p1 * 1.9 + float3(7.0, -5.0, 11.0), 3, 2.15, 0.50);
    carve = 0.5 + 0.5 * carve;
    float cavity = smooth01(1.0 - carve);

    float pillarDetail = (0.55 + 1.10 * ridge) * (0.55 + 0.45 * cavity);
    float pillarDensity = pillars * pillarDetail;

    // Extra wisps around pillars for that “dust in light” feel.
    float wisp = fbm3(p1 * 1.35 + float3(-9.0, 4.0, 3.0), 3, 2.1, 0.55);
    wisp = 0.5 + 0.5 * wisp;
    float wisps = smooth01(wisp) * pillars * 0.35;

    float totalDensity = background + pillarDensity * 1.30 + wisps * 0.60;
    return max(0.0, totalDensity) * params.densityScale;
}

// MARK: - Phase Function

// Henyey-Greenstein phase function for anisotropic scattering
float phaseHG(float cosTheta, float g) {
    float g2 = g * g;
    float denom = 1.0 + g2 - 2.0 * g * cosTheta;
    return (1.0 - g2) / (4.0 * M_PI_F * pow(denom, 1.5));
}

// MARK: - Shadow Ray

// Compute transmittance along shadow ray to light
float shadowTransmittance(float3 pos, constant VolumetricNebulaParams& params) {
    float3 lightDir = normalize(-params.lightDirection);
    
    // March towards light
    float shadowOpticalDepth = 0.0;
    float shadowStep = params.stepSize * 2.0; // Coarser for performance
    
    for (int i = 0; i < params.shadowSteps; i++) {
        float3 shadowPos = pos + lightDir * shadowStep * float(i + 1);
        
        // Check bounds
        float3 uvw = (shadowPos - params.volumeMin) / (params.volumeMax - params.volumeMin);
        if (any(uvw < 0.0) || any(uvw > 1.0)) break;
        
        float density = sampleDensity(shadowPos, params);
        shadowOpticalDepth += density * (params.scatteringCoeff + params.absorptionCoeff) * shadowStep;
    }
    
    return exp(-shadowOpticalDepth);
}

// MARK: - Main Raymarching Kernel

kernel void fx_volumetric_nebula(
    depth2d<float, access::sample> depthTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant VolumetricNebulaParams& params [[buffer(0)]],
    constant GradientStop3D* colorGradient [[buffer(1)]],
    constant int& gradientCount [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    float2 resolution = float2(outputTexture.get_width(), outputTexture.get_height());
    float2 uv = (float2(gid) + 0.5) / resolution;
    float2 ndc = uv * 2.0 - 1.0;
    
    // Generate camera ray
    float tanHalfFov = tan(params.fov * 0.5 * M_PI_F / 180.0);
    float3 rayDir = normalize(
        params.cameraForward +
        params.cameraRight * ndc.x * tanHalfFov * params.aspectRatio +
        params.cameraUp * ndc.y * tanHalfFov
    );
    
    // Read scene depth for early termination
    constexpr sampler depthS(address::clamp_to_edge, filter::nearest, coord::normalized);
    float sceneDepth = depthTexture.sample(depthS, uv);
    float maxDist = sceneDepth < 1.0 ? sceneDepth * 100.0 : 1e10; // Convert to world units
    
    // Intersect volume AABB
    float2 tHit = intersectAABB(params.cameraPosition, rayDir, params.volumeMin, params.volumeMax);
    
    if (tHit.x < 0.0) {
        // No hit - output transparent
        outputTexture.write(float4(0.0), gid);
        return;
    }
    
    // Clamp to scene depth
    tHit.y = min(tHit.y, maxDist);
    
    // Jitter start position to reduce banding
    float jitter = Core::Noise::interleavedGradientNoise(float2(gid));
    float t = tHit.x + jitter * params.stepSize;
    
    // Accumulation
    float3 accumulatedColor = float3(0.0);
    float transmittance = 1.0;

    float prevDensity = 0.0;
    float maxDensityNorm = 0.0;
    float minEdgeWidth = 1e9;
    float meanDensityPre = 0.0;
    float meanDensityPost = 0.0;
    float densitySamples = 0.0;
    float maxForwardScatter = 0.0;
    float maxScatterLuma = 0.0;
    
    float3 lightDir = normalize(-params.lightDirection);
    
    // Raymarch through volume
    for (int step = 0; step < params.maxSteps && t < tHit.y && transmittance > 0.01; step++) {
        float3 pos = params.cameraPosition + rayDir * t;

        float densityRaw = sampleDensity(pos, params);

        // Continuous low-density gate (no thresholds).
        float density = densityRaw * (densityRaw / (densityRaw + 0.0015));

        float densityDenom = max(params.densityScale, 1e-3);
        float densityNormPre = saturate(density / densityDenom);

        // Approximate ∇density via central differences (required for variable edge width).
        float eps = max(params.stepSize * 0.75, 0.01);
        float dx = sampleDensityForGradient(pos + float3(eps, 0.0, 0.0), params) - sampleDensityForGradient(pos - float3(eps, 0.0, 0.0), params);
        float dy = sampleDensityForGradient(pos + float3(0.0, eps, 0.0), params) - sampleDensityForGradient(pos - float3(0.0, eps, 0.0), params);
        float dz = sampleDensityForGradient(pos + float3(0.0, 0.0, eps), params) - sampleDensityForGradient(pos - float3(0.0, 0.0, eps), params);
        float gradMag = length(float3(dx, dy, dz)) / max(2.0 * eps, 1e-3);

        // B) Edge model (no global thresholds): edge width = f(|∇density|)
        // High gradient -> narrow edge; low gradient -> wide edge.
        float edgeWidth = 1.0 / (1.0 + gradMag * 2.5);
        // Track narrowest edge encountered (high gradient -> narrow).
        minEdgeWidth = min(minEdgeWidth, edgeWidth);

        // Apply width-dependent erosion of low-density boundary.
        float boundaryAtten = densityNormPre / (densityNormPre + edgeWidth * 0.45);
        float densityShaped = density * boundaryAtten;

        // C) Mandatory mid-tone remap: expand 0.30 → 0.60, preserve >0.60, <0.30 unchanged.
        float densityNorm = saturate(densityShaped / densityDenom);
        float densityNormPost = densityNorm;
        if (densityNorm >= 0.30 && densityNorm < 0.60) {
            float u = (densityNorm - 0.30) / 0.30;
            // Logistic S-curve with steeper mid-slope -> perceptually obvious expansion.
            float s = 8.0;
            float a = 1.0 / (1.0 + exp(-s * (u - 0.5)));
            float a0 = 1.0 / (1.0 + exp(-s * (0.0 - 0.5)));
            float a1 = 1.0 / (1.0 + exp(-s * (1.0 - 0.5)));
            float un = (a - a0) / max(1e-6, (a1 - a0));
            densityNormPost = 0.30 + 0.30 * un;
        }
        densityNorm = densityNormPost;

        float densityFinal = densityNorm * densityDenom;

        maxDensityNorm = max(maxDensityNorm, densityNorm);
        meanDensityPre += densityNormPre;
        meanDensityPost += densityNormPost;
        densitySamples += 1.0;

        // Approximate forward-scatter strength (for rim diagnostics).
        float cosTheta = dot(rayDir, lightDir);
        float forward = pow(max(0.0, cosTheta), 6.0);
        maxForwardScatter = max(maxForwardScatter, forward);

        // Extinction coefficient
        // Make dense dust pillars significantly more absorptive (silhouette), while keeping enough scattering for bright rims.
        float d2 = densityNorm * densityNorm;
        float scatteringEff = params.scatteringCoeff * (0.90 + 0.50 * densityNorm);
        float absorptionEff = params.absorptionCoeff * (0.90 + 2.20 * d2);
        float extinction = (scatteringEff + absorptionEff) * densityFinal;

        // Compute in-scattering
        float shadowT = shadowTransmittance(pos, params);

        // Phase function
        float phase = phaseHG(cosTheta, params.phaseG);

        // A) Rim highlight neutralization: force high-scatter highlights toward neutral.
        // We approximate high-scatter with forward dominance and low extinction.
        float lowExt = 1.0 / (1.0 + extinction * 0.35);
        float rim = forward * lowExt;

        float lightLuma = dot(params.lightColor, float3(0.2126, 0.7152, 0.0722));
        float3 lightNeutral = float3(lightLuma);
        float3 lightScatterColor = mix(params.lightColor, lightNeutral, rim);

        // In-scattered light (neutralized at rim)
        float3 inScatter = lightScatterColor * shadowT * phase * scatteringEff * densityFinal;
        float inScatterLuma = dot(inScatter, float3(0.2126, 0.7152, 0.0722));
        maxScatterLuma = max(maxScatterLuma, inScatterLuma);

        // Emission (self-illumination for nebula gas)
        float emissionT = densityNorm;
        float3 emissionColor = mix(params.emissionColorCool, params.emissionColorWarm, emissionT);

        // A) Density-driven chromatic divergence (visible but bounded).
        float divergence = clamp(0.06 * (densityNorm - 0.5), -0.03, 0.03);
        float3 diverged = emissionColor * float3(1.0 + divergence, 1.0, 1.0 - divergence);
        emissionColor = mix(emissionColor, diverged, 0.85);

        // Force highlight chroma toward neutral at very high scatter contribution.
        float eLuma = dot(emissionColor, float3(0.2126, 0.7152, 0.0722));
        float3 eNeutral = float3(eLuma);
        float highlightPull = (inScatterLuma * 6.0) / (1.0 + inScatterLuma * 6.0);
        emissionColor = mix(emissionColor, eNeutral, highlightPull);

        // Dense dust should read darker; bias emission toward lower-density gas.
        float emissionFactor = 0.35 + 0.65 * (1.0 - densityNorm);
        float3 emission = emissionColor * (params.emissionIntensity * emissionFactor) * densityFinal;

        // Ambient contribution
        float3 ambient = params.lightColor * (params.ambientIntensity * 0.95) * densityFinal;

        // Integrate
        float stepTransmittance = exp(-extinction * params.stepSize);
        float3 luminance = (inScatter + emission + ambient);

        // Energy-conserving integration
        float3 integScatter = luminance * (1.0 - stepTransmittance) * params.hdrScale;
        accumulatedColor += transmittance * integScatter;

        transmittance *= stepTransmittance;
        
        t += params.stepSize;
    }
    
    // Output with alpha = 1 - transmittance
    float alpha = 1.0 - transmittance;

    // Enforce 1A) Blue channel dominance hard limit when density is high.
    float3 color = accumulatedColor;
    float sumRGB = max(1e-6, color.r + color.g + color.b);
    float blueRatioBefore = color.b / sumRGB;
    float blueRatioAfter = blueRatioBefore;
    // Use pixel opacity (alpha) as the density proxy for gating.
    if (alpha > 0.40 && blueRatioBefore > 0.65) {
        float targetB = 0.65 * sumRGB;
        float excess = color.b - targetB;
        color.b -= excess;
        color.r += 0.5 * excess;
        color.g += 0.5 * excess;

        float sum2 = max(1e-6, color.r + color.g + color.b);
        blueRatioAfter = color.b / sum2;
    }

    // Debug outputs (required):
    // 1 = Blue energy ratio heatmap (R=pre, G=post)
    // 2 = Edge width visualization (grayscale)
    // 3 = Density pre/post (R=pre mean, G=post mean)
    if (params.debugMode >= 0.5) {
        if (params.debugMode < 1.5) {
            float gate = alpha > 0.40 ? 1.0 : 0.0;
            outputTexture.write(float4(blueRatioBefore * gate, blueRatioAfter * gate, 0.0, 1.0), gid);
            return;
        } else if (params.debugMode < 2.5) {
            float ew = minEdgeWidth;
            // False-color: blue=wide/soft, red=narrow/sharp
            float r = 1.0 - ew;
            float b = ew;
            float g = 0.25 + 0.75 * (1.0 - fabs(ew - 0.5) * 2.0);
            outputTexture.write(float4(r, g, b, 1.0), gid);
            return;
        } else if (params.debugMode < 3.5) {
            float invN = 1.0 / max(1.0, densitySamples);
            float pre = meanDensityPre * invN;
            float post = meanDensityPost * invN;
            outputTexture.write(float4(pre, post, 0.0, 1.0), gid);
            return;
        }
    }

    outputTexture.write(float4(color, alpha), gid);
}

// MARK: - Composite Kernel

// Composite volumetric result over scene
kernel void fx_volumetric_composite(
    texture2d<float, access::read> sceneTexture [[texture(0)]],
    texture2d<float, access::read> volumetricTexture [[texture(1)]],
    texture2d<float, access::write> outputTexture [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }
    
    float4 scene = sceneTexture.read(gid);
    float4 volumetric = volumetricTexture.read(gid);

    // Boundary strength estimate from alpha neighborhood (ties radius to local density/boundary).
    float aC = volumetric.a;
    float aR = volumetricTexture.read(uint2(min(gid.x + 1, outputTexture.get_width() - 1), gid.y)).a;
    float aL = volumetricTexture.read(uint2(max(int(gid.x) - 1, 0), gid.y)).a;
    float aU = volumetricTexture.read(uint2(gid.x, min(gid.y + 1, outputTexture.get_height() - 1))).a;
    float aD = volumetricTexture.read(uint2(gid.x, max(int(gid.y) - 1, 0))).a;
    float gradA = fabs(aR - aL) + fabs(aU - aD);
    float boundary = gradA / (gradA + 0.15);

    float sceneLuma = dot(scene.rgb, float3(0.2126, 0.7152, 0.0722));
    float starMask = sceneLuma / (sceneLuma + 0.08);

    // 4) Star–medium interaction: <5% attenuation + subtle halo near boundaries.
    float atten = 1.0 - 0.05 * starMask * boundary * (0.25 + 0.75 * aC);
    float3 sceneMod = scene.rgb * atten;
    float3 halo = volumetric.rgb * (0.03 * starMask * boundary);

    // Pre-multiplied alpha compositing with interaction
    float3 composited = (volumetric.rgb + halo) + sceneMod * (1.0 - volumetric.a);

    outputTexture.write(float4(composited, 1.0), gid);
}
