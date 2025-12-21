# MetaVisKit2 Capabilities Report (Code-First Audit)

This document inventories **what the current code can do** and **how it does it**, organized **module-by-module** across all `MetaVis*` targets in `Sources/`.

Scope note:
- This is grounded in the Swift source and bundled resources (shaders/manifests).
- Where a component is clearly placeholder/mock, that is called out explicitly.

## System-Level Architecture (How the pieces fit)

### Primary render/export pipeline
1. **Edit model**: `MetaVisTimeline` defines `Timeline` / `Track` / `Clip` / `Transition` / `FeatureApplication`.
2. **Compilation**: `MetaVisSimulation/TimelineCompiler.swift` compiles a `Timeline` at a time `t` into a `MetaVisCore.RenderRequest` + node graph (`MetaVisCore.RenderGraph`).
3. **GPU execution**: `MetaVisSimulation/MetalSimulationEngine.swift` executes the node graph via Metal compute kernels from `MetaVisGraphics/Resources/*.metal`.
4. **Export**: `MetaVisExport/VideoExporter.swift` drives per-frame compilation/render, writes video via `AVAssetWriter`, and (optionally) writes audio.
5. **Deterministic QC + deliverables**: `MetaVisQC/*` validates container/audio presence and samples frame fingerprints/stats; `MetaVisExport/Deliverables/*` writes bundle manifests/sidecars.

### Primary audio pipeline
- `MetaVisAudio/AudioTimelineRenderer.swift` offline-renders `.audio` tracks (procedural sources, mixing, optional mastering) to sample buffers for export.

### Orchestration surface
- `MetaVisSession/ProjectSession.swift` is the “brain” actor that holds `ProjectState`, applies commands, runs perception, and invokes export.
- `MetaVisLab/*` provides CLI entrypoints to drive exports, local assessments, and decode probing.

---

## Module-by-Module Capabilities

## `MetaVisCore`
**Purpose**: shared types + governance + traceability + render graph primitives.

**Key capabilities**
- **Governance & policy modeling**:
  - AI usage/network/media posture via `AIUsagePolicy` and redaction rules (e.g. local-only defaults).
  - Export gating via `ExportGovernance` / `ExportGovernanceError`.
  - Bundle policy container `QualityPolicyBundle` which groups export + deterministic QC + optional AI gate + privacy.
  - Files: `Sources/MetaVisCore/AIGovernance.swift`, `ExportGovernance.swift`, `GovernanceTypes.swift`, `QualityPolicyBundle.swift`.
- **Render graph model** (device-agnostic):
  - Node graph representation, requests, timing.
  - Files: `Sources/MetaVisCore/RenderGraph.swift`, `RenderRequest.swift`, `Time.swift`, `SignalTypes.swift`.
- **Virtual devices** (pluggable “tools” interface):
  - `VirtualDevice` protocol, device knowledge base, typed-ish `NodeValue` payloads.
  - Files: `Sources/MetaVisCore/VirtualDevice.swift`, `DeviceKnowledgeBase.swift`.
- **Tracing/observability**:
  - `TraceSink` protocol with `NoOpTraceSink` and in-memory sink.
  - Files: `Sources/MetaVisCore/Tracing/Trace.swift`.

**Notable constraints**
- Policies are enforceable in export paths (via `MetaVisExport` / `MetaVisSession`), but policy authoring/selection is currently code-driven.

---

## `MetaVisTimeline`
**Purpose**: NLE-style timeline model.

**Key capabilities**
- **Timeline graph**:
  - `Timeline` containing `Track`s (kinds: `.video`, `.audio`, `.data`) and a declared overall `duration`.
  - `Clip` with `startTime`, `duration`, transitions, and `effects`.
  - Files: `Sources/MetaVisTimeline/Timeline.swift`.
- **Transitions**:
  - Explicit transition modeling with easing.
  - Files: `Sources/MetaVisTimeline/Transition.swift`.
