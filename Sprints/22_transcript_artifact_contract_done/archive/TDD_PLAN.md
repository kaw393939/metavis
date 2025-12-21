# Sprint 22 — TDD Plan (Transcript Artifact Contract)

## Tests (write first)

### 1) `TranscriptWordContractTests.test_seconds_to_ticks_is_deterministic()`
- Assert conversion from seconds → ticks uses a single, documented rule.
- Validate boundary cases (exact millisecond, sub-tick fractions, negative/NaN rejected).

### 2) `TranscriptWordContractTests.test_word_ordering_is_stable()`
- Given a shuffled set of words, assert stable sort order.

### 3) `TranscriptToCaptionsTests.test_groups_words_into_caption_cues_deterministically()`
- Define a deterministic grouping rule (max chars or max seconds).
- Assert cues are stable and non-overlapping.

### 4) `TranscriptToCaptionsTests.test_vtt_roundtrip_preserves_speaker_tag()`
- Convert transcript → `[CaptionCue]` with speaker labels.
- Use `CaptionSidecarWriter.writeWebVTT(to:cues:)` then parse back.
- Assert speaker labels survive.

## Production steps
1. Add `TranscriptWord` model + conversion helpers.
2. Land unit tests.
3. Ensure no changes to export/session behavior.

## Definition of done
- All tests pass.
- The schema is documented and treated as stable.
