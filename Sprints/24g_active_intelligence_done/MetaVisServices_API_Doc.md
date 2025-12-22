# MetaVisServices API Documentation

`MetaVisServices` provides access to intelligent agents, both cloud-based (Gemini) and local.

## 1. Gemini Integration

### Configuration
The service is auto-configured via environment variables:
- `GEMINI_API_KEY` (Required)
- `GEMINI_MODEL` (Default: `gemini-2.5-flash`)

### `GeminiClient`
Direct access to the Google Gemini API.

```swift
let config = try GeminiConfig.fromEnvironment()
let client = GeminiClient(config: config)

// Text Generation
let answer = try await client.generateText(
    system: "You are a colorist.",
    user: "How do I fix white balance?"
)

// Multimodal (Text + Images)
let request = GeminiGenerateContentRequest(...)
let response = try await client.generateContent(request)
```

### `GeminiDevice`
Engine-compatible wrapper implementing `VirtualDevice`. Exposed as "Gemini Expert" in the device graph.

**Actions:**
- `ask_expert`:
    - `prompt` (String): The question to ask.
    - `system` (String, optional): System instructions.
    - Returns: `["text": answer]`
- `reload_config`: Reloads API key/model from environment.

## 2. Local Intelligence

### `LocalLLMService`
**NOTE:** Currently a **MOCK** implementation.

Simulates a local instruction-tuned model (like Llama 3) to interpret natural language editing commands.

```swift
let service = LocalLLMService()
let request = LLMRequest(
    userQuery: "Ripple delete the second clip",
    context: "{...}" // Timeline state context
)
let response = try await service.generate(request: request)
// response.text -> "Sure, removing that clip."
// response.intentJSON -> "{ 'action': 'ripple_delete', ... }"
```

### `IntentParser`
Parses structured commands from the LLM's raw text response.

```swift
let parser = IntentParser()
if let intent = parser.parse(response: response.text) {
    switch intent.action {
    case .rippleDelete:
        // Execute delete...
    // ...
    }
}
```
