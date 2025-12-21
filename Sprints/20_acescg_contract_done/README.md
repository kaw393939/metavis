# Sprint 20 — ACEScg Contract

This sprint codifies the working-color-space contract:
- Rec.709 sources are converted to ACEScg via an IDT.
- Rendering/effects operate in ACEScg.
- Preview/export is converted back to Rec.709 SDR via an ODT.
- SDR exports are tagged with explicit Rec.709 color metadata.

See:
- PLAN.md
- AWAITING_IMPLEMENTATION.md
- IMPLEMENTED.md
