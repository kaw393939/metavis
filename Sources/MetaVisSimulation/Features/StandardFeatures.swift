import Foundation
import MetaVisCore
import simd

/// Defines the standard set of built-in features.
public enum StandardFeatures {
    
    public static let bloom = FeatureManifest(
        id: "com.metavis.fx.bloom",
        version: "2.0.0",
        name: "Cinematic Bloom",
        category: .stylize,
        inputs: [
            PortDefinition(name: "source", type: .image, description: "Input ACEScg Texture")
        ],
        parameters: [
            .float(name: "threshold", min: 0.0, max: 10.0, default: 1.0),
            .float(name: "intensity", min: 0.0, max: 5.0, default: 0.5),
            .float(name: "knee", min: 0.0, max: 1.0, default: 0.1),
            .float(name: "clampMax", min: 10.0, max: 65504.0, default: 100.0)
        ],
        kernelName: "fx_bloom_composite"
    )
    
    public static let filmGrain = FeatureManifest(
        id: "com.metavis.fx.filmgrain",
        version: "1.0.0",
        name: "Film Grain",
        category: .stylize,
        inputs: [
            PortDefinition(name: "source", type: .image)
        ],
        parameters: [
            .float(name: "time", min: 0.0, max: 10000.0, default: 0.0),
            .float(name: "intensity", min: 0.0, max: 1.0, default: 0.1),
            .float(name: "size", min: 0.1, max: 5.0, default: 1.0),
            .float(name: "shadowBoost", min: 0.0, max: 2.0, default: 0.5)
        ],
        kernelName: "fx_film_grain"
    )
    
    public static let volumetricLight = FeatureManifest(
        id: "com.metavis.fx.volumetric",
        version: "1.0.0",
        name: "Volumetric Light",
        category: .stylize,
        inputs: [
            PortDefinition(name: "source", type: .image),
            PortDefinition(name: "depth", type: .image)
        ],
        parameters: [
            // Note: Vector parameters like lightPosition (float2) are mapped to vector3 for now or handled as separate floats?
            // Manifest supports vector3. Let's use vector3 for lightPos (x,y,0).
            .vector3(name: "lightPosition", default: SIMD3<Float>(0.5, 0.5, 0.0)),
            .float(name: "density", min: 0.0, max: 2.0, default: 1.0),
            .float(name: "decay", min: 0.0, max: 1.0, default: 0.95),
            .float(name: "weight", min: 0.0, max: 1.0, default: 0.4),
            .float(name: "exposure", min: 0.0, max: 5.0, default: 1.0),
            .int(name: "samples", min: 10, max: 100, default: 50),
            .float(name: "lightDepth", min: 0.0, max: 1.0, default: 0.0),
            .color(name: "color", default: SIMD4<Float>(1, 1, 1, 1))
        ],
        kernelName: "fx_volumetric_light"
    )
    
    public static let anamorphic = FeatureManifest(
        id: "com.metavis.fx.anamorphic",
        version: "1.0.0",
        name: "Anamorphic Streaks",
        category: .stylize,
        inputs: [
            PortDefinition(name: "source", type: .image),
            PortDefinition(name: "streaks", type: .image, description: "Pre-thresholded streaks")
        ],
        parameters: [
            .float(name: "intensity", min: 0.0, max: 5.0, default: 1.0),
            .vector3(name: "tint", default: SIMD3<Float>(0.0, 0.5, 1.0)) // Cyan default
        ],
        kernelName: "fx_anamorphic_composite"
    )
    