- **Effect application records**:
  - Serializable `FeatureApplication(id:parameters:)`.
  - Files: `Sources/MetaVisTimeline/FeatureApplication.swift`.

**Notable constraints**
- Timeline semantics are compiled by `MetaVisSimulation/TimelineCompiler.swift` (so supported behaviors depend on compiler + shader feature registry).

---

## `MetaVisGraphics`
**Purpose**: bundled Metal kernels + feature manifests + LUT parsing.

**Key capabilities**
- **Shader library**:
  - A large set of `.metal` resources used by `MetalSimulationEngine`.
  - Files: `Sources/MetaVisGraphics/Resources/*.metal`.
- **Feature manifests**:
  - JSON manifests describing features/effects (including video and audio IDs).
  - Files: `Sources/MetaVisGraphics/Resources/Manifests/*.json`.
- **LUT utilities**:
  - `.cube` LUT parsing/loading.
  - Files: `Sources/MetaVisGraphics/LUTHelper.swift`.
- **Resource bundle access**:
  - `Bundle.module` helpers.
  - Files: `Sources/MetaVisGraphics/GraphicsBundleHelper.swift`.

**Notable constraints**
- A manifest existing doesn’t guarantee the full effect is active; runtime depends on `MetaVisSimulation` registry/compilers and which domains are supported in which pipeline (video vs audio).

---

## `MetaVisSimulation`
**Purpose**: compile timeline → render graph; execute render graph on Metal; decode clips.

**Key capabilities**
- **Metal render engine**:
  - Loads shader libraries (bundled and/or runtime compilation fallback), caches pipeline states.
  - Renders to CPU images and directly to `CVPixelBuffer` for export; optional watermarking.
  - Files: `Sources/MetaVisSimulation/MetalSimulationEngine.swift`.
- **Timeline compilation**:
  - Builds per-time render request; inserts color transforms (IDT/ODT), composites active clips, applies video-domain effects.
  - Files: `Sources/MetaVisSimulation/TimelineCompiler.swift`.
- **Feature system (multi-pass)**:
  - Feature manifest parsing, domain inference, multi-pass compilation, pass scheduling, shader registry, bootstrap and standard features.
  - Files: `Sources/MetaVisSimulation/Features/*`.
- **Video decode integration**:
  - `ClipReader` uses `AVAssetReader` to decode frames; produces Metal textures via `CVMetalTextureCache`.
  - Files: `Sources/MetaVisSimulation/ClipReader.swift`.
- **Render device abstraction**:
  - `RenderDevice` protocol, Metal implementation, catalog.
  - Files: `Sources/MetaVisSimulation/RenderDevice*.swift`.

**Notable constraints**
- Decode/scale paths are AVFoundation + CoreImage centric; failure cases may fall back to deterministic “black” textures (see `MetalSimulationEngine.prepareSourceTexture`).

---

## `MetaVisAudio`
**Purpose**: offline deterministic audio rendering for timelines.

**Key capabilities**
- **Offline timeline audio render**:
  - Manual rendering in chunks using `AVAudioEngine` graphs.
  - Files: `Sources/MetaVisAudio/AudioTimelineRenderer.swift`.
- **Deterministic procedural audio sources**:
  - Parses `ligm://audio/...` (sine, noise, sweep, impulse) and constructs sources deterministically.
  - Files: `Sources/MetaVisAudio/AudioGraphBuilder.swift`.
- **Mixing and clip transitions**:
  - Uses timeline `Clip.alpha(at:)` as gain envelope for crossfades.
  - Files: `Sources/MetaVisAudio/AudioMixing.swift` (and integration in builder).
- **Mastering chain + “Engineer” agent**:
  - Optional deterministic mastering preset (e.g. `audio.dialogCleanwater.v1`) and parameter adjustment.
  - Files: `Sources/MetaVisAudio/AudioMasteringChain.swift`, `EngineerAgent.swift`.
- **Loudness analysis**:
  - RMS/peak-ish analysis utilities.
  - Files: `Sources/MetaVisAudio/LoudnessAnalyzer.swift`.
