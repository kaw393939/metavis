# Sprint 10 — TDD Plan (Feature Registry Hardening)

## Tests (write first)

### 1) `ManifestValidationTests.test_valid_manifest_passes()`
- Location: `Tests/MetaVisSimulationTests/Features/ManifestValidationTests.swift`
- Decode the bundled SMPTE manifest and validate.

### 2) `ManifestValidationTests.test_invalid_manifest_fails_with_error()`
- Add `Sources/MetaVisGraphics/Resources/Manifests/invalid_missing_kernel.json`.
- Assert validation fails with a specific error.

### 3) `RegistryLoaderTests.test_loader_reports_bundle_layout()`
- Add a loader assertion test ensuring manifests can be found regardless of subdirectory flattening.

### 4) `ManifestValidationTests.test_manifest_port_contract_mismatch_fails()`
- Add an invalid manifest fixture whose declared input ports don’t match the implementation expectation (e.g. wrong input count).
- Assert validation fails with a specific, actionable error (expected vs actual).

## Production steps
1. Add schema version field and validation layer.
2. Run validation during `FeatureRegistryLoader.loadManifests()`.
3. Update tests and resources.

## Definition of done
- Loader + validation is robust and covered by real resource-based tests.
