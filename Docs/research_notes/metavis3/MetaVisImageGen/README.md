# MetaVisImageGen - Agent Mission Control

## 1. Mission
**"The Imagination"**
MetaVisImageGen houses the "Large Image Generation Model" (LIGM) and other procedural generation tools. It creates visual assets from scratch based on seeds and parameters.

## 2. Current State
- [x] Directory Structure Created
- [x] Legacy Code Migrated (`legacy_sources/`)
- [ ] LIGM Ported
- [ ] Tests Passing

## 3. Legacy Intelligence
- **Sources**: `./legacy_sources/`
    - `ImageGen/`: The generation logic.
- **Tests**: `./legacy_tests/`
    - `ImageGen/`: Unit tests.

## 4. Documentation
- **[Spec](./docs/sprints/future/spec.md)**: Requirements for deterministic generation.

## 5. Task List
### Phase 1: LIGM
1. [ ] **Port**: Migrate the LIGM logic.
2. [ ] **Determinism**: Verify that the same seed produces the exact same image.
