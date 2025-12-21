# MetaVisCalibration - Agent Mission Control

## 1. Mission
**"The Standard"**
MetaVisCalibration is the source of truth for Color Science. It defines the ACES pipeline, color space transforms, and validation logic. It ensures that "Red" is mathematically "Red".

## 2. Current State
- [x] Directory Structure Created
- [x] Legacy Code Migrated (`legacy_sources/`)
- [ ] ACES Matrices Ported
- [ ] Validation Logic Ported
- [ ] Tests Passing

## 3. Legacy Intelligence
- **Sources**: `./legacy_sources/`
    - `Color/`: Contains `ColorSpace.metal` (legacy shader code to be adapted to Swift/Metal shared types) and validation logic.
- **Tests**: `./legacy_tests/`
    - `ColorDebugTest.swift`: Validation tests.

## 4. Documentation
- **[Spec](./docs/sprints/future/spec.md)**: ACES and Lab Delta E requirements.
- **[TDD Plan](./docs/tdd_plan.md)**: (To Be Created) Numerical accuracy verification.

## 5. Task List
### Phase 1: Color Science
1. [ ] **Matrices**: Define `ACES` constants (AP0, AP1, D60) in Swift.
2. [ ] **Transforms**: Implement `RGB <-> XYZ <-> Lab` conversions.

### Phase 2: Validation
1. [ ] **Delta E**: Implement `DeltaE 2000` algorithm.
2. [ ] **Verifier**: Create a tool to compare a rendered frame against a reference chart.
