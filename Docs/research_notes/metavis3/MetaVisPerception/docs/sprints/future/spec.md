# MetaVisPerception - Specification

## Goals
1.  Port the Gemini-based qualitative analysis.
2.  Port the deterministic CV-based quantitative analysis.

## Requirements

### AI Analysis
- **Model**: Gemini 2.0 Flash (or newer).
- **Input**: Video frames (sampled).
- **Output**: Structured JSON.
- **Prompts**: Must use the legacy "System Prompts" for consistent evaluation.

### CV Analysis
- **Sharpness**: Implement Laplacian variance.
- **Noise**: Implement SNR estimation.
- **Motion**: Implement Optical Flow or simple frame difference for jitter detection.
