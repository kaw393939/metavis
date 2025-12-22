# MetaVisCore Code Review

**Date:** 2025-12-21
**Reviewer:** Antigravity Agent
**Module:** `MetaVisCore`

## 1. Executive Summary

`MetaVisCore` acts as the foundational layer for the system, defining primitives for Time, Governance, Signals, and Abstract Interfaces. It is designed with safety, determinism, and enterprise-grade compliance in mind.

**Strengths:**
- **Governance & Safety:** `AIGovernance` and `ProjectLicense` logic is embedded at the type level, preventing accidental misuse of AI features or unlicensed export capabilities.
- **Precision:** Usage of `Rational` numbers for `Time` ensures frame-accurate editing without floating-point drift, critical for long-form video.
- **Color Accuracy:** `ColorScienceReference` provides a ground-truth CPU implementation for ACEScg transforms, enabling robust unit testing of GPU shaders.
- **Abstraction:** Clean separation of intent (`RenderGraph`) from execution (`RenderEngineInterface`).

**Critical Gaps:**
- **Values:** Some key values are hardcoded (e.g., `LocationData` presets, `EnvironmentProfile` defaults). These should likely be moved to a configuration file or non-compiled resource.
- **Architecture:** `FeedbackLoopOrchestrator` handles direct file I/O and JSON serialization. This makes it harder to test without touching the filesystem.
- **Missing Tests:** No unit tests were found alongside the source code (though `ColorScienceReference` implies they exist elsewhere or are intended).

---

## 2. Detailed Findings

### 2.1 Time & Math (`Time.swift`)
- **Implementation:** `Rational` struct with `Int64` numerator/denominator.
- **Optimization:** Uses a `.ticks(Int64)` fast path (1/60000s) which covers all standard frame rates (24, 30, 60, 1000/1001 variants).
- **Verdict:** Excellent. This is industry-standard for video editors (similar to CMTime but Swift-native).

### 2.2 Governance (`AIGovernance.swift`, `GovernanceTypes.swift`)
- **Design:** Explicitly models "AI Usage Policy" (text vs image vs video) and "Privacy" (redaction of PI).
- **Observation:** `allowsNetworkRequests(privacy:)` acts as a gatekeeper. This is a strong pattern for a tool that handles sensitive user media.
- **Watermarking:** `WatermarkSpec` is defined here, reinforcing that rights management is a core concern.

### 2.3 Determinism (`FeedbackLoopOrchestrator.swift`)
- **Pattern:** Uses a "Hooks" struct for dependency injection (`makeInitialProposal`, `buildEvidence`).
- **Issues:**
    - The `run` method performs `FileManager` operations directly (`createDirectory`, `write`).
    - *Recommendation: Abstract filesystem access behind a protocol to allow in-memory testing of the orchestration logic.*

### 2.4 Color Science (`ColorScienceReference.swift`)
- **Scope:** Covers Rec.709 <-> ACEScg, ASC CDL, and ACES Filmic Tone Mapping.
- **Correctness:** Matrix values match standard SMPTE/ACES specifications.
- **Usage:** Explicitly marked "CPU Reference... for Unit Testing". This is best practice.

### 2.5 Interfaces & Tracing
- **Tracing:** `TraceSink` protocol allows pluggable logging (InMemory vs Stdout).
- **AI Inference:** `AIInferenceService` (Actor) cleanly abstracts hardware availability checks (`isSupported`, `warmUp`, `coolDown`).

---

## 3. Recommendations

1.  **Refactor Orchestrator:** Extract `FileManager` usage in `FeedbackLoopOrchestrator` to a `FileSystemAdapter` protocol.
2.  **Configuration:** Move hardcoded constant values (Cities, presets) to a JSON/Plist resource or a separate `MetaVisConfig` package.
3.  **Float16/32 Strategy:** Standardize on `Float` (32-bit) for CPU reference code and `Float16` for GPU/Signal types to ensure consistent precision expectations.