    public static let halation = FeatureManifest(
        id: "com.metavis.fx.halation",
        version: "1.0.0",
        name: "Film Halation",
        category: .stylize,
        inputs: [
            PortDefinition(name: "source", type: .image),
            PortDefinition(name: "halation", type: .image, description: "Pre-thresholded halation")
        ],
        parameters: [
            .float(name: "intensity", min: 0.0, max: 2.0, default: 0.5),
            .float(name: "time", min: 0.0, max: 10000.0, default: 0.0),
            // Radial Falloff (Int) mapped to Float for now or adding Int to Manifest? Manifest has Int.
            // NodeValue uses Int -> Float conversion logic I wrote unless I fix it.
            // Let's use Int in manifest.
            .int(name: "radialFalloff", min: 0, max: 1, default: 1),
            .vector3(name: "tint", default: SIMD3<Float>(1.0, 0.3, 0.1)) // Red-Orange Tint
        ],
        kernelName: "fx_halation_composite"
    )

    public static let vignette = FeatureManifest(
        id: "com.metavis.fx.vignette",
        version: "1.0.0",
        name: "Physical Vignette",
        category: .stylize,
        inputs: [
            PortDefinition(name: "source", type: .image)
        ],
        parameters: [
            .float(name: "sensorWidth", min: 10.0, max: 100.0, default: 36.0), // Full Frame
            .float(name: "focalLength", min: 10.0, max: 200.0, default: 35.0),
            .float(name: "intensity", min: 0.0, max: 1.0, default: 1.0),
            .float(name: "smoothness", min: 0.0, max: 1.0, default: 1.0),
            .float(name: "roundness", min: 0.0, max: 1.0, default: 1.0)
        ],
        kernelName: "fx_vignette_physical"
    )

    public static let lensSystem = FeatureManifest(
        id: "com.metavis.fx.lens",
        version: "1.0.0",
        name: "Lens System",
        category: .stylize,
        inputs: [
            PortDefinition(name: "source", type: .image)
        ],
        parameters: [
            .float(name: "k1", min: -1.0, max: 1.0, default: 0.0),
            .float(name: "k2", min: -1.0, max: 1.0, default: 0.0),
            .float(name: "chromaticAberration", min: 0.0, max: 0.1, default: 0.0)
        ],
        kernelName: "fx_lens_system"
    )

    public static let volumetricNebula = FeatureManifest(
        id: "com.metavis.fx.nebula",
        version: "1.0.0",
        name: "Volumetric Nebula",
        category: .stylize,
        inputs: [
            PortDefinition(name: "depth", type: .image),
            PortDefinition(name: "output", type: .image) // Raymarcher writes to output directly?
            // Kernel signature: depth (read), output (write), params, gradient...
            // RenderNode inputs usually imply 'source' images.
            // This is a GENERATOR or EFFECT that reads depth.
            // Let's assume input[0] is depth.
        ],
        parameters: [
             .vector3(name: "cameraPosition", default: SIMD3<Float>(0, 0, 10)),
             .vector3(name: "cameraForward", default: SIMD3<Float>(0, 0, -1)),
             .vector3(name: "cameraUp", default: SIMD3<Float>(0, 1, 0)),
             .vector3(name: "cameraRight", default: SIMD3<Float>(1, 0, 0)),
             .float(name: "fov", min: 10, max: 120, default: 60),
             .float(name: "aspectRatio", min: 0.1, max: 5.0, default: 1.77),
             
             .vector3(name: "volumeMin", default: SIMD3<Float>(-10, -10, -10)),
             .vector3(name: "volumeMax", default: SIMD3<Float>(10, 10, 10)),
             
             .float(name: "baseFrequency", min: 0.1, max: 5.0, default: 1.0),
             .int(name: "octaves", min: 1, max: 5, default: 3),
             .float(name: "lacunarity", min: 1.0, max: 4.0, default: 2.0),
             .float(name: "gain", min: 0.0, max: 1.0, default: 0.5),
             .float(name: "densityScale", min: 0.0, max: 10.0, default: 1.0),
             .float(name: "densityOffset", min: -1.0, max: 1.0, default: 0.0),
             
             .float(name: "time", min: 0, max: 1000, default: 0),
             .vector3(name: "windVelocity", default: SIMD3<Float>(0.1, 0, 0)),
             
             .vector3(name: "lightDirection", default: SIMD3<Float>(0.5, -0.5, -0.5)),
             .vector3(name: "lightColor", default: SIMD3<Float>(1, 0.9, 0.8)),
             .float(name: "ambientIntensity", min: 0, max: 1.0, default: 0.1),
             
             .float(name: "scatteringCoeff", min: 0, max: 10, default: 1.0),
             .float(name: "absorptionCoeff", min: 0, max: 10, default: 0.1),
             .float(name: "phaseG", min: -1.0, max: 1.0, default: 0.2),
             
             .int(name: "maxSteps", min: 10, max: 200, default: 64),
             .int(name: "shadowSteps", min: 1, max: 20, default: 4),
             .float(name: "stepSize", min: 0.01, max: 1.0, default: 0.1),
             
             .vector3(name: "emissionColorWarm", default: SIMD3<Float>(1.0, 0.4, 0.1)),
             .vector3(name: "emissionColorCool", default: SIMD3<Float>(0.1, 0.2, 0.8)),
             .float(name: "emissionIntensity", min: 0, max: 10, default: 1.0),
             .float(name: "hdrScale", min: 0, max: 10, default: 1.0)
        ],
        kernelName: "fx_volumetric_nebula"
    )

