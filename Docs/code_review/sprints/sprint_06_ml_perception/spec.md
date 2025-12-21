# Sprint 06: ML Perception Integration

## 1. Objective
Integrate Apple's `SoundAnalysis` framework (or CoreML) into `MetaVisPerception` to augment the existing heuristic-based Voice Activity Detection (VAD).

## 2. Scope
*   **Target Modules**: `MetaVisPerception`
*   **Key Files**: `MasterSensorIngestor.swift`, `AudioVADHeuristics.swift`

## 3. Acceptance Criteria
1.  **Classification**: Accurately classify "Speech", "Music", "Applause" with > 80% confidence.
2.  **Fusion**: Combine ML confidence with Heuristic VAD to produce a final `AudioSegment` descriptor.

## 4. Implementation Strategy
*   Use `SNClassifySoundRequest` on audio buffers.
*   Map Apple's default labels to `MetaVis` internal taxonomy.

## 5. Artifacts
*   [TDD Plan](./tdd_plan.md)
