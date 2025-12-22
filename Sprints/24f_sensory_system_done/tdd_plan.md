# Sprint 24f: TDD Plan

## 1. Unit Tests

### `MetaVisPerceptionTests`
*   **`testStreamingMemoryUsage`**:
    *   **Setup:** Synthesize a 2-hour blank WAV (headers only + seeking mock).
    *   **Action:** `MasterSensorIngestor.ingest(url: bigFile)`.
    *   **Assert:** Process memory does not spike > 200MB.
*   **`testBiteAssignment`**:
    *   **Setup:** Mock sensors with 2 overlapping faces (P1, P2). Mock audio segment at same time.
    *   **Action:** `BiteMapBuilder.build(...)`.
    *   **Assert:** `BiteMap` behaves deterministically (assigns to P1 or P2 based on logic, not random).

### `MetaVisQCTests`
*   **`testStreamingHash`**:
    *   **Action:** Hash a known file using `SourceContentHashV1`.
    *   **Assert:** Matches `shasum -a 256` output.
    *   **Assert:** Completion time < X seconds, RAM usage < Y MB.

## 2. Integration Tests

### `MetaVisLab Sensors`
*   Run the sensors command on `conversation_2_people.mp4`.
*   Inspect `bites.v1.json`.
*   Verify existence of at least 2 unique `personId`s.

### `Strict Fixture Acceptance (env-gated)`
*   Keep a strict acceptance test that can be enabled via env var and pointed at an override fixture directory.
*   Add a regression assertion that boundary-adjacent evidence is not dropped (epsilon / inclusive window).
