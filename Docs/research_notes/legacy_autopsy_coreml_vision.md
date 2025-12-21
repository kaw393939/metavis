# Autopsy — CoreML / Vision Features (MetaVisKit2 + legacy metavis1/2)

## TL;DR (what’s actually useful)
- You already have a **real Vision-based Perception layer** in MetaVisKit2 (face detection + person segmentation), plus a small CoreML configuration helper.
- Legacy metavis2 contains a **substantial VisionProvider** (saliency, segmentation, optical flow, faces, OCR-ish, horizon) and a **working CoreML depth estimator** wired to a bundled model (`DepthAnythingV2SmallF16.mlpackage`).
- Several other “CoreML” pieces in legacy metavis2 are **placeholders** (e.g. a generic `NeuralPass`, and an image-gen backend that mostly does deterministic noise fallback).

This is enough to justify a near-term roadmap:
1) keep Sprint 04 focused on deterministic multi-pass,
2) when you’re ready, port **TexturePool + VisionProvider + MLDepthEstimator** as your “Perception substrate” for motion-graphics and smart compositing.

---

## MetaVisKit2 (current repo) — what exists today

### Vision-first perception services (real)
- `Sources/MetaVisPerception/Services/PersonSegmentationService.swift`
  - Uses `VNGeneratePersonSegmentationRequest`.
  - Returns a OneComponent8 `CVPixelBuffer` mask (white=person).
  - This is “free” Apple Vision segmentation (no custom model mgmt required).

- `Sources/MetaVisPerception/Services/FaceDetectionService.swift`
  - Uses `VNDetectFaceRectanglesRequest`.
  - Includes a basic tracker loop via `VNTrackObjectRequest(detectedObjectObservation:)`.
  - Normalizes Vision coordinates to top-left origin.

### CoreML configuration helper (real, small)
- `Sources/MetaVisPerception/Infrastructure/NeuralEngineContext.swift`
  - Provides `MLModelConfiguration` and maps internal `AIComputeUnit` → `MLComputeUnits`.
  - Note: “ANE only” is not strictly available; it falls back to `.all`.

### Local LLM (stub)
- `Sources/MetaVisServices/LocalLLMService.swift`
  - Currently mock behavior + sleep; no model loading/inference.

### Face identity / faceprint (stub/blocked)
- `Sources/MetaVisPerception/Services/FaceIdentityService.swift`
  - Uses `VNDetectFaceRectanglesRequest` as a placeholder; mentions `VNGenerateFaceprintRequest` as unavailable in current env.

---

## Legacy metavis2 — where the strong CoreML/Vision work is

### 1) Unified VisionProvider (high leverage)
- `Docs/research_notes/metavis2/Sources/MetaVisRender/AI/Vision/VisionProvider.swift`

It’s a broad wrapper over Vision that returns **GPU-friendly results** (often as `MTLTexture`) and provides:
- saliency (attention/objectness)
- person segmentation
- optical flow (`VNGenerateOpticalFlowRequest`)
- face detection + landmarks
- text observations (bounding boxes; optional OCR)
- horizon/leveling output

This is the best “single surface area” to port if you want smart motion-graphics:
- subject isolation for titles
- saliency-driven framing
- optical-flow-driven glitch/displacement

### 2) Depth estimation using bundled CoreML model (very useful)
- `Docs/research_notes/metavis2/Sources/MetaVisRender/AI/Depth/MLDepthEstimator.swift`
- `Docs/research_notes/metavis2/Sources/MetaVisRender/AI/Depth/DepthEstimator.swift`

Notable:
- Loads `DepthAnythingV2SmallF16` from `Bundle.module` (tries `mlmodelc` or `mlpackage`, subdirectory `Models`).
- Forces `MLModelConfiguration.computeUnits = .cpuAndNeuralEngine`.
- Compiles `mlpackage` → cached `mlmodelc` on first run.
- Produces an `R32Float`-style depth map texture and caches results.

