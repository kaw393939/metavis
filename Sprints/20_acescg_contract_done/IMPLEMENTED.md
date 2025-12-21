# Implemented Features

## Status: Implemented

## Accomplishments
- ACEScg working-space contract is enforced by the compiler:
	- Rec.709 sources use `idt_rec709_to_acescg`.
	- EXR sources use `idt_linear_rec709_to_acescg`.
	- Graph root applies `odt_acescg_to_rec709`.
- Deterministic contract tests cover IDT/ODT insertion:
	- `ACEScgWorkingSpaceContractTests`
- SDR exports are explicitly tagged as Rec.709 via `AVVideoColorPropertiesKey`.
- Export metadata contract test verifies primaries/transfer/matrix are present and non-HDR:
	- `SDRPreviewMetadataContractTests`
