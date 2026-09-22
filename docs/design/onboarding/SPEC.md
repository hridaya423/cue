# Cue onboarding implementation specification

Status: approved visual direction translated into an implementation contract, 2026-09-22. The images are approved concepts, not pixel-perfect production designs. This document resolves practical behavior and known image artifacts. No application code was changed while preparing this handoff.

## Start here

1. Read the repository's current `AGENTS.md`, then [DESIGN.md](../../../DESIGN.md).
2. Open the six [reference images](references/manifest.json). Read this spec beside them.
3. Follow [the implementation plan](../../plans/2026-09-22-onboarding-redesign.md). It identifies existing APIs, changes and verification gates.
4. Record progress and remaining issues in [HANDOFF.md](HANDOFF.md). Do not treat rendered concept images as evidence that application behavior works.

Precedence: explicit user requirements > this specification's corrections > approved image composition > existing cosmetic implementation. Existing security, paste fallback and provider contracts remain binding. If code has drifted, re-read the named symbols rather than trusting line numbers.

## Goal and boundaries

Replace the current onboarding with a cohesive native Mac flow matching the approved fold-out design. Teach extraction from ONE copied message containing multiple details. Help the user grant Accessibility, choose their trigger, configure a decision model, understand redaction and perform a first paste.

Scope includes onboarding window geometry, its shared components, setup states, the existing hotkey recorder's accessibility if reused, a compact model-picker presentation, and a truthful practice experience. Retain Settings and menu capabilities. A redesign of clipboard history, queues, storage, inference protocols, model installation or application branding is outside this task.

### Evidence that must not be silently ignored

- `Controller.swift`, `SmartPasteController.smartPaste()`, currently passes `store.candidates()` to `DecisionEngine.decide`. The runtime does consider stored clips. The user explicitly wants the onboarding to represent a single copied block. Keep the welcome simulation isolated from user history. A one-message practice session may explicitly supply only the sample candidate, but must be labeled a guided test. Do not silently change general candidate selection to match the illustration.
- `Decide.swift`, `PasteTransform.apply`, extracts the FIRST detected email/phone/URL. The earlier concept with two email addresses and semantic selection of the billing address is not supported by this transform. Use one of each supported detail in the sample. Do not promise arbitrary phrase, date, name or multi-email selection.
- `SelfCheck.run` checks that field text equals pasteboard text, not that the correct substring was extracted. It cannot substantiate practice success alone; compare the actual field against the explicit expected substring.
- `AppModel.testProvider()` returns a human-readable string. Do not gate progression by checking whether a string starts with “Connected”. Add a small typed result at that boundary if a gate needs it; preserve the Settings caller's formatted status.
- `ModelManager.install` installs the environment; `start` can download weights. A single “Download model” label in the image compresses multiple phases. Show actual phase text, indeterminate progress where no byte fraction exists, and do not mark ready until the selected model is running.
- `AppModel.init` may already warm redaction and start the selected local model before onboarding. Display the actual current status on entry. Do not reset readiness to reproduce a screenshot.
- `PIIRedactor` documents numbered placeholders such as `[EMAIL_1]`. The image's `[EMAIL]` and `[NAME]` are illustrative. Live previews must show actual redactor output; static examples must be labeled “Example”.
- `ModelCatalog` ranks Von first, Kev second and Laya third at inspection. The approved model image omits Von and invents descriptions/logos. Preserve the layout, populate the list from the catalog. Do not change model metadata to fit an image.

## Reference map

| Screen | Reference | Authority / corrections |
| --- | --- | --- |
| Welcome | [01-welcome.png](references/01-welcome.png) | Selected by user. Use fold-out composition and one-message demonstration. |
| Accessibility | [02-accessibility.png](references/02-accessibility.png) | Latest approved revision. OS settings guide, no focused-field illustration. |
| Trigger | [03-trigger.png](references/03-trigger.png) | Earlier concept in same family. Correct shortcut glyphs using runtime display string. |
| Models | [04-models.png](references/04-models.png) | Latest approved dedicated screen. Replace generated claims, icons and ordering. |
| Privacy | [05-privacy.png](references/05-privacy.png) | Latest approved separate screen. Distinguish example from actual redaction status. |
| Practice success | [06-practice-success.png](references/06-practice-success.png) | Shows success only; implement all preceding and failure states below. |

