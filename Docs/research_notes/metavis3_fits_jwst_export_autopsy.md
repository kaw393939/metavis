# metavis3 autopsy: FITS → JWST composite → zero‑copy export

## Why this exists
metavis3 already contains a mostly end‑to‑end pipeline for using FITS science imagery (JWST Carina/MIRI bands) as source material for VFX-style composites, rendered on GPU and exported through a 10‑bit, Metal‑compatible pixel buffer path.

This note captures the concrete “source of truth” wiring: FITS parsing, caching, graph compilation, shader dispatch, and the export path, plus the key mismatches/risks to resolve.

## Pipeline map (files)
**FITS ingest + stats**
- `Docs/research_notes/metavis3/MetaVisCore/Sources/MetaVisCore/Data/FITSReader.swift`
- `Docs/research_notes/metavis3/MetaVisCore/Sources/MetaVisCore/Data/FITSData.swift`
- `Docs/research_notes/metavis3/MetaVisCore/Sources/MetaVisCore/Data/FITSAssetRegistry.swift`

**FITS → GPU textures**
- `Docs/research_notes/metavis3/MetaVisCore/Sources/MetaVisCore/Rendering/MetalTextureManager.swift` (uploads to `.r32Float`)
- `Docs/research_notes/metavis3/MetaVisSimulation/Sources/MetaVisSimulation/Video/VideoFrameProvider.swift` (registers `.fits`, caches textures)

**Graph + compilation**
- `Docs/research_notes/metavis3/MetaVisTimeline/Sources/MetaVisTimeline/TimelineGraphBuilder.swift` (auto tone-map insertion after FITS sources; composite wiring modes)
- `Docs/research_notes/metavis3/MetaVisSimulation/Sources/MetaVisSimulation/Simulation/GraphCompiler.swift` (emits render commands)

**Engine dispatch + shaders**
- `Docs/research_notes/metavis3/MetaVisSimulation/Sources/MetaVisSimulation/Engine/SimulationEngine.swift` (maps command `shaderName` to actual pipeline state)
- `Docs/research_notes/metavis3/MetaVisSimulation/Sources/MetaVisSimulation/Resources/Shaders/Pipeline.metal` (`toneMapKernel`, `compositeKernel`, `acesOutputKernel`)
- `Docs/research_notes/metavis3/MetaVisSimulation/Sources/MetaVisSimulation/Resources/Shaders/Effects/Composite.metal` (`jwst_composite_v4`)
- `Docs/research_notes/metavis3/MetaVisSimulation/Sources/MetaVisSimulation/Resources/Shaders/PostProcessing.metal` (`final_composite`)

**Export (zero‑copy)**
- `Docs/research_notes/metavis3/MetaVisScheduler/Sources/MetaVisScheduler/Workers/RenderWorker.swift` (render loop + mux)
- `Docs/research_notes/metavis3/MetaVisExport/Sources/MetaVisExport/Processing/ZeroCopyConverter.swift` (Metal → CVPixelBuffer planes)
- `Docs/research_notes/metavis3/MetaVisExport/Sources/MetaVisExport/Muxing/Muxer.swift` (AVAssetWriterInputPixelBufferAdaptor)
- `Docs/research_notes/metavis3/MetaVisExport/Sources/MetaVisExport/Encoding/VideoEncoder.swift` (VideoToolbox session; includes CPU-copy fallback path)

## What the repo FITS assets actually look like
The JWST Carina MIRI assets in `assets/` are ~112MB each and follow the common JWST/HST convention:
- **Primary HDU is empty** (`NAXIS=0`, `BITPIX=8`, `EXTEND=T`).
- The first image is in **HDU #1** (`XTENSION=IMAGE`, `EXTNAME=SCI`).
- Image encoding: **Float32** (`BITPIX=-32`), **2D**, **3499×1196**.

This matches the metavis3 `FITSReader` design, which scans HDUs until it finds a 2D image.

## FITS ingest (what it actually does)
- Reads the entire file into memory (`Data`) and iterates HDUs in 2880‑byte blocks.
- Parses header cards (80 bytes each) until `END` and then advances to the padded data segment.
- Supports endian swapping for:
  - `BITPIX == -32` (Float32)
  - `BITPIX == 16` (Int16)
