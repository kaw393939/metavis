# Sprint 12 — Creator Workflow + Cleanwater Backlog (Discuss Later)

## Purpose
Capture the expanded product vision and new feature ideas (local-first, Mac/M‑chip focused, privacy-first) so we can discuss and schedule them without derailing the current sprint sequence.

This is a backlog sprint (planning-only). No implementation commitments yet.

## North Star ("Clean Water")
Enable a solo creator to:
- record messy real-world iPhone footage (starts/stops, noise, wind, variable distance)
- transfer it seamlessly to a Mac “director” workstation
- get professional dialog + captions automatically
- export platform-ready deliverables with minimal manual work

## Product stance
- Local-first, Mac-first, Apple Silicon optimized.
- Privacy by default: no raw media leaves the machine unless explicitly enabled per project.
- “Pro for everyone”: ship opinionated, best-practice engineering defaults (sound + picture).

## Current scope (deliberately narrow)
- **Primary capture device**: iPhone 16 Pro Max.
- **Native / reference image format**: **OpenEXR** (scene-linear **ACEScg**). This is the “truth” format for internal frame dumps, deterministic reference renders, and loss-minimized project chaining.
- **Other I/O is edge quality**: all other inputs/outputs are treated as quality tiers below EXR and may involve quantization, gamut/transfer transforms, or metadata loss.
- **In-scope inputs (for now)**:
  - OpenEXR image sequences (reference fixtures + internal interchange).
  - iPhone-origin HDR video at highest quality settings (HEVC 10-bit HDR and/or ProRes variants where present).
- **Out of scope (for now)**: other cameras/devices, RAW workflows, arbitrary codec zoo support.

## Format contracts (testable)
- **ACEScg at the door**: all image/video inputs must be converted into scene-linear ACEScg as early as possible.
- **HDR preservation**: values > 1.0 are valid and must be preserved through ingest → render → EXR dump.
- **Non-finite safety**: NaN/Inf must be sanitized to finite values before any GPU compositing/export steps.
- **Deterministic preview**: SDR previews are deterministic transforms from the scene-linear pipeline (never “mystery tone mapping”).
- **Quality ladder**:
  - **Tier 0 (reference)**: EXR (ACEScg, scene-linear) — loss-minimized, used for truth + tests.
  - **Tier 1 (capture edge)**: iPhone HDR video — preserved as faithfully as practical.
  - **Tier 2 (deliverables edge)**: platform codecs — optimized for compatibility, explicitly lower fidelity than EXR.

## Backlog themes

### 0) Science data → VFX templates (JWST/FITS)
Reference workflow: `research_notes/specs/science_data_to_vfx_trailer_workflow_jwst_carina.md`
Pipeline autopsy: `Docs/research_notes/metavis3_fits_jwst_export_autopsy.md`

- Define a `ScientificRaster` abstraction and ingestion path (FITS first).
- Decide and lock the JWST composite contract (v45 4-band vs v46 density+color) and implement/validate it end-to-end.
- Add determinism/QC strategy specific to science data (strict hashes for deterministic kernels; tolerant metrics for ML/perception stages).

### A) Seamless iPhone → Mac transfer (privacy-first)
- Pairing + session identity (project-scoped pairing keys)
- Transfer transport options (implementation later):
  - folder-drop contract (for tests + first automation)
  - AirDrop/Photos import
  - local network transfer (Wi‑Fi LAN)
- Resumable transfer + integrity checks (hashes)
- Automatic proxy generation on Mac for live preview/edit

#### iPhone “Highest Quality” Footage Support (Core Requirements)
- Ingest: robust handling of iPhone-origin footage at highest quality settings (HEVC 10-bit HDR and/or ProRes variants where present)
- Metadata: extract + persist per-asset color metadata (primaries, transfer function, matrix, full-range flag), audio metadata (channels/layout, sample rate), and rotation/orientation
- Variable frame rate: detect and normalize VFR footage into a stable timeline timebase (preserve A/V sync)
- HDR handling: preserve HDR throughout pipeline (scene-linear ACEScg working space) and provide deterministic SDR preview path
- Log capture handling: support camera log encodings when present (require explicit input transform selection)
- Timecode/timestamps: preserve capture time and stable sort order for multi-take sessions
- Spatial audio: preserve multichannel/spatial tracks where present (at minimum: don’t drop channels)
- External-storage workflows: support “file-based” ingest where creators record to external media and copy to Mac

