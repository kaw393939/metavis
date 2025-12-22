# MetaVisServices

**MetaVisServices** connects the rendering engine to the "Brain" of the operation. It manages connections to Large Language Models (LLMs) to power features like semantic search, automated quality control, and natural language editing.

## Supported Services

### 1. Google Gemini (Cloud)
We use Google's Gemini models (Flash/Pro) for high-reasoning tasks, such as:
- **Quality Control:** "Is this shot in focus?"
- **Content Moderation:** "Is there sensitive content?"
- **Reasoning:** "Why does this edit feel jumpy?"

**Setup:**
You must set the `GEMINI_API_KEY` environment variable.

### 2. Local LLM (On-Device)
**Status: Prototype / Mock**
Intended to host a quantized model (e.g., Llama 3 8B) via CoreML for private, low-latency instruction following ("Cut here", "Make it faster"). 

*Note: The current implementation simulates intelligence with keyword matching.*

## Architecture
- **Clients:** Raw API clients (`GeminiClient`) handle networking and protocol details.
- **Devices:** `VirtualDevice` wrappers (`GeminiDevice`) expose these services to the `MetaVisSimulation` engine, allowing them to appear as nodes in the processing graph.
