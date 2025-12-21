# MetaVisCore - Agent Mission Control

## 1. Mission
**"The Nervous System"**
MetaVisCore defines the shared vocabulary, data structures, and configuration for the entire MetaVis ecosystem. It must have **zero dependencies** on other MetaVis modules to prevent circular references.

## 2. Current State
- [x] Directory Structure Created
- [x] Legacy Code Migrated (`legacy_sources/`)
- [x] Architecture Defined (Virtual Studio / Creative OS)
- [x] Core Session Data (`MetaVisSession`, `CastRegistry`)
- [ ] Virtual Device Protocol (`VirtualDevice`)
- [ ] Tests Passing

## 3. Legacy Intelligence
The following legacy files contain the "DNA" for this module:
- **Sources**: `./legacy_sources/`
    - `Data/RenderManifest.swift`: The core project structure (Scene, Camera, Layers).
    - `Data/RenderJob.swift`: The unit of work.
    - `Core/TimelineClock.swift`: Timing logic.
    - `Utils/`: General extensions.
- **Tests**: `./legacy_tests/`
    - `Manifest/`: Tests for JSON serialization/deserialization.

## 4. Documentation
- **[SPEC](./SPEC.md)**: The Master Specification for the Virtual Studio Architecture.
- **[Architecture](./docs/architecture.md)**: (To Be Created) Defines the thread-safe, Sendable type system.
- **[Data Dictionary](./docs/data_dictionary.md)**: (To Be Created) Definitions of `ManifestMetadata`, `SceneDefinition`, etc.

## 5. Task List
### Phase 1: Virtual Studio Foundation
1. [x] **Session**: Implement `MetaVisSession` and `CastRegistry`.
2. [x] **Devices**: Implement `VirtualDevice` protocol and `DeviceType`.
3. [ ] **Manifest**: Refactor `RenderManifest` to support the new Device graph.
4. [ ] **Test**: Ensure all Core data structures are `Sendable` and `Codable`.

### Phase 2: Utilities
1. [ ] Port `TimelineClock` to `Sources/MetaVisCore/Time/`.
2. [ ] Port `Logger` configuration.
