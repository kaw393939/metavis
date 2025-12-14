# Definitive Performance Optimization Plan

This document outlines the optimization strategy for MetaVis, ranked by impact.

1. Critical Priority (The "frame killers")
A. Implement Texture Reuse Pool (MetaVisSimulation)
Problem: MetalSimulationEngine currently calls device.makeTexture for every node in the graph, roughly 10-50 times per frame. This causes massive memory churn, driver overhead, and will prevent stable 60fps playback. Solution:

Status (as of Dec 13, 2025): Implemented a real `TexturePool` keyed by (w,h,format,usage,storageMode) and wired `MetalSimulationEngine` to check out textures for node outputs and check them back in via a per-render downstream refcount, enabling reuse across nodes and across frames. Remaining work is to extend this into a more advanced pool (optional `MTLHeap` aliasing, better limits/eviction, and broader coverage for temporary textures like deterministic black fallbacks).

Create class TexturePool holding a cache of [MTLTexture].
Use MTLHeap for efficient aliasing (optional) or just simple caching by (width, height, format).
Checkout a texture before rendering a node; check it back in when downstream consumers are done. Impact: Massive. Essential for real-time performance.
B. Implement Async Asset Loading (MetaVisSimulation / MetaVisIngest)
Problem: The current implementation of source_texture shader expects an input texture, but no logic exists to read video frames from disk into that texture. Solution:

Status (as of Dec 13, 2025): Replaced the interim `AVAssetImageGenerator` path with an `AVAssetReader` + `AVAssetReaderVideoCompositionOutput` decode pipeline that outputs `CVPixelBuffer` (32BGRA) and bridges to `MTLTexture` via `CVMetalTextureCache` (low/zero-copy), wired into `MetalSimulationEngine` for `source_texture`. Decode failures are non-silent (logged + surfaced via `RenderResult.metadata["warnings"]`), while still binding deterministic black to keep the graph executable.

Implement ClipReader service using AVAssetReader or VideoToolbox.
Run readers on a background queue (Lookahead pattern: Decode frame N+1 while N is rendering).
Upload decoded CVPixelBuffer to MTLTexture and cache it. Impact: Functional Blocker. The engine cannot render video without this.
C. Optimize Bokeh Blur Loop (MetaVisGraphics)
Problem: fx_bokeh_blur uses a fixed 64-sample loop per pixel. On a 4K frame, this is ~500 million texture samples per frame. This will kill the GPU execution time. Solution:

Status (as of Dec 13, 2025): Reduced worst-case sampling by making the loop adaptive and capping samples at 32 (down from 64). Remaining work is to add a true multi-resolution path (downsample -> blur -> upsample) for large radii.

Implement "Importance Sampling" or a specific "Gather" kernel that adapts sample count based on radius.
Use a lower-res pass for large radii (downsample -> blur -> upsample). Impact: Crucial for rendering large blurs in real-time.
2. High Priority (The "battery savers")
D. Metalize Quality Control (MetaVisQC)
Problem: VideoContentQC uses CoreGraphics (CPU) CVPixelBuffer locking and pixel iteration to calculate fingerprints. This forces a GPU->CPU synchronization and heavy CPU load. Solution:

Status (as of Dec 13, 2025): Fingerprints are Metal-accelerated and no longer rely on `AVAssetImageGenerator`/CGContext in the normal path. `VideoContentQC` samples frames via `AVAssetReader` -> `CVPixelBuffer`, runs a two-stage GPU reduction (accumulate + finalize), and reads back only a packed 16-byte result per sample (mean/std RGB). CPU fallback remains for non-Metal environments.

Status (as of Dec 13, 2025): Also Metal-accelerated `VideoContentQC.validateColorStats` by computing mean RGB + a 256-bin luma histogram on a downsampled proxy grid (`qc_colorstats_accumulate_bgra8`), again reading back only a tiny accumulator + histogram buffer. CPU VideoAnalyzer remains as fallback.

Note: `GeminiQC` and deliverable thumbnail extraction may still use `AVAssetImageGenerator` (non-critical vs export hot path).

Implement QC metrics (Mean/StdDev) as Metal Compute Kernels (reduce_sum).
Read back only the tiny result struct, not the whole image. Impact: Removes the massive CPU stall during export.
E. Throttle Vision Analysis (MetaVisSession, MetaVisPerception)
Problem: ProjectSession.analyzeFrame appears to be called freely. If driven by the render loop (60fps), running FaceDetectionService will overheat the device and saturate the Neural Engine. Solution:

Decouple Analysis from Rendering.
Run Analysis at 5Hz (every 12 frames) or only on scene changes.
Cache results (e.g. face rects) and interpolate them for intermediate render frames. Impact: Significantly reduced thermal throttling and CPU usage.
F. Optimize Time Math (MetaVisCore)
Problem: Time and Rational perform gcd (Greatest Common Divisor) on every arithmetic operation (+, -). In a complex Timeline traversal, this happens millions of times. Solution:

Implement a "Lazy Rational" or specialized Time struct that defers simplification until necessary (e.g., only when checking equality or exporting).
Alternatively, use fixed-point math (Int64 ticks) for the hot path if denominator is constant (e.g. 60000). Impact: 10-20% reduction in CPU time for TimelineCompiler.

Status (as of Dec 13, 2025): Implemented a fast fixed-tick (1/60000s) storage path in `Time` for add/sub/compare/seconds, avoiding Rational GCD work in the hot path while preserving the existing Codable shape (`{ "value": { "numerator": ..., "denominator": ... } }`) and reduced `Rational` semantics via a computed `Time.value`.
3. Medium Priority (The "polish")
G. Audio Buffer Reuse (MetaVisAudio)
Problem: AudioTimelineRenderer allocates a new AVAudioPCMBuffer for every chunk. Solution:

Allocated a single "scratch" buffer of maximumFrameCount size.
Reuse this buffer for the render loop. Key Note: AVAudioEngine manual rendering might require unique buffers? Verify if renderOffline allows overwriting the same buffer pointer safely. (It usually does).
H. Vision Request Reuse (MetaVisPerception)
Problem: FaceDetectionService recreates VNImageRequestHandler and VNTrackObjectRequest objects frequently. Solution:

Keep the VNImageRequestHandler alive if analyzing the same pixel buffer (not possible, it consumes the buffer).
Focus on reusing the Request objects (VNDetectFaceRectanglesRequest), which is partly done but tracking logic recreates arrays.
4. Implementation Roadmap
Phase 1 (Engine Core): Fix Texture Pool & Asset Loading. (Required for "It Works").
Phase 2 (Shader & QC): Optimize Blur Loop & Metalize QC. (Required for 4K real-time).
Phase 3 (Efficiency): Implement Throttling & Buffer Reuse. (Required for "It runs smooth").
Phase 4 (Micro-Opt): Profile Time math with Instruments and optimize if it shows up >5% of trace.
