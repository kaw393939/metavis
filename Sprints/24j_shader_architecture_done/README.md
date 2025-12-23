# Sprint 24j — Shader Architecture (implementation)

## Goal
Turn research + registry into an executable architecture that supports:
- multi-resolution nodes,
- post-stack fusion,
- render-vs-compute migrations where tile memory wins.

## Sprint documentation (24j source of truth)
- Architecture: [ARCHITECTURE.md](ARCHITECTURE.md)
- Data dictionary: [DATA_DICTIONARY.md](DATA_DICTIONARY.md)
- API + contracts: [API_CONTRACTS.md](API_CONTRACTS.md)

## Coverage
- Matrix of all owned files: [shader_archtecture/COVERAGE_MATRIX_24H_24O.md](shader_archtecture/COVERAGE_MATRIX_24H_24O.md)
- RenderGraph + perception integration contract: [shader_archtecture/RENDER_GRAPH_INTEGRATION.md](shader_archtecture/RENDER_GRAPH_INTEGRATION.md)

### Owned files (primary)
- Core integration points:

  - [Sources/MetaVisCore/RenderGraph.swift](Sources/MetaVisCore/RenderGraph.swift)
  - [Sources/MetaVisCore/RenderRequest.swift](Sources/MetaVisCore/RenderRequest.swift)
  - [Sources/MetaVisSimulation/TimelineCompiler.swift](Sources/MetaVisSimulation/TimelineCompiler.swift)
  - [Sources/MetaVisSimulation/MetalSimulationEngine.swift](Sources/MetaVisSimulation/MetalSimulationEngine.swift)
- Perception-facing shader sources:

  - [Sources/MetaVisGraphics/Resources/MaskSources.metal](Sources/MetaVisGraphics/Resources/MaskSources.metal)
  - [Sources/MetaVisGraphics/Resources/FaceMaskGenerator.metal](Sources/MetaVisGraphics/Resources/FaceMaskGenerator.metal)
  - [Sources/MetaVisGraphics/Resources/FaceEnhance.metal](Sources/MetaVisGraphics/Resources/FaceEnhance.metal)
- Multi-resolution enablers:

  - [Sources/MetaVisGraphics/Resources/FormatConversion.metal](Sources/MetaVisGraphics/Resources/FormatConversion.metal)
  - Graph output contracts (resolution + pixel format)
  - Engine edge policy (auto-resize vs explicit adapters)
  - Tiered allocation + in-frame reuse for mixed resolutions

### Owned files (tests)

- [Tests/MetaVisCoreTests/RenderNodeOutputSpecTests.swift](Tests/MetaVisCoreTests/RenderNodeOutputSpecTests.swift)
- [Tests/MetaVisSimulationTests/ResizeBilinearNodeTests.swift](Tests/MetaVisSimulationTests/ResizeBilinearNodeTests.swift)
- [Tests/MetaVisSimulationTests/AutoResizeEdgePolicyTests.swift](Tests/MetaVisSimulationTests/AutoResizeEdgePolicyTests.swift)
- [Tests/MetaVisSimulationTests/RequireExplicitAdaptersEdgePolicyTests.swift](Tests/MetaVisSimulationTests/RequireExplicitAdaptersEdgePolicyTests.swift)
- [Tests/MetaVisSimulationTests/OutputPixelFormatOverrideTests.swift](Tests/MetaVisSimulationTests/OutputPixelFormatOverrideTests.swift)

## Inputs
- Architecture decisions: `shader_archtecture/24J_ARCHITECTURE_PLAN.md`
- Call path registry: `shader_archtecture/REGISTRY.md`
- Research: `shader_research/*.md`

## Work items
- Add a graph-level way to request output resolution per node (full/half/quarter/fixed).
- Update `MetalSimulationEngine` texture allocation to honor per-node resolution.
- Define a PostStack strategy (function constants + variants) and which effects are eligible (handoff to Sprint 24l).

Implemented in 24j:

- `RenderNode.OutputSpec` includes resolution + pixel format.
- `RenderRequest.edgePolicy` controls mixed-resolution edge handling.
  - `.autoResizeBilinear` inserts `resize_bilinear_rgba16f` adapters.
  - `.requireExplicitAdapters` emits warnings for mismatches.
- `MetalSimulationEngine` honors per-node output sizes and can safely bridge mismatched edges.

## Acceptance criteria
- ✅ Multi-resolution allocations are deterministic and test-covered.
- ✅ No binding-index regressions (compositor/volumetric/mask output special-cases still correct).
- ✅ The graph can express at least one half-res branch (even before we wire bloom/volumetric).
