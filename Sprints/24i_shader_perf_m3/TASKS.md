# Sprint 24i — Per-shader Tasks (from shader_research)

This file turns `shader_research/Research_*.md` into implementation tasks grounded in the current codebase and test harness.

## How to use this doc
- Each shader section has:
  - **Research signals** (from `shader_research/` and `shader_review/`)
  - **Code anchors** (current files/kernels/engine path)
  - **Tasks** (what we will actually do)
  - **Validation** (how we prove it didn’t regress behavior)

## Shared infrastructure tasks (apply to all)
- [ ] Record baseline numbers in `FINDINGS.md`.
- [ ] For each perf change: capture *before/after* using `RenderPerfTests` (and Xcode GPU Frame Capture when attribution is needed).
- [ ] Keep changes semantics-preserving unless explicitly marked as an allowed approximation.

---

## Research_ACES.md — ACES 1.3 analytical chain
**Research signals**
- Current ACES is “implicit/fitted” and lacks ACES 1.3 sweeteners and Reference Gamut Compression.
- Replace piecewise branches with branchless `select()`.

**Code anchors**
- Research: `../../shader_research/Research_ACES.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/ACES.metal`
- Kernels: *(helper-only; no `kernel void` in this file)* — impacts kernels that include ACES helpers (e.g. `fx_tonemap_aces`, `fx_color_grade_simple`, `fx_masked_grade`)

**Tasks**
- [ ] Implement ACES 1.3 analytical chain (segmented spline), replacing fitted curves where applicable.
- [ ] Add Reference Gamut Compression (RGC) to address saturated artifacts.
- [ ] Replace `if` thresholds with branchless `select()` in ACES helper functions.

**Validation**
- Run `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift` with `METAVIS_PERF_LOG=1` and record before/after.
- Validate downstream export sanity via `Tests/MetaVisExportTests/*` smoke runs that exercise tonemap/ODT.

---

## Research_Anamorphic.md — Horizontal streak optimization
**Research signals**
- Anamorphic streaks are a 1D horizontal blur over thresholded highlights.
- Optimize with threadgroup shared memory for large radii; `simd_shuffle_*` for small radii.

**Code anchors**
- Research: `../../shader_research/Research_Anamorphic.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/Anamorphic.metal`
- Kernels: `fx_anamorphic_threshold`, `fx_anamorphic_composite`

**Tasks**
- [ ] Add a shared-memory horizontal blur path (load row → barrier → shared reads) for wide streak settings.
- [ ] Add a SIMD-lane sharing path for small radii (avoid global re-fetch loops).
- [ ] Keep the external kernel interface stable so graphs/manifests don’t churn.

**Validation**
- Add/extend a glare stack perf graph in `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`.
- Run `Tests/MetaVisSimulationTests/Perf/RenderMemoryPerfTests.swift` to ensure intermediate reuse didn’t regress RSS.

---

## Research_Bloom.md — Dual-filter pyramid
**Research signals**
- Replace large-radius Gaussian with dual-filter (Kawase) pyramid.
- Ensure energy conservation (avoid runaway “adding bloom”).

**Code anchors**
- Research: `../../shader_research/Research_Bloom.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/Bloom.metal`
- Kernels: `fx_bloom_prefilter`, `fx_bloom_threshold`, `fx_bloom_downsample`, `fx_bloom_upsample_blend`, `fx_bloom_composite`

**Tasks**
- [ ] Implement/verify dual-filter pyramid: downsample leveraging linear filtering + upsample tent blend.
- [ ] Confirm pyramid levels are reused via engine texture pooling (avoid per-frame allocations).
- [ ] Add a simple “energy sanity” check: bloom weights do not exceed expected bounds.

**Validation**
- Measure bloom-heavy scenes using `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`.
- Track RSS deltas via `Tests/MetaVisSimulationTests/Perf/RenderMemoryPerfTests.swift`.

---

## Research_Bloom_Glare.md — Bloom/Halation/Anamorphic coordination
**Research signals**
- Bloom, halation, and anamorphic overlap; avoid redundant pyramids/passes.
- Halation should reuse Bloom mips; anamorphic should be horizontal-only and optimized.