- **Standalone signal generator**:
  - Interactive generator for tones/noise/sweeps.
  - Files: `Sources/MetaVisAudio/AudioSignalGenerator.swift`.

---

## `MetaVisExport`
**Purpose**: export a timeline to a movie file and/or a deliverable bundle.

**Key capabilities**
- **Movie export**:
  - Drives frame-by-frame render and encodes video via `AVAssetWriter` (HEVC/H.264 depending on caller).
  - Runs audio export in parallel (policy-controlled) and appends as sample buffers.
  - Performs export preflight (feature ID validation; track/effect expectations).
  - Files: `Sources/MetaVisExport/VideoExporter.swift`, `ExportPreflight.swift`, `AudioPolicy.swift`, `VideoExporting.swift`.
- **Deliverable bundles**:
  - Atomic staging + finalization, manifest writing.
  - Files: `Sources/MetaVisExport/Deliverables/DeliverableWriter.swift`, `DeliverableManifest.swift`, `ExportDeliverable.swift`.
- **Sidecar generation**:
  - Captions stubs (empty VTT/SRT), thumbnail JPEG, contact sheet JPEG.
  - Files: `Sources/MetaVisExport/Deliverables/DeliverableSidecar.swift`, `SidecarWriters.swift`.
- **Expanded QC report schemas**:
  - Content fingerprint / luma stats, metadata QC, sidecar QC structures.
  - Files: `Sources/MetaVisExport/Deliverables/DeliverableExpandedQC.swift`.

**Notable constraints**
- Sidecar caption writers currently emit valid-but-empty caption files.

---

## `MetaVisQC`
**Purpose**: deterministic QC checks and optional Gemini acceptance.

**Key capabilities**
- **Container-level validation**:
  - Duration, dimensions, FPS tolerance, minimum sample count; plus optional audio presence/silence checks.
  - Files: `Sources/MetaVisQC/VideoQC.swift`.
- **Metadata inspection**:
  - Extracts codec FourCC, color primaries/transfer/matrix, bit depth, full-range flag, HDR heuristic; audio channel count/sample rate.
  - Files: `Sources/MetaVisQC/VideoMetadataQC.swift`.
- **Content sampling & gating**:
  - Computes lightweight frame fingerprints and enforces temporal-variety threshold (`minDistance`) to detect stuck/black/unchanging exports.
  - Computes deterministic luma histogram-derived stats (mean luma, low/high fractions, peak bin).
  - Files: `Sources/MetaVisQC/VideoContentQC.swift`.
- **GPU acceleration for QC metrics**:
  - Metal kernels for fingerprints and color stats.
  - Files: `Sources/MetaVisQC/MetalQCFingerprint.swift`, `MetalQCColorStats.swift`, `Resources/QCFingerprint.metal`.
- **Gemini QC (optional, policy-gated)**:
  - Extracts keyframes and (optionally) inline JPEG/video evidence and asks Gemini for an accept/reject JSON response.
  - Enforces a local near-black upload gate before sending media.
  - Files: `Sources/MetaVisQC/GeminiQC.swift`, `GeminiPromptBuilder.swift`, `DotEnvLoader.swift`.

**Notable constraints**
- Gemini calls are skipped unless `AIUsagePolicy` allows network/media and `GEMINI_API_KEY` is present.

---

## `MetaVisServices`
**Purpose**: LLM/service integration and intent parsing.

**Key capabilities**
- **Local LLM service (currently mocked)**:
  - Actor that returns a fake response and optional intent JSON.
  - Files: `Sources/MetaVisServices/LocalLLMService.swift`.
- **Intent parsing**:
  - Extracts JSON from markdown-fenced or inline `{...}` blocks and decodes `UserIntent`.
  - Files: `Sources/MetaVisServices/IntentParser.swift`, `UserIntent.swift`.
