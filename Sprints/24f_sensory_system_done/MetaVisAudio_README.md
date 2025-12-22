# MetaVisAudio

**MetaVisAudio** is the audio rendering subsystem of the MetaVisKit engine. It provides high-performance, offline audio composition and mastering capabilities using Apple's `AVAudioEngine`.

## Features

- **Timeline Composition:** Mixes multiple tracks and clips with precise timing.
- **Offline Rendering:** Renders complex graphs faster than real-time.
- **Smart Streaming:** Efficiently streams audio from files with bounded memory usage, suitable for 4K/8K video workflows where memory is scarce.
- **Procedural Generation:** Built-in signal generators for testing and synthesis.
- **AI Engineer:** Automated mastering chain that normalizes loudness and cleans up dialog.

## Usage

### Basic Rendering
```swift
import MetaVisAudio
import MetaVisTimeline

let timeline: Timeline = ... // Your editing timeline
let renderer = AudioTimelineRenderer()

// Render 10 seconds
let result = try await renderer.render(
    timeline: timeline,
    timeRange: Time.zero..<Time(seconds: 10)
)
```

### Automated Mastering
```swift
let agent = EngineerAgent()
// Optimize for Spotify (-14 LUFS)
try await agent.optimize(timeline: timeline, renderer: renderer, governance: .spotify)
```

## Architecture

- **`AudioGraphBuilder`**: Translates `Timeline` models into `AVAudioNode` graphs.
- **`AudioTimelineRenderer`**: Drives the `AVAudioEngine` in `.offline` manual rendering mode.
- **`AudioMasteringChain`**: The final output bus applying EQ, Compression, and Limiting.

## Contributing

See `code_review/MetaVisAudio_Review.md` for current architectural findings and known limitations.
