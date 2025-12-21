# MetaVisPerception Specification

## Overview
MetaVisPerception is the "Eyes" of the system. It uses Computer Vision and AI to analyze content, populating the `CastRegistry` and `LookAssets` to give the Agent context.

## 1. Person Intelligence
**Goal:** Identify and track people across the project.

### Components
*   **`FaceEmbeddingEngine` (Existing):** Extracts face vectors.
*   **`IdentityClusterer` (Existing):** Groups faces into Identities.
*   **`CastService` (New):**
    *   Orchestrates the Engine and Clusterer.
    *   Updates `MetaVisCore.CastRegistry`.
    *   Exposes "Who is this?" API to the Agent.

### Implementation Plan
*   [ ] Implement `CastService`.
*   [ ] Connect `CastService` to `MetaVisSession`.

## 2. Style Intelligence
**Goal:** Reverse-engineer visual styles from reference images.

### Components
*   **`ColorAnalyzer` (Existing):** Extracts Histograms and Stats.
*   **`LookService` (New):**
    *   Uses `ColorMatchSolver` (Simulation) to generate `ColorGradeParams`.
    *   Creates `LookAsset` in `MetaVisCore`.

### Implementation Plan
*   [ ] Implement `LookService`.
*   [ ] Connect `LookService` to `MetaVisSession`.

## 3. Scene Understanding
**Goal:** Analyze the environment for "Virtual Set" reconstruction.

### Components
*   **`DepthAnalyzer`:**
    *   Extracts/Refines LiDAR depth maps.
    *   Generates a 3D point cloud for the "RelightNode."
*   **`SaliencyDetector`:**
    *   Identifies the subject of the shot for auto-focus/auto-crop.

### Implementation Plan
*   [ ] Implement `DepthAnalyzer`.
