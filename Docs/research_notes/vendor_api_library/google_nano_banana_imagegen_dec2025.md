# Search Results: Nano Banana image generation Google API

**Date:** 2025-12-13 07:33:59

## Answer

Do you want a quick-start for generating images with Google’s Nano Banana models (Gemini image models) via the Gemini API? If so, which language do you prefer (JavaScript/Node, Python, cURL)?

If you just want the fastest path, here’s a minimal Node example using the Nano Banana (Gemini 2.5 Flash Image) model:
- Get an API key from Google AI Studio and set GOOGLE_API_KEY in your env. ([ai.google.dev](https://ai.google.dev/gemini-api/docs/image-generation))
- npm i @google/genai
- Sample code:
  import { GoogleGenAI } from "@google/genai";
  import fs from "node:fs";

  const ai = new GoogleGenAI({ apiKey: process.env.GOOGLE_API_KEY });

  const prompt = "isometric miniature diorama of a tiny 'nano banana' glowing in a glass cube lamp, soft rim lighting, detailed materials";
  const res = await ai.models.generateContent({
    model: "gemini-2.5-flash-image",
    contents: prompt,
  });

  const imgPart = res.candidates[0].content.parts.find(p => p.inlineData)?.inlineData;
  fs.writeFileSync("nano-banana.png", Buffer.from(imgPart.data, "base64"));

Notes and options:
- Model names:
  - gemini-2.5-flash-image = “Nano Banana” (fast, 1024px default).
  - gemini-3-pro-image-preview = “Nano Banana Pro” (higher quality; supports 1K/2K/4K outputs and more advanced editing/grounding). ([ai.google.dev](https://ai.google.dev/gemini-api/docs/image-generation))
- To request higher resolutions with Pro, specify image size in the generation config (e.g., 1K, 2K, 4K – use an uppercase K). If you’d like, I can show the exact snippet for your language. ([ai.google.dev](https://ai.google.dev/gemini-api/docs/image-generation))
- Image-to-image editing is supported: send a prompt plus an input image and the API will return an edited image. I can provide a short example once you confirm your language. ([ai.google.dev](https://ai.google.dev/gemini-api/docs/image-generation))
- All generated images include a SynthID watermark. ([ai.google.dev](https://ai.google.dev/gemini-api/docs/image-generation))
- Official docs (models, parameters, pricing links, and troubleshooting) are here if you need to reference them. ([ai.google.dev](https://ai.google.dev/gemini-api/docs/image-generation))

Tell me your language and whether you want speed (Nano Banana) or higher fidelity/4K (Nano Banana Pro), and I’ll tailor the code accordingly.
