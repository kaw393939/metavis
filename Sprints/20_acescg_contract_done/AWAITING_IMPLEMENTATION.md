# Awaiting Implementation

## Status: Core contract complete

The narrow Sprint 20 scope (Rec.709 → ACEScg → Rec.709 SDR preview) is now codified by tests.

## Potential extensions (intentionally out of Sprint 20 scope)
- **Input transform coverage**: non-Rec.709 inputs (HDR, wide gamut, HLG/PQ, camera log) need an explicit IDT selection/override contract.
- **QC tightening**: add deterministic QC thresholds specifically for SDR preview exports (beyond metadata presence).

## Recommendations
- Keep Sprint 20 narrow and stable.
- If expanding, create a new sprint for HDR / wide-gamut ingest and ODT variants.
