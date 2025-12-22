# MetaVisCore API Documentation

`MetaVisCore` provides the fundamental data types and protocols for the MetaVis engine.

## Key Primitives

### 1. Time
Precision time handling for video.
```swift
let t1 = Time(seconds: 1.5)
let t2 = Time(Rational(1, 24)) // Exact 1/24th second
let duration = t1 + t2
```

### 2. Render Graph
Declarative description of a rendering operation.
```swift
let node = RenderNode(
    name: "Blur",
    shader: "gaussian_blur_kernel",
    parameters: ["radius": .float(5.0)]
)
```

### 3. Governance
Manage user rights and AI safety.
```swift
let privacy = PrivacyPolicy(allowRawMediaUpload: false)
let policy = AIUsagePolicy(mode: .textAndImages)

if policy.allowsNetworkRequests(privacy: privacy) {
    // Proceed with AI request
}
```

## Interfaces

### Virtual Device
Protocol for controllable entities (Cameras, Lights, etc).
```swift
class MyCamera: VirtualDevice {
    let deviceType = .camera
    func perform(action: String, with params: [String: NodeValue]) async throws -> ...
}
```

### AI Inference
Protocol for abstraction over CoreML / ANE.
```swift
actor VisionService: AIInferenceService {
    func infer<Req, Res>(request: Req) async throws -> Res { ... }
}
```

## Color Science
CPU reference implementations are available for verification.
```swift
let linear = ColorScienceReference.srgbToLinear(pixel)
let aces = ColorScienceReference.mat709toACES * linear
```
