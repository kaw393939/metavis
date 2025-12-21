# Implemented Features

## Status: Fully Implemented

## Accomplishments
- **AIUsagePolicy**: Typed policy for privacy and network usage.
- **GeminiPromptBuilder**: Structured prompt generation with deterministic metrics.
- **Privacy Integration**: Enforces privacy policy before API calls.
- **Prompt Redaction**: `RedactionPolicy` is enforced in prompt text fields (`expectedNarrative`, `notes`) and evidence labels.
- **Model Recording (In-Memory + Codable)**: Gemini QC verdicts record the configured model string when an actual request is made, and verdicts are `Codable` for persistence.
- **Coverage**: Added/updated tests verifying redaction on/off behavior and that skipped/rejected verdicts have `model == nil`.