    public static let tonemapACES = FeatureManifest(
        id: "com.metavis.fx.tonemap.aces",
        version: "1.0.0",
        name: "ACES Tone Map (SDR)",
        category: .color,
        inputs: [PortDefinition(name: "source", type: .image)],
        parameters: [.float(name: "exposure", min: -5.0, max: 5.0, default: 0.0)],
        kernelName: "fx_tonemap_aces"
    )

    public static let tonemapPQ = FeatureManifest(
        id: "com.metavis.fx.tonemap.pq",
        version: "1.0.0",
        name: "ST.2084 Tone Map (HDR)",
        category: .color,
        inputs: [PortDefinition(name: "source", type: .image)],
        parameters: [.float(name: "maxNits", min: 100.0, max: 4000.0, default: 1000.0)],
        kernelName: "fx_tonemap_pq"
    )

    public static let applyLUT = FeatureManifest(
        id: "com.metavis.fx.lut",
        version: "1.0.0",
        name: "3D LUT",
        category: .color,
        inputs: [
            PortDefinition(name: "source", type: .image),
            PortDefinition(name: "lut", type: .texture3d)
        ],
        parameters: [.float(name: "intensity", min: 0.0, max: 1.0, default: 1.0)],
        kernelName: "fx_apply_lut"
    )

    public static let colorGradeSimple = FeatureManifest(
        id: "com.metavis.fx.grade.simple",
        version: "1.0.0",
        name: "Basic Color Grade",
        category: .color,
        inputs: [PortDefinition(name: "source", type: .image)],
        parameters: [
            .float(name: "exposure", min: -5.0, max: 5.0, default: 0.0),
            .float(name: "contrast", min: 0.0, max: 2.0, default: 1.0),
            .float(name: "saturation", min: 0.0, max: 2.0, default: 1.0),
            .float(name: "temperature", min: -1.0, max: 1.0, default: 0.0),
            .float(name: "tint", min: -1.0, max: 1.0, default: 0.0)
        ],
        kernelName: "fx_color_grade_simple"
    )

    public static let blurGaussian = FeatureManifest(
        id: "com.metavis.fx.blur.gaussian",
        version: "1.0.0",
        name: "Gaussian Blur",
        category: .blur,
        inputs: [PortDefinition(name: "source", type: .image)],
        parameters: [.float(name: "radius", min: 0.0, max: 100.0, default: 10.0)],
        kernelName: "fx_blur_v",
        passes: [
            FeaturePass(logicalName: "fx_blur_h", function: "fx_blur_h", inputs: ["source"], output: "blur_tmp"),
            FeaturePass(logicalName: "fx_blur_v", function: "fx_blur_v", inputs: ["blur_tmp"], output: "output")
        ]
    )
    
