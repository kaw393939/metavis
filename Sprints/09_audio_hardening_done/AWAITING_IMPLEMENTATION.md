# Awaiting Implementation

## Gaps & Missing Features
- None identified.

## Technical Debt
- **Advanced DSP**: No compressor/true limiter; current hardening uses a simple deterministic peak safety limiter.
- **Noise Reduction**: Cleanwater v1 is EQ-based only (no spectral denoising).
- **Multi-channel**: Working format is stereo; no 5.1/7.1 support or downmix rules.

## Recommendations
- Implement a deterministic compressor/true limiter stage (custom DSP).
- Support mono-to-stereo upmixing and define explicit downmix rules.
