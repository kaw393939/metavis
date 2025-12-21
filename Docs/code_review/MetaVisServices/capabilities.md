# MetaVisServices Assessment

## Initial Assessment
MetaVisServices encapsulates the "Intelligence" layer of the application, intending to provide on-device LLM capabilities for natural language editing ("Jarvis"). Currently, it is a structural skeleton with a mock implementation that relies on deterministic heuristics.

## Capabilities

### 1. Local Intelligence (`LocalLLMService`)
- **Architecture**: Designed to wrap a local CoreML/Transformer model.
- **Current Logic**: Implements a robust "Mock Mode" using Regex heuristics to simulate NLU. It can parse commands like "ripple delete clip 2", "move macbeth by 1s", and "trim in by 0.5s".
- **Targeting**: Sophisticated deterministic resolution logic to map vague user utterances ("clip 2", "that blue clip") to specific UUIDs based on the provided context.

### 2. Context Management (`LLMEditingContext`)
- **Optimization**: Compresses the heavy `Timeline` model into a lightweight `ClipSummary` struct suitable for LLM context windows.
- **Determinism**: Enforces strict sorting of context items to ensure consistent LLM outputs for the same project state.

### 3. Intent Parsing (`IntentParser`)
- **Robustness**: Handles common LLM output quirks, such as Markdown code fences (` ```json `) vs raw JSON, ensuring reliable bridging between text generation and strong Swift types.

## Technical Gaps & Debt

### 1. Mock Implementation
- **Issue**: `LocalLLMService` does not actually use an LLM. It's a glorified command parser.
- **Impact**: Complex nuances ("Make it look sad", "Cut on the beat") will fail or require infinite regex rules.

### 2. Context Scaling
- **Issue**: `LLMEditingContext` dumps linear clip lists.
- **Limit**: For a feature-film timeline (2000+ clips), this will blow out the context window (even 128k) or incur massive latency.
- **Fix**: Needs RAG (Retrieval Augmented Generation) or a sliding window approach focused on the user's viewport.

## Improvements

1.  **Real Model**: Integrate `MLX` or `CoreML` binding for Llama-3-8B-Quantized.
2.  **Vector Search**: Add embedding support to `LLMEditingContext` to search clips by semantic similarity ("find the dog") rather than just name/index.
3.  **Grammar Constraints**: Use a constrained generation library to guarantee valid JSON `UserIntent` output, removing the parsing failure mode entirely.
