# Sprint 33: The Sealed Transport (Delivery Verification)

## Goal
Establish a "Golden Seal" for exports. Implement a verification tool that mathematically proves the exported Video, Sidecars, and QC Report match the `DeliverableManifest` intent.

## Rationale
In professional workflows, "trust but verify" is insufficient. We need "verify then trust." The `MetaVisExport` module generates complex packages. We need a standalone verifier that acts as the "Receiver" (like a Netflix QC bot) to ensure our exports are valid before they leave the machine.

## Deliverables
1.  **`DeliverableVerifier`:** A class that takes a directory path and returns a `pass/fail` verdict.
2.  **Manifest Integrity Check:** Parsing `manifest.json` and verifying checksums of all listed assets (video, subtitles, images).
3.  **Sidecar Validation:** Parsing `.vtt` / `.srt` files and checking if they align with the timeline duration declared in the manifest.
4.  **CLI Command:** `metavis verify <path/to/export>`

## Optimization: Apple Silicon I/O
*   **Mapped Reads:** For checksumming huge 8K video masters, use `DispatchIO` or memory-mapped reads (`mmap`) to maximize SSD throughput (7GB/s on M3) without blocking the main thread.

## Out of Scope
- Visual Quality Assessment (VQA). We are verifying *structural and metadata integrity*, not whether the movie is "good".