**Code anchors**
- Research: `../../shader_research/Research_Bloom_Glare.md`
- Shaders: `../../Sources/MetaVisGraphics/Resources/Bloom.metal`, `../../Sources/MetaVisGraphics/Resources/Halation.metal`, `../../Sources/MetaVisGraphics/Resources/Anamorphic.metal`
- Kernels:
  - Bloom: `fx_bloom_prefilter`, `fx_bloom_threshold`, `fx_bloom_downsample`, `fx_bloom_upsample_blend`, `fx_bloom_composite`
  - Halation: `fx_halation_threshold`, `fx_halation_composite`
  - Anamorphic: `fx_anamorphic_threshold`, `fx_anamorphic_composite`

**Tasks**
- [ ] Rewire halation to sample existing bloom pyramid levels (no standalone blur/pyramid).
- [ ] Ensure the glare “stack” shares intermediates (single pyramid, minimal full-res passes).
- [ ] Document the shared-intermediate strategy and record before/after in `FINDINGS.md`.

**Validation**
- Add a “Bloom → Halation → Anamorphic” perf graph in `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`.
- Ensure export E2E tests that use QC stats still pass: `Tests/MetaVisExportTests/*`.

---

## Research_Blur.md — Prefer MPS Gaussian blur
**Research signals**
- MPS’s Gaussian blur is likely faster than custom MSL on M3; recommendation is to hook MPS.

**Code anchors**
- Research: `../../shader_research/Research_Blur.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/Blur.metal`
- Perf tests: `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`, `Tests/MetaVisSimulationTests/Perf/RenderMemoryPerfTests.swift`
- Kernels: `fx_blur_h`, `fx_blur_v` (plus variants: `fx_bokeh_blur`, `fx_spectral_blur_h`)

**Tasks**
- [ ] Benchmark MPS vs current `fx_blur_h`/`fx_blur_v` at radii used in graphs (include a large-radius case).
- [ ] If MPS wins materially, add an engine fast-path for the generic Gaussian blur feature.
- [ ] Keep custom blur variants (e.g. bokeh/spectral) intact.

**Validation**
- Frame budget perf check via `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`.
- Memory check via `Tests/MetaVisSimulationTests/Perf/RenderMemoryPerfTests.swift`.

---

## Research_ClearColor.md — Prefer render-pass clear
**Research signals**
- Clearing via compute dispatch is inefficient on tile GPUs; prefer `MTLLoadAction.clear`.

**Code anchors**
- Research: `../../shader_research/Research_ClearColor.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/ClearColor.metal`
- Kernels: `clear_color` *(deprecated in engine hot paths; prefer render-pass clear)*
- Engine: `Sources/MetaVisSimulation/MetalSimulationEngine.swift` (render-pass `MTLLoadAction.clear` fast-path)

**Tasks**
- [ ] Identify where `ClearColor.metal` is used in the engine and quantify cost in perf graphs.
- [ ] If a render-pass path exists (or is introduced), replace clear-color compute usage with render attachment loadAction clears.
- [ ] If compute-only remains required, keep the kernel but ensure dispatch only covers the needed region (no over-dispatch).

**Validation**
- Ensure `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift` remains stable for “empty/clear-only” graphs.

---

## Research_ColorGrading.md — LUT sampling + shaper LUT
**Research signals**
- Default to hardware trilinear 3D LUT sampling.
- Avoid per-pixel `log2/exp2` by using a precomputed 1D shaper LUT.
- Tetrahedral interpolation is for final export quality only (higher ALU).

**Code anchors**
- Research: `../../shader_research/Research_ColorGrading.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/ColorGrading.metal`
- Helper: `../../Sources/MetaVisGraphics/LUTHelper.swift`
- Kernels: `fx_color_grade_simple`, `fx_apply_lut`, `fx_false_color_turbo`

**Tasks**
- [ ] Add/verify a 1D shaper LUT path to reduce per-pixel log/exponent math.
- [ ] Confirm default path uses hardware trilinear sampling.
- [ ] (Optional, gated) Add a tetrahedral interpolation path for export-quality mode only.

