# TDD Strategy: Feature Registry

**Status:** DRAFT
**Role**: Orchestration of Modular Effects
**Related**: `PROPOSAL_REFINED_ARCHITECTURE.md`

## 1. The Core Concept
Moves hardcoded effects (e.g., `BloomNode`, `GrainNode`) out of the Engine core and into a dynamic **Feature Registry**. This allows third-party (or user-created) shaders to be added at runtime.

## 2. The Data Structure (`FeatureManifest`)
A Value Type that describes *what* a feature is.

```swift
struct FeatureManifest: Codable, Identifiable {
    let id: String // "com.metavis.fx.bloom"
    let version: String // "1.0.0"
    let name: String // "Cinematic Bloom"
    let category: FeatureCategory // .stylize, .blur, .utility
    
    // Inputs (e.g. "Main Image", "Depth Map")
    let inputs: [PortDefinition]
    
    // Parameters (e.g. "Threshold", "Intensity")
    let parameters: [ParameterDefinition]
    
    // Shader Source (The metal function name)
    let kernelName: String
}

enum ParameterDefinition: Codable {
    case float(name: String, min: Float, max: Float, default: Float)
    case color(name: String, default: SIMD4<Float>)
    case bool(name: String, default: Bool)
    // ...
}
```

## 3. The Actor (`FeatureRegistry`)
A Thread-Safe Actor that manages the catalog.

```swift
actor FeatureRegistry {
    private var features: [String: FeatureManifest] = [:]
    
    func register(_ manifest: FeatureManifest)
    func feature(for id: String) -> FeatureManifest?
    func allFeatures() -> [FeatureManifest]
}
```

## 4. TDD Steps

### Step 1: Manifest Logic (Unit Tests)
*   **Test**: Create `FeatureManifestTests`.
*   **Verify**: JSON Encoding/Decoding works for complex parameter lists.
*   **Verify**: Parameter validation (defaults within min/max).

### Step 2: Registry Logic (Unit Tests)
*   **Test**: Create `FeatureRegistryTests`.
*   **Verify**: Registration adds feature.
*   **Verify**: Duplicate registration policies (overwrite or error).
*   **Verify**: Thread safety (concurrent access).

### Step 3: Node Integration (Integration Tests)
*   **Test**: Create `GenericRenderNodeTests`.
*   **Action**: Create a `GenericRenderNode` that takes a `FeatureManifest` in init.
*   **Verify**: Its `ports` array matches the Manifest `inputs`.
*   **Verify**: Its `properties` dictionary matches the Manifest `parameters`.

### Step 4: Loading (Integration Tests)
*   **Test**: Create `RegistryLoaderTests`.
*   **Verify**: Can load a `.json` manifest from the Bundle.
