# Sprint 15 — Sensor (Master Ingest)

## Goal
Create a deterministic, local-first “master sensor ingest” pass that turns a source video (and its audio) into a rich, versioned `sensors.json` that acts as the **eyes and ears of an editor**.

This sprint explicitly targets:
- Reliable extraction on macOS using Apple frameworks already present in this repo (Vision/AVFoundation/Accelerate).
- Support for **at least two people** in-frame (and more when possible).
- A foundation for **person identity (faceprint)** to target edits/features to “Person A vs Person B”.
- A **cutting warning system** (green/yellow/red) derived from sensors.

Non-goals (for this sprint): cloud LLM calls, “best effort” hallucinated labels, or unstable third-party ML models without a clear determinism story.

## Current repo building blocks (already present)
Video / Vision:
- `FaceDetectionService`: face rectangles + multi-face tracking via `VNTrackObjectRequest`.
- `PersonSegmentationService`: `VNGeneratePersonSegmentationRequest` mask (1-channel).
- `FaceIdentityService`: placeholder; intended to become Vision faceprint-based re-identification.
- `VideoAnalyzer`: deterministic color/luma histogram + dominant colors + skin likelihood.

Audio:
- `MetaVisAudio/LoudnessAnalyzer`: RMS-based LUFS-ish + peak dB.
- `MetaVisPerception/AudioAnalyzer`: FFT-based dominant frequency + basic classification.

### Repo alignment (greenfield)
Sprint 15 treats **`MasterSensors` as the single authoritative `sensors.json` schema**.
There is intentionally **no legacy/alternate sensors model** and no legacy writer.

## Deliverables
1) A new CLI pass (or subcommand) that produces:
- `sensors.json` (versioned schema, deterministic, stable ordering)
- Optional artifacts (for debugging/inspection only): downsampled keyframes, masks, thumbnails

### Smoke command (real fixture)
This should produce both `sensors.json` and `bites.v1.json` in the output directory:

```bash
swift run -c debug MetaVisLab sensors ingest \
  --input Tests/Assets/VideoEdit/keith_talk.mov \
  --out test_outputs/sprint15_keith_sensors \
  --stride 0.5 \
  --max-video-seconds 10 \
  --audio-seconds 10 \
  --emit-bites \
  --allow-large
```

2) A single “Master Sensors” schema that includes **video + audio + identity + warnings**.

3) Sampling strategy and performance budgets so ingest finishes in reasonable time on laptop hardware.

---

## Raising the odds of a watchable cut (pragmatic checklist)
Goal: move from “sensors exist” → “the system reliably produces something a human would watch” by adding a small set of deterministic planning tools that an LLM can invoke.

Highest-leverage additions (in order):
1) **Implement code-generated `descriptors`** (not only the spec) so downstream reasoning stays grounded and token-light.
2) **Build a deterministic bite map** (`bites.json`) from transcript+timings so we can reason in editorial units, not raw words.
3) **Add deterministic dedupe grouping** (`dedupe.json`) so repeat/retake removal is stable and explainable.
4) **Add one assembly mode first** (`tightenOnly` or `keyPoints`) with tests, then expand to `miniArc` / `continuousStory`.
5) **Add B-roll slot planning** (`broll_plan.json`) to cover risky cuts, while keeping it optional.
6) **Add a verify pass** that re-checks warnings/descriptors on the assembled cut and fails fast if we violate vetoes.

Why these raise odds:
- They convert noisy sensor streams into a few deterministic artifacts (`descriptors`, `bites`, `dedupe`, `edl`) that can be tested.
- They keep the LLM “on rails”: the LLM chooses among tool outputs rather than inventing structure.

---

## LLM toolchain contract (think: a series of tools)
Principle: the LLM should act like an *orchestrator*, calling deterministic tools that each produce a versioned artifact with evidence.

Each tool must:
- be deterministic (same inputs → same outputs)
- emit stable IDs and stable ordering
- include `evidence` fields pointing back to sensors/transcript
- honor `veto` descriptors (and surface hard failures rather than silently violating)

Proposed high-level tools (names illustrative):
1) `sensors.ingest` → produces `sensors.json`
  - Inputs: media asset, stride/detector flags
  - Outputs: `sensors.json` (+ optional artifacts)

