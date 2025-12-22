# Sprint 24f: Sensory System

**Focus:** Optimization, Detail, and Safety.

This sprint upgrades the system's "Eyes and Ears". We are moving from a single-threaded, memory-heavy "Toy" implementation to a streaming, multi-speaker professional implementation. This is critical for handling long-form content (podcasts, interviews) without crashing.

## Contents
*   [Specification](spec.md)
*   [Architecture](architecture.md)
*   [TDD Plan](tdd_plan.md)
*   **Artifacts:** `MetaVisPerception`, `MetaVisQC`, `MetaVisAudio` reviews.

## Primary Deliverables
1.  **Multi-Speaker Aware BiteMap** (attribute bites per `personId`).
2.  **Memory-Safer Audio Analysis** (reduce peak memory; enable streaming/chunking if needed).
3.  **Integrated Content Hashing** (persist source content hash in `MasterSensors.source`).

## Current status
- **DONE:** `BiteMapBuilder` attributes bites per `personId` in a deterministic, multi-speaker aware way (uses available sensor evidence, including mouth activity).
- **DONE:** Audio analysis peak memory is reduced via streaming/windowed accumulation (no full-window mono buffering).
- **DONE:** Source content hash is persisted in the sensors artifact (`MasterSensors.source.contentHashHex`) for downstream QC/export use.
- **DONE:** QC no longer throws `NSError` magic codes; QC errors are typed (`LocalizedError`) and human-readable.
- **DONE:** VAD thresholds are configurable via `VADConfiguration`.

## Cross-cutting learnings (from real fixtures)
*   Strict fixture acceptance tests should be env-gated and support fixture-dir override for fast iteration.
*   Identity binding depends heavily on diarization evidence quality, and window boundary conditions can silently drop evidence.

## Closeout
This sprint folder is suffixed `_done` to indicate the deliverables above are complete and validated by the test suite.
