# Shader call-path registry (shipping)

This document maps **who creates each shader node** (feature registry vs compiler vs core helpers), and **how it is bound** at runtime.

## End-to-end call path (golden thread)

Primary path compiled by `TimelineCompiler`:

1. **Clip source**
   - `RenderNode(shader: "source_texture")` for file-based clips
   - `RenderNode(shader: "source_test_color" | "source_linear_ramp" | "fx_macbeth" | "fx_zone_plate" | "fx_starfield" | "fx_smpte_bars")` for `ligm://` clips
2. **IDT to ACEScg** (inserted per clip, before clip effects)
   - `idt_rec709_to_acescg` (non-EXR)
   - `idt_linear_rec709_to_acescg` (EXR)
3. **Clip effects** (compiled from `FeatureRegistry` manifests)
   - Each effect becomes one or more `RenderNode(shader: ...)` via `FeatureManifest.compileNodes(...)`
4. **Compositing** (inserted by compiler when multiple clips overlap)
   - 2 clips: `compositor_crossfade` / `compositor_dip` / `compositor_wipe`
   - 3+ clips: repeated `compositor_alpha_blend`
5. **ODT to display** (always appended)
   - `odt_acescg_to_rec709`

Where it happens:
- Compilation: [Sources/MetaVisSimulation/TimelineCompiler.swift](Sources/MetaVisSimulation/TimelineCompiler.swift)
- Dispatch + binding rules: [Sources/MetaVisSimulation/MetalSimulationEngine.swift](Sources/MetaVisSimulation/MetalSimulationEngine.swift)

## Public feature manifests → shader kernels

These are registered in `StandardFeatures.registerAll()`.

## CompilationDomain (authoritative compatibility label)

Feature manifests now carry an explicit `compilationDomain` value:

- `clip`: safe to compile from `Clip.effects` via `TimelineCompiler.compileEffects(...)` (subject to supported port mapping).
- `scene`: requires graph-level wiring / multi-input bindings / runtime-managed state; **not** compiled as a clip effect today.
- `generator`: produces frames (e.g. `ligm://` sources) and is not a clip effect.
- `transition`: intended for multi-clip operations (not currently emitted from `Clip.effects`).
- `utility`: non-rendering semantics (e.g. intrinsic/audio features) that do not compile into Metal nodes.

Shipping enforcement:
- Registry-load validation rejects `domain: video` manifests claiming `compilationDomain: clip` while declaring unsupported ports.
- `TimelineCompiler.compileEffects(...)` fails fast if a `Clip.effects` manifest has `compilationDomain != clip`.

Format: **Feature ID** → **kernel function(s)** → **Metal source**

