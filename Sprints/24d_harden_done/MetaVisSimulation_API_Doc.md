# MetaVisSimulation API Documentation

`MetaVisSimulation` performs the actual rendering.

## Core Components

### `MetalSimulationEngine`
The production renderer.
```swift
let engine = try MetalSimulationEngine()

// The engine is an Actor.
let result = try await engine.render(request: renderRequest)
// result.imageBuffer contains raw texture bytes (mocked in vertical slice)
```

### `TimelineCompiler`
Transforms an editing `Timeline` into a renderable `RenderRequest`.

```swift
let compiler = TimelineCompiler()
let request = try await compiler.compile(
    timeline: myTimeline,
    at: Time(seconds: 1.5),
    quality: .proRes422HQ
)
// 'request' contains the full RenderGraph (Nodes, Inputs, Parameters).
```

### `ClipReader`
Accesses video data. Typically internal to the engine but can be used for pre-flighting.
```swift
let texture = try await clipReader.texture(
    assetURL: url,
    timeSeconds: 1.5,
    width: 3840,
    height: 2160
)
```

## Architecture Notes

### Color Pipeline
The simulation pipeline enforces ACEScg (AP1 primaries, Linear gamma) as the working space.
- **Inputs:** Converted via IDT (e.g. `idt_rec709_to_acescg`).
- **Processing:** All blends, effects, and grading happen in ACEScg linear.
- **Outputs:** Converted via ODT (e.g. `odt_acescg_to_rec709`) at the very end of the graph.

### Coordinates
- **Texture:** 0,0 is Top-Left (Metal standard).
- **Normalized:** Some effects use 0..1 normalized coordinates where 0,0 is Bottom-Left (Cartesian). Be careful when writing custom shaders.
