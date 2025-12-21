# MetaVisExport - Agent Mission Control

## 1. Mission
**"The Hands"**
MetaVisExport is responsible for writing the final output. It takes rendered frames (from Simulation) and mixed audio (from Audio) and encodes them into a distribution format (HEVC, ProRes) using `VideoToolbox`.

## 2. Current State
- [x] Directory Structure Created
- [x] Legacy Code Migrated (`legacy_sources/`)
- [ ] Zero-Copy Pipeline Ported
- [ ] Muxer Ported
- [ ] Tests Passing

## 3. Legacy Intelligence
- **Sources**: `./legacy_sources/`
    - `Export/`: `VideoExporter`, `VideoToolboxEncoder`.
- **Tests**: `./legacy_tests/`
    - `VideoExportTests.swift`: Output verification.

## 4. Documentation
- **[Spec](./docs/sprints/future/spec.md)**: Requirements for Zero-Copy Metal interop.

## 5. Task List
### Phase 1: Encoding
1. [ ] **VideoToolbox**: Port `VideoToolboxEncoder`. Ensure it accepts `CVPixelBuffer` directly from Metal.
2. [ ] **Configuration**: Support HEVC 10-bit and ProRes 4444.

### Phase 2: Muxing
1. [ ] **Writer**: Implement `AVAssetWriter` logic to combine Audio and Video.