- `com.metavis.fx.bloom` → `fx_bloom_composite` → `Sources/MetaVisGraphics/Resources/Bloom.metal`
- `com.metavis.fx.filmgrain` → `fx_film_grain` → `Sources/MetaVisGraphics/Resources/FilmGrain.metal`
- `com.metavis.fx.volumetric` → `fx_volumetric_light` → `Sources/MetaVisGraphics/Resources/Volumetric.metal`
- `com.metavis.fx.vignette` → `fx_vignette_physical` → `Sources/MetaVisGraphics/Resources/Vignette.metal`
- `com.metavis.fx.lens` → `fx_lens_system` → `Sources/MetaVisGraphics/Resources/Lens.metal`
- `com.metavis.fx.tonemap.aces` → `fx_tonemap_aces` → `Sources/MetaVisGraphics/Resources/ToneMapping.metal`
- `com.metavis.fx.tonemap.pq` → `fx_tonemap_pq` → `Sources/MetaVisGraphics/Resources/ToneMapping.metal`
- `com.metavis.fx.lut` → `fx_apply_lut` → `Sources/MetaVisGraphics/Resources/ColorGrading.metal`
- `com.metavis.fx.grade.simple` → `fx_color_grade_simple` → `Sources/MetaVisGraphics/Resources/ColorGrading.metal`
- `com.metavis.fx.false_color.turbo` → `fx_false_color_turbo` → `Sources/MetaVisGraphics/Resources/ColorGrading.metal`
- `com.metavis.fx.blur.gaussian` → `fx_blur_h` + `fx_blur_v` → `Sources/MetaVisGraphics/Resources/Blur.metal`
- `com.metavis.fx.blur.gaussian.h` → `fx_blur_h` → `Sources/MetaVisGraphics/Resources/Blur.metal`
- `com.metavis.fx.blur.gaussian.v` → `fx_blur_v` → `Sources/MetaVisGraphics/Resources/Blur.metal`
- `com.metavis.fx.blur.bokeh` → `fx_bokeh_blur` → `Sources/MetaVisGraphics/Resources/Blur.metal`
- `com.metavis.fx.blur.masked` → `fx_masked_blur` → `Sources/MetaVisGraphics/Resources/MaskedBlur.metal`
- `com.metavis.fx.temporal.accum` → `fx_accumulate` → `Sources/MetaVisGraphics/Resources/Temporal.metal`
- `com.metavis.fx.face.enhance` → `fx_face_enhance` → `Sources/MetaVisGraphics/Resources/FaceEnhance.metal`
- `com.metavis.fx.beauty.enhance` → `fx_beauty_enhance` → `Sources/MetaVisGraphics/Resources/FaceEnhance.metal`
- `com.metavis.fx.lightleak` → `cs_light_leak` → `Sources/MetaVisGraphics/Resources/LightLeak.metal`
- `com.metavis.fx.spectral.dispersion` → `cs_spectral_dispersion` → `Sources/MetaVisGraphics/Resources/SpectralDispersion.metal`
- `com.metavis.fx.anamorphic` → `fx_anamorphic_composite` → `Sources/MetaVisGraphics/Resources/Anamorphic.metal`
- `com.metavis.fx.halation` → `fx_halation_composite` → `Sources/MetaVisGraphics/Resources/Halation.metal`
- `com.metavis.fx.face.mask_gen` → `fx_generate_face_mask` → `Sources/MetaVisGraphics/Resources/FaceMaskGenerator.metal`
- `com.metavis.fx.masked_grade` → `fx_masked_grade` → `Sources/MetaVisGraphics/Resources/MaskedColorGrade.metal`
- `com.metavis.fx.nebula` → `fx_volumetric_nebula` → `Sources/MetaVisGraphics/Resources/VolumetricNebula.metal`

Manifests that are **not clip-compilable today** should be labeled `compilationDomain: scene` (or `generator`/`transition` as appropriate).
Common reasons:

- requires secondary image inputs (e.g. `mask`, `lut`, `depth`, `streaks`)
- requires feedback/state textures (e.g. temporal accumulation)
- generator semantics (writes output directly / not a single-input effect)

Where it happens:
- Feature manifests: [Sources/MetaVisSimulation/Features/StandardFeatures.swift](Sources/MetaVisSimulation/Features/StandardFeatures.swift)
- Port mapping limitation: [Sources/MetaVisSimulation/TimelineCompiler.swift](Sources/MetaVisSimulation/TimelineCompiler.swift)

## TimelineCompiler clip-effect port mapping (shipping)

`TimelineCompiler.compileEffects(...)` currently supports a deliberately small set of input-port semantics for **clip-level** effects.

### Supported input ports (clip-compilable)
- `source`: bound to the current clip image stream (the output of the IDT + prior effects)
- `input`: alias of `source` for manifests that use `input` naming
- `faceMask`: compiler-inserted generator node `fx_generate_face_mask` (driven by `RenderFrameContext.faceRectsByClipID`)

This behavior is implemented in [Sources/MetaVisSimulation/TimelineCompiler.swift](Sources/MetaVisSimulation/TimelineCompiler.swift) and validated by:
- [Tests/MetaVisSimulationTests/Timeline/TimelineCompilerPortMappingTests.swift](Tests/MetaVisSimulationTests/Timeline/TimelineCompilerPortMappingTests.swift)

