# RenderGraph integration (shaders + perception)

This document is the bridge between:

- The **current** runtime graph executor (Swift `RenderGraph` + `MetalSimulationEngine`).
- The **shader plans** in `shader_archtecture/plans/`.
- **Perception** producers in `Sources/MetaVisPerception` (mask/flow/depth/face parts), and how those results become GPU-friendly inputs.

## 1) Current reality (today)

### 1.1 RenderGraph model

- A `RenderGraph` is a DAG of `RenderNode`s.
- Each `RenderNode` names a **Metal kernel** via `shader` and references upstream nodes via `inputs`.
- `RenderNode` can optionally carry an `output` contract (resolution + pixel format).
  - Resolution is honored for per-node allocations.
  - Pixel format is currently conservative: float intermediates remain the default; non-float outputs are only honored for terminal outputs in export-oriented paths.
- The engine can create intermediate textures and already has **in-frame reuse** keyed by descriptor in `MetalSimulationEngine`.

### 1.1.1 Mixed-resolution edge policy (now)

The executor can now run graphs where upstream/downstream nodes output different resolutions.

- `RenderNode.output` defines the **node's output size** (full/half/quarter/fixed).
- When an input texture size does not match the consuming node's output size, the behavior is controlled by `RenderRequest.edgePolicy`:
  - `.autoResizeBilinear` (default): the engine inserts a `resize_bilinear_rgba16f` adapter step on the mismatched edge.
  - `.requireExplicitAdapters`: the engine does not insert adapters; it records a warning and continues.

Notes:

- This policy is intentionally **engine-level** today so existing `TimelineCompiler` output remains valid.
- Some inputs (e.g. masks) are sampled in normalized UV space in current shaders and do not require identical pixel dimensions.

### 1.2 Perception → GPU (what exists)

- `MaskDevice` (Vision) produces `kCVPixelFormatType_OneComponent8` masks.
- `MetalSimulationEngine` already has a path that converts mask `CVPixelBuffer` → `MTLTexture(.r8Unorm)` via `CVMetalTextureCache` (or manual upload fallback).
- `TimelineCompiler` can generate a face rect mask node (`fx_generate_face_mask`) from `RenderFrameContext.faceRectsByClipID`.

## 2) What the definitive refactor should add

The shader plans are written assuming we introduce **explicit render-graph contracts**, so we stop revisiting core architecture.

### 2.1 RenderNode output contracts (needed)

Add a way for a node to declare its output characteristics:

- **Resolution tier**: full / half / quarter / fixed small / mip pyramid
- **Pixel format**: `.rgba16Float` (scene-linear), `.bgra8Unorm` (display/output), `.r8Unorm` (masks), etc.
- **Mip support**: whether the output must be mipmapped (MaskedBlur, bloom pyramids).
- **Lifetime**: reusable transient vs must-persist (temporal history)

Implementation options (pick one):

- Extend `RenderNode` with an optional `output: RenderNodeOutputSpec` (preferred).
- Or encode as standardized parameters (works but is harder to type-check and validate).

### 2.2 Fusion groups (needed)

Define explicit “fusion groups” so we don’t end up with accidental pass sprawl:

- **FinalColor**: grading + vignette + grain + tonemap/ODT (ideally one full-frame pass)
- **LensSystem**: distortion + CA + optional vignette/grain (dependent read + latency hiding)
- **BloomSystem**: downsample pyramid + upsample composite (quarter/half res)
- **VolumetricSystem**: half/quarter res lighting + upscale (MetalFX if available)
- **MaskOps**: mask generation/feathering (often small or mask-res)

### 2.3 Perception as first-class graph inputs (needed)

Treat perception outputs as explicit, cacheable *graph sources* rather than ad-hoc side work.

Recommended set of source nodes:

- `source_person_mask` (already exists): outputs `.r8Unorm` mask.
- `source_flow` (future): outputs flow field (likely `.rg16Float` or `.rg32Float`).
- `source_depth` (future): outputs depth (likely `.r16Float`/`.r32Float`).
- `source_face_parts_mask` (future): outputs semantic face-part masks.

Key constraints:

- **Time alignment**: graph frame time must be passed into perception caches; avoid recomputing expensive inference.
- **Resolution alignment**: perception may run at a smaller “analysis resolution” and be upscaled deterministically.
- **Interop**: prefer IOSurface-backed `CVPixelBuffer` + `CVMetalTextureCache` to avoid copies.

