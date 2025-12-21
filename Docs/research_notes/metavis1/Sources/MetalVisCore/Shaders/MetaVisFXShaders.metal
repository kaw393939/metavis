#include <metal_stdlib>
using namespace metal;

// MARK: - MetaVisFXShaders (Legacy Forwarding Header)
// This file is deprecated. All kernels have been moved to the Atomic Shader Library.
// We include the new files here to maintain backward compatibility for Swift code
// that loads "MetaVisFXShaders.metal" library.

#include "Effects/Bloom.metal"
#include "Effects/Energy.metal"
#include "Effects/ToneMapping.metal"
#include "Effects/FilmGrain.metal"
#include "Effects/Halation.metal"
#include "Effects/Vignette.metal"
#include "Effects/Lens.metal"
#include "Effects/Anamorphic.metal"
#include "Core/Compositing.metal"
#include "Effects/Temporal.metal"
#include "Effects/ColorGrading.metal"
#include "Effects/Volumetric.metal"
#include "Core/Debug.metal"
#include "Effects/Blur.metal" // Assuming blur was also used here or available
