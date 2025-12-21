# MetalVis Shader Library

## Architecture

The MetalVis shader library follows the "Atomic Shader Library" pattern, with modular, reusable components organized into two main categories:

### Core Modules (`Core/`)
Foundational utilities and color science:
- **ACES.metal**: ACES 1.3 RRT+ODT implementation
- **Color.metal**: Color utilities, luminance calculation, tone mapping curves
- **ColorSpace.metal**: Comprehensive color space transforms (sRGB, Rec.709, P3, Rec.2020, PQ, HLG)
- **Noise.metal**: Procedural noise functions (hash, interleaved gradient)
- **Compositing.metal**: Compositing operations
- **Debug.metal**: Debug visualization kernels

### Effects Modules (`Effects/`)
Visual effects with reusable inline functions:
- **Bloom.metal**: Physically-based bloom with energy conservation
- **Halation.metal**: Film halation simulation
- **FilmGrain.metal**: Luminance-masked film grain
- **Vignette.metal**: Physical vignette (cos⁴ law)
- **ColorGrading.metal**: LUT application with HDR preservation
- **Lens.metal**: Lens distortion, chromatic aberration, optical flares
- **Blur.metal**: Optimized separable Gaussian blur, spectral blur, bilateral blur
- **Anamorphic.metal**: Anamorphic lens streaks
- **Temporal.metal**: Temporal accumulation
- **ToneMapping.metal**: ACES-based tone mapping
- **Volumetric.metal**: Volumetric lighting
- **Energy.metal**: Energy field generation

## Namespace Conventions

All shader code follows consistent namespace organization:

```metal
// Core modules
namespace Core {
    namespace ModuleName { ... }
}

// Effects modules  
namespace Effects {
    namespace EffectName { ... }
}
```

**Usage Example:**
```metal
#include "Core/ACES.metal"
#include "Effects/Bloom.metal"

float3 color = Effects::Bloom::Prefilter(input, threshold, knee, maxClamp);
float3 output = Core::ACES::ACEScg_to_Rec709_SDR(color);
```

## Include Path Patterns

Always use relative paths from the shader file location:

```metal
// From Effects/ directory
#include "../Core/Color.metal"

// From Core/ directory  
#include "ColorSpace.metal"

// From root Shaders/ directory
#include "Core/ACES.metal"
#include "Effects/Bloom.metal"
```

## Texture Binding Conventions

**Standard Index Layout**:
- `[[texture(0)]]` - Primary input texture
- `[[texture(1)]]` - Secondary input OR output texture
- `[[texture(2)]]` - Output texture (for composite operations)

**Examples**:
```metal
// Single-pass effect
kernel void fx_effect(
    texture2d<float, access::sample> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]]
)

// Composite operation
kernel void fx_composite(
    texture2d<float, access::sample> source [[texture(0)]],
    texture2d<float, access::sample> effect [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]]
)
```

**Buffer Binding Convention**:
- `[[buffer(0)]]` - Primary uniform struct or parameters
- `[[buffer(1)]]` - MVP matrix (for vertex shaders)
- `[[buffer(2+)]]` - Additional data as needed

## Include Guards

All shader files use consistent include guard naming:

```metal
#ifndef <DIR>_<FILE>_METAL
#define <DIR>_<FILE>_METAL

// ... shader code ...

#endif // <DIR>_<FILE>_METAL
```

**Examples:**
- `Core/Color.metal` → `CORE_COLOR_METAL`
- `Effects/Bloom.metal` → `EFFECTS_BLOOM_METAL`

## Inline Function Pattern

Effects expose reusable logic as inline functions:

```metal
namespace Effects {
namespace EffectName {
    inline float3 Apply(float3 input, /* params */) {
        // Effect logic here
        return output;
    }
} // namespace EffectName
} // namespace Effects

// Kernel wrapper
kernel void fx_effect_name(...) {
    float3 result = Effects::EffectName::Apply(input, params);
    destTexture.write(result, gid);
}
```

This enables:
- Composition in uber-shaders
- Reuse across multiple kernels
- Consistent API surface

## Legacy Compatibility

Deprecated files maintain backward compatibility:
- `ACES.metal` → Forwards to `Core/ACES.metal`
- `MetaVisFXShaders.metal` → Includes all Effects modules

**Migration:** Update shader loading code to use new module paths:
```swift
// Old
library.loadSource(resource: "MetaVisFXShaders")

// New
library.loadSource(resource: "Effects/Bloom")
```

## Color Space Working Principles

1. **Scene-Referred**: All intermediate computations in **Linear ACEScg** (AP1 primaries, D60)
2. **Input Decoding**: Convert source textures → ACEScg using `ColorSpace::DecodeToACEScg()`
3. **Effects Processing**: Apply effects in linear space
4. **Output Encoding**: Convert ACEScg → Display using ACES ODTs or `ColorSpace::EncodeFromACEScg()`

## Best Practices

1. **Always use namespaces** for organization
2. **Include guards** on all files
3. **Relative include paths** for portability
4. **Document algorithm sources** (e.g., "Based on Jimenez 2014")
5. **Named constants** instead of magic numbers
6. **Inline for reusability** where applicable

## TODOs

- [ ] Split `ColorSpace.metal` into `Core/ColorSpace/` submodules
- [ ] Remove test kernels from production files (move to `Tests/Shaders/`)
- [ ] Complete SIMD optimization of ACEScct functions
