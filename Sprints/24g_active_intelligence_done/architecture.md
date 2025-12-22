# Sprint 24g: Architecture - Real AI

## 1. The Intelligence Stack

**Current:**
`ProjectSession` -> `LocalLLMService` (Mock) -> `IntentParser` (Regex)

**Target:**
```mermaid
graph TD
    Session[ProjectSession] -->|Prompt| Router[ModelRouter]
    
    Router -->|Simple intent| SLM[Local CoreML Model]
    Router -->|Deep reasoning| Cloud[Gemini Pro]
    
    SLM -->|JSON| Parser[IntentParser]
    Cloud -->|JSON| Parser
    
    Parser -->|UserIntent| Session
```

### 1. LLM Abstraction Layer

We need to break the direct dependency on `LocalLLMService` (the concrete actor).

```mermaid
classDiagram
    class LLMProvider {
        <<interface>>
        +generate(request: LLMRequest) async throws -> LLMResponse
    }
    class LocalLLMService {
        +warmUp()
    }
    class MockLLMService {
        +deterministicResponses
    }
    LLMProvider <|-- LocalLLMService
    LLMProvider <|-- MockLLMService
    ProjectSession --> LLMProvider
```

### 2. Request Management (Brain Loop)

**Current:**
Fire-and-forget async calls.

**Target:**
```mermaid
sequenceDiagram
    User->>ProjectSession: Type "Make it..."
    ProjectSession->>TaskHandle: Cancel Previous
    ProjectSession->>TaskHandle: Start New(LLMRequest)
    TaskHandle->>LLMProvider: generate()
    LLMProvider-->>ProjectSession: Response
    ProjectSession->>UI: Update Intent
```

### 3. Multimodal Payload
`GeminiClient` internal structs already support `inlineData` / `fileData`. We just need to expose them in the `GeminiDevice` action interface (e.g. `ask_expert(prompt: String, image: Data?)`).

## 2. Multimodal Data Flow

**Current:**
`GeminiDevice` is a `SimulationDevice` that takes `Text`.

**Target:**
`GeminiDevice` accepts `MultimodalPayload`.
```swift
struct MultimodalPayload {
    let text: String
    let visualContext: [UnifiedImage] // JPEGs or PixelBuffers
    let audioContext: [AudioBuffer]?
}
```
The `MetalSimulationEngine` must be updated to feed this payload when executing a Graph Node that taps into an AI Service.
