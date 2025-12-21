# Legacy Text Engine Extraction Report

**Date:** 2025-12-20
**Scope:** `metavis2` (Text Layout, SDF Generation)
**Status:** COMPLETE

## 1. Executive Summary
This report details the layout and generation engine behind the "Hollywood Grade" text rendering. It combines **CoreText** for layout with a custom **Euclidean Distance Transform (EDT)** for high-quality SDF generation.

## 2. Feature Deep Dive

### A. Layout Engine (`TextLayout.swift`)
**Approach:** CPU-side Layout using CoreText metrics.
**Key Capabilities:**
*   **Metric-Based:** Uses `CTFontGetAdvancesForGlyphs` to measure text precisely.
*   **Word Wrapping:** Implements a custom word-wrap algorithm that respects container width.
*   **Alignment:** Supports Left, Center, and Right alignment by calculating line widths and offsetting origin.
*   **Output:** Generates a list of `TextDrawCommand` structs (position, glyphID) ready for the GPU.

### B. SDF Generation (`EDT.swift` & `GlyphSDFGenerator.swift`)
**Approach:** CPU-side High-Res Render -> Boolean Grid -> Squared EDT -> Downsample.
**Key Capabilities:**
*   **High-Res Source:** Renders glyphs at 4x target resolution using CoreGraphics to capture curvature.
*   **O(N) EDT:** Uses the linear-time "Squared Euclidean Distance Transform" algorithm (Felzenszwalb & Huttenlocher). This is much faster than naive implementations.
*   **Bilinear Downsample:** Downsamples the float SDF grid to the target texture size using bilinear interpolation for smoothness.
*   **Padding:** Automatically handles padding to prevent SDF artifacts at glyph edges.

### C. Glyph Management (`GlyphManager.swift`)
**Approach:** Async Generation Queue + Atlas.
**Key Capabilities:**
*   **Thread-Safe Cache:** Uses `NSLock` to protect the glyph cache.
*   **Persistence:** Saves the generated Atlas and Cache Manifest to disk to avoid re-generating glyphs on startup.
*   **Double Caching:** Runtime cache (GlyphID) + Persisted Cache (Stable Key: FontName + Size + Index).

## 3. Integration Plan

### Phase 1: Core Graphics (Sprint 02+)
1.  **Port `EDT.swift`** to `MetaVisGraphics`. It's a pure math utility.
2.  **Port `GlyphSDFGenerator.swift`** immediately.

### Phase 2: Layout & Rendering (Sprint 05+)
3.  **Port `TextLayout.swift`** to `MetaVisGraphics/Text`. Implementation is solid.
4.  **Port `GlyphManager.swift`**, ensuring `GlyphCacheStore` (seen in directory list) is also brought over for persistence.

### Recommendation
The combination of `CoreText` for accurate metrics and `EDT` for crisp GPU rendering is the gold standard. We should keep this exact pipeline.
