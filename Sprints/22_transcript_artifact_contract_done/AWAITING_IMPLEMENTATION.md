# Awaiting Implementation

## Goal
Define and lock a stable, word-level transcript sidecar contract that supports exact edit-point work.

## Gaps & Missing Features
- No system-generated word-level transcript exists today (captions are pass-through only).
- Timeline-aware mapping for complex edits is not implemented yet (v1 assumes cue times are already in timeline time; source==timeline).

## Non-goals (this sprint)
- No Whisper installation or transcription runtime.
- No speaker diarization algorithm.
- No EvidencePack or Gemini planning.

## References (reuse; avoid drift)
- Caption cue model: Sources/MetaVisCore/Captions/CaptionCue.swift
- Caption VTT/SRT writer + speaker tags: Sources/MetaVisExport/Deliverables/SidecarWriters.swift
- Export caption sidecar discovery behavior: Sources/MetaVisSession/ProjectSession.swift
