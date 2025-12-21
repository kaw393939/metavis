# Sprint 11: Native Evidence Generation

## 1. Objective
Remove `ffmpeg` CLI dependency from `MetaVisLab`.

## 2. Scope
*   **Target Modules**: `MetaVisLab`

## 3. Acceptance Criteria
1.  **Self Contained**: `MetaVisLab` needs no external binaries to run.
2.  **Accuracy**: JPEGs extracted match exactly (or close enough) to the source time.

## 4. Implementation Strategy
*   Use `AVAssetImageGenerator` (slow but easy) or `VideoExporter` (fast, engine-accurate) to produce JPEGs.
