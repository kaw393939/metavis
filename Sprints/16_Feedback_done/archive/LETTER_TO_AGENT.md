Subject: Sprint 16 — Evidence Packs + Pluggable QA: contract tweaks to prevent churn

Sprint 16 spec is the right abstraction. A few targeted tightenings will prevent future rework while keeping the system DRY and deterministic when QA is off.

1) Make `EvidencePack` a formal contract (not just prose)
- Add canonical Swift structs + JSON encoding so all auto-features + QA engines share the same shape.
- Required fields:
  - `manifest`: budgets configured + budgets used, timestamps selected, cycle index, seed
  - `assets`: frames/videoClips/audioClips each with `{path, tStart/tEnd, rationaleTags}`
  - `textSummary`: always present and includes sensors digest, descriptors digest, proposals, diff vs last cycle, constraints + whitelist, budgets used/remaining

2) Define `AcceptanceReport` explicitly
Normalize QA engine output into:
- `accepted: Bool`
- `score?: 0..1` (optional)
- `reasons[]`
- `violations[]` (machine-readable codes)
- `suggestedEdits[]` (bounded, whitelist-friendly)
- `requestedEvidenceEscalation?` (e.g., “need 2 more frames at timestamps X/Y”)

3) Add a deterministic escalation ladder (budgeted)
- Cycle 0 uses default pack.
- If QA says “insufficient evidence” and budget remains: add targeted evidence only (e.g. +2 frames at failure timestamps, extend one audio window 2s → 5s).
- Hard stop on budget/cycle exhaustion.

4) Make the whitelist first-class (governance + safety)
Implement `ParameterWhitelist` with:
- allowed params
- min/max ranges
- max delta per cycle
- no-go params
QA may propose edits, but the applier must enforce bounds strictly.

5) Determinism rules + optional seed
- Proposal generation deterministic given (sensors, descriptors, config, seed).
- Evidence selection deterministic given (sensors, descriptors, config, seed).
- Add `--seed` for reproducible evidence selection in QA-on runs.

6) Explicit privacy / IO rules
- QA backends may only receive Evidence Pack assets by default.
- No full deliverable upload unless explicitly enabled.
- Require `RUN_GEMINI_QC=1` for network and log it into the run manifest.

7) Evidence selection is strategy-driven per feature
Define an interface so AutoColor / AutoAudio / AutoEdit can provide “evidence hints” without embedding QA specifics:
- AutoColor: highlights/shadows/skin frames + transitions
- AutoAudio: noise windows, near-clip peaks, typical speech baseline
- AutoEdit: cut candidates, pacing-risk windows, transcript spans (when available)

No other changes needed — lock these contracts now so later features are plug-and-play.
