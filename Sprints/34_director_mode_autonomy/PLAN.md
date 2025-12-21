# Sprint 34: Director Mode (Autonomous Logic)

## Goal
The "Premiere" Sprint. Connect all previous layers (Math, CRDT, GBNF, Delivery) into an autonomous mode where the system can act as a Director/Editor.

## Rationale
This is the realization of the "Generative-Native OS" vision: a Deterministic Engine + Safe Collaboration + a model that can reliably convert intent into actions.

By early 2027 we can take an aggressive Apple-first approach:
- **Primary runtime**: Apple Foundation Models (Apple Intelligence) on-device.
- **Customization**: App-specific **adapters** trained for MetaVis intents + cinematic editor voice.
- **Fallback posture**: capability-tiered behavior when the system model is unavailable (Apple Intelligence off, device not eligible, locale unsupported, etc.).

Director Mode should be able to ingest a standard “dailies” reel and autonomously produce a polished cut (edit decisions + captions + export), with no human intervention until sign-off, while still being safe and reversible.

## Key Assumptions (2027)
- We do **not** optimize for backwards compatibility.
- We target the contemporary iOS/macOS SDKs that provide the Foundation Models framework.
- Adapter distribution is treated as a **versioned asset** fetched at runtime (not bundled), and adapters may be tied to a specific system model version.

## Deliverables
1. **`DirectorMode` Configuration**
	 - A preset for `AutoStartHeuristics` that enables autonomous intervention.
	 - Includes explicit autonomy tier selection, safety gates, and runtime availability checks.
2. **`AutoEditorLoop` (On-device)**
	 - A loop that monitors the CRDT/timeline for “stable” moments.
	 - Requests a structured **Action Plan** from the on-device Foundation Model.
	 - Executes validated actions against the deterministic engine.
3. **`IntentPlan` / Action Plan Contract (Structured Output)**
	 - Typed/structured output (Swift types) representing:
		 - `actions[]`: executable tool calls/intents
		 - `message`: user-facing cinematic explanation
		 - `needsClarification`: optional question when required inputs are missing
	 - The plan is the “source of truth”; narration must not affect correctness.
4. **Adapter Lifecycle (Production-shippable)**
	 - A place in the system for:
		 - selecting the correct adapter at runtime (by system model version)
		 - downloading adapters as background assets
		 - observability for adapter performance/regressions
5. **End-to-End Demo (“Zero Touch”, Confirmed Safe)**
	 - Ingest Raw Media → Wait → Export Final Movie
	 - Includes QC verification before declaring success.

## Autonomy Tiers (explicit)
Director Mode must support a ladder of autonomy so we can scale from “safe assist” to “hands-free”.

- **Tier 0: Suggest**
	- Produces a plan + explanation; no edits are applied.
- **Tier 1: Propose + Confirm**
	- Produces plan; system shows preview; user confirms to apply.
- **Tier 2: Auto-execute (Reversible)**
	- Applies only operations that are trivially reversible and low-risk.
	- Uses conservative thresholds; logs decisions for training data.
- **Tier 3: Full Auto (Sign-off only)**
	- Runs full pipeline (edit + captions + export), then requires final sign-off.

Each tier must be selectable and must degrade gracefully if the system model is unavailable.

## Out of Scope
- Creative Writing. The AI is editing existing footage, not writing scripts from scratch (unless `LIGM` is heavily expanded).

## Safety + Governance (non-negotiable)
- Every tool call/intention must be validated and be idempotent or reversible where possible.
- Default to **Confirm** for destructive operations unless Tier explicitly permits auto-execute.
- Runtime availability must be checked (Apple Intelligence can be off/unavailable).
- All autonomous runs must produce a trace suitable for later adapter training and regression tests.

## Integration: Sealed Verification
*   **Verifier Link:** The `DirectorMode` loop MUST call the `DeliverableVerifier` (Sprint 33) before marking a job as success.
*   **Audio Clock:** Ensure the `AVAudioEngine` is set to manual rendering mode (Sprint 30) during the autonomous export pass.

