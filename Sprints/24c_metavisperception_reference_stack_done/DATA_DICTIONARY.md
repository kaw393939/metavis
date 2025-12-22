# Sprint 24c — Data Dictionary

This sprint introduces **versioned, governed perception artifacts** that serve as the *perception compiler output*.

## 1) Confidence ontology

### `ConfidenceLevelV1`
Epistemic type for *how* confidence was derived.

```swift
enum ConfidenceLevelV1: String, Codable {
  case deterministic   // math, hashes, geometry
  case heuristic       // rule thresholds, rule-based scoring
  case modelEstimated  // ML output with known error
  case inferred        // cross-signal reasoning
}
```

Notes:
- This is **not** a numeric confidence score.
- It complements `ConfidenceRecordV1`.

### `EvidencedValueV1<T>` (recommended)
A typed wrapper for perception attributes.

Fields (conceptual):
- `value: T`
- `confidence: ConfidenceRecordV1`
- `confidenceLevel: ConfidenceLevelV1`
- `provenance: [ProvenanceRefV1]`

## 2) Provenance

### `ProvenanceRefV1`
A structured pointer to where evidence came from.

Fields (conceptual):
- `kind`: `signal | device | artifact | interval | metric`
- `id`: optional stable identifier (device name, artifact id, track id)
- `field`: optional field name
- `value`: optional numeric value
- `startSeconds` / `endSeconds`: optional window

This can be implemented as a superset of `EvidenceRefV1` or as a new type.

## 3) Temporal context

### `temporal.context.v1.json`
A single JSON document that represents aggregated temporal perception.

Fields (conceptual):
- `schema: "temporal.context.v1"`
- `source`: content hash + duration + dimensions
- `windowing`: stride / window size
- `events: [TemporalEventV1]`
- `stability: [StabilityMetricV1]`
- `warnings: [WarningSegmentV1]` (governed)

### `TemporalEventV1`
Examples:
- `face_track_stable`
- `speaker_change`
- `lighting_shift`

Each event includes:
- `startSeconds`, `endSeconds`
- typed payload (e.g., `trackId`, `speakerId`)
- `confidence: ConfidenceRecordV1`
- `confidenceLevel: ConfidenceLevelV1`
- `provenance`

## 4) Identity binding graph

### `identity.bindings.v1.json`
A single JSON document representing bindings between modalities.

Fields (conceptual):
- `schema: "identity.bindings.v1"`
- `nodes`: `speakerId`, `trackId`, optional `personId`
- `edges`: speaker↔track bindings with posterior + confidence record
- `updates`: promotion/demotion events with windows + reasons

Edge fields (conceptual):
- `speakerId`
- `trackId`
- `posterior`: Double (0..1)
- `confidence: ConfidenceRecordV1`
- `confidenceLevel: ConfidenceLevelV1` (likely `inferred`)
- `evidenceWindows`: list of time intervals

## 5) Strengthened LLM boundary

### `semantic.frame.v2.jsonl` (or equivalent)
One JSON record per sampled timestamp.

Schema requirements:
- `schema: "semantic.frame.v2"`
- bounded typed fields only
- no untyped dictionaries for attributes
- per-attribute `EvidencedValueV1<T>`

Example shape (conceptual):
- `timestampSeconds`
- `subjects: [SubjectV2]`
- `context: ContextV2`

Where `SubjectV2` includes:
- stable `trackId`/`personId` references (when available)
- `rect`
- typed attributes (examples):
  - `isSpeaking` (inferred)
  - `visibility` (heuristic)
  - `dominantSkinLikelihood` (heuristic)
  - `faceprintHash64` (deterministic)

## 6) Migration notes
- `MasterSensors.DescriptorSegment` currently contains free-text `reasons: [String]`.
  - Sprint 24b should either:
    - introduce a governed reasons list (e.g., `ReasonCodeV1`), or
    - clearly scope descriptor reasons as non-governed *explanations* and move governed signals into the new temporal context outputs.

