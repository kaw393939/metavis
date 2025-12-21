# Sprint 17 Audit: Auto Speaker Audio

## Status: Fully Implemented

## Accomplishments
- **AutoSpeakerAudioEnhancer**: Implemented a deterministic proposal engine that uses `MasterSensors` warnings (`audio_noise_risk`, `audio_clip_risk`) to suggest audio enhancements.
- **Dialog Cleanup Integration**: Correctly proposes enabling `audio.dialogCleanwater.v1` with adjusted gain based on clipping risk.
- **Safety Bounds**: Implemented `AutoEnhance.SpeakerAudioProposal.clamped()` to ensure gain adjustments stay within conservative limits (±6dB).
- **Evidence Selection**: `AutoSpeakerAudioEvidenceSelector` (implied by file list) selects deterministic audio snippets for QA.

## Gaps & Missing Features
- **Granular Control**: The proposal is currently "all or nothing" for the `dialogCleanwaterV1` preset. It does not yet propose specific EQ band gains or dynamics settings.
- **Telemetry Usage**: The rich `audioFrames` telemetry (prosody, frequency) is not yet used to inform the proposal.
- **Loudness Targeting**: The system does not yet propose a specific LUFS target, relying instead on "relative leveling" via fixed gain offsets.

## Performance Optimizations
- **Deterministic Logic**: Like the color corrector, the audio enhancer is extremely fast as it relies on pre-extracted sensors.

## Low Hanging Fruit
- Use `audioFrames` to detect "muffled" audio and propose a high-shelf EQ boost.
- Implement a "Peak Safety" rule that automatically reduces gain if `audio_clip_risk` is high.
- Add a `LoudnessProposal` that suggests a gain offset to reach a target RMS level.
