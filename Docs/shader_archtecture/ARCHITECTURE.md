# World-class shader architecture plan (Apple M3+)

## 1) Goals

1. **Deterministic, inspectable pipeline**: every shader has a stable name, stable bindings, and a spec.
2. **Low bandwidth, high occupancy** on Apple Silicon (M3+): minimize texture reads/writes; prefer half where safe.
3. **Composable render graph**: effects are expressed as small, testable kernels; multi-pass is explicit.
4. **Color correctness as a “golden thread”**: a consistent working space (ACEScg) and explicit IDT/ODT.

## 2) Shipping modules and responsibilities

### `MetaVisGraphics` (shader library)
- Owns `.metal` sources as SwiftPM resources (`Package.swift` processes `Sources/MetaVisGraphics/Resources`).
- Exposes the resource bundle via `Sources/MetaVisGraphics/GraphicsBundleHelper.swift`.

### `MetaVisSimulation` (production renderer)
- Loads the default Metal library from the `MetaVisGraphics` bundle.
- Falls back (in non-production mode) to concatenated, runtime compilation of a minimal shader set.
- Owns pipeline state caching, dispatch sizing, and *current* binding conventions.

### `MetaVisTimeline` + `MetaVisSimulation/TimelineCompiler`
- Builds the render graph and enforces the “golden thread”:
  - IDT into ACEScg before compositing/effects.
  - ODT back to Rec.709 at the end.

## 3) Layering model (what we want, and what exists today)

### 3.1 “Core” library layer
Files that provide functions/constants used by multiple kernels (ideally no kernels):
- `ACES.metal`, `Noise.metal`, `Procedural.metal`

### 3.2 “Pipeline” kernels layer
Kernels that implement core color/pipeline stages:
- `ColorSpace.metal` (IDT/ODT + scopes + utility transforms)
- `FormatConversion.metal` (format swizzles)

### 3.3 “Effects” kernels layer
Single-purpose kernels (often 1-in/1-out):
- `Blur.metal`, `ColorGrading.metal`, `ToneMapping.metal`, `Vignette.metal`, `FilmGrain.metal`, `Lens.metal`, etc.

### 3.4 “Generators” kernels layer
No-input sources/generators:
- `SMPTE.metal`, `Macbeth.metal`, `ZonePlate.metal`, `StarField.metal`, `DepthOne.metal`

### 3.5 “Compositors” kernels layer
Multi-input compositing kernels:
- `Compositor.metal`

### 3.6 “Specialty / ML-adjacent” kernels layer
Kernels that interact with perception outputs or produce masks:
- `FaceMaskGenerator.metal`, `FaceEnhance.metal`, `MaskedBlur.metal`, `MaskedColorGrade.metal`, `MaskSources.metal`

## 4) Naming, stability, and evolution rules

### 4.1 Kernel naming
- Compute kernels are named with stable, semantic prefixes:
  - `idt_*` / `odt_*` for color IO transforms.
  - `fx_*` for effects.
  - `compositor_*` for compositors.
  - `scope_*` for scopes.
- These names are referenced in:
  - `TimelineCompiler` and feature manifests.
  - `MetalSimulationEngine` PSO cache and dispatch.

### 4.2 Binding compatibility
- Treat bindings as an ABI:
  - Keep `[[texture(N)]]` and `[[buffer(N)]]` stable for shipping kernels.
  - If a kernel needs a new input, append at the end (or create a new kernel name).

### 4.3 Pixel formats and working space
- The engine’s intermediate working format today is **`.rgba16Float`**.
- The intended working color space is **ACEScg**.
- IDT/ODT boundaries are explicit nodes.

## 5) PSO strategy

Current:
- `MetalSimulationEngine` caches `MTLComputePipelineState` by function name.
- It “pre-warms” a core set in `configure()`.

Target:
- Keep a single PSO cache keyed by:
  - function name + (optional) function constants (specialization)
  - pixel format / “variant” when kernels branch on format.
- Add a small “pipeline registry” document (this folder) and keep it in sync.

## 6) Dispatch strategy

Current:
- Many kernels dispatch `threadsPerGrid = (width, height, 1)`.
- Threadgroup sizing varies (sometimes uses `threadExecutionWidth`).

Target (M3+):
- Prefer `dispatchThreads` with `threadsPerThreadgroup` built from:
  - `w = pso.threadExecutionWidth`
  - `h = max(1, pso.maxTotalThreadsPerThreadgroup / w)`
- For heavy kernels (e.g., volumetric), consider 2D tiles like `8x8`/`16x8` depending on registers.
