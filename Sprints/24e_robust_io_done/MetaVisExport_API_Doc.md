# MetaVisExport API Documentation

The `MetaVisExport` module manages the transcoding of timelines into final deliverables.

## Core Components

### VideoExporter
The primary actor for driving exports. It coordinates the `RenderDevice`, `AudioTimelineRenderer`, and `AVAssetWriter`.

```swift
let exporter = VideoExporter(device: myMetalDevice)

// Basic Export
try await exporter.export(
    timeline: myTimeline,
    to: outputURL,
    quality: .preset4KInitial,
    codec: .hevc
)
```

### Export Governance
Enforce business logic constraints on exports.

```swift
let governance = ExportGovernance(
    userPlan: .free,
    projectLicense: .basic,
    watermarkSpec: WatermarkSpec(...)
)

// Will throw ExportGovernanceError if constraints (e.g. resolution) are violated
try await exporter.export(..., governance: governance)
```

## Deliverables & Sidecars

### DeliverableManifest
A JSON-serializable record of an export job. Use `DeliverableWriter` to package it.

```swift
let manifest = try await DeliverableWriter.writeBundle(at: bundleURL) { stagingURL in
    // 1. Perform Export
    let videoURL = stagingURL.appendingPathComponent("video.mov")
    try await exporter.export(..., to: videoURL)
    
    // 2. Generate Sidecars
    try await CaptionSidecarWriter.writeWebVTT(
        to: stagingURL.appendingPathComponent("captions.vtt"),
        cues: myCues
    )
    
    // 3. Return Metadata
    return DeliverableManifest(...)
}
```

### Sidecar Writers
Standalone utilities for generating auxiliary files.

- `CaptionSidecarWriter`: VTT / SRT generation.
- `ThumbnailSidecarWriter`: JPEG thumbnails and contact sheets.
- `TranscriptSidecarWriter`: JSON word-level transcripts.
