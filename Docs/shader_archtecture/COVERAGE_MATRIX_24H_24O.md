# Coverage Matrix — Sprints 24h–24o

This document guarantees coverage of **every shipping shader**, **every shipping graphics manifest**, and **key Swift glue** across the shader sprints 24h–24o.

Legend:
- **Primary sprint**: accountable owner for ensuring the file is fully addressed.
- **Secondary sprint**: may touch the file for cross-cutting work (architecture/perf/fusion), but is not the primary owner.

## Shipping Metal shaders

| File | Primary sprint | Secondary sprint(s) | Plan | Spec |
| --- | --- | --- | --- | --- |
| [Sources/MetaVisGraphics/Resources/ACES.metal](../Sources/MetaVisGraphics/Resources/ACES.metal) | 24k | 24l, 24i | [plans/ACES.md](plans/ACES.md) | [specs/ACES.md](specs/ACES.md) |
| [Sources/MetaVisGraphics/Resources/Anamorphic.metal](../Sources/MetaVisGraphics/Resources/Anamorphic.metal) | 24l | 24i | [plans/Anamorphic.md](plans/Anamorphic.md) | [specs/Anamorphic.md](specs/Anamorphic.md) |
| [Sources/MetaVisGraphics/Resources/Bloom.metal](../Sources/MetaVisGraphics/Resources/Bloom.metal) | 24l | 24o, 24i | [plans/Bloom.md](plans/Bloom.md) | [specs/Bloom.md](specs/Bloom.md) |
| [Sources/MetaVisGraphics/Resources/Blur.metal](../Sources/MetaVisGraphics/Resources/Blur.metal) | 24i | 24l | [plans/Blur.md](plans/Blur.md) | [specs/Blur.md](specs/Blur.md) |
| [Sources/MetaVisGraphics/Resources/ClearColor.metal](../Sources/MetaVisGraphics/Resources/ClearColor.metal) | 24m | 24j | [plans/ClearColor.md](plans/ClearColor.md) | [specs/ClearColor.md](specs/ClearColor.md) |
| [Sources/MetaVisGraphics/Resources/ColorGrading.metal](../Sources/MetaVisGraphics/Resources/ColorGrading.metal) | 24k | 24l, 24i | [plans/ColorGrading.md](plans/ColorGrading.md) | [specs/ColorGrading.md](specs/ColorGrading.md) |
| [Sources/MetaVisGraphics/Resources/ColorSpace.metal](../Sources/MetaVisGraphics/Resources/ColorSpace.metal) | 24k | 24n, 24l, 24i | [plans/ColorSpace.md](plans/ColorSpace.md) | [specs/ColorSpace.md](specs/ColorSpace.md) |
| [Sources/MetaVisGraphics/Resources/Compositor.metal](../Sources/MetaVisGraphics/Resources/Compositor.metal) | 24m | 24j, 24i | [plans/Compositor.md](plans/Compositor.md) | [specs/Compositor.md](specs/Compositor.md) |
| [Sources/MetaVisGraphics/Resources/DepthOne.metal](../Sources/MetaVisGraphics/Resources/DepthOne.metal) | 24m | 24j | [plans/DepthOne.md](plans/DepthOne.md) | [specs/DepthOne.md](specs/DepthOne.md) |
| [Sources/MetaVisGraphics/Resources/FaceEnhance.metal](../Sources/MetaVisGraphics/Resources/FaceEnhance.metal) | 24j | 24i | [plans/FaceEnhance.md](plans/FaceEnhance.md) | [specs/FaceEnhance.md](specs/FaceEnhance.md) |
| [Sources/MetaVisGraphics/Resources/FaceMaskGenerator.metal](../Sources/MetaVisGraphics/Resources/FaceMaskGenerator.metal) | 24j | 24h, 24i | [plans/FaceMaskGenerator.md](plans/FaceMaskGenerator.md) | [specs/FaceMaskGenerator.md](specs/FaceMaskGenerator.md) |
| [Sources/MetaVisGraphics/Resources/FilmGrain.metal](../Sources/MetaVisGraphics/Resources/FilmGrain.metal) | 24l | 24i | [plans/FilmGrain.md](plans/FilmGrain.md) | [specs/FilmGrain.md](specs/FilmGrain.md) |
| [Sources/MetaVisGraphics/Resources/FormatConversion.metal](../Sources/MetaVisGraphics/Resources/FormatConversion.metal) | 24k | 24j, 24i | [plans/FormatConversion.md](plans/FormatConversion.md) | [specs/FormatConversion.md](specs/FormatConversion.md) |
| [Sources/MetaVisGraphics/Resources/Halation.metal](../Sources/MetaVisGraphics/Resources/Halation.metal) | 24l | 24i | [plans/Halation.md](plans/Halation.md) | [specs/Halation.md](specs/Halation.md) |
| [Sources/MetaVisGraphics/Resources/Lens.metal](../Sources/MetaVisGraphics/Resources/Lens.metal) | 24l | 24i | [plans/Lens.md](plans/Lens.md) | [specs/Lens.md](specs/Lens.md) |
| [Sources/MetaVisGraphics/Resources/LightLeak.metal](../Sources/MetaVisGraphics/Resources/LightLeak.metal) | 24l | 24i | [plans/LightLeak.md](plans/LightLeak.md) | [specs/LightLeak.md](specs/LightLeak.md) |
| [Sources/MetaVisGraphics/Resources/Macbeth.metal](../Sources/MetaVisGraphics/Resources/Macbeth.metal) | 24h | 24i | [plans/Macbeth.md](plans/Macbeth.md) | [specs/Macbeth.md](specs/Macbeth.md) |
| [Sources/MetaVisGraphics/Resources/MaskSources.metal](../Sources/MetaVisGraphics/Resources/MaskSources.metal) | 24j | 24h, 24i | [plans/MaskSources.md](plans/MaskSources.md) | [specs/MaskSources.md](specs/MaskSources.md) |
| [Sources/MetaVisGraphics/Resources/MaskedBlur.metal](../Sources/MetaVisGraphics/Resources/MaskedBlur.metal) | 24i | 24l | [plans/MaskedBlur.md](plans/MaskedBlur.md) | [specs/MaskedBlur.md](specs/MaskedBlur.md) |
| [Sources/MetaVisGraphics/Resources/MaskedColorGrade.metal](../Sources/MetaVisGraphics/Resources/MaskedColorGrade.metal) | 24k | 24l, 24i | [plans/MaskedColorGrade.md](plans/MaskedColorGrade.md) | [specs/MaskedColorGrade.md](specs/MaskedColorGrade.md) |
| [Sources/MetaVisGraphics/Resources/Noise.metal](../Sources/MetaVisGraphics/Resources/Noise.metal) | 24i | 24l | [plans/Noise.md](plans/Noise.md) | [specs/Noise.md](specs/Noise.md) |
| [Sources/MetaVisGraphics/Resources/Procedural.metal](../Sources/MetaVisGraphics/Resources/Procedural.metal) | 24h | 24i | [plans/Procedural.md](plans/Procedural.md) | [specs/Procedural.md](specs/Procedural.md) |
| [Sources/MetaVisGraphics/Resources/SMPTE.metal](../Sources/MetaVisGraphics/Resources/SMPTE.metal) | 24h | 24i | [plans/SMPTE.md](plans/SMPTE.md) | [specs/SMPTE.md](specs/SMPTE.md) |
| [Sources/MetaVisGraphics/Resources/SpectralDispersion.metal](../Sources/MetaVisGraphics/Resources/SpectralDispersion.metal) | 24l | 24i | [plans/SpectralDispersion.md](plans/SpectralDispersion.md) | [specs/SpectralDispersion.md](specs/SpectralDispersion.md) |
| [Sources/MetaVisGraphics/Resources/StarField.metal](../Sources/MetaVisGraphics/Resources/StarField.metal) | 24h | 24i | [plans/StarField.md](plans/StarField.md) | [specs/StarField.md](specs/StarField.md) |
| [Sources/MetaVisGraphics/Resources/Temporal.metal](../Sources/MetaVisGraphics/Resources/Temporal.metal) | 24i | 24j | [plans/Temporal.md](plans/Temporal.md) | [specs/Temporal.md](specs/Temporal.md) |
| [Sources/MetaVisGraphics/Resources/ToneMapping.metal](../Sources/MetaVisGraphics/Resources/ToneMapping.metal) | 24k | 24l, 24i | [plans/ToneMapping.md](plans/ToneMapping.md) | [specs/ToneMapping.md](specs/ToneMapping.md) |
| [Sources/MetaVisGraphics/Resources/Vignette.metal](../Sources/MetaVisGraphics/Resources/Vignette.metal) | 24l | 24k, 24i | [plans/Vignette.md](plans/Vignette.md) | [specs/Vignette.md](specs/Vignette.md) |
| [Sources/MetaVisGraphics/Resources/Volumetric.metal](../Sources/MetaVisGraphics/Resources/Volumetric.metal) | 24o | 24j, 24i | [plans/Volumetric.md](plans/Volumetric.md) | [specs/Volumetric.md](specs/Volumetric.md) |
| [Sources/MetaVisGraphics/Resources/VolumetricNebula.metal](../Sources/MetaVisGraphics/Resources/VolumetricNebula.metal) | 24o | 24j, 24i | [plans/VolumetricNebula.md](plans/VolumetricNebula.md) | [specs/VolumetricNebula.md](specs/VolumetricNebula.md) |
| [Sources/MetaVisGraphics/Resources/Watermark.metal](../Sources/MetaVisGraphics/Resources/Watermark.metal) | 24l | 24i | [plans/Watermark.md](plans/Watermark.md) | [specs/Watermark.md](specs/Watermark.md) |
| [Sources/MetaVisGraphics/Resources/ZonePlate.metal](../Sources/MetaVisGraphics/Resources/ZonePlate.metal) | 24h | 24i | [plans/ZonePlate.md](plans/ZonePlate.md) | [specs/ZonePlate.md](specs/ZonePlate.md) |
| [Sources/MetaVisQC/Resources/QCFingerprint.metal](../Sources/MetaVisQC/Resources/QCFingerprint.metal) | 24n | 24i | [plans/Compute_QC.md](plans/Compute_QC.md) | [specs/QCFingerprint.md](specs/QCFingerprint.md) |

