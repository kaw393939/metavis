# MetaVisQC Assessment

## Initial Assessment
MetaVisQC is a comprehensive Quality Control module that combines traditional deterministic checks (file specs, black frames) with cutting-edge AI verification (Gemini). It ensures that exported deliverables meet strict technical and semantic standards.

## Capabilities

### 1. Deterministic QC (`VideoQC`)
- **Spec Verification**: rigorously checks file duration, resolution, frame rate, and valid sample counts against expectations.
- **Audio Integrity**: Scans for "digital silence" and ensures audio tracks are present when required.

### 2. Content QC (`VideoContentQC`)
- **Sampling**: Analyzes video frames at specific timepoints (p10, p50, p90) to ensure visual integrity.
- **Dead Pixel/Freeze Detection**: `assertTemporalVariety` fails if adjacent reference frames are identical, catching "stuck buffer" rendering bugs.
- **Luma/Color Stats**: Computes luma histograms and RGB averages to detect exposure issues or color cast errors.
- **Acceleration**: Hybrid implementation uses Metal for speed on GPU devices, with a robust CoreGraphics CPU fallback.

### 3. Semantic QC (`GeminiQC`)
- **Concept**: Uses a Multimodal LLM (Gemini 1.5) to "watch" the video (via keyframes) and verify it matches the user's intent ("Does this video show a cat?").
- **Safety**: Includes PII redaction (UUIDs, Emails, Paths) to sanitize prompts before they leave the device.
- **Cost Control**: Implements a "Local Gate" (checks for black screens locally) to prevent wasting API tokens on obviously bad renders.

## Technical Gaps & Debt

### 1. Hardcoded Heuristics
- **Issue**: Magic numbers abound (e.g., silence threshold `0.0005`, black screen luma `0.01`, color stat tolerances).
- **Debt**: Tuning these requires code changes. They should be lifted into the `QualityPolicyBundle`.

### 2. Sparse Sampling
- **Issue**: QC only looks at a few frames (p10, p50, p90).
- **Risk**: A 1-second glitch in a 10-minute video is statistically unlikely to be caught.
- **Fix**: Continuous scanning or "smart sampling" based on scene changes.

### 3. Network & Secrets
- **Issue**: `GeminiQC` relies on environment variables (`GEMINI_API_KEY`).
- **Debt**: Hard to test in CI/CD without secrets.
- **Fix**: Improved mocking strategy for offline verification.

## Improvements

1.  **Streaming QC**: Integrate `VideoContentQC` directly into the `VideoExporter` pipeline to analyze *every* frame as it renders, with zero IO overhead.
2.  **Policy Configuration**: Externalize all QC thresholds into a JSON profile.
3.  **Local CoreML**: Use a small local mode (e.g. "yolo") for basic object detection to reduce dependency on the cloud LLM.