### Unsupported input ports (NOT clip-compilable today)
Any manifest input port not in the supported set above should be treated as `compilationDomain: scene` until the compiler can source it.

For `Clip.effects`, `TimelineCompiler.compileEffects(...)` now fails fast when `compilationDomain != clip`.

Practically, this means features requiring **secondary images** (e.g. `mask`, `lut`, `depth`, `streaks`, `accum`) are not clip-compilable until we either:
- (A) extend the compiler to source those secondary inputs, or
- (B) treat those features as graph-level nodes wired by a higher-level system (not per-clip effects).

### Intrinsic / non-video features
Features in non-video domains (e.g. `mv.retime`) may affect compilation semantics without compiling to Metal nodes.
Example: `mv.retime` is interpreted by the compiler to adjust procedural generator time.

## StandardFeatures: compilationDomain summary (shipping)

This section is the “shipping truth” for what can be placed in `Clip.effects` and compile successfully.

### `compilationDomain: clip` StandardFeatures
These use only `source`/`input` and/or `faceMask` (where `faceMask` is compiler-synthesized).

- `com.metavis.fx.bloom`
- `com.metavis.fx.filmgrain`
- `com.metavis.fx.vignette`
- `com.metavis.fx.lens`
- `com.metavis.fx.tonemap.aces`
- `com.metavis.fx.tonemap.pq`
- `com.metavis.fx.grade.simple`
- `com.metavis.fx.false_color.turbo`
- `com.metavis.fx.blur.gaussian`
- `com.metavis.fx.blur.gaussian.h`
- `com.metavis.fx.blur.gaussian.v`
- `com.metavis.fx.blur.bokeh`
- `com.metavis.fx.face.enhance` (compiler inserts `fx_generate_face_mask` from `RenderFrameContext`)
- `com.metavis.fx.beauty.enhance`
- `com.metavis.fx.lightleak`
- `com.metavis.fx.spectral.dispersion`

### `compilationDomain: scene` StandardFeatures
These manifests declare ports that the compiler does not currently know how to source at clip scope.

| Feature ID | Unsupported ports | Why it fails as a clip effect | Recommended integration path |
| --- | --- | --- | --- |
| `com.metavis.fx.volumetric` | `depth` | compiler only knows how to provide the primary clip image and optional `faceMask` | **B** (graph-level wiring) until we have a clip-level depth provider |
| `com.metavis.fx.anamorphic` | `streaks` | requires a pre-thresholded secondary texture | **B** (post-stack/graph stage) or **A** (compiler generates streaks) |
| `com.metavis.fx.halation` | `halation` | requires a pre-thresholded secondary texture | **B** (post-stack/graph stage) or **A** (compiler generates halation input) |
| `com.metavis.fx.nebula` | `depth`, `output` | generator/renderer semantics don’t match clip-effect single-output model | **B** (graph-level feature) |
| `com.metavis.fx.blur.masked` | `mask` | requires a mask texture not provided by clip compiler | **A** (add compiler support for mask sourcing) or **B** (graph-level wiring) |
| `com.metavis.fx.lut` | `lut` | requires a 3D LUT texture handle/asset binding | **A** (compiler resolves LUT asset → external input) |
| `com.metavis.fx.temporal.accum` | `accum` | requires feedback/state texture (history) which is not a clip-effect input | **B** (graph/runtime-managed history) |
| `com.metavis.fx.masked_grade` | `mask` | requires a mask texture not provided by clip compiler | **A** (mask sourcing) or **B** (graph-level wiring) |

**Path A (extend compiler):** teach `TimelineCompiler.compileEffects(...)` how to source additional ports (mask/depth/lut/etc.) via explicit providers (similar in spirit to `RenderFrameContext` but for textures/assets).

**Path B (graph-level wiring):** keep `Clip.effects` restricted to simple single-input effects; wire multi-input features at a higher layer that can construct a `RenderGraph` with the right upstream producers.