The rejected combined processing/privacy screen is deliberately excluded. The six reference PNGs are the asset package. Their SHA-256 checksums and provenance filenames are in `references/manifest.json`.

## Window and layout contract

Use a standard titled, closable NSWindow with full-size content and a transparent titlebar, hidden title text, and native traffic lights. Keep the existing manual AppModel window ownership so the LSUIElement app can activate and take focus. Window title for accessibility remains “Welcome to Cue”. Do not draw traffic lights in SwiftUI. Disallow fullscreen; resizing may be disabled at canonical size if content remains accessible at larger system text sizes via internal scrolling.

Canonical SwiftUI content bounds: 760 × 580 points. Native outer frame/titlebar may add OS-dependent pixels. Set the content size, not a guessed total frame size. Remove the current 14-point shadow padding and black material overlays. AppKit owns the window shadow. Use a solid theme-aware canvas, avoiding double shadows around the entire window.

Coordinates below are relative to the top-left of content, y increasing downward. They are implementation targets, not literal pixel measurements from generated images. Top titlebar/control safe area: 28 points. Do not let dragged text or input clicks move the window; restrict dragging to titlebar/background regions.

| Region | Bounds / spacing |
| --- | --- |
| Cue wordmark | centered, top y=26, 25-point line box |
| Title | centered, y=72, width 680, target 34-point line box |
| Support | centered, y=116, width 680, 22-point line box; allow wrapping to 44 |
| Content column | x=80, width=600, top y=166, normal bottom ≤500 |
| Upper sheet | width 600, horizontal content inset 24 |
| Lower sheet | x=96, width=568, top overlaps upper bottom by 12 |
| Footer primary | centered x=380, top y=524, height 38; max width 240 |
| Back | x=24, top y=524, height 38 |
| Bottom margin | 18 |

Do not mechanically force every screen into identical heights. Target panel heights: welcome upper 158/lower 132; Accessibility upper 154/lower 170; trigger upper 174/lower 126; models upper 254/lower 98; privacy upper 98/lower 84 plus controls; practice upper 134/lower 146. Model upper+lower total is 340 after overlap; start it at y=158 so it ends at 498. Keep footer out of the panels, correcting the model image where it drifted inside.

At text enlargement, let the title/support wrap and center content scroll in a bounded region ending 16 points above footer. Minimum horizontal window width 680 if resizing is enabled. At 680, panel width becomes available width minus 64. Do not scale the entire interface to fit. At 200% text size, use a single-column model-detail layout and scrolling; all controls remain reachable. Vertical overflow is preferable to unreadable type.

## Flow and persistence

Route sequence: Welcome → Accessibility → Trigger → Models → Privacy → Practice. Privacy is a separate route. Local/loopback providers show the local variant below; hosted/remote providers show the redaction variant. Keep stable route names, not index-dependent business logic.

Persist trigger/provider/key/redaction changes through existing AppSettings bindings as the user confirms or edits them. Preserve existing values when re-running onboarding. Route and example animation state are session-local. Set `onboardingDone` only when the user explicitly finishes or chooses “Finish setup later”. Closing the window before completion leaves it false. Reopening within the same app session should preserve progress if feasible through the existing window instance; after relaunch start Welcome with persisted settings intact.

One primary action per state. Return invokes it only when the user is not recording a shortcut or editing a multi-line control. Escape cancels hotkey recording first. Otherwise Escape may close onboarding without marking complete. Back never clears credentials or uninstalls models. Revoked Accessibility sends the next attempted practice back to the permission route with an explanation.

Provide a quiet “Finish setup later” action on Models when setup is unavailable or the user chooses Off, and on Practice when they cannot complete the test. It must state that smart paste needs a working model when applicable. Do not add a second brightly filled button. Off remains an advanced choice and routes to a truthful finish state, not simulated success.

## Screen 1: Welcome

Copy:

- Title: “Copy it all. Paste just what fits.”
- Support: “Cue finds the right detail in your copied text.”
- Source caption: “Example copied message”
- Source paragraph: “Hey, here are the details for the launch. Reach Mira at mira@example.com or +44 7700 900123. The brief is at https://example.com/launch. Let’s review everything on Friday.”
- Lower title: current target, “Email” or “Website”.
- Control label: “Try a different field:”
- Segments: “Email”, “Website”.
- Primary: “Continue”.

