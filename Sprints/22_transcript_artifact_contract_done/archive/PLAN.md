# Sprint 22 — Transcript Artifact Contract (Word-Level)

## Goal
Make a transcript a **first-class, stable, testable artifact** that can drive precise editing (source-time + timeline-time).

## Acceptance criteria
- A stable **`TranscriptWord.v1`** schema exists and is documented (JSONL).
- Conversion rules between seconds and ticks (1/60000s) are explicit and tested.
- A deterministic mapping exists from `TranscriptWord.v1` → captions (`CaptionCue`) for VTT/SRT export.
- Schema is forward-compatible with diarization (speaker fields are present but may be unset).

## Existing code reused (no duplication)
- `CaptionCue` data model: Sources/MetaVisCore/Captions/CaptionCue.swift
- VTT/SRT parse/render + speaker tags: Sources/MetaVisExport/Deliverables/SidecarWriters.swift
- Deliverable caption discovery behavior (single-source only): Sources/MetaVisSession/ProjectSession.swift

## New code to add (minimal)
- A new transcript model type (likely under `MetaVisCore/Captions/` adjacent to `CaptionCue`).
- A small helper to convert transcript words to caption cues deterministically.

## Deterministic data strategy
- Use purely synthetic transcript fixtures in tests (no external tools).
- Ensure deterministic ordering rules are written down (primary key: `sourceTimeTicks`, then `sourceTimeEndTicks`, then `wordOrdinal`).

## Test strategy
- Unit tests only, no ffmpeg/whisper dependency.
- Round-trip tests through VTT writer/parser to prove speaker tag compatibility.

## Docs
- Spec: archive/SPEC.md
- Architecture: archive/ARCHITECTURE.md
- Data dictionary: archive/DATA_DICTIONARY.md
- TDD plan: archive/TDD_PLAN.md
