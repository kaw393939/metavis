# Sprint 10 — TDD Plan (Feature Registry Hardening)

## Tests (write first)

### A) Schema + typed validation errors

#### 1) `ManifestValidationTests.test_valid_video_manifest_passes()`
- Location: `Tests/MetaVisSimulationTests/Features/ManifestValidationTests.swift`
- Decode the bundled manifest(s) and validate.

#### 2) `ManifestValidationTests.test_invalid_missing_required_field_fails_with_typed_error()`
- Add: `Sources/MetaVisGraphics/Resources/Manifests/invalid_missing_required_field.json`.
- Assert validation fails with an actionable, typed error that includes at least: file, featureId (if present), and stable error code.

#### 3) `ManifestValidationTests.test_unknown_schema_version_fails_forward_compat()`
- Add: `Sources/MetaVisGraphics/Resources/Manifests/invalid_unknown_schema_version.json`.
- Assert forward-compat failure is explicit and actionable.

#### 4) `ManifestValidationTests.test_parameter_out_of_range_rejected()`
- Add: `Sources/MetaVisGraphics/Resources/Manifests/invalid_parameter_range.json`.
- Assert the failing JSON path/field is captured.

### B) Contract/port validation by usage context

#### 5) `ManifestValidationTests.test_clip_effect_contract_rejects_wrong_inputs()`
- Add: `Sources/MetaVisGraphics/Resources/Manifests/invalid_clip_effect_wrong_input_ports.json`.
- Assert a video clip effect must either:
	- declare exactly one image input named `source`, OR
	- declare itself as a generator (0 inputs).

#### 6) `ManifestValidationTests.test_manifest_port_contract_mismatch_fails()`
- Add an invalid fixture whose declared ports don’t match implementation expectation.
- Assert validation fails with a specific, actionable error (expected vs actual).

### C) Cross-domain ID policy (video/audio/intrinsic)

#### 7) `FeatureIDPolicyTests.test_reserved_namespaces_enforced()`
- New: `Tests/MetaVisSimulationTests/Features/FeatureIDPolicyTests.swift`.
- Validate reserved namespaces exist and are treated consistently:
	- `com.metavis.fx.*` (registry-backed)
	- `audio.*` (audio presets/chains referenced by timelines)
	- `mv.*` (timeline-intrinsic)

#### 8) `TimelineFeatureResolutionTests.test_timeline_feature_ids_resolve_or_fail_actionably()`
- New: `Tests/MetaVisSimulationTests/Features/TimelineFeatureResolutionTests.swift`.
- Build a minimal timeline with feature IDs we already reference (e.g. `audio.dialogCleanwater.v1`, `mv.retime`) and assert policy outcome is deterministic:
	- either allowlisted as intrinsic (explicitly documented),
	- or resolvable via registry,
	- otherwise rejected with an actionable error.

### D) Loader determinism + bundle layout

#### 9) `RegistryLoaderTests.test_loader_finds_manifests_in_flattened_and_subdir_layout()`
- Extend `Tests/MetaVisSimulationTests/Features/RegistryLoaderTests.swift`.
- Assert manifests can be discovered deterministically regardless of whether resources are flattened or under `Manifests/`.

#### 10) `RegistryLoaderTests.test_loader_ordering_is_deterministic()`
- Assert deterministic ordering (e.g. sort by `featureId` then `version`).

### E) Observability (Sprint 08 integration)

#### 11) `RegistryTracingTests.test_load_validate_register_emits_trace_events()`
- New: `Tests/MetaVisSimulationTests/Features/RegistryTracingTests.swift`.
- Use `InMemoryTraceSink` to assert stable trace events and fields for:
	- load begin/end
	- decode/validate failure
	- register/overwrite behavior (if applicable)

## Production steps
1. Add `schemaVersion` and a manifest domain discriminator (video/audio/intrinsic).
2. Implement typed validation errors (file + featureId + stable error code; include JSON path when feasible).
3. Run validation during `FeatureRegistryLoader.loadManifests()`.
4. Add deterministic ordering to discovery/validation.
5. Add `TraceSink` emission around load/validate/register.
6. Update tests + add invalid manifest fixtures.

## Definition of done
- Loader + validation is robust and covered by real resource-based tests.
- Registry hardening is compatible with how we reference features today (video + audio preset IDs + intrinsic timeline IDs).
- Registry operations are observable (trace assertions pass) and deterministic.