- Computes basic stats and histogram‑based percentiles (median/p90/p99). Stats are effectively Float32‑centric.

Implications:
- “Loadable” FITS is real today, but the reader is intentionally narrow: not a general FITS library.
- Keeping FITS as “one decoder” into a generalized ScientificRaster asset type is the sane direction.

## Graph + shader naming (resolved mapping)
There is an intentional indirection between compiler kernel names and actual Metal function names.

- `GraphCompiler` emits `RenderCommand.process(..., shaderName: "jwst_composite", ...)`.
- `SimulationEngine` handles `shaderName == "jwst_composite"` specially, but the compute pipeline state it creates is from Metal function `jwst_composite_v4`.

Similarly:
- `shaderName == "toneMapKernel"` → `toneMapKernel` in `Pipeline.metal`.
- `shaderName == "acesOutputKernel"` → `acesOutputKernel` in `Pipeline.metal`.
- `shaderName == "final_composite"` → `final_composite` in `PostProcessing.metal`.

This means the earlier “jwst_composite vs jwst_composite_v4” mismatch is *not* a bug by itself; the engine is the mapping layer.

## Important mismatch / risk: v45 (4‑band) composite path
- `GraphCompiler` still supports a legacy v45 port set (`f770w`, `f1130w`, `f1280w`, `f1800w`) and will emit **4** input IDs for `jwst_composite` when v46 ports aren’t present.
- `SimulationEngine`’s `jwst_composite` execution path currently binds only **2** inputs (assumes v46: `density`, `color`) before dispatching `jwst_composite_v4`.
- The shader bundle in metavis3 only contains `jwst_composite_v4` (no 4‑input kernel).

Net: any timeline/graph that produces the v45 wiring will render incorrectly (only the first two textures are bound).

Actionable options (pick one):
- Remove/disable the v45 compilation + builder paths, and standardize on v46 “density + color” assets.
- Add a 4‑input JWST composite kernel and dispatch path (engine and/or shader) to support legacy timelines.

## Tone mapping behavior (for FITS)
- The timeline builder inserts a ToneMap node immediately after each FITS source.
- The compute kernel `toneMapKernel` is an astronomical asinh stretch:
  - Normalizes by `(val - blackPoint) / (whitePoint - blackPoint)`
  - Applies `asinh(norm * stretch) / asinh(stretch)`
  - Uses the `gamma` parameter as `stretch` (>= 1)
- The output is `rgba16Float` where only the **R** channel contains the mapped value.

## Export path (zero‑copy in the intended hot path)
Render/export loop (in `RenderWorker`):
- Renders into a `.rgba16Float` Metal texture.
- Allocates a `CVPixelBuffer` from a pool configured as `kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange` with Metal compatibility.
- Uses `ZeroCopyConverter` to create Metal texture views into the pixel buffer planes via `CVMetalTextureCacheCreateTextureFromImage`:
  - Y plane: `.r16Unorm`
  - UV plane: `.rg16Unorm`
- Dispatches `convert_rgba16float_to_yuv10_zerocopy` to write those planes.
- Appends the pixel buffer via `AVAssetWriterInputPixelBufferAdaptor` in `Muxer`.

Notes:
- `VideoEncoder.textureToPixelBuffer(...)` *does* do a CPU readback (`texture.getBytes`) but it is not on the RenderWorker hot path when muxing via pixel buffer adaptor.
- `ZeroCopyConverter` currently awaits GPU completion per-frame; batching or pipelining could improve throughput, but the zero-copy memory model is already correct.

## Backlog-ready fixes (high value)
- Decide and enforce a single JWST composite contract:
  - Prefer v46 (`density`, `color`) and remove v45 code paths, *or* implement a real 4‑band composite.
- Ensure the “color” input for v46 is truly RGB (today, auto tone-map on FITS makes it effectively single-channel unless a dedicated IDT/false-color pass is used).
- Add a small “export validation” mode that asserts no CPU readbacks occur in the render-to-export path (e.g., disallow `getBytes` in the hot path).
