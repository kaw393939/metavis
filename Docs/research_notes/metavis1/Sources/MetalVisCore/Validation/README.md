# Validation Subsystem

The Validation subsystem is the "Scientific Instrument" of MetaVis. It provides a framework for quantitatively verifying that rendering effects adhere to physical laws.

## Components

* **ValidationRunner**: The orchestrator that loads effect definitions, runs tests, and aggregates results.
* **EffectValidator**: Protocol for implementing specific effect tests (e.g., `BloomValidator`, `ACESValidator`).
* **VisionAnalyzer**: Computer vision utilities for measuring image properties (luminance, color distribution, SSIM, etc.).
* **ValidationLogger**: Persists validation results to `logs/` for longitudinal tracking and research data collection.

## Logging & Data Collection

The `ValidationLogger` automatically records every validation run to support the "Empirical Alignment" research methodology.

* **Metrics History**: `logs/validation_metrics.csv` - Flat CSV format suitable for plotting convergence curves (e.g., Delta E over time).
* **Detailed Logs**: `logs/validation_history.jsonl` - Full JSON structured logs containing diagnostics and metadata.

## Usage

Run validation via the CLI:

```bash
# Run all validations
swift run metavis validate

# Run specific effect
swift run metavis validate --effect bloom

# Output JSON to stdout (for agent consumption)
swift run metavis validate --json
```
