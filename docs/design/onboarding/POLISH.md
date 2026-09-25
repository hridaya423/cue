# Onboarding follow-up — 2026-09-22

Implemented the requested reference-fidelity pass in the native SwiftUI onboarding. The flow keeps Cue's real permission, trigger, provider, privacy, and practice behavior while making each step clearer and more deliberate.

## Changes

- Accessibility is skipped when permission already exists. When it is needed, the step explains why Cue needs it, animates a pointer to the macOS-style switch, and returns to Cue automatically after the grant.
- The transition from copied detail to destination field uses a curved arrow. The welcome and practice copy now show the actual extracted value with the coral highlight, including across wrapped lines.
- Hosted is the first provider tab. TypeSafe and Vercel marks are bundled from first-party assets; local model rows use model-specific symbols.
- The model detail area describes the selected size and its download and memory cost. Setup progress recognizes percentage output, while startup waits for one real local decision and records its latency before showing Ready.
- Practice places a distinct invoice brief on the clipboard as soon as the page opens, focuses a real labeled field, and uses a 1.8-second decision budget. It reports the observed result instead of claiming success when Cue only performs ordinary paste.
- Local privacy explanation is skipped when there is no remote provider to explain. Remote provider configuration still leads through the privacy choice.
- Onboarding colors follow system light/dark appearance. The 760 × 620 window gives the model details and fixed footer enough space.

## Verification

- `swift test`: 74 tests in 13 suites passed.
- `Scripts/bundle.sh debug`: built the app successfully.
- Inspected native screenshots for welcome, shortcut, hosted providers, local model selection, and the invoice practice screen. The practice screenshot shows the billing URL highlighted across its wrapped lines and the arrow aligned to that source span; provider rows and model details fit above the footer.
- The practice sample is currently on the system clipboard because opening practice performs the requested automatic copy. No permission, provider, API key, or model selection was changed.

The machine already has `/Applications/Cue.app` running a Von server on port 8766. That conflicts with the workspace debug copy, so its local-model detail screenshot reports that the debug server stopped before readiness. I left the installed app and its server untouched. The configured model could not be exercised end to end without that port conflict; no global smart-paste shortcut was triggered.

Provider mark sources and licensing context are recorded in [PROVIDER-ASSETS.md](PROVIDER-ASSETS.md).
