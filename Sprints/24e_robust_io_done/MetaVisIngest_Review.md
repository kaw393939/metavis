# MetaVisIngest Code Review

**Date:** 2025-12-21
**Reviewer:** Antigravity Agent
**Module:** `MetaVisIngest`

## 1. Executive Summary

`MetaVisIngest` handles the induction of new media into the system. It currently focuses on two precise workflows: Scientific Imaging (FITS) and Variable Frame Rate (VFR) Detection. It also contains `LIGMDevice` which appears to be a mock for a "Local Image Generation Module".

**Strengths:**
- **Scientific Precision:** The `FITSReader` provides a specialized, dependency-free implementation for reading 32-bit floating point scientific data, which is critical for ACEScg workflows that require high dynamic range inputs.
- **Robust Timing logic:** `VideoTimingProbe` correctly handles compressed buffers to avoid expensive decoding while checking for VFR issues via PTS deltas. It includes statistical analysis (std dev, distinct counts) to make informed decisions.
- **Diagnostics:** The `Diagnostics` struct in `FITSReader` allows for thread-safe tracking of I/O volume during debugging.

**Critical Gaps:**
- **Mock Code in Source:** `LIGMDevice` (Local Image Generation Module) contains hardcoded simulation delays (`Task.sleep`) and mock URLs. This appears to be test/fixture code that has leaked into the main source tree.
- **FITS Limitations:** The FITS reader only supports a specific subset of the standard (2D images, specific BITPIX). While documented, this limits its general utility.

---

## 2. Detailed Findings

### 2.1 Generative Ingest (`LIGMDevice.swift`)
- **Status:** **PROTOTYPE**.
- **Issue:** The `perform(action:)` method simulates prompt generation with `Task.sleep` and returns a `ligm://` URL. This code path is essentially a stub.
- **Recommendation:** Move this to a test target or a dedicated `MetaVisMocks` module unless it is intended to be the production interface for a local Stable Diffusion runner (in which case it needs real implementation).

### 2.2 FITS Pipeline (`FITS/`)
- **Reader:** `FITSReader` manually parses the 2880-byte block structure of FITS files. It correctly handles big-endian to little-endian conversion for the host machine.
- **Registry:** `FITSAssetRegistry` provides a simple in-memory cache to prevent re-reading the same heavy scientific files multiple times.
- **Performance:** It reads the entire dataset into memory (`Data`). For massive astronomical files, this will OOM. A memory-mapped approach or strip-based reading would be safer for >4GB files.

### 2.3 Timing Analysis (`Timing/`)
- **Analysis:** `VideoTimingProbe` scans the PTS (Presentation Time Stamps) of a video file.
- **Policy:** `VideoTimingNormalization` provides a deterministic logic tree to decide if a clip should be treated as "Passthrough" or normalized to a CFR (Constant Frame Rate). This is essential for timeline stability in NLEs.

---

## 3. Recommendations

1.  **Refactor LIGM:** Determine if `LIGMDevice` is a feature or a fixture. If feature, implement the CoreML call. If fixture, move to Tests.
2.  **Streaming FITS:** Update `FITSReader` to support reading scanlines on demand (mapped) rather than `readExact`'ing the whole blob, to support 8K+ scientific images.
3.  **Error Handling:** `FITSReader` throws generic errors like `dataReadFailed`. Adding context (offset, expected count) would help debugging corruption issues.
