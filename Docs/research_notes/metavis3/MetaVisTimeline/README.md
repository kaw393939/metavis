# MetaVisTimeline - Agent Mission Control

## 1. Mission
**"The Conductor"**
MetaVisTimeline manages time. It handles the sequencing of clips, keyframe interpolation, and the conversion of a linear "Edit" into a spatial "Graph" for the simulation engine.

## 2. Current State
- [x] Directory Structure Created
- [x] Legacy Code Migrated (`legacy_sources/`)
- [ ] Keyframe Logic Ported
- [ ] Graph Conversion Ported
- [ ] Tests Passing

## 3. Legacy Intelligence
- **Sources**: `./legacy_sources/`
    - `Timeline/`: The core NLE data model.
    - `Animation/`: Bezier curve logic.
- **Tests**: `./legacy_tests/`
    - `TimelineToGraphTests.swift`: Critical logic for engine handoff.

## 4. Documentation
- **[Spec](./docs/sprints/future/spec.md)**: Requirements for frame-accurate editing.
- **[TDD Plan](./docs/tdd_plan.md)**: (To Be Created).

## 5. Task List
### Phase 1: The Model
1. [ ] **Time**: Adopt `CMTime` or a custom Rational time type from `MetaVisCore`.
2. [ ] **Keyframes**: Port `Keyframe` and `AnimationCurve`.

### Phase 2: The Converter
1. [ ] **Graph**: Port `TimelineToGraphConverter`. Ensure it produces a valid `NodeGraph` for `MetaVisSimulation`.