2) `sensors.describe` → produces `descriptors[]` (inside `sensors.json` or as `descriptors.json`)
  - Inputs: `sensors.json`
  - Outputs: segment-level descriptor list with confidence + evidence

3) `transcript.generate` → produces `transcript.json` + optional `captions.vtt`
  - Inputs: audio track
  - Outputs: timestamped transcript aligned to the same seconds timebase
  - Local-first note: we can run this via `WhisperCLITranscriber` (external CLI, no network required by default).

4) `bites.build` → produces `bites.json`
  - Inputs (v1): **either** `transcript.json` **or** (`sensors.json` with `audioSegments` + `suggestedStart`)
  - Inputs (v2): transcript + descriptors/warnings for better bite boundaries
  - Outputs: atomic editorial units (`Bite{id,start,end,text,tags,evidence}`)
  - Determinism rules:
    - stable ID generation (`bite_<start_ms>_<end_ms>`)
    - stable ordering by `(start,end,id)`
    - no semantic guessing if transcript is missing
  - Audio-only fallback behavior (required):
    - If transcript is unavailable, create `bites` from contiguous `.speechLike` regions (optionally split on silence gaps).
    - Set `text` to `"(speech)"` (or empty) and rely on `evidence` + timestamps.
    - This keeps the entire planning pipeline runnable without ASR.

5) `dedupe.group` → produces `dedupe.json`
  - Inputs: `bites.json`
  - Outputs: stable groups + “best take” selection with evidence

6) `edit.plan` (mode-driven) → produces `edit_map.json`
  - Inputs: `bites.json`, `dedupe.json`, mode settings (`tightenOnly|keyPoints|miniArc|continuousStory`)
  - Outputs: ordered beats with alternates + constraints

7) `timeline.assemble` → produces `edl.json`
  - Inputs: `edit_map.json` (+ optional hard user constraints)
  - Outputs: concrete clip list with trims + per-cut rationale

8) `broll.plan` (optional) → produces `broll_plan.json`
  - Inputs: `edl.json` + `sensors.json` (+ settings)
  - Outputs: B-roll slots + prompts/tags + evidence

9) `verify.cut` → produces `verification.json`
  - Inputs: `edl.json` (+ `broll_plan.json`) + `sensors.json`
  - Outputs: pass/fail + violations (e.g. veto breaks, red-dominant coverage, missing face for beauty)

LLM usage rule:
- The LLM should never output an EDL “from scratch”. It should propose settings, call tools, then select among tool-produced candidates.

## Data contract: `sensors.json` (proposed schema v3)
### Top-level
- `schemaVersion: 3`
- `source`: path, duration, frameRate (if known), dimensions, audio presence
- `sampling`: stride seconds, keyframe policy, detector config hash
- `timeline`: arrays of time-stamped samples/segments

### Time primitives
- All times are in seconds from start.
- Samples are either:
  - `instant` (at t)
  - `window` (start/end)

### Video sensors (reliable)
#### 1) Color / exposure / stability
Per-sample (e.g. every 0.5s):
- `meanLuma`, `lumaHistogram[256]` (optional; heavy)
- `dominantColors` (quantized)
- `skinLikelihood`
- `exposureRisk`: flags for under/over exposure (heuristics)
- `flickerLikelihood`: heuristic (luma variance across adjacent samples)

#### 2) Faces and people count
Per-sample:
- `faces`: list of face boxes (normalized) + `trackId` (stable across time)
- `peopleCountEstimate`: `max(faceCount, segmentationPresence)`

Tracking:
- Use existing `FaceDetectionService.trackFaces`.
- Maintain `trackId` → track timeline (start/end, box trajectory, confidence).

#### 3) Person segmentation
Per-sample (lower rate, e.g. every 1.0s):
- `personMaskPresence`: ratio of mask pixels > threshold
- Optional: store a compressed mask reference (NOT raw per-frame in JSON).

Mask storage strategy:
- Store masks as external PNGs or a compact binary blob and reference by path+time.
- Keep JSON lightweight; masks are optional artifacts.

### Scene context sensors (for grading decisions)
Goal: determine *environmental context* that affects grading/enhancement.

Deliver as **probabilistic tags** with confidence and simple deterministic fallbacks:
- `scene.indoorOutdoor`: `indoor|outdoor|unknown`, confidence
- `scene.lightSource`: `natural|artificial|mixed|unknown`, confidence
- `scene.whiteBalanceHint`: approximate CCT bucket (`warm|neutral|cool`) from avg chroma
- `scene.timeOfDayHint`: `day|night|unknown` (brightness + color)