## Shipping manifests (Graphics)

| File | Primary sprint | Secondary sprint(s) |
| --- | --- | --- |
| [Sources/MetaVisGraphics/Resources/Manifests/mv.colorGrade.json](../Sources/MetaVisGraphics/Resources/Manifests/mv.colorGrade.json) | 24h | 24k |
| [Sources/MetaVisGraphics/Resources/Manifests/mv.retime.json](../Sources/MetaVisGraphics/Resources/Manifests/mv.retime.json) | 24h | 24i |
| [Sources/MetaVisGraphics/Resources/Manifests/audio.dialogCleanwater.v1.json](../Sources/MetaVisGraphics/Resources/Manifests/audio.dialogCleanwater.v1.json) | 24h | 24i |
| [Sources/MetaVisGraphics/Resources/Manifests/com.metavis.fx.smpte_bars.json](../Sources/MetaVisGraphics/Resources/Manifests/com.metavis.fx.smpte_bars.json) | 24h | 24i |

## Key Swift glue (Graphics)

| File | Primary sprint | Secondary sprint(s) |
| --- | --- | --- |
| [Sources/MetaVisGraphics/GraphicsBundleHelper.swift](../Sources/MetaVisGraphics/GraphicsBundleHelper.swift) | 24h | 24j |
| [Sources/MetaVisGraphics/LUTHelper.swift](../Sources/MetaVisGraphics/LUTHelper.swift) | 24k | 24l |
| [Sources/MetaVisGraphics/Empty.swift](../Sources/MetaVisGraphics/Empty.swift) | 24h |  |

## Key RenderGraph / engine / compiler glue

These files are not exhaustive, but they are the primary integration points for “it compiles and runs” coverage.

| File | Primary sprint | Secondary sprint(s) |
| --- | --- | --- |
| [Sources/MetaVisSimulation/TimelineCompiler.swift](../Sources/MetaVisSimulation/TimelineCompiler.swift) | 24j | 24h |
| [Sources/MetaVisSimulation/MetalSimulationEngine.swift](../Sources/MetaVisSimulation/MetalSimulationEngine.swift) | 24j | 24i |
| [shader_archtecture/REGISTRY.md](REGISTRY.md) | 24h |  |
| [shader_archtecture/RENDER_GRAPH_INTEGRATION.md](RENDER_GRAPH_INTEGRATION.md) | 24j |  |
