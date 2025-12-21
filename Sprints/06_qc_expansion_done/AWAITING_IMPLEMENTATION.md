# Awaiting Implementation

## Status
- ✅ Sprint is complete (expanded QC metrics + metadata + sidecar QC embedded in deliverables).

## Gaps & Missing Features
- **Meaningful caption content**: Caption sidecars may be empty without transcription; speech-to-text integration is planned work.
- **Curated thresholds/presets**: QC thresholds exist, but presets per deliverable/genre are future work.

## Technical Debt
- **Policy distribution**: Decide where enforcement presets live (e.g., `PolicyLibrary` bundles) and how creators choose them.

## Recommendations
- Add curated `QualityPolicyBundle` presets that opt into content enforcement for specific workflows.
- When ready, connect captions to a speech-to-text provider and add QC rules for cue coverage.
