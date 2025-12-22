# MetaVisAudio API Documentation

The `MetaVisAudio` module handles offline audio rendering, signal processing, and mastering for the MetaVis rendering engine.

## Core Components

### 1. `AudioTimelineRenderer`
The primary entry point for rendering audio.

```swift
let renderer = AudioTimelineRenderer()

// Render a specific range of the timeline to an AVAudioPCMBuffer
let buffer = try await renderer.render(
    timeline: myTimeline, 
    timeRange: myTimeRange, 
    sampleRate: 48000
)
```

**Key Features:**
- **Offline Rendering:** High-speed, faster-than-realtime rendering.
- **Chunked Processing:** Support for `renderChunks` to stream output to disk without holding the full timeline in memory.

### 2. `AudioGraphBuilder`
Internal engine that constructs the `AVAudioEngine` graph from a `Timeline`.
- **Procedural Signals:** Supports `ligm://` URLs for test tone generation (sine, sweep, noise).
- **File Streaming:** specific optimization for bounded-memory file streaming.

### 3. `EngineerAgent`
An automated mastering assistant.

```swift
let agent = EngineerAgent()
// Analyzes the timeline and configures the renderer's mastering chain
try await agent.optimize(timeline: timeline, renderer: renderer, governance: .spotify)
```

**Capabilities:**
- Auto-detects loudness (LUFS approximation).
- Applies EQ and Dynamics to meet target standards (e.g. -14 LUFS).

## Advanced Usage

### Procedural Audio (Test Signals)
You can create clips with specific source filenames to generate audio programmatically:
- `ligm://audio/sine?freq=440`
- `ligm://audio/white_noise`
- `ligm://audio/sweep?start=20&end=20000`
- `ligm://audio/impulse?interval=1`

### Diagnostics
Use `FileAudioStreamingDiagnostics` (Debug builds only) to verify streaming buffer usage.

## Current Limitations
- **Sample Rate:** Optimized for 48kHz.
- **Loudness:** Uses RMS-based estimation, not full K-weighted LUFS (EBU R128).
