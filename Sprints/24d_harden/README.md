# Sprint 24d: Engine Hardening

**Focus:** Stability, Security, and Independence.

This sprint addresses the "Cardboard Steering Wheel" problem by reinforcing the chassis. Before we add complex AI features, we must ensure the engine runs deterministically and without fragile shell dependencies.

## Contents
*   [Specification](spec.md): Detailed requirements.
*   [Architecture](architecture.md): Diagram of the new decoding pipeline.
*   [TDD Plan](tdd_plan.md): How we will verify the fixes.
*   **Artifacts:** Contains the code review docs for `MetaVisCore`, `MetaVisGraphics`, `MetaVisSimulation`, and `MetaVisTimeline`.

## Primary Deliverables
1.  **Native-first EXR Reader** (CoreImage/ImageIO when available; `ffmpeg` fallback when EXR decode is unavailable on the host).
2.  **Portable Engine** (Removal of hardcoded "kwilliams" paths).
3.  **Verified Bundle Loading** (Production-ready shader loading).

> Note: A fully dependency-free EXR decode path (e.g., TinyEXR) is still a follow-on if we want “works without `ffmpeg` installed” to be a hard requirement on all machines.

## Cross-cutting hardening learnings (from recent codebase work)
1. **Deterministic acceptance tests should be fixture-driven + gated**
	- Use explicit env gating for strict tests to avoid flaky CI (example pattern: `METAVIS_BINDING_ACCEPTANCE=1`).
	- Prefer a fixture directory override env var for iteration without code changes (example pattern: `..._FIXTURE_DIR=<dir>`).

2. **Avoid brittle floating-point boundary checks in time alignment**
	- Even when the project uses rational/tick time internally, some pipelines use `Double` sample times.
	- For window checks like `dt <= window`, use a tiny epsilon to avoid dropping values due to floating-point representation.

3. **Don’t assume dev machine tools exist**
	- Scripts/docs should not require optional tools (`rg`, bespoke binaries) unless they’re part of the repo contract.
	- Prefer ubiquitous tools or provide fallback commands.