**Validation**
- Run LUT-heavy perf graphs in `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`.
- Run representative export tests that already validate color stats: `Tests/MetaVisExportTests/*`.

---

## Research_ColorSpace.md — Branchless transfer functions
**Research signals**
- Piecewise EOTF/OETF functions cause divergence; use branchless `select()`.
- Optionally consider minimax polynomial fits; prefer `select()` as the minimal change.

**Code anchors**
- Research: `../../shader_research/Research_ColorSpace.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/ColorSpace.metal`
- Kernels (primary): `idt_rec709_to_acescg`, `odt_acescg_to_rec709`, `idt_linear_rec709_to_acescg` (plus utilities: `exposure_adjust`, `contrast_adjust`, `cdl_correct`, `aces_tonemap`)

**Tasks**
- [ ] Refactor piecewise transfer function branches to branchless `select()` (sRGB/Rec.709/PQ where present).
- [ ] Keep behavior stable; if “fast preview” approximations are introduced, gate behind an existing quality mode.

**Validation**
- Run `Tests/MetaVisExportTests/*` that use `VideoContentQC.validateColorStats` to catch gross transfer regressions.
- Re-run render perf tests for any regression from added math.

---

## Research_Compositor.md — Reduce bandwidth via programmable blending
**Research signals**
- Compute blending is bandwidth bound (read A + read B + write C).
- Tile memory programmable blending in a render pipeline can be 2–4× faster.

**Code anchors**
- Research: `../../shader_research/Research_Compositor.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/Compositor.metal`
- Kernels: `compositor_alpha_blend`, `compositor_crossfade`, `compositor_dip`, `compositor_wipe`, `compositor_multi_layer`

**Tasks**
- [ ] Profile compositor kernels on representative multi-layer graphs; confirm bandwidth-bound behavior.
- [ ] If/when a render pipeline path is viable, migrate the highest-frequency blend modes first (e.g., source-over/crossfade).
- [ ] Keep compute compositor as a fallback path to avoid destabilizing compute-only graphs.

**Validation**
- Re-run transition E2E tests that already validate stats: `Tests/MetaVisExportTests/TransitionDipWipeE2ETests.swift`.
- Track frame budget changes in `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`.

---

## Research_Compute_QC.md — Reduce atomic contention
**Research signals**
- Current per-pixel global atomics are highly contended.
- Use multi-stage reduction: `simd_sum` → threadgroup reduction → one atomic add per group.

**Code anchors**
- Research: `../../shader_research/Research_Compute_QC.md`
- Shader: `../../Sources/MetaVisQC/Resources/QCFingerprint.metal`
- Swift integration: `../../Sources/MetaVisQC/MetalQCFingerprint.swift`, `../../Sources/MetaVisQC/VideoContentQC.swift`
- Kernels: `qc_fingerprint_accumulate_bgra8`, `qc_fingerprint_finalize_16`, `qc_colorstats_accumulate_bgra8`

**Tasks**
- [ ] Rewrite accumulation to reduce atomics using SIMD + threadgroup reduction.
- [ ] Keep output packing stable (`qc_fingerprint_finalize_16` behavior must remain compatible).
- [ ] Consider applying the same reduction approach to histogram accumulation if profiling shows it matters.

**Validation**
- Re-run export tests that depend on QC sampling: `Tests/MetaVisExportTests/*`.
- Add a deterministic QC unit test only if no existing test asserts stable fingerprint behavior.

---

## Research_DepthOne.md — Prefer depth attachment clear
**Research signals**
- Writing depth=1 via compute defeats depth compression; prefer render-pass depth clear.

**Code anchors**
- Research: `../../shader_research/Research_DepthOne.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/DepthOne.metal`
- Kernels: `depth_one` *(deprecated in engine hot paths; prefer depth attachment clear)*
- Engine: `Sources/MetaVisSimulation/MetalSimulationEngine.swift` (depth attachment clear fast-path)

