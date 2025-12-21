# Sprint 13 Audit: FCP Parity

## Status: Partially Implemented

## Accomplishments
- **Timeline Model**: `Clip` supports `startTime`, `duration`, `offset`, and `effects`.
- **Video Compilation**: `TimelineCompiler` handles overlapping clips, transitions (alpha), and ACEScg working space.
- **Time Mapping**: File-backed sources correctly use `(time - clip.startTime) + clip.offset`.
- **Basic Commands**: `IntentCommand` supports `applyColorGrade`, `trimEnd`, and `retime`.

## Gaps & Missing Features
- **Retime (Render Semantics)**: `mv.retime` exists as an intrinsic clip effect/command, but the render pipeline does not currently apply retiming during compilation; exports are not expected to reflect retime.
- **Transition Logic (Type-Specific)**: `TransitionType` supports `.dip`/`.wipe` in the model, but the compiler currently uses transitions only to compute alpha; type-specific compositing is not implemented.

## Performance Optimizations
- **ACEScg Thread**: The compiler enforces a consistent working space, which simplifies effect implementation and ensures color correctness.

## Low Hanging Fruit
- Implement retime time-mapping in the video compiler (and eventually audio) so that retime has observable export effects.
- Either implement `.dip`/`.wipe` compositing or mark them explicitly out-of-scope for “fade/crossfade only” parity.
