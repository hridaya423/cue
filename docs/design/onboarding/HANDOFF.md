# Cue onboarding handoff

## Assignment for the implementing agent

Implement the six-screen native macOS onboarding described in [SPEC.md](SPEC.md), following [DESIGN.md](../../../DESIGN.md) and [the ordered implementation plan](../../plans/2026-09-22-onboarding-redesign.md). Open the six PNG references before coding. Preserve the approved fold-out layout and finish, with the functional corrections in the spec. The user has approved the visual direction; routine implementation does not need another direction-selection round.

The user wants Cue explained as extracting the relevant part of ONE copied text block for a focused field. Do not show clipboard history, competing copied items or a stack of separate clips. Existing runtime behavior is broader; the spec records that difference and bounds the practice path. This assignment is onboarding implementation, not an engine rewrite.

## Authoring checkpoint

- Completed: repository inspection, six-reference asset package, detailed screen/state specification, shared DESIGN.md, task-by-task plan and asset provenance.
- Not done: SwiftUI implementation, runtime verification, dark-mode screenshots, hosted/local alternate-state images.
- No source code, dependencies, settings, Keychain values or Accessibility grants changed in this authoring task.
- Pre-existing repository state: `output/` was untracked. Preserve it. No existing DESIGN.md was found.
- Source baseline examined: current Onboarding.swift, ProviderPicker.swift, CueApp.swift, Settings.swift, Models.swift, Redaction.swift, Controller.swift, Decide.swift, SelfCheck.swift and Package.swift.

## Runtime assets

None required. Use native SF Pro, SF Symbols or actual app icon, real text, vector RoundedRectangle/Shape surfaces and shadows. The reference PNGs remain documentation assets and must not be bundled as interface backgrounds. No new font, texture, logo, 3D scene, image-generation request or UI dependency is necessary to implement the approved look.

If the paper lip is difficult, use the small vector fold defined in DESIGN.md. Preserve editable text and native controls. Do not substitute a screenshot, decorative arrow or long photoreal ribbon.

## Reference inventory

| File | What to implement |
| --- | --- |
| [Welcome](references/01-welcome.png) | Single-message demonstration, source over receiving preview |
| [Accessibility](references/02-accessibility.png) | OS settings guide and direct grant action |
| [Trigger](references/03-trigger.png) | Dedicated recorder versus intercept choice |
| [Models](references/04-models.png) | Dedicated picker plus selected setup detail |
| [Privacy](references/05-privacy.png) | Separate example redaction screen |
| [Practice](references/06-practice-success.png) | Verified first-paste success state |

[manifest.json](references/manifest.json) records original built-in imagegen output filenames and SHA-256 hashes. The images were generated during this design conversation; they are not actual app screenshots. Copies are now stored in this repository so implementation is independent of the original Codex session directory. The exact authoring prompts were supplied in the conversation; the normative reconstruction instructions are in SPEC.md and DESIGN.md, including corrections to generated artifacts.

## Important corrections

1. Model descriptions and colorful icons in the generated picker were invented. Use catalog-backed reasons and uniform neutral tiles; current rank order starts Von, Kev, Laya.
2. Original hotkey glyphs were distorted. Display the configured binding through the existing runtime string.
3. `[NAME]` and `[EMAIL]` are illustrative; actual Redact output may use numbered placeholders.
4. Practice success must be observed, not assigned by an animation or inferred from nonempty text.
5. The original welcome image has no dark variant. DESIGN.md defines proposed dark tokens, which must be inspected in the running app.
6. Layout coordinates and token values are explicit implementation targets, not measurements extracted from the generated raster.
7. Generated model screenshot places navigation in the detail card. Use a stable outer footer for every route.

See [documentation validation](VALIDATION.md) for package checks and proposed token contrast.

## Implementation progress ledger

Update this table as work proceeds. Add evidence links rather than “done” without a check.

| Milestone | State | Evidence |
| --- | --- | --- |
| Baseline build/test and screenshot | Done | 61/61 tests green pre-change; prior onboarding captured before rewrite |
| Native shell and shared styling | Done | `Views/OnboardingStyle.swift` (tokens, fold seam, paragraph renderer); `CueApp.swift` 760×580 transparent-titlebar window; `01-welcome-light.png`, `02-accessibility-*.png` |
| Single-message welcome | Done | `Views/Onboarding.swift` Welcome route — single paragraph, coral span highlight (multi-line wrap verified), Email/Website segments, preview field; `01-welcome-light.png`, `01-welcome-website-dark.png` |
| Accessibility and trigger | Done | Live `ContextCaptor.isTrusted` poll + settings guide; trigger radios + real `HotkeyRecorder` binding, dimmed in intercept; `02-accessibility-*.png`, `03-trigger-*.png` |
| Model picker and connection | Done | `Views/OnboardingModelPicker.swift` — On this Mac/Hosted tabs, catalog-ranked specs, detail panel, install/start states, typed `ProviderConnectionResult` + stale-result discard; `04-models-*.png`; live stub round-trip flipped primary to Continue |
| Separate privacy | Done | Locality from actual endpoint `isRemote` (loopback custom = local), tri-state PII; `05-privacy-light.png` |
| Real practice | Done | `OnboardingPractice.swift` — real pasteboard write, real ⌃⌥V dispatch, real engine/stub endpoint, real synthetic ⌘V, observed field text `mira@example.com`; `06-practice-*.png`. Production trigger path verified, not a sample-scoped substitute |
| Light/dark and accessibility review | Done | Light + dark captures of all six routes; AX labels on controls; `output/onboarding/` |
| Final build/test and native verification | Done | 70/70 tests, 12 suites; `Scripts/bundle.sh` cert-signed build; menu self-check PASS end-to-end |

## Implementation notes (beyond the spec)

- **Self-check crash fixed** (pre-existing): closing a window whose field editor is still first responder over-released the editor at autorelease drain — `isReleasedWhenClosed = false` + explicit first-responder teardown.
- **Intercept-mode synthetic-paste bug fixed** (pre-existing): `RegisterEventHotKey` consumed our own reposted ⌘V — `isSynthesizing` only stopped the handler, the event was already gone. `HotkeyManager.suspendIntercept()`/`resumeIntercept()` now lift the ⌘V registration around synthetic pastes; without it every intercept-mode paste (success or bail repost) delivered nothing.
- **Self-check keystroke leg**: an LSUIElement app cannot self-activate from a synthetic driver, so the ⌘V leg rides `PasteExecutor.onWouldPost` → `performKeyEquivalent`/`paste:` on the field editor. Capture → decide → pasteboard write remain the production path.
- **Menu-bar privacy caption** now follows actual endpoint locality (`isRemote`), not provider category — a loopback custom endpoint no longer claims "pii scrubbed".
- **Footer dedup**: "Finish setup later" no longer renders twice when the primary action already is finish-later.

## Completion report required

Report implemented routes, source changes, relevant test results, real-app screenshot links and limitations. State explicitly whether practice verified the production trigger path or a sample-scoped engine path. Note unresolved failures and external permissions. Do not claim the feature complete using concept images as verification.