## Internal kernels (compiler/core/engine-owned)

### TimelineCompiler-owned nodes
- `clear_color` → `Sources/MetaVisGraphics/Resources/ClearColor.metal` (empty timeline)
- `source_texture` → `Sources/MetaVisGraphics/Resources/ColorSpace.metal` (video clip source)
- `source_test_color` → `Sources/MetaVisGraphics/Resources/ColorSpace.metal` (procedural)
- `source_linear_ramp` → `Sources/MetaVisGraphics/Resources/ColorSpace.metal` (procedural)
- `fx_macbeth` → `Sources/MetaVisGraphics/Resources/Macbeth.metal` (procedural)
- `fx_zone_plate` → `Sources/MetaVisGraphics/Resources/ZonePlate.metal` (procedural)
- `fx_starfield` → `Sources/MetaVisGraphics/Resources/StarField.metal` (procedural)
- `fx_smpte_bars` → `Sources/MetaVisGraphics/Resources/SMPTE.metal` (procedural)
- `idt_rec709_to_acescg` → `Sources/MetaVisGraphics/Resources/ColorSpace.metal`
- `idt_linear_rec709_to_acescg` → `Sources/MetaVisGraphics/Resources/ColorSpace.metal`
- `odt_acescg_to_rec709` → `Sources/MetaVisGraphics/Resources/ColorSpace.metal`
- `compositor_crossfade` / `compositor_dip` / `compositor_wipe` / `compositor_alpha_blend` → `Sources/MetaVisGraphics/Resources/Compositor.metal`

### MetaVisCore-owned nodes
- `waveform_monitor` (special multi-pass implementation in engine)
  - Accumulate: `scope_waveform_accumulate` → `Sources/MetaVisGraphics/Resources/ColorSpace.metal`
  - Render: `scope_waveform_render` → `Sources/MetaVisGraphics/Resources/ColorSpace.metal`
  - Node factory: [Sources/MetaVisCore/ShaderDefinitions.swift](Sources/MetaVisCore/ShaderDefinitions.swift)

### Engine-owned/prewarmed utilities
- `rgba_to_bgra` → `Sources/MetaVisGraphics/Resources/FormatConversion.metal`
- `resize_bilinear_rgba16f` → `Sources/MetaVisGraphics/Resources/FormatConversion.metal`
- `source_person_mask` → `Sources/MetaVisGraphics/Resources/MaskSources.metal`

### Reserved / present but not compiler-produced today
- `fx_volumetric_composite` → `Sources/MetaVisGraphics/Resources/VolumetricNebula.metal` (engine has bindings, but compiler doesn’t emit it currently)

## Runtime binding contract (MetalSimulationEngine)

Binding rules implemented in [Sources/MetaVisSimulation/MetalSimulationEngine.swift](Sources/MetaVisSimulation/MetalSimulationEngine.swift):

- **Default**: primary input at `texture(0)`; output at `texture(1)`.
- **Compositors**:
  - Inputs: `clipA/layer1` at `texture(0)`, `clipB/layer2` at `texture(1)`
  - Output: `texture(2)`
  - Extra named inputs (masks, etc) start at `texture(3)`
- **Volumetric nebula**:
  - `fx_volumetric_nebula` binds `depth` at `texture(0)`; output uses default (`texture(1)`) per shader signature.
- **Volumetric composite**:
  - `fx_volumetric_composite` binds `scene` at `texture(0)`, `volumetric` at `texture(1)`, output at `texture(2)`.
- **Face mask generator**:
  - `fx_generate_face_mask` output is `texture(0)`.
- **Extra inputs**:
  - Non-compositor kernels bind extra named inputs starting at `texture(2)`.
  - Keys are stabilized: `mask` / `faceMask` are bound first.
- **Waveform monitor** is a special 2-pass path and does not use the default output convention.

See also: `shader_archtecture/BINDINGS.md` for the broader binding conventions.
