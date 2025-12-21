# Architecture — Speaker Diarization v1 (Sticky Fusion)

## Reuse points (avoid drift)
- **Face track IDs**: use `MasterSensors.VideoSample.faces[].trackId` generated deterministically in ingest.
- **Speech segmentation**: use `MasterSensors.audioSegments` (`.speechLike`) and optionally `audioFrames`.
- **Caption speaker tags**: use `CaptionCue.speaker` and `CaptionSidecarWriter`.

## Components

### `SpeakerDiarizer` (MetaVisPerception)
Pure function style API:
- Input: `MasterSensors`, `[TranscriptWord]`
- Output: `[TranscriptWord]` with speaker fields populated + `SpeakerMap`

Key responsibilities:
- Build face presence intervals from `videoSamples`.
- Gate by `.speechLike`.
- Assign speakers using stickiness/hysteresis.

### CLI (`MetaVisLab diarize`)
- Reads sensors and transcript.
- Runs diarizer.
- Writes:
  - updated transcript JSONL
  - captions VTT
  - speaker map

## Confidence + thresholds
- v1 can compute a lightweight `speakerConfidence` field internally (not required in the output schema yet).
- Stickiness threshold should be a named constant with tests.

## Future upgrades (explicit)
- Merge/repair face tracks after tracking loss.
- Add unknown-speaker clustering for offscreen speakers.
- Fuse in edit timeline mapping (timeline ticks) post-edit.
