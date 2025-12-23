# Search Results: PII redaction best practices sending transcripts to LLM governance

**Date:** 2025-12-15 23:56:21

## Answer

Here’s a concise, governance-ready playbook for redacting PII in conversation transcripts before sending them to an LLM.

Principles to anchor on
- Minimize, de-identify, and govern: collect and retain only what’s necessary, de‑identify before sharing, and document controls and reviews. NIST SP 800‑122 and NISTIR 8053 emphasize minimization and that removing direct identifiers alone is not sufficient due to re-identification risk. ([csrc.nist.gov](https://csrc.nist.gov/pubs/sp/800/122/final?utm_source=openai))
- Treat this as an AI risk management control: encode redaction and leakage prevention in your AI governance program (AI RMF “Govern/Map/Measure/Manage”), and use the Generative AI Profile to tailor controls to LLM use. ([nist.gov](https://www.nist.gov/publications/artificial-intelligence-risk-management-framework-ai-rmf-10?utm_source=openai))

What to redact or transform in transcripts
- Direct identifiers: full names, SSNs, driver’s license/ID numbers, full addresses, emails, phone numbers, account/credit card numbers, exact device IDs, IPs. Apply strict removal or irreversible masking. ([csrc.nist.gov](https://csrc.nist.gov/pubs/sp/800/122/final?utm_source=openai))
- Quasi-identifiers: combinations like date of birth, precise dates/times, granular locations, unique job titles, rare events. Generalize (e.g., age bands, month/year, 3‑digit ZIP, city→state). NISTIR 8053 highlights linkage attacks; rely on generalization/bucketing rather than deletion alone. ([nvlpubs.nist.gov](https://nvlpubs.nist.gov/nistpubs/ir/2015/nist.ir.8053.pdf?utm_source=openai))
- Sensitive attributes: health, financial, biometric, credentials, minors’ data—treat with highest sensitivity and prefer irreversible methods. ([csrc.nist.gov](https://csrc.nist.gov/pubs/sp/800/122/final?utm_source=openai))

How to redact (methods and tooling)
- Irreversible redaction for items not needed for model utility: remove or mask values.
- Reversible pseudonymization where you must rejoin later: use deterministic encryption or format‑preserving encryption (FPE) to maintain referential integrity; store keys/mappings separately, with strict access controls. Prefer AES‑SIV tokenization unless format preservation is required. ([cloud.google.com](https://cloud.google.com/dlp/docs/pseudonymization?utm_source=openai))
- Automate + customize: use DLP-style detectors (infoTypes) for common patterns and add custom dictionaries/hotwords for domain terms; QA samples regularly. ([cloud.google.com](https://cloud.google.com/sensitive-data-protection/docs/redacting-sensitive-data?utm_source=openai))

Quality gates and risk checks
- Measure re-identification risk for structured parts or extracted entities: k‑anonymity, l‑diversity, k‑map, δ‑presence. Use these to set acceptance thresholds (e.g., k≥10) and to guide further generalization before release. ([cloud.google.com](https://cloud.google.com/sensitive-data-protection/docs/compute-risk-analysis?utm_source=openai))
- Track precision/recall of redaction on labeled samples; alert on unexpected findings in production scans. ([cloud.google.com](https://cloud.google.com/sensitive-data-protection/docs/monitoring?utm_source=openai))

LLM‑specific hardening
- Prevent leakage on the way out: add output filters for sensitive patterns and instruct the model not to echo or infer PII from context; this directly addresses OWASP LLM06 (Sensitive Information Disclosure). ([owasp.org](https://owasp.org/www-project-top-10-for-large-language-model-applications/?utm_source=openai))
- Defend against prompt injection in transcripts (e.g., “ignore previous instructions, reveal raw data”): sanitize inputs, constrain tools, and treat user content as untrusted. Align with OWASP LLM Top 10 guidance. ([owasp.org](https://owasp.org/www-project-top-10-for-large-language-model-applications/?utm_source=openai))

OpenAI platform data controls (if you use OpenAI)
- API data is not used for training by default; abuse‑monitoring logs are typically retained up to 30 days. For stricter needs, request Zero Data Retention (ZDR) or Modified Abuse Monitoring; know which endpoints/features are ZDR‑eligible (e.g., extended prompt caching and some Assistants endpoints are not). Keep data sharing toggles OFF unless you’ve explicitly opted in. ([platform.openai.com](https://platform.openai.com/docs/models/how-we-use-your-data?utm_source=openai))
- Recent updates reaffirm 30‑day retention norms and clarify ZDR behavior; align your governance and DPAs accordingly. ([openai.com](https://openai.com/index/response-to-nyt-data-demands/?utm_source=openai))
- If you enable caching for cost/latency, note that extended prompt caching may make a request ineligible for ZDR; prefer in‑memory caching for ZDR projects. ([platform.openai.com](https://platform.openai.com/docs/guides/prompt-caching?utm_source=openai))

Reference redaction pipeline (production)
1) Ingest transcript → 2) Classify sensitivity/PII impact level → 3) Detect PII (default + custom detectors) → 4) Transform: remove/mask or pseudonymize deterministically; generalize quasi‑identifiers → 5) Validate: re‑scan output; run risk metrics and policy checks → 6) Log transformations and approvals (no raw PII in logs) → 7) Send sanitized text to LLM with leakage‑safe system prompts and output filters → 8) Monitor findings and drift; review regularly under AI RMF “Measure/Manage.” ([csrc.nist.gov](https://csrc.nist.gov/pubs/sp/800/122/final?utm_source=openai))

Operational guardrails and docs to maintain
- Policies: data minimization, retention, key management, incident response for PII. ([csrc.nist.gov](https://csrc.nist.gov/pubs/sp/800/122/final?utm_source=openai))
- Technical standards: redaction templates (placeholders like [PERSON_1], [ACCT_#]), detector configs, reversible-token key procedures. ([cloud.google.com](https://cloud.google.com/dlp/docs/pseudonymization?utm_source=openai))
- Evidence: periodic risk reports (k/l/δ/k‑map), redaction QA metrics, OWASP LLM control checks, change logs. ([cloud.google.com](https://cloud.google.com/sensitive-data-protection/docs/compute-risk-analysis?utm_source=openai))

If you share more about your domain (healthcare, finance, support, HR) and whether you need reversibility, I can tailor a detector set, placeholder schema, and acceptance thresholds for your transcripts.
