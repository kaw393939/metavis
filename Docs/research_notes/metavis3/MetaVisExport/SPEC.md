# MetaVisExport Specification

## Overview
MetaVisExport handles the final delivery of the project. It converts the `NodeGraph` output into standard video formats (ProRes, H.264) or specialized formats (USDZ for Spatial).

## 1. Video Export
**Goal:** High-performance encoding.

### Components
*   **`VideoEncoder`:**
    *   Wraps AVAssetWriter.
    *   Supports HDR (PQ/HLG) metadata injection.

### Implementation Plan
*   [ ] Update `VideoEncoder` to support ACES ODTs.

## 2. Spatial Export
**Goal:** Export for Vision Pro / AR.

### Components
*   **`USDZExporter`:**
    *   Exports the 3D Scene (Camera, Lights, Planes) as a USDZ file.
    *   Allows the project to be viewed "spatially" on Vision Pro.

### Implementation Plan
*   [ ] Implement `USDZExporter`.
