# Sprint 24 — Speaker Diarization + Sticky Fusion (ECAPA‑TDNN)

**Status (2025-12-22):** DONE.

## Start Here
- Plan: `PLAN.md`
- Architecture: `ARCHITECTURE.md`
- Data dictionary: `DATA_DICTIONARY.md`
- TDD plan: `TDD_PLAN.md`

## Current Reality
- **Implemented:** ECAPA‑TDNN embeddings + deterministic clustering (when enabled), with Sticky Fusion as deterministic fallback.
- **Artifacts:** diarized `transcript.words.v1.jsonl`, governed `transcript.attribution.v1.jsonl`, `captions.vtt` voice tags, `speaker_map.v1.json`, and identity spine `identity.timeline.v1.json`.

## Run Real-Asset E2E Tests (opt-in)
The real-video diarization tests live in `DiarizeIntegrationTests` and are gated because they require whisper.cpp + heavier compute.

Required env vars:
```bash
export METAVIS_RUN_DIARIZE_TESTS=1
export METAVIS_RUN_WHISPERCPP_TESTS=1
export WHISPERCPP_BIN=/absolute/path/to/whisper.cpp/main
export WHISPERCPP_MODEL=/absolute/path/to/model.bin
```

Recommended for multi-speaker assertions:
```bash
export METAVIS_DIARIZE_MODE=ecapa
```

Optional strictness (OFFSCREEN expectations on “dirty” fixtures):
```bash
export METAVIS_DIARIZE_STRICT=1
```

Run:
```bash
swift test --filter DiarizeIntegrationTests
```

See `Docs/specs/REAL_VIDEO_E2E_TEST_MATRIX.md` for fixture-by-fixture expectations.

Details:
- `IMPLEMENTED.md`
- `AWAITING_IMPLEMENTATION.md`

## What Sprint 24 Depends On (from Sprint 24a)
- Governed confidence primitives: `ConfidenceRecordV1` / `ReasonCodeV1`.
- Deterministic sensor identity: stable `trackId` remap + `personId`.

## Historical drafts
- `archive/*`
