# Sprint 24f: Sensory System - Implementation Plan

## Goal Description
Ensure the system can see and hear reliably, efficiently, and with nuance. We will upgrade the perception layer to handle multiple speakers, process audio without OOMing on feature films, and robustify the Quality Control pipeline.

## User Review Required
> [!NOTE]
> **Diarization Scope:** This sprint implements the *data structures* and *heuristics* for multi-speaker support. Actual speaker identification (using pyannote-audio or similar) is a future model integration.
> **API Stability:** Audio analysis was refactored for streaming/windowed accumulation without requiring an externally-visible breaking API change.

## Proposed Changes

### MetaVisPerception
#### [MODIFY] [Sources/MetaVisPerception/Bites/BiteMapBuilder.swift](../../Sources/MetaVisPerception/Bites/BiteMapBuilder.swift)
- `BiteMap` already supports per-bite attribution via `personId`.
- Update builder logic to attribute each merged speech window to the most likely `personId` when multiple faces are present.
    - Prefer deterministic evidence available in sensors: `Face.mouthOpenRatio` when present; otherwise face presence/area heuristics.
    - Remove the single global `personId` selection (first face / "P0").

#### [MODIFY] [Sources/MetaVisPerception/MasterSensorIngestor.swift](../../Sources/MetaVisPerception/MasterSensorIngestor.swift)
- **Refactor** `readAudioAnalysis` to reduce peak memory usage.
    - Target: chunk/stream through `AVAssetReader` (implementation details TBD based on test + profiling).
    - Preserve determinism (quantization + stable ordering).

#### [MODIFY] [Sources/MetaVisPerception/AudioVADHeuristics.swift](../../Sources/MetaVisPerception/AudioVADHeuristics.swift)
- Extract magic numbers to `VADConfiguration` struct.
- Refactor `process()` to accept a `Chunk` and update internal state (if stateful) or return partial results.

### MetaVisQC
#### [MODIFY] [Sources/MetaVisQC/VideoContentQC.swift](../../Sources/MetaVisQC/VideoContentQC.swift)
- Ensure QC can consume the same `SourceContentHashV1` that ingest computes (avoid redundant reads).

#### [MODIFY] [Sources/MetaVisQC/VideoQC.swift](../../Sources/MetaVisQC/VideoQC.swift)
- Create `QCError` enum (e.g. `invalidResolution`, `audioSilent`, `frameDrops`).
- Replace `NSError` returns with `QCError`.

## Verification Plan

### Automated Tests
2.  **Multi-Speaker Logic:**
    - Unit test `BiteMapBuilder` with synthetic Face/Audio data simulating two alternating speakers.
    - Assert at least two distinct `personId` values across produced bites.
3.  **QC Errors:**
    - Test `VideoQC` with a known bad file (silent audio). Assert `QCError.audioSilent` is thrown.

## Status
- Implemented multi-speaker BiteMap attribution.
- Implemented audio analysis refactor to reduce peak memory via windowed accumulation.
- Implemented persisted source content hash in sensors artifacts.
- Implemented typed QC errors (no `NSError` magic codes) and configurable VAD thresholds.

### Manual Verification
1.  **Sensory Tuning:**
    - Run `lab sensors` on a noisy file.
    - Adjust `VADConfiguration` sensitivity.
    - Verify `sensors.json` output changes reflect the tuning.