Use a full https URL to eliminate detector ambiguity. Expected Email: `mira@example.com`; expected Website: `https://example.com/launch`. Confirm both against the existing SpanExtractor before implementation. The URL's trailing sentence punctuation is not part of the expected value.

Upper paragraph inset 24, target line box 25. Preserve natural wrapping. Coral highlight hugs ONLY the selected substring with 3 horizontal and 2 vertical points of expansion. Source text remains present during transfer. Lower panel has label/segmented control row, 12-point gap, native-looking field with 36-point height. This field is a read-only illustrative preview exposed as such to accessibility, not an editable field that triggers real system pastes.

Initial Email state is immediately legible. On pointer selection of Website, retarget a duplicate highlight through the short fold and update the preview. Keyboard selection updates immediately. Do not continuously loop while the user reads. This screen never reads the real clipboard, requests Accessibility, changes history or calls a model. The sample is fixed and explicitly labeled.

Use existing extract transforms for deterministic sample output if practical. Measure the selected substring's layout bounds with native text layout rather than estimating character widths. Start with a static coral highlight and fold; add a transfer overlay only after wrapping remains correct. See rendering recipe below.

## Screen 2: Accessibility

Copy:

- Title: “Allow Accessibility access”.
- Support: “Cue needs permission to read field labels and paste into your apps.”
- Preview caption: “In System Settings”.
- Preview heading: “Privacy & Security › Accessibility”.
- App row: actual Cue app icon or neutral paperclip tile; label “Cue”; noninteractive switch illustration.
- Instructions: “Open System Settings below.” / “Turn on Cue under Accessibility.”
- Helper: “Return here after enabling access.”
- Waiting status: “Access not yet granted”.
- Primary: “Open System Settings”.

Upper panel: caption at 24 inset, heading 12 below, app row 16 below; row height 54. Preview switch at far right, 20-point coral halo around it as the guide target. Lower panel: instructions left aligned to a shared 64-point inset, 30-point row spacing. Keep instructions in real text outside the screenshot-like preview. Hide the redundant preview from VoiceOver; announce status changes politely.

Button calls `ContextCaptor.requestTrust()` and opens the existing `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` URL. A click is not proof of grant. Poll `ContextCaptor.isTrusted` while this screen is visible and recheck on app activation. Use one owned cancellable task/timer; stop on exit. Show “Access granted” and a checkmark when true; primary becomes Continue. Prefer explicit Continue over auto-advancing 400 ms after grant so the user can see confirmation. If already trusted on entry, show granted immediately. If opening Settings fails, show “Open System Settings, then Privacy & Security → Accessibility.” with Retry. Do not reset TCC automatically.

## Screen 3: Trigger

Copy:

- Title: “Make it your shortcut.”
- Support: “Choose when Cue steps in.”
- Option A: “Dedicated shortcut”. Detail: “Use Cue when you choose. ⌘V stays unchanged.”
- Recorder hint: “Click to record”; recording label “Press a shortcut”; Escape cancels.
- Option B: “Use ⌘V”. Detail: “Let Cue choose the relevant text when you paste.”
- Lower preview caption: “Your shortcut pastes the part that fits the focused field.”
- Primary: “Continue”.

Two radio rows, each at least 72 points. Option A includes a 116 × 34 recorder to the right. Whole label area selects the option; recorder is a sibling interactive control, not nested in a Button. When intercept is selected, recorder is disabled/dimmed but stored shortcut retained. Record actual value via existing HotkeyRecorder and AppSettings; use runtime displayString. Do not hardcode glyphs rendered in the reference.

After a valid change: persist trigger, update `hotkeys.interceptCmdV`, and re-register using established Settings behavior. Preserve permission gating in HotkeyManager. A new shortcut must include a modifier, reject conflicts with other Cue bindings with a clear inline message, and retain prior valid value after cancellation. Do not promise detection of all other apps' reserved shortcuts. Surface registration failure if existing API exposes it.

Improve recorder keyboard entry: focus with Tab, Enter/Space starts recording, Escape restores prior value and focus. Expose its label, value and recording state to VoiceOver. Lower preview is a small version of ONE paragraph → one Email preview. It is optional at enlarged text sizes only if the explanatory sentence remains; the choice and recorder always take priority.

## Screen 4: Model picker

Copy:

- Title: “Choose your model”.
- Support: “Run a model on your Mac or connect a hosted service.”
- Tabs: “On this Mac”, “Hosted”.
- Disclosure: “More models”.
- Advanced disclosure: “Custom endpoint or no model”.

Initial tab follows saved provider. A fresh Off configuration may show On this Mac visually, but do not silently persist a selected model or begin installation. Offer a supported catalog model as an initial highlighted proposal; the user initiates setup. If a saved model is not visible, expand the list to include it.

### Local layout

Upper panel: segmented picker centered with 24 top inset; 16 gap to list. Show the top three catalog-ranked models, preferably filtering unsupported models to More models while keeping them discoverable. At inspection these are Von, Kev, Laya, not the mockup's Laya/Kev/Jevons. Sort using catalog rank; do not duplicate entries through `ModelCatalog.others`, whose current definition can include Von. Entire list uses unique model IDs.

Rows: 60 points minimum, 16 inset, 20 radio, 12 gap, 32 neutral monogram tile, 16 gap, title and one-line catalog-backed reason. Selected background blue tint, subtle stroke, radio filled. Other rows use only a separator between them. No accuracy/speed bars. Keep real disk/RAM and variant choice in the lower selected detail panel; these are meaningful setup constraints, not decoration. Do not invent benchmarks or simplify support tiers away.

Lower panel: selected model title, supported/experimental/unsupported note, variant menu when >1, real disk and RAM labels from WeightSpec, setup phase/status. Long operational detail expands central scrolling; footer stays fixed. More models expands inline or in the central scroll area, not a new application window. Preserve unsupported explanation and disable setup only for that option.

| Model status | Primary label | Behavior |
| --- | --- | --- |
| Not installed | Set up model | Resolve selected model+variant, install environment, then start |
| Installing | Setting up… | Disabled duplicate action; show actual phase; indeterminate progress |
| Installed selected variant | Start model | Start existing installation |
| Installed different variant | Set up selected variant | Show mismatch before initiating replacement through existing manager |
| Starting | Starting model… | Wait for actual running state; weights may download |
| Running selected configuration | Continue | Proceed; optionally keep a quiet Test connection action |
| Failed | Retry setup / Retry start | Retry the failed phase, not indiscriminately reinstall |
| Unsupported | Choose another model | Informational state; no installation call |

No fabricated percentage if ModelManager only supplies a phase string. Selecting another model during installation must not implicitly run a second install; disable conflicting selection or wait for existing operation, with visible explanation. Back may leave app-owned work running; re-entering observes it. Do not promise Cancel until process cancellation is actually implemented. Uninstall is not an onboarding action.

### Hosted layout

Same panel dimensions, two provider choices: TypeSafe direct and AI Gateway. Selecting either reveals a labeled SecureField for the corresponding key. Reuse settings' `apiKey`/`gatewayKey` bindings and Keychain. Do not print keys to logs, errors or screenshots. A quiet link can open provider documentation only after its URL is verified by the implementing agent; do not invent a signup URL.

Primary “Test connection”; pending “Testing…”, disabled repeated submit. Success “Connected” and primary Continue. Failure is inline with Retry, preserving input. A changed key/provider invalidates prior test status. Testing uses the existing benign test payload, never the real clipboard. Model names/endpoints come from settings. Connect success does not mean redaction setup completed; Privacy follows.

Advanced: custom endpoint, model identifier and optional Bearer key retain current behavior and normalization. Off explains “Smart paste will use ordinary paste until you choose a model.” Primary becomes “Finish setup later”; never shows successful practice.

## Screen 5: Privacy

Keep this separate from Models. Resolve provider locality through the configured endpoint's actual `isRemote` behavior. `Provider.mayBeRemote` is conservative for custom endpoints; a loopback custom endpoint must not be described as sending text to a remote model. Preserve the existing `piiRedaction` tri-state; do not write an explicit override merely by opening this screen.

### Remote branch

- Title: “Choose what leaves your Mac”.
- Support: “Mask personal details before Cue sends text to a hosted model.”
- Upper caption: “Example copied text”.
- Example: “Send the launch brief to Mira at mira@example.com.”
- Lower caption: “Example sent to the model”.
- Scrubbed illustration: “Send the launch brief to [NAME] at [EMAIL].”
- Toggle: “Redact personal details”.
- Helper: “The detail you paste keeps its original text.”
- Setup note: “Redaction uses a small model on your Mac.”

