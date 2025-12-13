# Sprint 10 — Feature Registry Hardening (Schema + Validation)

## Goal
Make feature manifests reliable for long-term evolution:
- schema versioning
- validation (required fields, ranges, ports)
- loader assertions around resource layout

Alignment: manifests are the basis for a future marketplace of templates (titles/intros), looks/LUTs, and audio chains.

## Acceptance criteria
- `FeatureManifest` has an explicit schema version and supports forward-compat checks.
- Validation runs on load and rejects invalid manifests with actionable errors.
- Validation checks structural compatibility between declared ports and runtime implementation expectations (e.g. expected input count/types), to prevent “contract mismatch” failures.
- Tests cover:
  - valid manifests load
  - invalid manifests fail validation
  - resource layout assumption is documented/validated (bundle flattening)

## Existing code likely touched
- `Sources/MetaVisSimulation/Features/FeatureManifest.swift`
- `Sources/MetaVisSimulation/Features/FeatureRegistryLoader.swift`
- `Sources/MetaVisGraphics/Resources/Manifests/*.json`
- `Tests/MetaVisSimulationTests/Features/RegistryLoaderTests.swift`

## New code to add
- `Sources/MetaVisSimulation/Features/FeatureManifestValidation.swift`
- Add at least one intentionally-invalid manifest resource for tests.

## Deterministic generated-data strategy
- Use bundled JSON manifests as “generated data”; keep them deterministic.

## Test strategy (no mocks)
- Use real bundle resources.
- Validation is pure + deterministic.
