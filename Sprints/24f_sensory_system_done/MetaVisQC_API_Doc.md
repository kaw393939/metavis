# MetaVisQC API Documentation

`MetaVisQC` provides tools for validating media assets against technical and creative standards.

## Modules

### `VideoQC`
Validates technical specifications of a video file.
```swift
let expectations = VideoQC.Expectations.hevc4K24fps(durationSeconds: 60.0)
let report = try await VideoQC.validateMovie(at: url, expectations: expectations)
```

### `VideoContentQC`
Analyzes the *content* of the video for anomalies.
```swift
// Check for frozen frames or black screens
let fingerpints = try await VideoContentQC.fingerprints(movieURL: url, samples: samples)
try await VideoContentQC.assertTemporalVariety(movieURL: url, samples: samples)
```

### `GeminiQC`
Uses Google Gemini to perform a semantic review ("Is the lighting good?", "Is the audio clear?").
```swift
// 1. Define Policy
let usage = GeminiQC.UsageContext(
    policy: .init(mode: .textImagesAndVideo, mediaSource: .deliverablesOnly),
    privacy: .init(allowDeliverablesUpload: true)
)

// 2. Run QC
let verdict = try await GeminiQC.acceptMulticlipExport(
    movieURL: url,
    keyFrames: frames,
    expectedNarrative: "A tech vlog about coding.",
    usage: usage
)
```

## Governance
All AI features in `MetaVisQC` are gated by `AIUsagePolicy` (from `MetaVisCore`). You must explicitly opt-in to uploading media. By default, the system runs in `localOnlyDefault` mode (no network requests).