**Tasks**
- [ ] Identify where `DepthOne.metal` is used and quantify whether it appears in perf graphs.
- [ ] If a render depth attachment exists for the path, replace compute writes with a depth loadAction clear (`clearDepth = 1.0`).
- [ ] If compute-only remains required, keep the kernel and avoid any extra work (write-only, minimal dispatch).

**Validation**
- Run perf graphs that include depth+volumetric flows and record before/after in `FINDINGS.md`.

---

## Research_FaceEnhance.md — Guided filter
**Research signals**
- Current bilateral approach is artifact-prone and scales poorly.
- Guided filter is $O(1)$ in radius; MPS provides `MPSImageGuidedFilter`.

**Code anchors**
- Research: `../../shader_research/Research_FaceEnhance.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/FaceEnhance.metal`
- Kernels: `fx_face_enhance`, `fx_beauty_enhance`

**Tasks**
- [ ] Profile face enhance on representative content; identify whether it is ALU or bandwidth bound.
- [ ] Prototype guided filter: prefer MPS guided filter if feasible; otherwise implement separable guided filter building blocks.
- [ ] Keep kernel inputs/outputs stable (avoid rippling graph API changes).

**Validation**
- Add a face-enhance perf graph variant to `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`.
- Ensure export E2E tests still pass if face enhance is used in any recipes.

---

## Research_FaceMaskGenerator.md — Prefer Vision/CoreML segmentation
**Research signals**
- Ellipse-from-rect masks are poor approximations.
- Offload segmentation to Vision (`VNGeneratePersonSegmentationRequest`) on the Neural Engine; keep shader as fallback/visualizer.

**Code anchors**
- Research: `../../shader_research/Research_FaceMaskGenerator.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/FaceMaskGenerator.metal`
- Kernels: `fx_generate_face_mask`

**Tasks**
- [ ] Audit call sites: when do we generate masks procedurally vs receiving masks from perception.
- [ ] Add a bypass path: if an upstream mask texture exists, skip procedural generation.
- [ ] Keep shader as deterministic fallback/debug visualizer (do not delete unless no longer referenced).

**Validation**
- Extend an integration smoke test in export flows if masks are part of recipes.

---

## Research_FilmGrain.md — 3D blue-noise texture
**Research signals**
- Film grain is not Gaussian; target blue-noise with luminance-dependent shaping.
- Prefer small tileable 3D noise texture over ALU-heavy procedural hash.

**Code anchors**
- Research: `../../shader_research/Research_FilmGrain.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/FilmGrain.metal`
- Kernels: `fx_film_grain`

**Tasks**
- [ ] Identify current grain noise source and whether it is ALU heavy.
- [ ] Add a 3D blue-noise texture sampling path (keep ALU fallback).
- [ ] Apply luminance masking (strongest in midtones) per the research guidance.

**Validation**
- Add a grain-heavy perf graph variant to `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`.
- Ensure determinism expectations are documented (grain may be time-varying by design).

---

## Research_FormatConversion.md — Prefer texture views
**Research signals**
- Many conversions are swizzles; `MTLTexture.makeTextureView` can eliminate compute.
- If compute is required, use vectorized `float4/half4` IO.

**Code anchors**
- Research: `../../shader_research/Research_FormatConversion.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/FormatConversion.metal`
- Kernels: `resize_bilinear_rgba16f`, `rgba_to_bgra`

**Tasks**
- [ ] Audit all format conversions in the engine; classify swizzle-only vs true format change.
- [ ] Use texture views for swizzle-only conversions; keep compute only when needed.
- [ ] Ensure compute conversion kernels use vector IO and avoid scalar per-channel ops.

**Validation**
- Run `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift` on graphs known to trigger format conversions.
- Keep an eye on export E2E tests since conversions can impact color stats.

---

## Research_Halation.md — Reuse bloom mips
**Research signals**
- Halation is a tinted blur of highlights; separate blur pass is wasteful.
- Reuse bloom pyramid levels and tint/composite.

**Code anchors**
- Research: `../../shader_research/Research_Halation.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/Halation.metal`
- Kernels: `fx_halation_threshold`, `fx_halation_composite`