    // We register H and V separate for now as Primitives.
    public static let blurGaussianH = FeatureManifest(
        id: "com.metavis.fx.blur.gaussian.h",
        version: "1.0.0",
        name: "Gaussian Blur H",
        category: .blur,
        inputs: [PortDefinition(name: "source", type: .image)],
        parameters: [.float(name: "radius", min: 0.0, max: 100.0, default: 10.0)],
        kernelName: "fx_blur_h"
    )
    
    public static let blurGaussianV = FeatureManifest(
        id: "com.metavis.fx.blur.gaussian.v",
        version: "1.0.0",
        name: "Gaussian Blur V",
        category: .blur,
        inputs: [PortDefinition(name: "source", type: .image)],
        parameters: [.float(name: "radius", min: 0.0, max: 100.0, default: 10.0)],
        kernelName: "fx_blur_v"
    )

    public static let blurBokeh = FeatureManifest(
        id: "com.metavis.fx.blur.bokeh",
        version: "1.0.0",
        name: "Bokeh Blur",
        category: .blur,
        inputs: [PortDefinition(name: "source", type: .image)],
        parameters: [.float(name: "radius", min: 0.0, max: 100.0, default: 10.0)],
        kernelName: "fx_bokeh_blur"
    )

    public static let blurredMask = FeatureManifest(
        id: "com.metavis.fx.blur.masked",
        version: "1.0.0",
        name: "Masked Blur",
        category: .blur,
        inputs: [
            PortDefinition(name: "source", type: .image),
            PortDefinition(name: "mask", type: .image)
        ],
        parameters: [
            .float(name: "radius", min: 0.0, max: 100.0, default: 10.0),
            .float(name: "threshold", min: 0.0, max: 1.0, default: 0.5)
        ],
        kernelName: "fx_masked_blur"
    )
    
    public static let temporalAccumulate = FeatureManifest(
        id: "com.metavis.fx.temporal.accum",
        version: "1.0.0",
        name: "Temporal Accumulate",
        category: .utility,
        inputs: [
            PortDefinition(name: "source", type: .image),
            PortDefinition(name: "accum", type: .image) // Needs read/write support or distinct input/output
        ],
        parameters: [.float(name: "weight", min: 0.0, max: 1.0, default: 0.1)],
        kernelName: "fx_accumulate"
    )

    public static let faceEnhance = FeatureManifest(
        id: "com.metavis.fx.face.enhance",
        version: "1.0.0",
        name: "Face Enhance",
        category: .specialty,
        inputs: [
            PortDefinition(name: "source", type: .image),
            PortDefinition(name: "faceMask", type: .image) // Requires external mask generation or prior node?
        ],
        parameters: [
            .float(name: "skinSmoothing", min: 0.0, max: 1.0, default: 0.2),
            .float(name: "intensity", min: 0.0, max: 1.0, default: 1.0)
        ],
        kernelName: "fx_face_enhance"
    )
    
    public static let lightLeak = FeatureManifest(
        id: "com.metavis.fx.lightleak",
        version: "1.0.0",
        name: "Light Leak",
        category: .style,
        inputs: [PortDefinition(name: "source", type: .image)],
        parameters: [
            .float(name: "intensity", min: 0.0, max: 1.0, default: 0.5),
            .vector3(name: "tint", default: [1.0, 0.5, 0.2]),
            .float(name: "animation", min: 0.0, max: 10.0, default: 0.0)
        ],
        kernelName: "cs_light_leak"
    )
    
    public static let spectralDispersion = FeatureManifest(
        id: "com.metavis.fx.spectral.dispersion",
        version: "1.0.0",
        name: "Spectral Dispersion",
        category: .style,
        inputs: [PortDefinition(name: "source", type: .image)],
        parameters: [
            .float(name: "intensity", min: 0.0, max: 1.0, default: 0.0),
            .float(name: "spread", min: 0.0, max: 20.0, default: 2.0),
            .vector3(name: "center", default: [0.5, 0.5, 0.0])
        ],
        kernelName: "cs_spectral_dispersion"
    )
    
