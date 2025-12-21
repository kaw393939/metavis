# Awaiting Implementation

## Gaps & Missing Features
None required for Sprint 13.

## Optional / Out of Scope (for Sprint 13)
- **Transition Types**: `TransitionType.dip` and `.wipe` are modeled but not implemented (compiler is alpha-only). Sprint 13 parity requires fades/crossfades only.

## Technical Debt
- **Retime Time Mapping**: Retiming is implemented as time-mapping (not a Metal node). Future work should apply the same mapping consistently across audio as well.

## Recommendations
- Keep `.dip`/`.wipe` as a future sprint item (or remove from the model if we decide not to support them).