**Tasks**
- [ ] Remove/avoid standalone halation blur where bloom pyramid is available.
- [ ] Update halation composite to sample bloom mip level(s) and apply red/orange tint.
- [ ] Ensure bloom+halation ordering is explicit in graphs.

**Validation**
- Use a glare stack perf graph in `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`.
- Ensure transition/export tests still pass.

---

## Research_Lens.md — Distortion + sampling quality
**Research signals**
- Lens distortion is a dependent texture read; sampling quality matters (bicubic suggested).
- Combine lens characteristics (vignette/grain) to hide latency.

**Code anchors**
- Research: `../../shader_research/Research_Lens.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/Lens.metal`
- Kernels: `fx_lens_system`, `fx_lens_distortion_brown_conrady`, `fx_spectral_ca`

**Tasks**
- [ ] Profile `Lens.metal` cost and identify whether quality upgrades (bicubic) are justified.
- [ ] If adding bicubic sampling, gate behind an existing quality mode (avoid affecting preview perf unexpectedly).
- [ ] Consider fusing lightweight lens characteristics in an existing pass only if it reduces full-res bandwidth.

**Validation**
- Add a lens-heavy perf graph in `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`.

---

## Research_Lens_Optics.md — Fuse low-cost optics math
**Research signals**
- Hide dependent-read latency by doing other ALU work before consuming samples.
- Keep spectral dispersion at 3 taps; fuse vignette into tonemap where possible.
- Light leaks should be generated low-res and upscaled.

**Code anchors**
- Research: `../../shader_research/Research_Lens_Optics.md`
- Shaders: `../../Sources/MetaVisGraphics/Resources/Lens.metal`, `../../Sources/MetaVisGraphics/Resources/SpectralDispersion.metal`, `../../Sources/MetaVisGraphics/Resources/Vignette.metal`, `../../Sources/MetaVisGraphics/Resources/LightLeak.metal`
- Kernels:
  - Lens: `fx_lens_system`, `fx_lens_distortion_brown_conrady`, `fx_spectral_ca`
  - SpectralDispersion: `cs_spectral_dispersion`
  - Vignette: `fx_vignette_physical`
  - LightLeak: `cs_light_leak`

**Tasks**
- [ ] Reorder lens ALU work to better hide dependent texture read latency (UV math → other ALU → sample).
- [ ] Ensure dispersion remains 3 taps (no high-sample spectral integration).
- [ ] Implement the vignette fusion into tonemap (see `Research_Vignette.md`) and light leak low-res generation (see `Research_LightLeak.md`).

**Validation**
- Measure pass-count reduction and GPU time in `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`.

---

## Research_LightLeak.md — Low-res generation
**Research signals**
- Light leaks are low-frequency; generate on a small texture then upscale/composite.

**Code anchors**
- Research: `../../shader_research/Research_LightLeak.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/LightLeak.metal`
- Kernels: `cs_light_leak`

**Tasks**
- [ ] Implement low-res intermediate generation (e.g. 256–512 square) for leak synthesis.
- [ ] Upscale during composite using existing resize kernels (avoid new upscalers).
- [ ] Ensure leak behavior is resolution-independent (parameters scale appropriately).

**Validation**
- Add a light-leak perf case at high res in `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`.
- Track memory via `Tests/MetaVisSimulationTests/Perf/RenderMemoryPerfTests.swift`.

---

## Research_Macbeth.md — Constant-table color chart
**Research signals**
- Macbeth patch values should be in ACEScg linear and stored as constants.
- Verify against BabelColor reference.

**Code anchors**
- Research: `../../shader_research/Research_Macbeth.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/Macbeth.metal`
- Kernels: `fx_macbeth`

**Tasks**
- [ ] Verify the patch constants match the intended reference dataset and documented working space.
- [ ] Keep patch table in `constant` address space.
- [ ] Confirm generator mapping and expected output format.

**Validation**
- Add a small deterministic check (sample a few patch pixels) only if generator tests don’t already cover this.

---

## Research_MaskSources.md — Blit vs resample + sampler choice
**Research signals**
- Pure copies should use blit; resamples need correct sampler (nearest vs linear) depending on mask semantics.

