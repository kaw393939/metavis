# Sprint 09: Audio Interleaving Refactor

## 1. Objective
Move unsafe pointer logic for converting `AVAudioPCMBuffer` to interleaved `CMSampleBuffer` out of `VideoExporter.swift` and into a tested utility in `MetaVisAudio`.

## 2. Scope
*   **Target Modules**: `MetaVisExport`, `MetaVisAudio`

## 3. Acceptance Criteria
1.  **Safety**: Logic is isolated and unit tested with sanitized inputs.
2.  **Correctness**: Stereo channels are correctly mapped (L/R) without swapping.

## 4. Implementation Strategy
*   Create `AudioBufferUtils` in `MetaVisAudio`.
*   Move `createAudioSampleBuffer` logic.
