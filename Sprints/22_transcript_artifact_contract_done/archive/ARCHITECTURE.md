# Architecture — Transcript Artifact Contract v1

## Reuse-first principles
- Reuse caption formatting/parsing infrastructure.
- Keep transcript schema independent of `MasterSensors` to avoid churn in that stable ingest artifact.

## Proposed module placement
- `TranscriptWord` model lives in `MetaVisCore` near captions:
  - alongside `Sources/MetaVisCore/Captions/CaptionCue.swift`

## Conversion helpers
- `TranscriptTime` helpers (seconds ↔ ticks) should live in `MetaVisCore` so both Lab tools and Session code can share the same rule.

## Caption generation
- Implement a tiny pure function:
  - `TranscriptWordsToCaptionCues.convert(words: [TranscriptWord], policy: CaptionGroupingPolicy) -> [CaptionCue]`
- Use `CaptionSidecarWriter.writeWebVTT(to:cues:)` and `writeSRT(to:cues:)` for output.

## Export integration (no new behavior)
- `ProjectSession` already discovers caption sidecars adjacent to a single source file.
- The transcript sprint does not change discovery rules.

## Future extension points (explicit)
- Diarization can populate `speakerId/speakerLabel` without changing the word schema.
- Edit compilation can populate `timelineTimeTicks` and `clipId` post-edit.
