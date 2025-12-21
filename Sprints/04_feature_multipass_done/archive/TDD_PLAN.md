# Sprint 04 — TDD Plan (Multi-pass)

## Tests (write first)

### 1) `MultiPassFeatureTests.test_blur_multipass_produces_expected_hash()`

- Location: `Tests/MetaVisSimulationTests/Features/MultiPassFeatureTests.swift`
- Steps:
  - Use Metal engine to render a deterministic generator frame.
  - Apply a multi-pass feature (e.g., Gaussian blur H then V).
  - Downsample deterministically and compute a hash.
  - Assert hash matches expected value.

### 2) `FeatureManifestPassesTests.test_manifest_decodes_passes_with_named_io()`

- Validate JSON/schema for multi-pass manifests, including named inputs/outputs (intermediates).

### 3) `MultiPassFeatureTests.test_pass_order_is_stable_for_motion_graphics_style_chains()`

- Build a synthetic multi-pass chain (displacement → chromatic aberration → optional blur) using the same pass semantics.
- Assert the engine executes passes in declared order and produces deterministic output for fixed input.

### 3b) `MultiPassFeatureTests.test_logical_pass_names_resolve_to_concrete_metal_functions()`

- Mirrors the metavis3 pattern where a logical node/pass name (e.g. `jwst_composite`) is mapped by the engine to a concrete Metal function (e.g. `jwst_composite_v4`).
- Assert the resolution is deterministic and failures are actionable (missing function reports available names).

### 4) `MultiPassFeatureTests.test_named_intermediates_support_perception_inputs()`

- Build a synthetic chain that consumes named intermediates (e.g. `person_mask`, `depth_map`) as explicit inputs.
- Assert wiring works (missing inputs throw), and pass ordering remains stable.
- Note: perception/ML generation itself is validated with tolerant metrics (not strict hashes).

### 5) `PassSchedulerTests.test_topological_sort_resolves_dependencies()` (New for v2)

- Define a graph with A->B->C dependencies via named intermediates.
- Assert that `PassScheduler` produces the correct execution order [A, B, C].
- Assert that circular dependencies throw a specific error.

### 6) `ShaderRegistryTests.test_logical_name_aliasing()` (New for v2)

- Register `std_blur` -> `gaussian_blur_v2`.
- Request `std_blur`.
- Assert it returns the function pointer for `gaussian_blur_v2`.

## Production steps

1. Extend `FeatureManifest` to support `passes` (array of kernels + named IO).
2. Update engine execution to allocate deterministic intermediates keyed by pass output names.
3. Update standard features / manifests for one multi-pass feature.

## Definition of done

- Multi-pass works end-to-end on real Metal execution and is deterministic.

Reference for later perf work: `Docs/research_notes/legacy_autopsy_optimizations_apple_silicon.md`
