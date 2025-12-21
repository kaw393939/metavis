# MetaVisImageGen Specification

## Overview
MetaVisImageGen handles 2D generative AI tasks (Stable Diffusion, Midjourney). It is treated as a "Generator Device" that produces Image Assets.

## 1. Image Generation
**Goal:** Create textures, backgrounds, and storyboards.

### Components
*   **`ImageGenerator`:**
    *   Interface for local (CoreML) or cloud (API) generation.
    *   Supports "Inpainting" and "Outpainting" nodes.

### Implementation Plan
*   [ ] Implement `ImageGenerator` interface.