**Code anchors**
- Research: `../../shader_research/Research_MaskSources.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/MaskSources.metal`
- Kernels: `source_person_mask` *(prefer non-shader mask generation / blit paths where possible)*

**Tasks**
- [ ] Identify mask operations that are pure copy and route them through `MTLBlitCommandEncoder`.
- [ ] Plumb/select a sampler choice for masks (nearest vs linear) without changing external API shape.
- [ ] Ensure mask textures can stay in compact formats end-to-end when possible.

**Validation**
- Add a tiny mask edge behavior test only if mask semantics require it.

---

## Research_MaskedBlur.md — Mip LOD masked blur
**Research signals**
- Replace per-pixel variable radius loops with mip-level sampling via `level(lod)`.

**Code anchors**
- Research: `../../shader_research/Research_MaskedBlur.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/MaskedBlur.metal`
- Kernels: `fx_masked_blur`

**Tasks**
- [ ] Rewrite masked blur to sample source with explicit `level(lod)` derived from mask.
- [ ] Ensure source texture is mipmapped and mips are generated before the masked blur pass.
- [ ] Keep current loop implementation only as a gated debug/reference path if needed.

**Validation**
- Add/update a masked-blur perf graph in `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`.
- Ensure any existing binding/compiler tests related to masked blur still pass.

---

## Research_MaskedColorGrade.md — Branchless selective grade math
**Research signals**
- Avoid branchy HSV/HSL conversions; use branchless HCV/Lab-like math.
- Blend with `mix()` using mask alpha.

**Code anchors**
- Research: `../../shader_research/Research_MaskedColorGrade.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/MaskedColorGrade.metal`
- Kernels: `fx_masked_grade`

**Tasks**
- [ ] Replace branchy hue/sat conversion paths with branchless math (HCV-style distance recommended).
- [ ] Ensure blend is stable and uses mask alpha via `mix()`.
- [ ] Align sampler semantics with `MaskSources.metal` (nearest vs linear choice).

**Validation**
- Add a masked-grade graph case to `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`.
- If no correctness coverage exists, add a basic invariant test: mask=0 → identity, mask=1 → fully graded.

---

## Research_Noise.md — Precomputed 3D noise
**Research signals**
- Heavy noise (FBM/simplex octaves) is ALU-expensive; prefer small tiling 3D noise texture.

**Code anchors**
- Research: `../../shader_research/Research_Noise.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/Noise.metal`
- Kernels: *(helper-only; no `kernel void` in this file)* — used by shaders that include noise helpers (e.g. volumetric/blur)

**Tasks**
- [ ] Implement a 3D noise texture sampling path for heavy users (keep ALU fallback for lightweight use).
- [ ] Update a known heavy consumer (e.g. `VolumetricNebula.metal`) to use the 3D texture path.
- [ ] Ensure noise helper APIs stay stable for dependent shaders.

**Validation**
- Add a noise-heavy perf scenario in `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`.

---

## Research_Procedural.md — Derivative-based AA
**Research signals**
- Use `fwidth(dist)`-based AA for SDF shapes to remain crisp across resolutions.

**Code anchors**
- Research: `../../shader_research/Research_Procedural.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/Procedural.metal`
- Kernels: *(helper-only; no `kernel void` in this file)* — used by procedural consumers (e.g. volumetric nebula helpers)

**Tasks**
- [ ] Update SDF shape helpers to compute AA width via `fwidth(dist)`.
- [ ] Remove fixed AA constants where they cause resolution dependence.
- [ ] Keep generator outputs deterministic for test charts.

**Validation**
- Visual sanity on procedural charts at multiple resolutions; add a deterministic test only if needed.

---

## Research_SMPTE.md — Constant-table bars
**Research signals**
- Replace branchy region logic with a constant color table index.
- Verify level interpretation (75% vs 100%, PLUGE) and document the encoding/space.

**Code anchors**
- Research: `../../shader_research/Research_SMPTE.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/SMPTE.metal`
- Kernels: `fx_smpte_bars`

