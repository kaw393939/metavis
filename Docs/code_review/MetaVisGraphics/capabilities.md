# MetaVisGraphics Assessment

## Initial Assessment
MetaVisGraphics acts as the primary repository for the system's Metal shading language code. It is less of a "logic" module and more of a "resource" module providing the raw compute kernels and fragment shaders.

## Capabilities

### 1. Comprehensive Shader Library
- **Content**: Contains ~30 `.metal` files covering a wide range of visual effects.
- **Categories**:
    - **Color Science**: `ACES.metal`, `ColorSpace.metal`, `ColorGrading.metal`, `ToneMapping.metal`.
    - **Optical Effects**: `Lens.metal`, `Bloom.metal`, `Halation.metal`, `Anamorphic.metal`, `Vignette.metal`.
    - **Generative**: `VolumetricNebula.metal`, `Noise.metal`, `ZonePlate.metal`, `SMPTE.metal`.
    - **Utility**: `Compositor.metal`, `FormatConversion.metal`, `ClearColor.metal`.
    - **Restoration**: `FilmGrain.metal`, `FaceEnhance.metal`.

### 2. LUT Support
- **`LUTHelper.swift`**: Provides a parser for Adobe `.cube` 3D LUT files, converting them into a flat float array suitable for Metal texture creation.

### 3. Resource Access
- **`GraphicsBundleHelper.swift`**: Exposes the module bundle to allow consumers to load the default Metal library (`default.metallib`).

## Technical Gaps & Debt

### 1. Lack of Swift Wrappers
- **Gap**: The module provides the *code* but not the *interface*. There are no `MPSUnaryImageKernel` subclasses or `CIFilter` wrappers here. Consumers must know the function names (e.g., "kernel_bloom") stringly-typed to use them.
- **Risk**: Refactoring shader function names will break consumers silently until runtime.

### 2. Shader Organization
- **Structure**: Flat list of files in `Resources`. As the library grows, this will become unmanageable.

## Improvements

1.  **Type-Safe Accessors**: Generate or write a Swift struct `ShaderFunctionNames` that contains constants for every kernel name in the library.
2.  **Shader Validation**: Add a test target that attempts to compile the Metal library during CI to catch syntax errors immediately (though Xcode usually handles this if `Resources` are part of the target).
3.  **Library Partitioning**: Group shaders into subdirectories (Color, Optical, Generators).
