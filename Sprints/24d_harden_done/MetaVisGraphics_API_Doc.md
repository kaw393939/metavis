# MetaVisGraphics Shader Reference

As a resource-only package, the "API" of `MetaVisGraphics` is primarily the set of Metal kernels it exposes to the `MetaVisSimulation` engine.

## Core Kernels

### Transforms
- `idt_rec709_to_acescg`: Convert sRGB video to working color space.
- `odt_acescg_to_rec709`: Convert working space to sRGB display/export.
- `aces_tonemap`: Apply filmic S-curve.

### Adjustments
- `exposure_adjust(texture src, texture dest, float ev)`
- `cdl_correct(...)`: ASC CDL implementation (Slope, Offset, Power).
- `lut_apply_3d(...)`: Apply 3D LUT (Cube).

### Compositing
- `compositor_alpha_blend`: Standard Over operator.
- `compositor_crossfade`: Dissolve A to B.
- `compositor_wipe`: Geometric transition.

## Generators
- `fx_volumetric_nebula`: Procedural space cloud renderer.
  - **Inputs:** Depth Buffer (optional), Camera Params.
  - **Buffers:** `VolumetricNebulaParams` (Buffer 0), `GradientStops` (Buffer 1).

## Swift Utilities

### GraphicsBundleHelper
```swift
// Get the bundle containing .metal files
let lib = try device.makeLibrary(from: GraphicsBundleHelper.bundle)
```

### LUTHelper
```swift
// Parse Adobe Cube LUT
let (size, data) = LUTHelper.parseCube(data: fileData)
```