Implementation tiers:
- Tier A (deterministic heuristics; always available):
  - sky-blue likelihood + high-key distribution → “outdoor day” bias
  - tungsten-warm dominant + low-key + stable highlights → “indoor artificial” bias
  - use `VideoAnalyzer` outputs (dominant colors, histogram) to compute these.
- Tier B (Vision classifier; gated + recorded):
  - If supported in target env, run Apple Vision image classification and map labels to indoor/outdoor cues.
  - Must be stable and cached; always store `modelIdentifier`/OS version used.

### Audio sensors (reliable)
Per-window (e.g. 0.25–0.5s windows):
- `loudness.lufsApprox` (RMS-based), `peakDb`
- `silenceLikelihood` (threshold)
- `dominantFrequencyHz` (from FFT)
- `spectralCentroid` (optional; compute via FFT magnitudes)

Segment-level:
- `speechLikeSegments`: simple VAD heuristic (energy + spectral shape) with confidence
- `musicLikeSegments`: heuristic (tonal stability + harmonic peaks)

Notes:
- This sprint focuses on robust features derivable from RMS/FFT.
- If we later add true VAD/ASR, it lives behind an explicit detector flag.

### Identity: faceprints + re-identification (required)
Goal: identify a person across time/cuts as a stable `personId`.

Design:
- `trackId`: per-continuous tracker output (frame-to-frame)
- `personId`: stable identity across discontinuities via faceprint matching

Plan:
1) Generate a faceprint embedding for selected face crops per track.
2) Build a lightweight gallery:
   - `personId` → set of embeddings (centroid + samples)
3) Matching:
   - cosine distance / L2 threshold → assign `personId` or create new

Constraints:
- Use Apple Vision face feature print request where available.
- If the build environment lacks the API, keep `FaceIdentityService` as a stub but define the exact interface and artifacts.

Privacy:
- Store embeddings in `sensors.json` only if explicitly allowed; otherwise store hashed IDs + local cache path.

---

## Editor warning system (green/yellow/red)
Purpose: make this ingest pass the “eyes of the editor” by flagging risky regions for cutting.

### Output
- `warnings`: array of segments with:
  - `start`, `end`
  - `severity`: `green|yellow|red`
  - `reasons`: list of stable reason codes
  - `scores`: numeric sub-scores for debugging

### Reason codes (initial, deterministic)
Video:
- `no_face_detected` (when we expect talking head)
- `multiple_faces_competing` (two+ faces, unclear focus)
- `face_too_small` (box area < threshold)
- `motion_blur_risk` (proxy via inter-sample luma variance + edge energy if added)
- `exposure_clip_risk` (histogram near 0/255 extremes)
- `flicker_risk`

Audio:
- `audio_silence` (low RMS)
- `audio_clip_risk` (peak near 0dB)
- `audio_noise_risk` (flat-ish spectrum / high centroid; heuristic)

Editing stability:
- `cut_on_non_speech` (cut point falls in silence window)
- `cut_on_transient` (high amplitude change)

### Scoring model
- Compute normalized sub-scores 0..1, then a weighted sum.
- Map to traffic-light:
  - green: < 0.35
  - yellow: 0.35–0.7
  - red: > 0.7

All thresholds must be config-driven and persisted in `sensors.json` under `sampling.detectors`.

---

## Descriptor layer (LLM-friendly scene reasoning)
Purpose: turn noisy, high-dimensional raw sensors into a small set of **human-readable, segment-level descriptors** that an LLM can reliably reason about.

Why this helps:
- Fewer tokens and less noise than raw per-sample arrays.
- Encourages grounded reasoning (“because face is stable + speech is continuous”).
- Makes decisions explainable and debuggable (descriptors cite evidence + confidence).

### Output
Add a new optional top-level array:
- `descriptors`: array of segments with:
  - `start`, `end`
  - `label`: stable descriptor code (see vocabulary)
  - `confidence`: 0..1
  - `veto` (optional): if true, downstream plans must not violate this constraint
  - `evidence`: compact list of `{field, value}` pairs pointing at raw sensor signals used
  - `notes` (optional): short deterministic string for debugging (no LLM prose)

