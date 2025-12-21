# MetaVisSimulation - Agent Mission Control

## 1. Mission
**"The Visual Cortex"**
MetaVisSimulation is the rendering engine. It takes a `RenderManifest` (from Core) and a `Timeline` (from Timeline) and produces pixels using Metal. It must support the "Cleanroom" engine standards: 16-bit float HDR, Zero-Copy, and Determinism.

## 2. Current State
- [x] Directory Structure Created
- [x] Legacy Code Migrated (`legacy_sources/`)
- [ ] Metal Context Initialized
- [ ] Graph Engine Ported
- [ ] Cinematic Pass Ported

## 3. Legacy Intelligence
- **Sources**: `./legacy_sources/`
    - `Engine/`: The core render loop.
    - `Shaders/`: Metal shader library (`.metal` files).
    - `Effects/`: Cinematic effects (Bloom, Grain).
    - `Text/`: SDF Glyph rendering.
- **Tests**: `./legacy_tests/`
    - `RenderEngineTests.swift`: Basic render loop verification.
    - `BloomPassTests.swift`: Visual regression tests.

## 4. Documentation
- **[Architecture](./docs/architecture.md)**: (To Be Created) The Render Graph pipeline.
- **[Spec](./docs/sprints/future/spec.md)**: Requirements for ACES, Zero-Copy, and Effects.
- **[TDD Plan](./docs/tdd_plan.md)**: (To Be Created) Shader unit testing and visual verification.

## 5. Task List
### Phase 1: The Engine
1. [ ] **Context**: Port `RenderContext` (Metal device management).
2. [ ] **Loop**: Implement the main `render(frame:)` loop.
3. [ ] **Graph**: Port `GraphPipeline` to support node-based rendering.

### Phase 2: The Look
1. [ ] **Shaders**: Move `.metal` files to `Sources/MetaVisSimulation/Resources/`.
2. [ ] **Cinematic**: Port the 12-stage `CinematicLookPass`.
3. [ ] **Text**: Port `GlyphManager` (SDF).
