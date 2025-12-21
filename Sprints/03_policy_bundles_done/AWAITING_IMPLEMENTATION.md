# Awaiting Implementation

## Status
- ✅ Sprint is complete (policy bundle + persistence).

## Gaps & Missing Features
- (Resolved) **Policy Persistence**: `Sources/MetaVisCore/PolicyLibrary.swift` stores/loads named `QualityPolicyBundle` presets.
- **Dynamic Adjustment**: Out of scope for v1; no ability to adjust based on incoming media (e.g. variable frame rate handling).

## Technical Debt
- None major, code is clean struct-based data models.

## Recommendations
- Add media-aware policy adaptation if needed (e.g., VFR normalization policy hints).
