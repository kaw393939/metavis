# MetaVisTimeline - Specification

## Goals
1.  Manage the temporal arrangement of clips and effects.
2.  Drive parameters via animation curves.

## Requirements
- **Precision**: Must use `CMTime` or rational time for frame-accurate editing.
- **Interpolation**: Must support Linear, Bezier, and Constant keyframe interpolation.
- **Conversion**: Must deterministically convert a Timeline state into a Render Graph for `MetaVisSimulation`.