Model asset present in this workspace (legacy resource):
- `Docs/research_notes/metavis2/Sources/MetaVisRender/Resources/Models/DepthAnythingV2SmallF16.mlpackage`

### 3) Segmentation-driven background blur (good example integration)
- `Docs/research_notes/metavis2/Sources/MetaVisRender/Engine/Passes/BackgroundBlurPass.swift`

Notable:
- Pulls segmentation mask via `VisionProvider.segmentPeople`.
- Caches segmentation for 500ms.
- Uses a compute blur and a `TexturePool` intermediate.

### 4) “NeuralPass” (mostly placeholder)
- `Docs/research_notes/metavis2/Sources/MetaVisRender/Engine/Passes/NeuralPass.swift`

This advertises CoreML/ANE but currently:
- doesn’t load a model (`TODO`), prints “model not found”,
- falls back to MPS scaling.

### 5) CoreML image generation backend (mostly placeholder)
- `Docs/research_notes/metavis2/Sources/MetaVisRender/ImageGen/LIGMCoreMLBackend.swift`

It has useful scaffolding:
- model caching + lookup paths
- deterministic seeding metadata
- color space conversion hooks

…but inference is placeholder (noise synthesis). Treat as architectural inspiration, not a ready feature.

---

## Legacy metavis1 — minimal CoreML, some Vision
- metavis1 primarily uses Vision in validation tooling (not core product inference).

---

## What I’d port into MetaVisKit2 (pragmatic order)

## Perception determinism policy (recommended)

### What must stay deterministic
- **Render execution + pass ordering:** given the same manifests, inputs, and seeds, the multi-pass engine must allocate and execute deterministically.
- **Named intermediates contract:** missing required intermediates is a hard error; wiring is stable.

### What is allowed to be non-deterministic
- **Vision/CoreML inference outputs** (segmentation masks, depth maps, optical flow) are not guaranteed bitwise stable across:
  - macOS versions
  - device families / ANE revisions
  - CoreML runtime changes

### How we validate ML/Vision outputs
- Prefer **tolerant metrics** over golden image hashes:
  - mask foreground coverage ratio range
  - depth min/max/mean/percentiles
  - optical flow average magnitude + dominant direction tolerance
- Keep strict golden hashes for **pure render** paths (procedural generators + GPU passes without ML).

### Tracing requirements (so non-determinism is explainable)
- Every perception run should emit metadata (for logs/QC):
  - model identifier (name/version/hash)
  - compute unit selection (`MLComputeUnits`)
  - input resolution + pre-processing crop/scale mode
  - execution latency

### Scheduling rule of thumb
- Don’t block render passes on async perception; schedule perception ahead-of-time and cache by a stable key (frame time + input asset id + settings).

### Phase 1 (when you’re ready for “smart compositing”)
- Port metavis2’s `TexturePool` + `VisionProvider` into `Sources/MetaVisPerception`.
- Keep Vision requests async; avoid the legacy pattern that blocks using semaphores in render passes.

### Phase 2 (depth-aware 2.5D stage + titles)
- Port `DepthEstimator` + `MLDepthEstimator` and bundle `DepthAnythingV2SmallF16` properly as a SwiftPM resource.
- Add a small determinism policy:
  - depth inference isn’t bitwise deterministic across OS/hardware; treat it as “best effort” and gate strict determinism tests appropriately.

### Phase 3 (featureization)
- Add “Perception-derived textures” as explicit named intermediates in the multi-pass feature pipeline:
  - `person_mask`, `depth_map`, `optical_flow`
  - then build motion-graphics passes that consume them.

---

## Risks / gotchas
- **Determinism:** ML results vary across devices/OS; use QC tolerances rather than golden hashes for ML outputs.
- **Real-time constraints:** Vision/CoreML calls can be expensive; cache per time-window or per-frame key.
- **Threading:** avoid semaphore-based “async made sync” inside render loops; schedule perception ahead-of-time.
- **Resource packaging:** the depth model is in a legacy folder; if you want it in MetaVisKit2 proper, it should live under a SwiftPM target `Resources/Models` with `.process`.
