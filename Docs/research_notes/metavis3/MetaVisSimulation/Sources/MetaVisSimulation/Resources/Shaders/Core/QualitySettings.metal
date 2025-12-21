#include <metal_stdlib>
using namespace metal;

#ifndef CORE_QUALITY_SETTINGS_METAL
#define CORE_QUALITY_SETTINGS_METAL

struct MVQualitySettings {
    uint mode;      // MVQualityMode rawValue

    // Blur / Bloom / Halation / Anamorphic
    float blurBaseRadius;
    float blurMaxRadius;
    uint blurTapCount;
    uint bloomMipLevels;
    float halationRadius;
    uint anamorphicStreakSamples;

    // Volumetric
    uint volumetricSteps;
    float volumetricJitterStrength;

    // Temporal
    uint temporalMaxSamples;
    uint temporalShutterCurve;  // 0: box, 1: Gaussian
    float temporalResponseSpeed;  // for EMA

    // Tone mapping / grading
    uint toneMappingMode;       // 0: ACES, 1: FilmicCustom
    uint gradingLUTResolution;  // 16/32/etc

    // Grain
    float grainResolutionScale;   // 1.0 = full res, 0.5 = half res
    uint grainBlueNoiseEnabled; // 0/1

    // Reserved
    float4 reserved0;
    float4 reserved1;
};

#endif // CORE_QUALITY_SETTINGS_METAL
