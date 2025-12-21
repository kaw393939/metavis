# Sprint 23 — TDD Plan (Whisper Transcription CLI)

## Tests (write first)

### 1) `WhisperTranscriberParsingTests.test_parses_wrapper_json_into_transcript_words()`
- Feed a small, committed sample JSON produced by the wrapper.
- Assert `TranscriptWord` fields are populated, ordered deterministically, and wordId is stable.

### 2) `WhisperTranscriberParsingTests.test_rejects_non_finite_or_negative_timestamps()`
- Validate robustness and safety.

### 3) `TranscriptToVTTTests.test_emits_vtt_from_words()`
- Convert words → cues → VTT using `CaptionSidecarWriter`.
- Assert header exists and timings format correctly.

### 4) `WhisperCLITranscriberIntegrationTests.test_generates_word_level_transcript_for_fixture()`
- Gate on env vars:
  - `WHISPER_BIN` (path to whisper executable)
  - `WHISPER_MODEL` (path or model name)
  - Optional: `WHISPER_LANG`, `WHISPER_DEVICE`
- Run on a small segment of `keith_talk.mov`.
- Assert:
  - output file exists
  - contains > N words
  - timestamps are monotonic

## Production steps
1. Implement `TranscriptCommand` CLI surface.
2. Implement `WhisperCLITranscriber` (wrapper invocation + parsing).
3. Wire output to transcript JSONL + captions VTT.
4. Land tests and env gating.

## Definition of done
- Unit tests pass in CI.
- Integration test can run locally when toolchain is installed.