### B) Director view (macOS app later; core APIs now)
Core services the UI will need:
- ingest/watch folder + import pipeline
- job progress + cancellation + resumable work
- preview/proxy artifacts
- timeline assembly utilities (auto-takes, chronological assembly)

Director features (UI layer, later):
- live preview
- teleprompter
- markers/retakes
- rough cut editing

### C) Dialog cleanup pipeline (MVP)
- dialog isolation / noise reduction (local-first)
- consistent loudness targets for deliverables
- optional room tone fill / de-click / de-ess
- deterministic validation of “not silent” + loudness range

### D) Diarization + captions
- speech-to-text with word timestamps
- diarization (speaker segments)
- caption sidecars: `.srt` / `.vtt`
- caption embedding/burn-in as an optional deliverable

### E) Output types / deliverables (first-class)
Treat “outputs” as project deliverable recipes:
- YouTube 4K master
- Shorts vertical
- Review proxy w/ burn-ins
- Captions-only deliverables
- Audio-only (podcast mix)

Governance gates (policy):
- deliverables allowed per plan/license
- upload permissions: deliverables-only vs proxies vs raw media

### F) Local render farm (LAN Mac devices)
- render devices as pluggable “workers” (see Sprint 02)
- discover + schedule across multiple Macs on local network
- job sandboxing + resource caps

### G) Marketplace (products/services)
- products: titles/intros/motion graphics templates, LUTs/looks, audio chains
- services: expert review, approval gates
- signing/versioning and sandboxing of marketplace assets

### H) Motion graphics + post/VFX chain (legacy reuse)
Legacy study: `Docs/research_notes/legacy_autopsy_render_graph_vfx.md`
Optimization study: `Docs/research_notes/legacy_autopsy_optimizations_apple_silicon.md`

- Deterministic post chain feature recipes (bloom → halation → vignette/grain → lens FX) built on Sprint 04 multi-pass.
- Texture pooling for intermediates (MTLHeap-backed) to avoid per-frame allocations.
- Memoryless transient render targets for tile-memory wins where intermediates are not sampled.
- Threadgroup sizing + non-uniform dispatch patterns as a baseline for compute passes.
- Temporal accumulation as an optional “subframe resolve” multi-pass (camera shutter-weighted).
- Timeline-driven parameterization for effects (keyframes → per-pass params), with a hard “no wall-clock time” invariant.

### I) Perception substrate (Vision/CoreML) for smart compositing
Legacy study: `Docs/research_notes/legacy_autopsy_coreml_vision.md`

Backlog items (implementation later; phrased as testable deliverables):
- Port a unified `VisionProvider`-style API into `Sources/MetaVisPerception` that can produce (at minimum) **person masks** and **optical flow** suitable for downstream GPU passes.
- Add a depth estimation service (`DepthEstimator`) backed by a bundled CoreML model (starting from Depth Anything V2) that produces a depth-map texture for compositing.
- Introduce perception-derived named intermediates for the multi-pass engine (e.g. `person_mask`, `depth_map`, `optical_flow`) so motion-graphics/post passes can depend on them explicitly.
- Define determinism policy for ML outputs: ML results are validated by tolerant QC metrics (not strict golden hashes) and gated separately from deterministic render hashing.
- Add packaging conventions for model assets (SwiftPM resources under `Resources/Models`) and runtime lookup/compilation caching.

## Relationship to existing sprints (alignment notes)
- Sprint 02: `RenderDevice` should be shaped to scale from local Metal → LAN Macs → cloud devices.
- Sprint 03: policy bundles should include privacy/upload policy + deliverable requirements.
- Sprint 05: deliverables should include captions sidecars and structured artifacts.
- Sprint 09: audio hardening should expand into “dialog cleanup” engineering chain.
- Sprint 04: multi-pass semantics are the foundation for post/VFX chains and motion-graphics recipes.

## Open questions (for discussion)
- On-device only speech/captions, or hybrid optional cloud for speed/accuracy?
- Does “never upload raw media” remain a hard default invariant?
- How do we represent “takes” and “camera sessions” in the timeline model?
