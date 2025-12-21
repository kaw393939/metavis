# Sprint 16 — Auto Color Correct (Deterministic Propose + Optional QA)

## Goal
Provide an automatic, deterministic color correction proposal (grade parameters / feature applications) derived from sensors/descriptors, optionally refined via the Feedback Loop (Sprint 16).

## Inputs
- `MasterSensors` + descriptors:
  - `grade_confidence_low`
  - `avoid_heavy_grade`
  - exposure/contrast/saturation-related signals (as available)
  - face presence / luma histogram if present

## Output
### Canonical output (machine-stable)
Produce a single deterministic `GradeProposal` artifact (JSON-serializable) that can represent either feature applications or intent commands.

`GradeProposal` (v1):
- `proposalId`: stable hash of (inputs + seed + policy version)
- `seed`: String (defaulted if not provided)
- `targetingPolicy`: `firstClip | allClips | selectedClips` (v1: `firstClip`)
- `target`: `{ firstClip: true }` (v1) or `{ clipId: "..." }` (future)
- `ops[]`:
  - `{ kind: "feature", featureId: "com.metavis.fx.grade.simple", params: { ... } }`
  - `{ kind: "intent", commandId: "applyColorGradeToFirstVideoClip", args: { ... } }`
- `confidence`: 0..1
- `flags[]`: `avoidHeavyGrade`, `gradeConfidenceLow`, etc.
- `whitelist`: `ParameterWhitelist` (ranges + max deltas per cycle)
- `metricsSnapshot` (optional): key sensor numbers used (e.g. median luma, highlight clip fraction)
- `summary[]`: deterministic reasoning strings (audit-friendly)

## Contracts (from Sprint 16)
- Proposal output must be representable as deterministic params/commands plus a `ParameterWhitelist` for bounded edits.
- QA results must be normalized into `AcceptanceReport`.
- Evidence for QA must be emitted as an `EvidencePack` (frames/micro-clips + required textSummary).

## Strategy (v1)
- Conservative defaults; do not apply heavy looks if descriptors indicate low confidence.
- Fix obvious technical issues first (gross exposure, mild saturation normalization).

### Conservative bounds (numeric; becomes the whitelist)
Define conservative policy as hard bounds (v1 example for `com.metavis.fx.grade.simple`):
- `exposure`: clamp to [-0.35, +0.35] per proposal
- `contrast`: clamp to [0.90, 1.15] per proposal
- `saturation`: clamp to [0.90, 1.20] per proposal
- `temperature`: clamp to [-0.30, +0.30] per proposal
- `tint`: clamp to [-0.15, +0.15] per proposal

If `grade_confidence_low || avoid_heavy_grade`:
- tighten bounds further (e.g. exposure [-0.20, +0.20], saturation [0.95, 1.10])
- prefer “do nothing” over guessing

## QA integration
- Evidence pack: frames + (optional) 1–2s micro-clips.
- Rubric: exposure, WB cast, skin tone plausibility, highlight clipping, consistency.

Evidence hints (minimal; strategy-driven):
- highlight/shadow extremes
- face/skin frames when available
- scene transitions

### Deterministic evidence selection rule (even if QA is off)
Selection MUST be deterministic given (sensors, descriptors, config, seed).

Default frame timestamps (budgeted):
- 1× highlight extreme
- 1× shadow extreme
- 1× face/skin frame if present
- 1× near a scene/transition boundary if detected
- fill remainder with evenly spaced sampling

Even when QA is off, still emit the selected timestamps (and optionally frames) for audit/debugging.

### Machine-readable violations (maps to `AcceptanceReport.violations[]`)
Use stable codes:
- `EXPOSURE_TOO_LOW`, `EXPOSURE_TOO_HIGH`
- `WB_CAST_STRONG`
- `SKIN_TONE_IMPLAUSIBLE`
- `HIGHLIGHT_CLIPPING`
- `INCONSISTENT_ACROSS_FRAMES`

## Non-goals (v1)
- No creative looks.
- No shot-by-shot matching.
- No IDT/ODT or color-management transform changes.

## Outputs
- Proposed grade parameters + confidence + reasoning.
- Optional QA cycle artifacts.
- Always write the canonical `GradeProposal` JSON into the run folder.
