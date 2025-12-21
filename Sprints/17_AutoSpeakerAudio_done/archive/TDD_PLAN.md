# Sprint 17 — TDD Plan (Auto Speaker Audio)

## Tests (write first)

### 1) `AutoSpeakerAudioTests.test_noise_risk_triggers_cleanup()`
- Sensors fixture with `audio_noise_risk`.
- Assert output includes dialog cleanup effect.

### 2) `AutoSpeakerAudioTests.test_clip_risk_triggers_gain_reduction()`
- Sensors fixture with `audio_clip_risk`.
- Assert output reduces gain / adds safety.

### 3) `AutoSpeakerAudioTests.test_deterministic_outputs()`
- Same sensors in → same recipe out.

### 4) Integration: `AutoEnhanceE2ETests.test_audio_recipe_generated_from_sensors()`
- Use deterministic ingest output.
- Generate audio recipe and assert stable encoding.

Implemented as: `FeedbackLoopOrchestratorE2ETests.test_autoSpeakerAudioCommand_usesFeedbackLoop_localText_runsWithoutMediaExtraction()`
- Uses `Tests/Assets/VideoEdit/keith_talk.mov` ingest output.
- Asserts byte-for-byte stable `audio_proposal.json` across two runs.

## Production steps
1. Implement `AutoSpeakerAudioEnhancer` mapping sensors → chain.
2. Encode chain as a stable `Codable` recipe.
3. Wire into Feedback Loop runner.

## Definition of done
- Deterministic audio proposal.
- Bounded behavior.
- Integration test green.