    public static let faceMaskGenerator = FeatureManifest(
        id: "com.metavis.fx.face.mask_gen",
        version: "1.0.0",
        name: "Face Mask Generator",
        category: .utility,
        inputs: [], // Generator
        parameters: [], // Dynamic parameters (rects) not listed in static manifest usually, or we list them as 'hidden'?
        kernelName: "fx_generate_face_mask"
    )
    
    // Generators (LIGM)
    public static let macbethGenerator = FeatureManifest(
        id: "com.metavis.fx.generator.macbeth",
        version: "1.0.0",
        name: "Macbeth Generator",
        category: .generator,
        inputs: [],
        parameters: [],
        kernelName: "fx_macbeth"
    )

    public static let zonePlateGenerator = FeatureManifest(
        id: "com.metavis.fx.generator.zone_plate",
        version: "1.0.0",
        name: "Zone Plate Generator",
        category: .generator,
        inputs: [],
        parameters: [
             .float(name: "time", min: 0.0, max: 1000.0, default: 0.0)
        ],
        kernelName: "fx_zone_plate"
    )
    
    public static let smpteGenerator = FeatureManifest(
        id: "com.metavis.fx.generator.smpte",
        version: "1.0.0",
        name: "SMPTE Bars Generator",
        category: .generator,
        inputs: [],
        parameters: [],
        kernelName: "fx_smpte_bars"
    )
    
    public static let maskedGrade = FeatureManifest(
        id: "com.metavis.fx.masked_grade",
        version: "1.0.0",
        name: "Masked Color Grade",
        category: .color,
        inputs: [
            PortDefinition(name: "input", type: .image),
            PortDefinition(name: "mask", type: .image) // Segmentation mask or empty for color key
        ],
        parameters: [
            .vector3(name: "targetColor", default: SIMD3<Float>(0,1,0)),
            .float(name: "tolerance", min: 0.0, max: 1.0, default: 0.1),
            .float(name: "softness", min: 0.0, max: 1.0, default: 0.05),
            .float(name: "hueShift", min: -1.0, max: 1.0, default: 0.0),
            .float(name: "mode", min: 0.0, max: 1.0, default: 1.0),
            .float(name: "saturation", min: 0.0, max: 2.0, default: 1.0),
            .float(name: "exposure", min: -5.0, max: 5.0, default: 0.0),
            .float(name: "invertMask", min: 0.0, max: 1.0, default: 0.0)
        ],
        kernelName: "fx_masked_grade"
    )

    public static func registerAll() async {
        await FeatureRegistry.shared.register(bloom)
        await FeatureRegistry.shared.register(filmGrain)
        await FeatureRegistry.shared.register(volumetricLight)
        await FeatureRegistry.shared.register(anamorphic)
        await FeatureRegistry.shared.register(halation)
        await FeatureRegistry.shared.register(vignette)
        await FeatureRegistry.shared.register(lensSystem)
        await FeatureRegistry.shared.register(volumetricNebula)
        await FeatureRegistry.shared.register(tonemapACES)
        await FeatureRegistry.shared.register(tonemapPQ)
        await FeatureRegistry.shared.register(applyLUT)
        await FeatureRegistry.shared.register(colorGradeSimple)
        await FeatureRegistry.shared.register(blurGaussian)
        await FeatureRegistry.shared.register(blurGaussianH)
        await FeatureRegistry.shared.register(blurGaussianV)
        await FeatureRegistry.shared.register(blurBokeh)
        await FeatureRegistry.shared.register(blurredMask)
        await FeatureRegistry.shared.register(temporalAccumulate)
        await FeatureRegistry.shared.register(faceEnhance)
        await FeatureRegistry.shared.register(lightLeak)
        await FeatureRegistry.shared.register(spectralDispersion)
        await FeatureRegistry.shared.register(faceMaskGenerator)
        await FeatureRegistry.shared.register(maskedGrade)
    }
}
