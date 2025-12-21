# Sprint 12 — TDD Plan (Backlog Only)

This sprint is planning-only. The goal is to record testable acceptance criteria and candidate E2E strategies so future sprints can be implemented “no mocks” with deterministic data.

## Candidate no-mock E2E tests (future)

### 0) `EXRReferenceE2ETests.test_exr_is_native_reference_format()`
- Fixture: one or more EXR reference images/sequences (scene-linear ACEScg), including HDR values > 1.0.
- Run: ingest → render (passthrough graph) → frame-dump back to EXR.
- Assert: values > 1.0 preserved within half-float quantization tolerance; dimensions unchanged; channel semantics correct.

### 0b) `EXRSafetyContractTests.test_non_finite_values_are_sanitized()`
- Fixture: synthetic EXR containing NaN/Inf and huge finite magnitudes.
- Run: ingest → render (passthrough) → readback.
- Assert: NaN/Inf become finite (policy-defined, e.g. 0); huge finite values clamp to Float16 range before GPU work.

### 1) `IngestE2ETests.test_folder_drop_import_builds_timeline()`
- Deterministic test data: generated media (procedural video/audio) + synthetic metadata files.
- Contract: dropping files into an ingest directory triggers import, integrity checks, and timeline assembly.
- Assert: project state includes clips, correct durations, and stable ordering.

### 1b) `FITSIngestE2ETests.test_fits_import_reads_sci_extension()`
- Fixture: one of the local JWST Carina FITS assets under `assets/`.
- Run: FITS ingest/import.
- Assert: primary HDU may be empty, but the first image extension (e.g. `SCI`) is loaded; dimensions match expected; pixel type is Float32.

### 1c) `JWSTCompositeContractTests.test_composite_contract_matches_shader_inputs()`
- Build a minimal graph using the JWST composite feature.
- Assert: the declared ports (count/types) match the implementation contract (e.g. v46 density+color), or the v45 path is explicitly supported and tested.

### 2) `DialogCleanwaterE2ETests.test_dialog_cleanup_pipeline_produces_audible_export()`
- Deterministic audio: `ligm://audio/sine?freq=1000` mixed with deterministic noise.
- Run: dialog cleanup chain (noise reduction + loudness normalization).
- Export: `.mov` with audio.
- Assert: `VideoQC.assertAudioNotSilent` and loudness within tolerance.

### 3) `CaptionE2ETests.test_export_deliverable_writes_srt_vtt()`
- Generate deterministic transcript input (fixture JSON) without calling network models.
- Produce: `.srt`/`.vtt` sidecars in deliverable bundle.
- Assert: decodable, timecodes monotonic, within duration.

### 4) `PrivacyPolicyTests.test_upload_policy_defaults_to_no_raw_media()`
- Policy bundle includes upload permissions.
- Assert: default is deliverables-only (or none), and raw uploads require explicit opt-in.

### 5) `LANRenderDeviceE2ETests.test_local_device_catalog_can_register_remote_worker()`
- Start with loopback/local fake worker as a real process later (integration gated).
- Assert: scheduling selects a worker based on capabilities.

### 6) `IngestIPhoneFootageE2ETests.test_import_preserves_color_and_audio_metadata()`
- Fixture: a small set of local test assets representing “highest quality” iPhone outputs (HEVC 10-bit HDR; ProRes if available).
- Run: ingest/import pipeline.
- Assert: persisted metadata includes transfer function / primaries / matrix, audio channel count/layout, and orientation.

### 7) `IngestIPhoneFootageE2ETests.test_vfr_normalization_preserves_av_sync()`
- Fixture: VFR clip + deterministic audio marker track.
- Run: normalize into a timeline and export.
- Assert: exported audio marker aligns with expected video event within tolerance.

### 8) `PerceptionVisionE2ETests.test_person_segmentation_produces_mask()`
- Fixture: a deterministic synthetic frame with a clear foreground silhouette (or a small local test still).
- Run: `PersonSegmentationService.generateMask` (Vision request).
- Assert: mask is non-nil, expected pixel format, and foreground coverage ratio is within a tolerant range.

### 9) `PerceptionDepthE2ETests.test_depth_estimator_produces_depth_map_when_model_available()`
- Fixture: a deterministic synthetic frame with simple depth cues.
- Run: depth estimation service.
- Assert: depth map texture exists; summary metrics (min/max/mean) within tolerant bounds.
- Note: avoid strict hashing; ML inference varies across hardware/OS.

### 10) `PerceptionOpticalFlowE2ETests.test_optical_flow_detects_motion_direction()`
- Fixture: two deterministic frames with known translation.
- Run: optical flow.
- Assert: average magnitude > 0 and dominant direction aligns with expected vector within tolerance.

## Definition of done (for planning)
- Backlog items are phrased as testable acceptance criteria.
- Each item has a deterministic test strategy sketched.