Design rules:
- Deterministic thresholds, stable ordering, stable rounding.
- Segment coalescing identical to warnings (merge adjacent windows when label unchanged).
- Prefer `unknown` over guessing: low confidence must not silently become a label.
- Descriptors must be *actionable*: each descriptor either (a) informs an edit decision or (b) gates a feature.

### Descriptor vocabulary (best-possible with current sensors)
The goal is to only include labels we can support deterministically with:
- faces (`faces[]`), plus basic stability computed from face rect time series
- segmentation presence (`personMaskPresence`)
- color/exposure (`meanLuma`, histogram-derived tails if present, dominant color votes)
- audio VAD-ish segments (`audioSegments[]`)

People / subject:
- `single_subject`
- `multi_person` (often a veto for “talking head” workflows)
- `no_face_detected`
- `face_tracking_unstable` (intermittent detection or high bbox jitter)
- `face_small_risk` (face area consistently low)
- `subject_occluded_risk` (mask present but face missing)

Audio intent:
- `continuous_speech`
- `interrupted_speech`
- `silence_gap`
- `broadband_noise_risk` (proxy: high centroid + non-speech)

Scene / light (conservative):
- `outdoor_foliage`
- `outdoor_sky`
- `indoor_warm_light`
- `mixed_light`
- `grade_confidence_low` (scene/light confidence below threshold)

Editability / safety:
- `safe_for_beauty`
- `safe_for_subject_mask`
- `avoid_heavy_grade`

Note: avoid adding labels like `backlit_risk` until we have a reliable highlight/subject-separation cue.

### Heuristic mapping (raw sensors → descriptors)
Windowing:
- Use the same window hop as audio segmentation (e.g. 0.5s windows, 0.25s hop) and nearest video sample(s).

Definitions we can compute today (no new ML):
- `facePresenceRate`: fraction of windows where `faces.count > 0`
- `singleFaceRate`: fraction of windows where `faces.count == 1`
- `people2pRate`: fraction of windows where `peopleCountEstimate ?? faces.count >= 2`
- `faceAreaMean`: mean area of the primary face box
- `faceCenterJitter`: mean absolute delta of face center (normalized) between adjacent windows
- `faceAreaJitter`: mean absolute delta of face area between adjacent windows
- `maskPresenceRate`: fraction of windows where `personMaskPresence > threshold`
- `speechCoverage`: fraction of segment covered by `.speechLike`
- `silenceCoverage`: fraction covered by `.silence`
- `warningRedCoverage`: fraction covered by `warnings.severity == red`
- `greenVoteRate` / `blueVoteRate`: from dominant colors

Recommended confidence policy:
- Compute confidence from margin-to-threshold (not just boolean), then clamp 0.0–1.0.
- If confidence < 0.55, emit `grade_confidence_low` or nothing (prefer unknown).

Examples (deterministic):

- `single_subject` when `singleFaceRate >= 0.70` AND `face_tracking_unstable` is false.
  Evidence: `singleFaceRate`, `faceCenterJitter`, `faceAreaJitter`, `faceAreaMean`

- `multi_person` when `people2pRate >= 0.30`.
  Suggested default: set `veto=true` for workflows that assume a single primary speaker.
  Evidence: `people2pRate`, `faces.maxCount`, `peopleCountEstimate`

- `no_face_detected` when `facePresenceRate <= 0.10`.
  Evidence: `facePresenceRate`

- `face_tracking_unstable` when `facePresenceRate` is moderate but jitter is high,
  e.g. `facePresenceRate >= 0.40` AND (`faceCenterJitter >= 0.05` OR `faceAreaJitter >= 0.04`).
  Evidence: `facePresenceRate`, `faceCenterJitter`, `faceAreaJitter`

- `face_small_risk` when `faceAreaMean <= 0.02` (2% of frame) for most windows.
  Evidence: `faceAreaMean`

- `subject_occluded_risk` when `maskPresenceRate >= 0.50` but `facePresenceRate <= 0.20`.
  Evidence: `maskPresenceRate`, `facePresenceRate`

- `continuous_speech` when `speechCoverage >= 0.80`.
  Evidence: `speechCoverage`, `audioSegments` kinds

- `interrupted_speech` when `speechCoverage >= 0.30` AND `silenceCoverage >= 0.15`.
  Evidence: `speechCoverage`, `silenceCoverage`

