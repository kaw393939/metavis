# MetaVisKit2 Stabilization Roadmap

This roadmap defines the surgical sprints required to harden the system. Prioritized by Risk (Stability) > Capability (AI) > Maintainability.

## Sequencing Gate

This roadmap is intended to be completed *before* starting the next wave of higher-level product sprints (e.g. Sprint 21–25 in the main `Sprints/` folder), unless we explicitly waive a gate for a specific deliverable.

**Rationale**: these sprints reduce systemic risk (memory, I/O, shader safety, QC config, determinism) and make later feature work cheaper and more testable.

## Phase 1: Foundation Hardening (Risk Reduction)

### [Sprint 01: State Management Hardening](./sprint_01_state_hardening/spec.md)
**Focus**: `MetaVisSession`
**Goal**: Eliminate O(N) memory usage in Undo/Redo by implementing structural sharing (COW).

### [Sprint 02: Streaming I/O Pipeline](./sprint_02_streaming_pipeline/spec.md)
**Focus**: `MetaVisAudio`, `MetaVisIngest`
**Goal**: Transition to streaming readers for Audio and FITS to ensure low RAM usage.

### [Sprint 03: Shader Safety](./sprint_03_shader_safety/spec.md)
**Focus**: `MetaVisGraphics`
**Goal**: Generate type-safe Swift accessors for Metal shaders to eliminate string failures.

### [Sprint 04: Heuristic Externalization](./sprint_04_heuristic_externalization/spec.md)
**Focus**: `MetaVisQC`, `MetaVisPerception`
**Goal**: Lift hardcoded "magic numbers" into configurable `QualityPolicy` JSON.

## Phase 2: Intelligence Activation

### [Sprint 05: Local Intelligence Integration](./sprint_05_local_intelligence/spec.md)
**Focus**: `MetaVisServices`
**Goal**: Replace `LocalLLMService` mock with real Quantized LLM (MLX) + RAG Context.

### [Sprint 06: ML Perception Integration](./sprint_06_ml_perception/spec.md)
**Focus**: `MetaVisPerception`
**Goal**: Integrate `SoundAnalysis` (Machine Learning) to augment heuristic VAD/Music detection.

### [Sprint 07: Continuous QC Sampling](./sprint_07_continuous_qc/spec.md)
**Focus**: `MetaVisQC`
**Goal**: Evaluate "Dense Sampling" strategies to catch glitches between keyframes.

## Phase 3: Engineering Maturity

### [Sprint 08: Primitive Extraction](./sprint_08_primitive_extraction/spec.md)
**Focus**: `MetaVisCore`
**Goal**: Extract `Time` and `Rational` into `MetaVisPrimitives` to decouple recompilation.

### [Sprint 09: Audio Interleaving Refactor](./sprint_09_audio_interleaving/spec.md)
**Focus**: `MetaVisExport`
**Goal**: Move unsafe pointer logic from Exporter into a tested Audio utility.

### [Sprint 10: Streaming Sidecars](./sprint_10_streaming_sidecars/spec.md)
**Focus**: `MetaVisExport`
**Goal**: Generate thumbnails/contact sheets during render pass, avoiding re-reads.

### [Sprint 11: Native Evidence Generation](./sprint_11_native_evidence/spec.md)
**Focus**: `MetaVisLab`
**Goal**: Replace `ffmpeg` CLI dependency with native AVFoundation image extraction.

## Future Sprints (TBD / Not Yet Authored Here)

These are planned but do not yet have specs in this folder.

### Sprint 12: Unified Lab Config
**Focus**: `MetaVisLab`
**Goal**: Console-ify argument parsing into shared configuration structs.

### Sprint 13: Command Protocol
**Focus**: `MetaVisSession`
**Goal**: Open `EditAction` enum into a `Command` protocol for extensibility.

### Sprint 14: Background Isolation
**Focus**: `MetaVisSession`
**Goal**: Offload heavy Intelligence/Perception tasks from the Session Actor.

### Sprint 15: Topology Validation
**Focus**: `MetaVisTimeline`
**Goal**: Implement `validate()` to prevent invalid overlapping clip states.

### Sprint 16: Shader Management
**Focus**: `MetaVisSimulation`
**Goal**: Remove hardcoded shader string fallbacks; harden Bundle loading.

### Sprint 17: Umbrella Kit
**Focus**: `MetaVisKit`
**Goal**: Implement top-level exports for the framework.
