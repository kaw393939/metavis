# Sprint 17 — Auto Speaker Audio (Deterministic Propose + Optional QA)

## Goal
Provide an automatic, deterministic audio enhancement proposal for spoken-word content (cleanup + leveling) derived from sensors/descriptors, optionally refined via the Feedback Loop.

## Inputs
- `MasterSensors` audio warnings and metrics:
  - `audio_noise_risk`
  - `audio_clip_risk`
  - silence segmentation
  - peak/RMS windows (as available)

## Output
### Canonical output (machine-stable)
Produce a single deterministic `AudioProposal` artifact (JSON-serializable) that can represent effect applications and/or intent-style commands.

`AudioProposal` (v1):
- `proposalId`: stable hash of (inputs + seed + policy version)
- `seed`: String (defaulted if not provided)
- `targetingPolicy`: `firstClip | allClips | selectedClips` (v1: `firstClip`)
- `target`: `{ firstClip: true }` (v1) or `{ clipId: "..." }` (future)
- `chain[]`: ordered ops
  - `{ kind: "effect", effectId: "audio.dialogCleanwater.v1", params: { ... } }`
  - `{ kind: "command", commandId: "...", args: { ... } }`
- `confidence`: 0..1
- `flags[]`: e.g. `noiseRisk`, `clipRisk`, `silenceHeavy`
- `whitelist`: `ParameterWhitelist` (ranges + max deltas per QA cycle)
- `metricsSnapshot` (optional): key audio sensor numbers used (e.g. approx peak, approx RMS dBFS)
- `reasoning[]`: deterministic text strings (audit/debug)

### Loudness terminology (v1)
v1 should not claim LUFS targeting unless true LUFS is computed. Use “relative leveling” and “peak safety” language.
If a target is expressed, name it explicitly as an approximation (e.g. `approxTargetRMSdBFS`).

## Contracts (from Sprint 16)
- Proposal output must be representable as deterministic effect applications/params plus a `ParameterWhitelist` for bounded edits.
- QA results must be normalized into `AcceptanceReport`.
- Evidence for QA must be emitted as an `EvidencePack` (short audio snippets by default + required textSummary).

## Strategy (v1)
- If noise risk is present: enable dialog cleanup preset.
- If clip risk is present: reduce gain (and/or limiter strategy when available).
- Keep changes bounded and explainable.

### Conservative bounds (numeric; becomes the whitelist)
Define conservative policy as hard bounds (v1 examples):
- max gain change per proposal: ±6 dB
- max gain delta per QA cycle: ±2 dB
- noise-reduction strength: conservative preset only (no aggressive tuning)
- EQ: small, speech-oriented moves only (bounded band gains)

If `audio_noise_risk` or `audio_clip_risk` is present:
- allow slightly wider bounds, but still capped and whitelisted

### Silence policy (explicit)
- Silence segmentation is used for analysis (profiling, baselines), not for editorial changes.
- v1 must not auto-gate, trim, or cut audio based on silence.

## QA integration
- Evidence pack: short audio snippets (default 2s), optionally with 1–2s video for sync.
- Rubric: intelligibility, noise reduction artifacts, clipping evidence, loudness consistency.

Evidence hints (minimal; strategy-driven):
- noise-risk windows
- near-clip peak windows
- typical speech baseline
- silence→speech transitions

### Deterministic evidence selection rule (even if QA is off)
Selection MUST be deterministic given (sensors, descriptors, config, seed).
Emit chosen timestamps/windows in the EvidencePack manifest even if QA is off.

### Machine-readable violations (maps to `AcceptanceReport.violations[]`)
Use stable codes:
- `INTELLIGIBILITY_LOW`
- `NOISE_ARTIFACTS_PRESENT`
- `CLIPPING_PRESENT`
- `LOUDNESS_INCONSISTENT`

## Non-goals (v1)
- Music mixing.
- Multi-track stem separation.
- No voice cloning, synthesis, or content alteration.
- No timing/stretching, prosody, or pitch changes.

## Outputs
- Proposed chain + confidence + reasoning.
- Optional QA cycle artifacts.
- Always write the canonical `AudioProposal` JSON into the run folder.
