# MetaVisPerception API Documentation

`MetaVisPerception` turns raw media into structured data.

## Key Concepts

### MasterSensors
The comprehensive JSON document describing everything the machine "saw" and "heard".

- **Source:** Resolution, FPS, Duration.
- **VideoSamples:** Per-frame metadata (Faces, Luma, Dominant Colors).
- **AudioSegments:** Spans of Speech, Music, Silence.
- **Warnings:** Technical issues (Clipping, Unstable shots).

### Bites
An editorial abstraction. A "Bite" is a continuous segment of a person speaking.

## Usage

```swift
import MetaVisPerception

// 1. Configure Ingest
let options = MasterSensorIngestor.Options(
    enableFaces: true,
    enableAudio: true,
    enablekSegments: true
)
let ingestor = MasterSensorIngestor(options)

// 2. Run Analysis (Async)
let sensors = try await ingestor.ingest(url: movieURL)

// 3. Serialize
let json = try JSONEncoder().encode(sensors)

// 4. Generate Bites
let biteMap = BiteMapBuilder.build(from: sensors)
print("Found \(biteMap.bites.count) speaking segments")
```

## Determinism
This module guarantees that running the same input file on the same machine architecture will produce bit-exact identical `MasterSensors` JSON output. This is achieved via:
- Quantized floating point values.
- Stable UUID generation.
- Deterministic sorting of detected objects.
