# Awaiting Implementation

## Gaps & Missing Features
- None identified.

## Technical Debt
- **Targeting surface area**: Targeting is intentionally minimal today (currently `clipId` or the backward-compatible `firstVideoClip`). Richer selectors will require careful determinism rules.

## Recommendations
- Implement a deterministic `TargetSelector` (e.g. track kind + time window + tie-break rules).
- Expand the command set only as needed by higher-level UX.
