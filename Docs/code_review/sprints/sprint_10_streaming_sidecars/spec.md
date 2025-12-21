# Sprint 10: Streaming Sidecars

## 1. Objective
Generate Thumbnails and Contact Sheets *during* the video encoding pass in `VideoExporter`.

## 2. Scope
*   **Target Modules**: `MetaVisExport`

## 3. Acceptance Criteria
1.  **One Pass**: The source is read once. Video is encoded, and thumbnails are sampled from the same buffer stream.
2.  **Performance**: Reduces export time for short clips by ~10% (avoiding re-read).

## 4. Implementation Strategy
*   Add a `SidecarGenerator` hook to the `VideoExporter` loop.
*   Accumulate buffers and resize using `vImage` or CoreGraphics.
