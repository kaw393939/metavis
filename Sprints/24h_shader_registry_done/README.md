# Sprint 24h — Shader Registry + Call Graph

## Goal
Create a single authoritative mapping from **timeline/feature IDs → render nodes → kernel function names → Metal sources → engine binding rules**, and close any “it exists but can’t be compiled” gaps.

## Coverage
- Matrix of all owned files: [shader_archtecture/COVERAGE_MATRIX_24H_24O.md](shader_archtecture/COVERAGE_MATRIX_24H_24O.md)

### Owned files (primary)
- Registry + integration docs:
  - [shader_archtecture/REGISTRY.md](shader_archtecture/REGISTRY.md)
- Shipping manifests:
  - [Sources/MetaVisGraphics/Resources/Manifests/mv.colorGrade.json](Sources/MetaVisGraphics/Resources/Manifests/mv.colorGrade.json)
  - [Sources/MetaVisGraphics/Resources/Manifests/mv.retime.json](Sources/MetaVisGraphics/Resources/Manifests/mv.retime.json)
  - [Sources/MetaVisGraphics/Resources/Manifests/audio.dialogCleanwater.v1.json](Sources/MetaVisGraphics/Resources/Manifests/audio.dialogCleanwater.v1.json)
  - [Sources/MetaVisGraphics/Resources/Manifests/com.metavis.fx.smpte_bars.json](Sources/MetaVisGraphics/Resources/Manifests/com.metavis.fx.smpte_bars.json)
- Shipping shaders that are “registry-owned” (test-pattern + procedural + reference generators):
  - [Sources/MetaVisGraphics/Resources/SMPTE.metal](Sources/MetaVisGraphics/Resources/SMPTE.metal)
  - [Sources/MetaVisGraphics/Resources/Macbeth.metal](Sources/MetaVisGraphics/Resources/Macbeth.metal)
  - [Sources/MetaVisGraphics/Resources/ZonePlate.metal](Sources/MetaVisGraphics/Resources/ZonePlate.metal)
  - [Sources/MetaVisGraphics/Resources/StarField.metal](Sources/MetaVisGraphics/Resources/StarField.metal)
  - [Sources/MetaVisGraphics/Resources/Procedural.metal](Sources/MetaVisGraphics/Resources/Procedural.metal)
- Swift glue:
  - [Sources/MetaVisGraphics/GraphicsBundleHelper.swift](Sources/MetaVisGraphics/GraphicsBundleHelper.swift)
  - [Sources/MetaVisGraphics/Empty.swift](Sources/MetaVisGraphics/Empty.swift)

## Scope (shipping codepaths only)
- Registry doc: [shader_archtecture/REGISTRY.md](shader_archtecture/REGISTRY.md)
- Compiler port mapping: [Sources/MetaVisSimulation/TimelineCompiler.swift](Sources/MetaVisSimulation/TimelineCompiler.swift)
- Standard feature manifests: [Sources/MetaVisSimulation/Features/StandardFeatures.swift](Sources/MetaVisSimulation/Features/StandardFeatures.swift)
- Engine bindings: [Sources/MetaVisSimulation/MetalSimulationEngine.swift](Sources/MetaVisSimulation/MetalSimulationEngine.swift)

## Deliverables
- Update the registry if any kernel owners/bindings drift.
- Make compiler input-port mapping explicit and test-covered.
- Decide: either (a) support multi-input ports in compiler, or (b) mark those features as non-clip effects.

## Execution checklist
- Verify every `FeatureManifest.inputs` port is either:
  - supported by `TimelineCompiler.compileEffects(...)`, OR
  - clearly documented as “not clip-compilable”.
- Add a small unit test for each supported port mapping:
  - `source` / `input` passthrough
  - `faceMask` generator insertion
- Add a regression test for 2-clip transitions:
  - compiler emits compositor nodes
  - engine binds textures in the expected indices

## Acceptance criteria
- A reader can trace any active kernel name from timeline → dispatch without guessing.
- Unsupported feature ports are clearly labeled and/or fixed.
- Tests cover the compiler’s port mapping and a basic transition compile.