## Research Pack (Sprint-local)
This sprint is grounded in the Sprint-local research bundle in [Sprints/34_director_mode_autonomy/research/README.md](research/README.md).

### Foundation Models + Adapters (primary)
- macOS Tahoe 26 requirements and testing constraints:
	- [research/research_notes/llm_model_research_2025-12-20/md/macos_tahoe_26_foundation_models_requirements.md](research/research_notes/llm_model_research_2025-12-20/md/macos_tahoe_26_foundation_models_requirements.md)
- Foundation Models overview (on-device, Swift-native, structured output/tool calling):
	- [research/research_notes/llm_model_research_2025-12-20/md/apple_foundation_models_on_device_llm_2025.md](research/research_notes/llm_model_research_2025-12-20/md/apple_foundation_models_on_device_llm_2025.md)
- Adapter training toolkit requirements + versioning expectations:
	- [research/research_notes/llm_model_research_2025-12-20/md/apple_foundation_models_adapters_training_toolkit_2025_2026.md](research/research_notes/llm_model_research_2025-12-20/md/apple_foundation_models_adapters_training_toolkit_2025_2026.md)
- Entitlements + distribution model for adapters:
	- [research/research_notes/llm_model_research_2025-12-20/md/foundation_models_entitlements_adapter_distribution.md](research/research_notes/llm_model_research_2025-12-20/md/foundation_models_entitlements_adapter_distribution.md)
- On-device system model technical notes (why it can be fast):
	- [research/research_notes/llm_model_research_2025-12-20/md/apple_on_device_foundation_model_3b_2bit_qat_2025.md](research/research_notes/llm_model_research_2025-12-20/md/apple_on_device_foundation_model_3b_2bit_qat_2025.md)

### iPhone availability + capability tiering
- Foundation Models availability checks and “Apple Intelligence off / device not eligible” scenarios:
	- [research/research_notes/llm_model_research_2025-12-20/md/ios18_iphone16_foundation_models_availability.md](research/research_notes/llm_model_research_2025-12-20/md/ios18_iphone16_foundation_models_availability.md)

### Supporting context (optional lanes)
These are not the primary Director Mode runtime, but help with performance strategy and fallbacks:
- Core ML stateful models / KV cache support:
	- [research/research_notes/llm_model_research_2025-12-20/md/coremltools_stateful_llm_kv_cache_2025.md](research/research_notes/llm_model_research_2025-12-20/md/coremltools_stateful_llm_kv_cache_2025.md)
- Core ML weight compression (4-bit) guidance:
	- [research/research_notes/llm_model_research_2025-12-20/md/coremltools_weight_compression_llm_2025.md](research/research_notes/llm_model_research_2025-12-20/md/coremltools_weight_compression_llm_2025.md)
- MLX OpenAI-compatible server options (useful for dev tooling / non-AFM environments):
	- [research/research_notes/llm_model_research_2025-12-20/md/mlx_openai_compatible_server_2025.md](research/research_notes/llm_model_research_2025-12-20/md/mlx_openai_compatible_server_2025.md)
- Fastest local LLM runtime on Apple Silicon (llama.cpp / Metal) notes:
	- [research/research_notes/llm_model_research_2025-12-20/md/fastest_local_llm_runtime_apple_silicon_2025.md](research/research_notes/llm_model_research_2025-12-20/md/fastest_local_llm_runtime_apple_silicon_2025.md)

## Research-derived Constraints (must be reflected in implementation)
- **Runtime availability is not guaranteed** (Apple Intelligence can be disabled/unavailable) → Director Mode must support tiered degradation.
- **Adapter shipping requires entitlement** (Account Holder request) → plan the entitlement lead time early.
- **Adapters are versioned against the system model** → plan an adapter registry + per-version selection.
- **Adapters are large and should be delivered as assets** (not embedded) → plan background asset delivery + caching.
- **Adapter training may require more memory than a 16GB dev laptop** → plan a dedicated training machine/worker.

## Notes
- This sprint assumes Apple Foundation Models + adapters as the primary production runtime by 2027.
- Cloud models remain useful as “teachers” during R&D (data generation, evaluation), but Director Mode’s production loop is on-device-first.