- `silence_gap` when any silence segment duration ≥ 0.4s.
  Evidence: `maxSilenceGapSeconds`

- `broadband_noise_risk` when there is low speech coverage AND centroid is high in many windows.
  (With current audio features, keep this conservative; low confidence is expected.)
  Evidence: `speechCoverage`, `centroidHz` stats if available

- `outdoor_foliage` when `meanLuma >= 0.30` AND `greenVoteRate >= 0.35`.
  Evidence: `meanLuma`, `greenVoteRate`

- `outdoor_sky` when `meanLuma >= 0.30` AND `blueVoteRate >= 0.30`.
  Evidence: `meanLuma`, `blueVoteRate`

- `indoor_warm_light` when `meanLuma <= 0.30` AND warm vote rate is high.
  Evidence: `meanLuma`, `warmVoteRate`

- `grade_confidence_low` when `summary.scene.*.confidence < 0.55`.
  Evidence: `scene.indoorOutdoor.confidence`, `scene.lightSource.confidence`

- `safe_for_beauty` when `single_subject` AND `continuous_speech` AND `warningRedCoverage <= 0.10`.
  Evidence: `singleFaceRate`, `speechCoverage`, `warningRedCoverage`

- `safe_for_subject_mask` when `maskPresenceRate >= 0.50` AND `single_subject`.
  Evidence: `maskPresenceRate`, `singleFaceRate`

- `avoid_heavy_grade` when `grade_confidence_low` OR exposure warnings are elevated.
  Evidence: `grade_confidence_low`, `warnings` reason codes

### LLM grounding contract (how to use sensors safely)
When an LLM is asked to propose edits/looks, it must:
- Prefer `descriptors` and `warnings` for reasoning; use raw samples only as evidence.
- Treat any label with confidence < threshold as `unknown`.
- Cite at least one reason code / descriptor for each non-trivial decision.
- Never infer “indoor/outdoor” (or people count) if sensors say `unknown`.
- Respect hard vetoes (tests can enforce): if sensors indicate `multi_person` or `scene.indoorOutdoor != outdoor` for this fixture, the plan is invalid.

---

## B-roll placeholders + coverage planning (optional)
Purpose: support “cover the edit” workflows (removing repeats/retakes/jump cuts) by planning *where* B-roll should sit, and *what it should be*, without requiring B-roll generation to be mandatory.

Key constraint: B-roll planning must be grounded in deterministic evidence.
- Inputs are only `warnings`, `descriptors`, `audioSegments`, and transcript alignment (if present).
- The planner can request placeholders (e.g. via LIGM) but must output a plan that is valid even if placeholder generation is disabled.

### User-facing settings (minimal)
These settings belong to the edit-plan stage (not ingest), but Sprint 15 defines the evidence contract.
- `broll.amount`: `none | light | medium | heavy`
  - `none`: never propose B-roll slots.
  - `light`: only cover high-risk cuts (hard jump cuts, red warning regions).
  - `medium`: cover risky cuts + some pacing relief.
  - `heavy`: maximize B-roll coverage subject to caps.
- `broll.placeholderProvider`: `none | ligm`
  - `ligm` means: generate synthetic placeholder shots when no source library exists.
- `broll.maxPercentOfRuntime`: default by amount (e.g. light 15%, medium 35%, heavy 60%).
- `broll.minShotSeconds`: e.g. 1.0–2.0
- `broll.maxShotSeconds`: e.g. 6.0–10.0
- `broll.neverCoverWhen`: list of descriptor labels that should block covering (default: `start_gate_ready` windows; we prefer to show the speaker there).
- `broll.preferCoverWhen`: list of descriptor labels or warning reason codes that encourage covering.
  - defaults: `interrupted_speech`, `silence_gap`, `face_tracking_unstable`, `exposure_clip_risk`, `multiple_faces_competing`.

### Output artifact: `broll_plan.json` (proposed)
This is intentionally separate from `sensors.json` (so sensors remain pure observation).

Top-level:
- `schemaVersion`: 1
- `source`: references the input video + `sensors.json` hash
- `settings`: the resolved B-roll settings snapshot
- `slots`: ordered array of B-roll slots

