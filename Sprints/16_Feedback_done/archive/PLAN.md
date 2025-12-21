# Sprint 16 — Feedback Loop (Evidence Packs + Pluggable QA)

## Goal
Build a reusable, DRY “feedback loop” system that any auto-feature (color, audio, editing, text layout, titles) can use.

## Core concept
**Evidence Pack**: a budgeted set of high-signal evidence selected from sensors/descriptors so we can QA without rendering/uploading full deliverables.

Evidence pack may contain:
- `frames[]`: JPEGs at chosen timestamps
- `videoClips[]`: micro-clips (e.g. 1–2s) at chosen timestamps
- `audioClips[]`: short audio snippets (default 2s; escalate if needed)
- `textSummary`: always present (sensors + descriptors + proposal diff + constraints)

## Contracts (make this explicit)

### `EvidencePack` (canonical shape)
Evidence is a **budgeted**, **auditable** bundle produced deterministically from sensors/descriptors.

- `manifest`
  - `cycleIndex`: Int
  - `seed`: String? (optional; for reproducible selection in QA-on runs)
  - `budgetsConfigured`: counts/seconds caps
  - `budgetsUsed`: counts/seconds actually used
  - `timestampsSelected[]`: `Double` (sorted)
  - `selectionNotes[]`: strings (brief; no prose essays)
- `assets`
  - `frames[]`: `{ path, timeSeconds, rationaleTags[] }`
  - `videoClips[]`: `{ path, startSeconds, endSeconds, rationaleTags[] }`
  - `audioClips[]`: `{ path, startSeconds, endSeconds, rationaleTags[] }`
- `textSummary` (ALWAYS present)
  - sensors digest
  - descriptors digest
  - proposal(s) for this cycle
  - diff vs last cycle
  - constraints + whitelist
  - budgets configured/used/remaining

Example JSON (shape only):
```json
{
  "manifest": {
    "cycleIndex": 0,
    "seed": "optional-seed",
    "budgetsConfigured": {
      "maxFrames": 8,
      "maxVideoClips": 4,
      "videoClipSeconds": 1.5,
      "maxAudioClips": 4,
      "audioClipSeconds": 2.0
    },
    "budgetsUsed": {
      "frames": 6,
      "videoClips": 2,
      "audioClips": 3,
      "totalAudioSeconds": 6.0,
      "totalVideoSeconds": 3.0
    },
    "timestampsSelected": [0.0, 12.0, 37.5],
    "selectionNotes": ["risk=audio_noise", "risk=highlights"]
  },
  "assets": {
    "frames": [
      {"path": "frames/f_001.jpg", "timeSeconds": 12.0, "rationaleTags": ["highlights", "face"]}
    ],
    "videoClips": [
      {"path": "video/v_001.mp4", "startSeconds": 36.75, "endSeconds": 38.25, "rationaleTags": ["framing_jump"]}
    ],
    "audioClips": [
      {"path": "audio/a_001.m4a", "startSeconds": 120.0, "endSeconds": 122.0, "rationaleTags": ["noise_risk"]}
    ]
  },
  "textSummary": "..."
}
```

### `AcceptanceReport` (normalized QA output)
QA engines should normalize into a single contract so the loop can apply edits safely.

- `accepted: Bool`
- `score: Double?` (0..1, optional)
- `reasons[]: String` (human-readable)
- `violations[]: String` (machine-readable codes)
- `suggestedEdits[]`: bounded, whitelist-friendly edits
- `requestedEvidenceEscalation?`: targeted request when evidence is insufficient

### `ParameterWhitelist` (first-class safety object)
Whitelist defines the edit space and bounds. The edit applier MUST enforce it.

- allowed params + min/max
- max delta per cycle
- explicit "no-go" params

## QA loop
- Runs in 0..N cycles (default N=2).
- Cycle structure:
  1) Build deterministic proposal(s) (e.g., grade params, audio chain, edit decisions)
  2) Select evidence pack using sensors + descriptors (budgeted)
  3) Run QA backend (Gemini multimodal or local text-only)
  4) If not accepted, apply bounded edits within a whitelisted parameter space

## Escalation ladder (budgeted; no churn)
- Cycle 0: build the smallest default pack.
- If QA reports insufficient evidence AND budgets remain:
  - add targeted evidence only (e.g., +2 frames at failure timestamps; extend ONE audio window from 2s → 5s)
- Hard stop if budgets exceeded or cycles exhausted.

## Requirements
- **Pluggable backends**:
  - `GeminiQAEngine` (multimodal when allowed)
  - `LocalTextQAEngine` (no media; textSummary only)
- **LLM independence**: all features must produce a usable output with QA off.
- **Budget control**: configure max frames/clips/seconds to minimize network + runtime.
- **Async parallelism** inside a single command:
  - parallel evidence extraction (frames/audio/video)
  - bounded-concurrency QA calls (e.g. max 2 concurrent)
  - progress reporting to avoid “stuck” runs

Note: QA concurrency applies when evaluating multiple proposals/features in the same cycle (e.g. color+audio) and/or running A/B candidate proposals. Otherwise, expect 1 QA call per cycle.
- **Governance**:
  - ability to turn QA on/off
  - explicit opt-in gate for network calls (e.g. `RUN_GEMINI_QC=1`)
  - respect deliverables-only upload policies

## Determinism policy
- Proposal generation MUST be deterministic given (sensors, descriptors, config, seed).
- Evidence selection MUST be deterministic given (sensors, descriptors, config, seed).
- QA-on runs are inherently nondeterministic because model output varies; however, the run folder must still be auditable via:
  - fixed evidence selection
  - recorded prompts
  - recorded model responses

Add an optional CLI `--seed` to stabilize evidence selection in QA-on runs.

## Privacy / IO policy
- QA backends may only receive Evidence Pack assets by default.
- Full deliverable uploads are forbidden unless explicitly enabled by a dedicated opt-in flag/policy.
- Network calls must require explicit opt-in (e.g. `RUN_GEMINI_QC=1`) and log this state into the run folder manifest.

## Evidence strategies (feature-provided hints)
Evidence selection should be strategy-driven but minimal:
- Auto Color: highlights/shadows extremes, skin/face frames when available, transitions.
- Auto Audio: noise-risk windows, near-clip peaks, typical speech baseline, silence→speech transitions.
- Auto Edit: cut candidates, pacing-risk windows, transcript spans (when available).

## Proposed CLI surface (MetaVisLab)
A single command that orchestrates:
- sensors ingest (or reuse existing sensors)
- auto proposals (color/audio/content)
- optional QA loop

Flags (draft):
- `--qa off|gemini|local-text` (default: off)
- `--qa-cycles <n>` (default: 2)
- `--qa-max-frames <n>` (default: 8)
- `--qa-max-video-clips <n>` (default: 4)
- `--qa-video-clip-seconds <s>` (default: 1.5)
- `--qa-max-audio-clips <n>` (default: 4)
- `--qa-audio-clip-seconds <s>` (default: 2.0)
- `--qa-max-concurrency <n>` (default: 2)
- `--seed <string>` (optional; stabilizes evidence selection)

## Non-goals (v1)
- No background job daemon / queue.
- No UI.
- No full deliverable renders per cycle unless explicitly requested.

## Outputs
Write a run folder with:
- proposed recipes/commands (initial + per-cycle revisions)
- evidence pack assets
- QA raw response + cleaned JSON
- final decision summary

## Risks
- Determinism: QA-on runs are inherently nondeterministic. Ensure QA-off is deterministic.
- Cost/runtime: must keep evidence pack small and bounded.
- Safety: restrict the editable parameter space.
