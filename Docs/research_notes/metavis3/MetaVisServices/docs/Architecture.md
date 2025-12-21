# MetaVisServices Architecture

## 1. High-Level Diagram

```mermaid
graph TD
    Client[MetaVis Client (UI/CLI)] --> Orchestrator[ServiceOrchestrator]
    
    subgraph "Configuration"
        Env[.env File] --> ConfigLoader[ConfigurationLoader]
        ConfigLoader --> Orchestrator
    end
    
    subgraph "Service Layer"
        Orchestrator --> Registry[ProviderRegistry]
        Registry --> Google[GoogleProvider]
        Registry --> Eleven[ElevenLabsProvider]
        Registry --> LIGM[LIGMProvider]
    end
    
    subgraph "External World"
        Google -- HTTP/GRPC --> VertexAI[Vertex AI API]
        Eleven -- HTTP --> ElevenAPI[ElevenLabs API]
        LIGM -- Metal --> LocalGPU[Local GPU]
    end
    
    subgraph "Data Flow"
        VertexAI --> ResponseHandler
        ElevenAPI --> ResponseHandler
        LocalGPU --> ResponseHandler
        ResponseHandler --> AssetFactory[AssetFactory]
        AssetFactory --> Client
    end
```

## 2. Core Components

### 2.1. `ServiceOrchestrator`
The main entry point. It initializes the system, loads configuration, and routes requests to the appropriate provider.

### 2.2. `ServiceProvider` (Protocol)
The contract that all providers must adhere to.
```swift
protocol ServiceProvider {
    var id: String { get }
    var capabilities: Set<ServiceCapability> { get }
    func initialize(config: ServiceConfig) async throws
    func generate(request: GenerationRequest) async throws -> GenerationResponse
}
```

### 2.3. `ConfigurationLoader`
Responsible for parsing the `.env` file from the project root and vending secure `ServiceConfig` objects. It ensures API keys are never hardcoded.

### 2.4. `GoogleProvider`
Implementation for Google's Vertex AI stack.
- Uses `Gemini 3 Pro` for text/multimodal analysis.
- Uses `Veo 3.1` for video.
- Uses `Lyria` for music.

### 2.5. `ElevenLabsProvider`
Implementation for ElevenLabs API.
- Handles TTS, STS (Speech-to-Speech), and SFX.

### 2.6. `LIGMProvider`
A wrapper around the `MetaVisImageGen` module. It adapts the local Metal-based generation to the `ServiceProvider` interface, allowing it to be swapped with cloud providers transparently.

## 3. Data Flow
1.  **Request:** Client creates a `GenerationRequest` (e.g., `.video(prompt: "...")`).
2.  **Routing:** Orchestrator finds a provider capable of `.videoGeneration`.
3.  **Execution:** Provider executes the task (HTTP call or GPU dispatch).
4.  **Normalization:** The raw result (JSON URL or `MTLTexture`) is wrapped in a `GenerationResponse`.
5.  **Asset Creation:** The response is converted into a `MetaVisCore.Asset` with full metadata.