Upper/lower heights 98/84 with 12 overlap. Name and email highlights are coral. Examples are static illustrative data until the redactor is ready. Never present those exact placeholder strings as guaranteed SDK output. Once ready, optional live preview uses only this sample and the real redactor result. The demonstration may omit name masking if the real model fails to detect the sample name; do not fabricate the result.

Below pair: toggle row 24 points down, helper 8 below, status 16 below. Initial toggle uses effective setting. A user action writes an explicit override. Include quiet “Use automatic setting” action when an override exists; reset to nil. Off preview shows the unmasked example with caption “Example sent without redaction”, so the consequence is apparent.

| Redaction state | Primary | Status / recovery |
| --- | --- | --- |
| Effective on, idle | Set up redaction | Starts prepare once |
| Downloading | Downloading… | Real fraction from status, accessible percentage |
| Ready | Continue | “Redaction ready” |
| Failed | Retry download | Inline error, keep redaction on; choosing off is separate explicit action |
| Effective off | Continue | Explain sample is sent without redaction |

Do not automatically disable redaction after download failure. Keep the fail-closed engine behavior. Progression with enabled but unavailable redaction should offer Retry or explicit Finish setup later, not silently enter a “ready” practice.

### Local or loopback branch

Title “Your model runs on this Mac”. Support “This connection keeps model requests on your Mac.” Show a compact source/processing relationship inside the same fold-out surfaces, with plain text “Local model” and configured model name. No cloud-redaction before/after image. Preserve any existing explicit redaction override and expose it under “Redaction settings” if needed; explain Auto is off for this local connection. Primary Continue. Do not imply clipboard history encryption or universal privacy of the computer. Off skips practice to finish-later state.

## Screen 6: Practice and completion

This is a real test after setup, not the Welcome simulation. It must never assign the expected result directly and call that success. Build a local, nonsecure NSTextField/SwiftUI field with verified AX label “Email” or “Website”. Use one fixed sample paragraph, not user's clipboard history.

### States

1. Intro: title “Try your first smart paste.” Support “Copy this message, then paste into Email.” Upper sample panel includes a small neutral “Copy sample” action. Lower Email field is empty. Instruction shows the ACTUAL configured shortcut from settings or ⌘V in intercept mode. Primary may be “Copy sample” if the copy action is moved to footer; use only one copy action, not both.
2. Armed: after explicit Copy sample, focus destination field; show “Now press {shortcut}”. Do not synthesize the user's trigger without them. The sample copy affects the system pasteboard, so label it as a real copy and avoid silently restoring over later user copies.
3. Pending: actual provider/paste operation is in flight. Show modest status, keep typed input intact, do not replay a timed fake success.
4. Success: actual field value equals exact expected extracted substring, and the operation used the intended extraction rather than plain fallback. Title becomes “That’s your first smart paste.” Lower field displays the observed text; checkmark and “Email pasted”. Primary “Start using Cue”. Secondary “Try Website” resets field, copies the SAME full sample explicitly as part of the labeled trial and focuses Website. It must not rely on the prior extraction left on the pasteboard.
5. Fallback/wrong result: actual paste may contain the whole sample; show “Cue used ordinary paste this time.” with “Check model” and Retry. Never mistake a nonempty field for extraction success.
6. Lost permission: “Accessibility access is needed to try this.” Route back to permission on action.
7. Finish later: user can exit with “Finish setup later”. Completion says model setup/practice is unfinished, not “Email pasted”. Preserve configured settings.

### Practice boundary

Choose a narrow practice path that calls the existing DecisionEngine with ONE sample Clip, the actual captured context, configured provider and real redaction, then uses PasteExecutor to synthesize the paste into the focused practice field. It must listen to the configured trigger only while the practice field is focused. Keep this scoped in the existing app hotkey dispatch with a practice handler that returns whether it consumed the action; otherwise dispatch normal behavior. Clear that handler on leaving/closing the screen. Do not register competing global hotkeys or temporarily replace application history with samples.

This practice path proves extraction, model connection, AX capture and paste delivery for the sample. It does not prove general multi-candidate runtime behavior. Record that distinction in final verification. If implementing agent instead reuses SmartPasteController unchanged, explicitly account for its store candidates and ensure no real user history is sent during the guided test. Never clear the user's store to get a deterministic screenshot.

