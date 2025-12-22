# MetaVisIngest API Documentation

`MetaVisIngest` provides specialized importers and analyzers for media assets.

## Scientific Imaging

### FITS Support
Read NASA/ESA standard Flexible Image Transport System files, often used for HDR skyboxes or scientific visualization.

```swift
// 1. Simple Load
let reader = FITSReader()
let asset = try reader.read(url: fileURL)
print(asset.statistics.mean) // Access pre-computed stats

// 2. Cached Load
let asset = try await FITSAssetRegistry.shared.load(url: fileURL)
```

**Supported Formats:**
- 2D Image HDUs only.
- BITPIX: -32 (Float32) and 16 (Int16, normalized).

## Media Analysis

### VFR Detection
Detect wildly fluctuating frame rates in user media to prevent timeline desync.

```swift
// Probe the file
let profile = try await VideoTimingProbe.probe(url: videoURL)

// Get a policy decision
let decision = VideoTimingNormalization.decide(profile: profile)

switch decision.mode {
case .passthrough:
    print("Safe to use as-is at \(decision.targetFPS)")
case .normalizeToCFR:
    print("Must transcode to \(decision.targetFPS) CFR")
}
```

## Devices

### LIGMDevice
*Local Image Generation Module*. A Virtual Device exposing generative AI capabilities.

- **Action:** `generate`
- **Params:** `prompt` (String)
- **Output:** `assetId`, `sourceUrl` (`ligm://...`)

*Note: Current implementation is a mock.*
