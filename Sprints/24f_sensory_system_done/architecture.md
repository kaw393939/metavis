# Sprint 24f: Architecture - Optimized Perception

## 1. Streaming Audio Pipeline

**Current (Buffered):**
```mermaid
graph TD
    File -->|Read All| RAM[[Float Array (Huge)]]
    RAM -->|Process| VAD[VAD Heuristics]
    VAD -->|Segments| Output
```

**Target (Streaming):**
```mermaid
graph TD
    File -->|Read Chunk| Chunk[Audio Chunk (~30s)]
    Chunk -->|Process| VAD[VAD Heuristics]
    VAD -->|Segments| Output
    Chunk -->|Iterate| File
```

## 2. Multi-Speaker Attribution (BiteMap)

**Current:**
`BiteMap` -> `[Bite(speaker: "P0"), Bite(speaker: "P0")]`

**Target:**
*   Sensors provide face tracks + (optionally) face parts / mouth activity.
*   Diarization provides time-stamped speaker evidence.
*   `BiteMapBuilder` assigns bites into multiple tracks when evidence supports it; otherwise falls back to Unknown.

## 3. QC Domain Model

New enum structure:
```swift
enum QCError: Error {
    case blackoutDetected(frame: Int)
    case freezeFrameDetected(start: Int, duration: Int)
    case audioClipping(channel: Int, peak: Float)
    case contentPolicyViolation(category: Governance.Category, confidence: Float)
}
```
