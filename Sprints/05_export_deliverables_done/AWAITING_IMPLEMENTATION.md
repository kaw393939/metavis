# Awaiting Implementation

## Status
- ✅ Sprint is complete (deliverable bundles + sidecars + batch export).

## Gaps & Missing Features
- (None required for Sprint 05 core.)

## Technical Debt
- **Caption content is minimal**: Captions may be empty (no speech-to-text integration yet), but sidecar generation and best-effort copy-from-disk behavior are implemented.

## Recommendations
- If/when captions become non-empty, add an integration point (e.g. transcription provider) to populate cue data.
- Consider per-deliverable batch configuration (different quality/sidecars per deliverable) if needed.