**Tasks**
- [ ] Implement/verify bar generation via constant lookup (minimize divergent `if/else`).
- [ ] Verify PLUGE and bar levels and document whether values are Rec.709 encoded or linearized.
- [ ] Keep implementation simple and deterministic.

**Validation**
- Add a small pixel-sample correctness test only if generator tests don’t already cover SMPTE.

---

## Research_SpectralDispersion.md — Keep 3-tap CA
**Research signals**
- Three nearby samples (R/G/B offsets) are the right quality/perf trade; cache locality makes it cheap.
- Bicubic is optional for quality.

**Code anchors**
- Research: `../../shader_research/Research_SpectralDispersion.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/SpectralDispersion.metal`
- Kernels: `cs_spectral_dispersion`

**Tasks**
- [ ] Keep 3-tap approach; ensure offsets are small and stable.
- [ ] If adding higher-quality sampling, gate behind an existing quality mode.

**Validation**
- Include dispersion in a lens/optics perf graph and run `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`.

---

## Research_StarField.md — Spatial hashing
**Research signals**
- Generate stars procedurally using spatial hashing (3×3 neighbor cell search).
- Keep stars-per-cell small to control register pressure.

**Code anchors**
- Research: `../../shader_research/Research_StarField.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/StarField.metal`
- Kernels: `fx_starfield`

**Tasks**
- [ ] Use a deterministic, fast hash (PCG-style) and avoid expensive trig in the inner loop.
- [ ] Clamp stars-per-cell and increase frequency for density instead of increasing per-cell work.
- [ ] Ensure output remains deterministic for a fixed seed/time input.

**Validation**
- Add a generator perf case if starfield shows up in profiling; otherwise keep as correctness guard.

---

## Research_Temporal.md — Velocity reprojection + clamping
**Research signals**
- Temporal accumulation without motion vectors is ineffective.
- Use velocity reprojection and AABB (neighborhood) clamping to prevent ghosting.

**Code anchors**
- Research: `../../shader_research/Research_Temporal.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/Temporal.metal`
- Kernels: `fx_accumulate`, `fx_resolve`

**Tasks**
- [ ] Inventory whether motion vectors exist in the render graph model; if not, scope the smallest viable representation.
- [ ] Implement history reprojection (`uv - velocity`) and add neighborhood/AABB clamp in resolve.
- [ ] Ensure cross-frame resource management is correct (history texture lifetime + fencing).

**Validation**
- Add a minimal multi-frame bench (N frames) and assert bounded memory growth.
- Measure perf impact with `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`.

---

## Research_ToneMapping.md — ACES SSTS
**Research signals**
- Current tonemap is Reinhard; target ACES 1.3 SSTS (segmented spline).
- Analytical spline is ALU-heavy but bandwidth-free.

**Code anchors**
- Research: `../../shader_research/Research_ToneMapping.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/ToneMapping.metal`
- Kernels: `fx_tonemap_aces`, `fx_tonemap_pq`

**Tasks**
- [ ] Replace Reinhard curve with ACES SSTS analytical spline implementation.
- [ ] Ensure tonemap parameters/wiring remain stable.

**Validation**
- Run export E2E tests that validate color stats: `Tests/MetaVisExportTests/*`.
- Re-run render perf tests to ensure no unacceptable ALU regression.

---

## Research_Utilities.md — Keep utility passes branchless and minimal
**Research signals**
- Utilities are mostly bandwidth-bound; avoid unnecessary compute work.
- Watermark branching should be removed when touching it.

**Code anchors**
- Research: `../../shader_research/Research_Utilities.md`
- Shaders: `../../Sources/MetaVisGraphics/Resources/FormatConversion.metal`, `../../Sources/MetaVisGraphics/Resources/Watermark.metal`, `../../Sources/MetaVisGraphics/Resources/MaskSources.metal`
- Kernels:
  - FormatConversion: `resize_bilinear_rgba16f`, `rgba_to_bgra`
  - Watermark: `watermark_diagonal_stripes`
  - MaskSources: `source_person_mask`

**Tasks**
- [ ] Ensure format conversion only runs when layout truly changes; prefer texture views for swizzles.
- [ ] Keep watermark branchless (see `Research_Watermark.md`).
- [ ] Use blit for mask copies where possible (see `Research_MaskSources.md`).