## 3) Per-shader placement map

Each shader plan includes a short “RenderGraph integration” section that points here. This is the authoritative map.

Legend:

- **Tier**: Full / Half / Quarter / Small / Mips
- **Fusion**: FinalColor / LensSystem / BloomSystem / VolumetricSystem / MaskOps / Standalone

### ACES

- Tier: Full
- Fusion: FinalColor
- Notes: IDT/ODT placement is graph-level, not clip-level.

### ToneMapping

- Tier: Full
- Fusion: FinalColor
- Notes: Prefer last full-frame pass if not fused into ODT.

### ColorSpace

- Tier: Full
- Fusion: FinalColor
- Notes: Owns IDT/ODT kernels today.

### ColorGrading

- Tier: Full
- Fusion: FinalColor
- Notes: LUT sampling should be fused with tonemap/ODT when feasible.

### Vignette

- Tier: Full
- Fusion: FinalColor (inline ALU)

### FilmGrain

- Tier: Full
- Fusion: FinalColor (inline ALU)

### Compositor

- Tier: Full
- Fusion: Standalone (candidate for render pipeline / programmable blending later)

### Blur

- Tier: Half/Quarter where allowed; Full when required
- Fusion: BloomSystem / MaskOps / Standalone
- Notes: Prefer MPS blur for primitives.

### MaskedBlur

- Tier: Full
- Fusion: Standalone
- Notes: Requires Mips on source.

### MaskedColorGrade

- Tier: Full
- Fusion: FinalColor (if keyed grading is part of final look) or Standalone
- Notes: Needs stable key math; mask input may come from perception.

### FaceEnhance

- Tier: Full (face ROI)
- Fusion: MaskOps (pre-final)
- Perception: consumes a face mask (either rect-derived today or segmentation later).

### FaceMaskGenerator

- Tier: Full
- Fusion: MaskOps
- Notes: Today: rect-derived mask. Future: replace with perception `source_person_mask` / face parts.

### MaskSources

- Tier: Full
- Fusion: MaskOps
- Notes: `source_person_mask` is the perception bridge.

### Lens

- Tier: Full
- Fusion: LensSystem

### Lens_Optics

- Tier: Full (+ small intermediates for leaks)
- Fusion: LensSystem

### SpectralDispersion

- Tier: Full
- Fusion: LensSystem

### LightLeak

- Tier: Small → Full composite
- Fusion: LensSystem

### Bloom

- Tier: Quarter/Half pyramid
- Fusion: BloomSystem

### Bloom_Glare

- Tier: Quarter/Half pyramid
- Fusion: BloomSystem

### Halation

- Tier: Half/Quarter threshold + Full composite
- Fusion: BloomSystem (or its own “LightEffects” system)

### Anamorphic

- Tier: Half/Quarter threshold + Full composite
- Fusion: BloomSystem

### Volumetric

- Tier: Half/Quarter + upscale
- Fusion: VolumetricSystem

### VolumetricNebula

- Tier: Half/Quarter + composite
- Fusion: VolumetricSystem
- Notes: Early termination + reduced-rate execution are mandatory.

### Temporal

- Tier: Full
- Fusion: Standalone
- Notes: Requires history persistence + motion vectors.

### Compute_QC

- Tier: Full (but reduction output is small)
- Fusion: Standalone
- Notes: Reduction strategy is critical; avoid global atomics.

### FormatConversion

- Tier: Any (commonly Full for export; also used as a mixed-resolution edge adapter)
- Fusion: Standalone (often last step for export)

### Watermark

- Tier: Full
- Fusion: Standalone (export-time)

### ClearColor

- Tier: Full
- Fusion: Standalone

### DepthOne

- Tier: Full
- Fusion: Standalone (debug)

### SMPTE

- Tier: Full
- Fusion: Standalone (debug)

### Macbeth

- Tier: Full
- Fusion: Standalone (debug)

### ZonePlate

- Tier: Full
- Fusion: Standalone (debug)

### StarField

- Tier: Full
- Fusion: Standalone (or fused into VolumetricSystem debug paths)

### Noise

- Tier: N/A (library)
- Fusion: N/A

### Procedural

- Tier: N/A (library)
- Fusion: N/A