- **Gemini HTTP client + config**:
  - REST client for `generateContent` + model auto-resolution via `listModels`; includes snake_case + camelCase fallback encoding.
  - Files: `Sources/MetaVisServices/Gemini/GeminiClient.swift`, `GeminiConfig.swift`, `GeminiModels.swift`, `GeminiError.swift`.
- **Gemini as a `VirtualDevice`**:
  - `GeminiDevice` implements `VirtualDevice` actions `ask_expert` / `reload_config`.
  - Files: `Sources/MetaVisServices/Gemini/GeminiDevice.swift`.
- **Convenience wrapper**:
  - `AskTheExpert` wraps a `VirtualDevice` to request `ask_expert`.
  - Files: `Sources/MetaVisServices/AskTheExpert.swift`.

---

## `MetaVisPerception`
**Purpose**: local perception (“eyes/ears”) utilities for frames.

**Key capabilities**
- **Deterministic frame analysis (fast CPU)**:
  - Computes dominant colors (coarse), luma histogram, skin-tone likelihood.
  - Files: `Sources/MetaVisPerception/Services/VideoAnalyzer.swift`.
- **Face detection & tracking**:
  - Uses Vision to detect faces and track them over time via `VNTrackObjectRequest`.
  - Provides normalized rects in a top-left origin coordinate system.
  - Files: `Sources/MetaVisPerception/Services/FaceDetectionService.swift`.
- **Person segmentation**:
  - Uses `VNGeneratePersonSegmentationRequest` to produce a mask pixel buffer.
  - Files: `Sources/MetaVisPerception/Services/PersonSegmentationService.swift`.
- **Face identity (placeholder)**:
  - Currently uses face rectangles request as a stand-in; true faceprint is noted as unavailable.
  - Files: `Sources/MetaVisPerception/Services/FaceIdentityService.swift`.
- **Audio analysis (FFT-based)**:
  - FFT-based dominant-frequency extraction and simple classification.
  - Files: `Sources/MetaVisPerception/Services/AudioAnalyzer.swift`.
- **Semantic frame aggregation**:
  - `VisualContextAggregator` builds `SemanticFrame` from detection/tracking.
  - Files: `Sources/MetaVisPerception/Services/VisualContextAggregator.swift`, `Models/SemanticFrame.swift`.
- **CoreML configuration helper**:
  - `NeuralEngineContext` provides `MLModelConfiguration` presets.
  - Files: `Sources/MetaVisPerception/Infrastructure/NeuralEngineContext.swift`.

---

## `MetaVisSession`
**Purpose**: stateful project orchestration + recipes + intent-to-edit command execution.

**Key capabilities**
- **Project state + undo/redo**:
  - `ProjectSession` actor stores `ProjectState` (timeline + config + optional `SemanticFrame`) and maintains undo/redo stacks.
  - Files: `Sources/MetaVisSession/ProjectSession.swift`.
- **Perception integration (throttled)**:
  - `ProjectSession.analyzeFrame(...)` calls `VisualContextAggregator` and stores `state.visualContext`.
  - Files: `Sources/MetaVisSession/ProjectSession.swift`.
- **Command processing (LLM → intent → commands)**:
  - Builds JSON context from `SemanticFrame`, calls `LocalLLMService`, parses `UserIntent`, maps to `IntentCommand`s, and applies them to the timeline.
  - Files: `Sources/MetaVisSession/ProjectSession.swift`, `Commands/IntentCommandRegistry.swift`, `Commands/CommandExecutor.swift`.
- **Concrete command set (current)**:
  - Apply color grade to first video clip, trim end of first clip, retime first clip.
  - Files: `Sources/MetaVisSession/Commands/IntentCommand.swift`.
- **Export orchestration**:
  - Builds `QualityPolicyBundle` from entitlements/license and invokes `VideoExporter`.
  - `exportDeliverable` runs deterministic QC, metadata/content sampling, optional temporal-variety enforcement, and writes requested sidecars.
  - Files: `Sources/MetaVisSession/ProjectSession.swift`.