**Validation**
- Re-run perf tests after any engine routing changes.

---

## Research_Vignette.md — Fuse into tonemap
**Research signals**
- Standalone vignette pass is pure bandwidth waste; inline into tone mapping/final pass.

**Code anchors**
- Research: `../../shader_research/Research_Vignette.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/Vignette.metal`
- Related: `../../Sources/MetaVisGraphics/Resources/ToneMapping.metal`
- Kernels: `fx_vignette_physical` (and potential fusion target: `fx_tonemap_aces`)

**Tasks**
- [ ] Measure vignette as a standalone pass (baseline cost).
- [ ] Inline vignette math into tonemap/final-color kernel where feasible; keep standalone kernel as fallback if needed.
- [ ] Ensure vignette is analytic (no texture mask sampling).

**Validation**
- Confirm output invariants: intensity=0 behaves as identity.
- Use `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift` to verify pass-count reduction yields perf gain.

---

## Research_Volumetric.md — Half/quarter res + upscale
**Research signals**
- Radial-blur volumetric lighting is low frequency; render at reduced resolution then upscale.
- Consider MetalFX upscaling when compatible.

**Code anchors**
- Research: `../../shader_research/Research_Volumetric.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/Volumetric.metal`
- Kernels: `fx_volumetric_light`

**Tasks**
- [ ] Implement reduced-resolution execution path (1/2 or 1/4 res) for volumetric.
- [ ] Reuse existing resize kernels (or MetalFX if already integrated) for upscaling.
- [ ] Ensure parameters are resolution-independent.

**Validation**
- Add a volumetric perf case in `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`.
- Track RSS in `Tests/MetaVisSimulationTests/Perf/RenderMemoryPerfTests.swift`.

---

## Research_VolumetricNebula.md — Early termination + effective VRS
**Research signals**
- Raymarching cost dominates; early ray termination is a major win.
- “VRS” intent maps to shading fewer pixels: render at reduced resolution and upscale.

**Code anchors**
- Research: `../../shader_research/Research_VolumetricNebula.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/VolumetricNebula.metal`
- Kernels: `fx_volumetric_nebula`, `fx_volumetric_composite`

**Tasks**
- [ ] Implement/tighten early ray termination once accumulated alpha saturates.
- [ ] Add a reduced-resolution rendering path for nebula (compute half/quarter res, then upscale/composite).
- [ ] Reduce noise cost by switching heavy noise to 3D texture sampling (see `Research_Noise.md`).

**Validation**
- Add a nebula-heavy perf case to `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`.
- Track RSS and ensure no runaway allocations.

---

## Research_Watermark.md — Branchless stripes
**Research signals**
- Refactor stripe selection to branchless `step`/`mix()`; avoid `if`.

**Code anchors**
- Research: `../../shader_research/Research_Watermark.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/Watermark.metal`
- Kernels: `watermark_diagonal_stripes`

**Tasks**
- [ ] Replace branchy stripe logic with `step` + `mix()` based blending.
- [ ] Keep watermark cost negligible relative to frame budget.

**Validation**
- Verify watermark presence in export flows that enable it.
- Confirm no perf regression via `Tests/MetaVisSimulationTests/Perf/RenderPerfTests.swift`.

---

## Research_ZonePlate.md — Preserve precision (test pattern)
**Research signals**
- Zone plate is a diagnostic chart; do not “optimize away” aliasing.
- Preserve `float` precision and pixel-center sampling (`gid + 0.5`).

**Code anchors**
- Research: `../../shader_research/Research_ZonePlate.md`
- Shader: `../../Sources/MetaVisGraphics/Resources/ZonePlate.metal`
- Kernels: `fx_zone_plate`

**Tasks**
- [ ] Confirm implementation preserves pixel-center sampling and float-precision trig.
- [ ] Avoid converting to `half` or approximations that change the diagnostic value.
- [ ] Keep deterministic output for fixed resolution.

**Validation**
- Add a deterministic output hash test only if generator regressions have occurred historically.