Each slot:
- `id`: stable string
- `start`, `end`: seconds on the master timeline
- `priority`: `low | medium | high`
- `coverageGoal`:
  - `covers`: `jump_cut | remove_repeat | hide_transient | hide_silence | pacing | safety`
  - `targetClipIds`: optional list of EDL clip IDs this slot is intended to cover
- `constraints`:
  - `allowFaces`: bool (default false for placeholders)
  - `motion`: `static | slow | any`
  - `style`: `match_scene | neutral`
- `prompt` (optional): deterministic, template-based prompt for placeholder generation
- `tags`: small list of stable tags (e.g. `outdoor_foliage`, `hands`, `wide_establishing`)
- `evidence`: list of `{field, value}` referencing descriptors/warnings used
- `confidence`: 0..1
- `veto` (optional): hard constraint (e.g. “must cover this cut”) used for downstream assembly checks

### Planning rules (deterministic)
The planner should generate slots from these triggers:
1) **Hard cut coverage**: if two adjacent A-roll clips create a jump cut (same angle, same speaker) and the cut is not on a natural pause, create a slot centered on the cut.
   - Evidence: `cut_on_transient` / `cut_on_non_speech` warnings, or `interrupted_speech` descriptor near the boundary.
2) **Repeat/retake removal**: when a dedupe decision removes a region, add a slot to smooth continuity if the cut would be visually harsh.
   - Evidence: dedupe group decision + face jitter / red warning coverage around boundary.
3) **Safety / quality cover**: if a region is `red` due to visual risk but audio is good, allow covering with B-roll while keeping audio.
   - Evidence: `warnings.severity == red` with reasons like `motion_blur_risk`, `exposure_clip_risk`.

Caps:
- Enforce `broll.maxPercentOfRuntime` and per-slot min/max seconds.
- Never place B-roll over the first few seconds after `suggestedStart` unless explicitly requested (we want to see the speaker settle).

### LIGM placeholders (optional provider)
If `broll.placeholderProvider == ligm`, placeholders are generated as *stand-ins*:
- The plan must still work if generation is skipped.
- Prompts must be deterministic templates derived from descriptors, never free-form narrative.
- Store placeholder outputs as separate media assets referenced by `slot.id` (do not embed binary in JSON).


---

## CLI shape (proposed)
- `metavislab sensors ingest --input <movie> --captions <vtt?> --out <dir> --stride 0.5 --enable face --enable segment --enable audio --enable warnings`

Outputs:
- `<out>/sensors.json`
- `<out>/artifacts/...` (optional)

---

## Acceptance criteria
- Produces `sensors.json` deterministically for the same input.
- Includes face tracks for at least 2 people when present.
- Includes audio loudness + FFT features.
- Produces warning segments with stable reason codes.
- Runs locally without network.

## TDD / Tests (no mocks)
- `Tests/MetaVisPerceptionTests/MasterSensorsIngestorTests.swift`
  - Uses `Tests/Assets/VideoEdit/keith_talk.mov`.
  - Asserts: `outdoor` + `natural` light, mostly single-face detection, audio not silence, warnings not dominated by red.

Additional Sprint 15 tests to add as we complete the toolchain (still no mocks; fixture-backed):
- `Tests/MetaVisPerceptionTests/DescriptorBuilderTests.swift`
  - Asserts descriptor invariants (bounds, ordering, confidence range) + expected high-level labels on `keith_talk.mov`.
- `Tests/MetaVisServicesTests/BitesBuildTests.swift`
  - Builds `bites.json` from:
    - transcript-present path (when available), and
    - audio-only fallback path (required)
  - Asserts: stable IDs, non-overlapping or well-defined overlaps, and non-empty bites when speech exists.
- `Tests/MetaVisServicesTests/DedupeGroupTests.swift`
  - Groups bites deterministically and selects best-take using evidence (`warnings` + continuity + (optional) transcript similarity).
- `Tests/MetaVisServicesTests/VerifyCutTests.swift`
  - Asserts the validator fails fast on veto violations and flags red-dominant plans.
  - Hard constraint: if any plan/tool claims `multi_person` or `scene.indoorOutdoor != outdoor` for `keith_talk.mov`, treat it as invalid.

## Risks / notes
- Vision API availability varies by SDK; faceprint generation must be gated + versioned.
- Storing per-frame masks in JSON will explode size; use artifacts + references.
- (Security) If you pasted API keys into terminals/chat, rotate them; we should treat them as compromised.