- **Entitlements**:
  - `EntitlementManager` enforces `UserPlan` limits; unlock-code based mock upgrade.
  - Files: `Sources/MetaVisSession/EntitlementManager.swift`.
- **Project/demo recipes**:
  - Deterministic demo timelines (including fallback to procedural sources when assets missing).
  - Files: `Sources/MetaVisSession/DemoRecipes.swift`, `ProjectRecipes.swift`, `GodTestBuilder.swift`.

---

## `MetaVisIngest`
**Purpose**: ingest/device sources.

**Key capabilities**
- **Mock generator device**:
  - `LIGMDevice` generates `ligm://generated/...` URLs based on prompts.
  - Files: `Sources/MetaVisIngest/LIGMDevice.swift`.

**Notable constraints**
- No camera/mic capture pipeline is present in code; ingest is currently generator/mock focused.

---

## `MetaVisLab` (CLI)
**Purpose**: developer/operator CLI entrypoints.

**Key capabilities**
- **`export-demos`**:
  - Exports curated `MetaVisSession.DemoRecipes` using `MetalSimulationEngine` + `VideoExporter` into `test_outputs/project_exports/` (or `--out`).
  - Large-asset opt-in via `--allow-large`.
  - Files: `Sources/MetaVisLab/ExportDemosCommand.swift`.
- **`sensors ingest`**:
  - Sprint 15 master sensor ingest: writes deterministic `sensors.json` (`MasterSensors`, schema v3).
  - Large-asset opt-in via `--allow-large`.
  - Files: `Sources/MetaVisLab/SensorsCommand.swift`, `Sources/MetaVisPerception/MasterSensorIngestor.swift`.
- **`probe-clip`**:
  - Debug tool to probe decode across timestamps; includes a direct `AVAssetReader` sanity check.
  - Files: `Sources/MetaVisLab/ProbeClipCommand.swift`.
- **Command routing**:
  - Subcommand dispatch lives in `MetaVisLabMain.swift` and `main.swift`.
  - Files: `Sources/MetaVisLab/MetaVisLabMain.swift`, `main.swift`.

---

## `MetaVisKit`
**Purpose**: currently an empty target (placeholder).

- Files: `Sources/MetaVisKit/Empty.swift`.

---

## Practical “What can we do today?” (Code-backed)

- Build deterministic demo timelines and procedural test patterns (`MetaVisSession/DemoRecipes.swift`, `GodTestBuilder.swift`).
- Decode real clips via AVFoundation and composite multi-clip edits with transitions (`MetaVisSimulation/ClipReader.swift`, `TimelineCompiler.swift`).
- Apply feature-driven video effects (manifest + shader registry + compiler) where supported (`MetaVisSimulation/Features/*`, `MetaVisGraphics/Resources/Manifests/*.json`).
- Offline-render procedural + timeline-mixed audio and optionally master it (`MetaVisAudio/*`).
- Export `.mov` deliverables with video+audio via `AVAssetWriter` and governance preflight (`MetaVisExport/VideoExporter.swift`).
- Generate deliverable bundles with manifests + sidecars (thumbnail/contact sheet/captions stubs) (`MetaVisExport/Deliverables/*`, `MetaVisSession/ProjectSession.exportDeliverable`).
- Run deterministic QC (container + audio existence/silence + content fingerprint/stats) and enforce temporal-variety gating for multi-clip edits (`MetaVisQC/*`, `MetaVisSession/ProjectSession.swift`).
- Optionally request Gemini acceptance checks when policy allows and keys are configured (`MetaVisQC/GeminiQC.swift`, `MetaVisServices/Gemini/*`).

## Explicit gaps / placeholders (Code-backed)
- `MetaVisServices/LocalLLMService.swift` is a mock and does not run a real on-device model yet.
- `MetaVisPerception/FaceIdentityService.swift` contains a placeholder note (faceprint request unavailable) and does not implement true re-identification.
- `MetaVisIngest` is generator/mock oriented; no camera capture code is present.
- `MetaVisKit` currently contains no implementation (placeholder target).