A native field bridge may expose observed string changes and explicit focus; keep its API small. Completion requires observed text plus the typed decision outcome, not a fixed delay. If the provider asks for confirmation, support that outcome or report a non-success with Retry; do not silently coerce confidence to force the expected result. Preserve never-no-op failure behavior.

## Fold and highlight rendering recipe

The references do not require a raster paper texture. Render panels with continuous RoundedRectangle shapes. Draw lower first, then upper with 12-point overlap. A small neutral wedge at the seam and coral 1-point lip are sufficient. Static fold must read at 1× without looking like a divider or arrow. Avoid applying perspective to interactive controls.

For paragraph highlight bounds, use TextKit layout in a narrow AppKit text view/renderer or SwiftUI TextRenderer if the executor verifies it works across wrapped runs on macOS 15. Match the native paragraph's exact font and width. Derive source rect from the substring range and destination rect via layout anchors. Never hardcode substring x positions or break the sentence into independent HStacks; both fail when text wraps or scales.

For the optional transfer: render duplicate selected text over a 4-radius coral backing, lift y=-3, move to destination anchor and fade. A shallow curved coral strip can briefly connect under it, with maximum 16-point bow and no broad 3D ribbon. Clip all decorative animation to the central scene. Keep source paragraph unchanged and reveal native destination value at completion. Fast retargeting cancels previous transfer. Reduce Motion bypasses the movement.

A static highlight plus fold is the first fidelity milestone. Custom shaders, SceneKit, Metal, external fonts, raster textures and generated alpha images are not required. Add none merely to chase photographic curl. If the movement is not convincing after a bounded visual pass, keep the clean static treatment and document the missing animation rather than replacing it with a long arrow.

## Accessibility and native behavior

All actions are keyboard reachable with logical order: Back when present, route content controls, primary. Group instructions semantically; expose row selection and switch states. Add a focus ring to the recorder. VoiceOver can identify Email/Website as fields in Practice; Welcome describes them as previews. Decorative folds and duplicated animation text are accessibility-hidden. Dynamic status changes are announced once, without repeatedly reading the whole screen.

Native hit targets are at least 36 points high, 40 where space permits. Enlarge label hit regions without overlap. Return submits only the visible enabled primary action. File/secure-field pass-through behavior remains unchanged outside practice. All required content remains reachable at increased text size. Fullscreen is not necessary for onboarding.

## Verification and delivery acceptance

Capture the real app, not SwiftUI preview alone, at canonical content size in light and dark. Before screenshot capture, replace any real key or personal data with isolated test state. Do not store sensitive data in fixtures or docs. Use an isolated defaults suite for previews; avoid constructing AppModel.shared just to render images, as it starts monitors and may download models.

Required screenshots: Welcome Email and Website; permission waiting/granted; trigger dedicated/recording/intercept; models local uninstalled/installing/running/failed/unsupported and hosted empty/testing/error/connected; privacy remote auto-on/downloading/ready/off/error and local; practice empty/pending/success/fallback. Capture representative large-text and Reduced Motion states. Each screenshot filename identifies route, state and theme.

First visual pass compares all six canonical screens against their reference at matched content size. Fix every actionable layout/contrast issue found, then do one confirmation pass. Accept differences in OS chrome, actual catalog content and native controls; reject missing fold relationship, tiny body copy, oversized spacing, fake logos, arrow substitutes, clipped footer or flattened text.

Functional checks: Back preserves inputs; closing never marks success; duplicate clicks do not launch duplicate operations; provider changes invalidate test status; grant detection uses actual trust; intercept registration respects permission; local state reflects manager readiness; loopback is treated as local; failed redaction stays on; sample practice never reads user history; success requires exact output; hotkey dispatch returns to normal on exit.

Run `swift build` and `swift test`, then `Scripts/bundle.sh` and `open build/Cue.app` for real native verification. Run the existing menu self-check but do not count it as extraction correctness evidence. Do not reset Accessibility unless the current signature requires it or the user explicitly wants to test denied state. Record any manual grant/signing dependency without claiming the inaccessible branch passed.

Done means: all routes/states implemented, approved visual hierarchy retained, tests pass, relevant real-app screenshots inspected, reference assets packaged only in docs, and remaining limitations recorded. No source changes outside this scope without a documented need.
