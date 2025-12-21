# Sprint 24 — TDD Plan (Speaker Diarization Sticky Fusion)

## Tests (write first)

### 1) `SpeakerDiarizerContractTests.test_assigns_single_face_track_as_speaker()`
- Sensors: one face track present over speech.
- Transcript: words within that time.
- Assert all words get `speakerId` for that face and `speakerLabel == "T1"`.

### 2) `SpeakerDiarizerContractTests.test_stickiness_prevents_oscillation_when_two_faces_present()`
- Sensors: two faces overlap; dominance alternates slightly.
- Transcript: continuous speech words.
- Assert speaker does not flip more often than a small threshold (or uses hysteresis).

### 3) `SpeakerDiarizerContractTests.test_offscreen_words_are_labeled_offscreen()`
- Sensors: speech-like segments but no faces.
- Assert `speakerId == "OFFSCREEN"` (or nil) and labels stable.

### 4) `SpeakerDiarizerContractTests.test_words_outside_speechLike_are_left_unassigned()`
- Assert diarizer doesn’t hallucinate speakers outside speech windows.

### 5) `SpeakerDiarizerContractTests.test_emits_vtt_with_voice_tags()`
- Convert diarized words → cues → VTT using existing writer.
- Assert VTT contains `<v T1>` tags.

## Production steps
1. Implement `SpeakerDiarizer` with stickiness + deterministic labeling.
2. Wire CLI command + artifact writing.
3. Add tests and synthetic fixtures.

## Definition of done
- Unit tests pass.
- Output is deterministic and stable across reruns.
