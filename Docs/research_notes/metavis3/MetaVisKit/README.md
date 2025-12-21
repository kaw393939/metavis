# MetaVisKit - Agent Mission Control

## 1. Mission
**"The Brain"**
MetaVisKit is the unified high-level API for macOS, iOS, and visionOS. It orchestrates the specialized modules (Simulation, Perception, Timeline) to perform complex tasks. It is the **only** module that client apps should import.

## 2. Current State
- [x] Directory Structure Created
- [x] Legacy Code Migrated (`legacy_sources/`)
- [ ] Architecture Defined
- [ ] API Surface Designed
- [ ] Integration Tests Passing

## 3. Legacy Intelligence
- **Sources**: `./legacy_sources/`
    - `MetaVisRender.swift`: The original monolithic entry point.
- **Tests**: `./legacy_tests/`
    - `MetaVisRenderTests.swift`: High-level integration tests.

## 4. Documentation
- **[Architecture](./docs/architecture.md)**: (To Be Created) The `MetaVisSystem` singleton and `MetaVisSession` lifecycle.
- **[Spec](./docs/sprints/future/spec.md)**: API requirements.
- **[TDD Plan](./docs/tdd_plan.md)**: (To Be Created) Integration testing strategy.

## 5. Task List
### Phase 1: The API Surface
1. [ ] **Design**: Define the public `MetaVisSystem` actor.
2. [ ] **Orchestrate**: Implement `load(project:)` which delegates to `MetaVisCore` and `MetaVisIngest`.
3. [ ] **Render**: Implement `render(timeline:)` which delegates to `MetaVisSimulation`.

### Phase 2: Platform Support
1. [ ] Create `MetaVisView` for SwiftUI (macOS/iOS).
2. [ ] Create `MetaVisVolume` for visionOS.
