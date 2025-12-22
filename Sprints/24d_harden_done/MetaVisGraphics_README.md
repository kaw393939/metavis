# MetaVisGraphics

**MetaVisGraphics** provides the Metal Shading Language (MSL) foundation for the MetaVis engine. It enables cinematic-grade rendering, color grading, and visual effects.

## Features

- **ACEScg Pipeline:** All shaders operate in the ACEScg linear color space for industry-standard color fidelity.
- **Cinematic Effects:** Includes highly optimized kernels for Bloom, Film Grain, Halation, and Volumetric Nebula rendering.
- **Compositing:** Standard set of blending and transition kernels (Crossfade, Wipe, Dip).
- **Diagnostics:** Built-in Waveform scope accumulation kernels.

## Integration

This package is intended to be used by `MetaVisSimulation`, which compiles the Metal library at runtime.

```swift
import MetaVisGraphics
import Metal

// Load the default library
let bundle = GraphicsBundleHelper.bundle
let library = try device.makeDefaultLibrary(bundle: bundle)

// Access a kernel
let kernel = library.makeFunction(name: "idt_rec709_to_acescg")
```

## Structure
- `Resources/*.metal`: The shader source code.
- `LUTHelper.swift`: CPU-side parsing of .cube files.
- `GraphicsBundleHelper.swift`: Safe bundle access.
