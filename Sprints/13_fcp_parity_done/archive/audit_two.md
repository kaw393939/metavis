# Sprint 13 Audit: FCP Parity

## Status: Partially Implemented

## Accomplishments
- **Timeline**: `Clip` offset/time mapping model.
- **Compiler**: Handles standard compositing.
- **Commands**: Basic trim/retime.

## Gaps & Missing Features
- **Retime (Render Semantics)**: `mv.retime` exists as an intrinsic clip effect/command, but compilation ignores intrinsic effects; exports are not expected to reflect retime.
- **Transitions (Type-Specific)**: `TransitionType` includes `.dip`/`.wipe`, but the compiler uses transitions only for alpha fades/crossfades; type-specific compositing is not implemented.

## Technical Debt
- **Retime Time Mapping**: Retiming likely belongs in time mapping (not a Metal node) and needs consistent application.

## Recommendations
- Implement retime time mapping so exports reflect speed changes.
- Implement `.dip`/`.wipe` compositing or explicitly de-scope them from Sprint 13 parity.
