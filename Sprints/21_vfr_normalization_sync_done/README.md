# Sprint 21 — VFR normalization + sync

This sprint hardens variable frame rate (VFR) handling:

- Probe timing (`VideoTimingProbe`)
- Decide a normalization policy (`VideoTimingNormalization`)
- Apply deterministic time mapping in the renderer (`ClipReader`)
- Prove the exported deliverable is CFR-like via an end-to-end contract test

See `PLAN.md` for acceptance criteria.

`PLAN.md` also includes “Where to look” pointers (code + tests) and a concise list of remaining gaps + next steps.
