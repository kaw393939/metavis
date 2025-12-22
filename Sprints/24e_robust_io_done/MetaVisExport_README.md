# MetaVisExport

**MetaVisExport** is the delivery engine for MetaVisKit. It handles high-performance video encoding, governance checks, and the generation of delivery artifacts (captions, thumbnails, manifests).

## Features

- **Parallel Encoding:** Decoupled audio and video encoding lanes for maximum throughput.
- **Safety First:** Strict preflight checks ensure all timeline features are valid and authorized before rendering begins.
- **Sidecar Generation:** Built-in generators for WebVTT, SRT, JSON Transcripts, and visual contact sheets.
- **Governance:** Enforce resolution limits, watermarking, and license restrictions automatically.

## Usage

### Simple Export
```swift
import MetaVisExport

let exporter = VideoExporter(engine: engine)
try await exporter.export(timeline: timeline, to: url, quality: .uhd4k)
```

### Creating a Delivery Bundle
Use `DeliverableWriter` to create a folder containing the video, manifest, and sidecars atomically.

```swift
try await DeliverableWriter.writeBundle(at: outputFolder) { staging in
    // Write components to 'staging'
    // Return a manifest describing them
}
```

## Architecture

- **`VideoExporter`**: The main orchestration actor.
- **`Deliverables/`**: Logic for defining and writing output bundles.
- **`SidecarWriters.swift`**: Zero-dependency implementation of widespread sidecar formats.

## Dependencies
- `MetaVisCore` (Types, Governance)
- `MetaVisAudio` (Audio Rendering)
- `MetaVisSimulation` (Video Rendering)
