# Cue onboarding redesign implementation plan

**Goal:** implement the approved fold-out onboarding faithfully as a native, accessible Mac flow with truthful setup and practice states.

**Architecture:** keep AppModel as the application object graph and window owner. Onboarding owns its route and presentation state; existing settings, model manager, redactor and paste engine own operational state. Introduce only a small visual primitive set and a focused practice boundary where the real engine can receive a single sample.

**Tech stack:** Swift 6, macOS 15+, SwiftUI, AppKit, existing Carbon hotkeys and existing Redact package. No new dependency or raster runtime asset is required.

**Execution:** read the repository AGENTS.md, then load the available `executing-plans` skill to work task by task. Also follow `ponytail`, `architect` for the practice/provider boundaries, `code-deslop`, and the native macOS build/verification skills as applicable. Do not invoke nonexistent `superpowers:*` skills. The user requested a handoff, not implementation in the authoring session.

**Required documents:** [DESIGN.md](../../DESIGN.md), [screen and state spec](../design/onboarding/SPEC.md), [handoff status](../design/onboarding/HANDOFF.md). The spec owns exact copy/behavior; do not duplicate it into new instructions. References are under `docs/design/onboarding/references`.

All existing paths below are repository-relative. Resolve against `/Users/hridyaagrawal/Honey/smartcopypaste`. Proposed paths are marked Create. Line numbers are deliberately omitted because symbols are the stable integration anchors. The code blocks are bounded starting contracts, not an untested replacement for the entire app. Adapt them only to current API evidence and record material deviations.

## Task 1: Baseline and scope checkpoint

**Read:** `Sources/CueKit/CueApp.swift`, `Sources/CueKit/Views/Onboarding.swift`, `Sources/CueKit/Views/ProviderPicker.swift`, `Sources/CueKit/Views/SettingsView.swift`, `Sources/CueKit/Settings.swift`, `Sources/CueKit/Models.swift`, `Sources/CueKit/Redaction.swift`, `Sources/CueKit/Decide.swift`, `Sources/CueKit/Controller.swift`, `Sources/CueKit/SelfCheck.swift`, `Package.swift`, `Scripts/bundle.sh`.

1. Run `git status --short`; record pre-existing changes in HANDOFF. Preserve the existing untracked `output/` directory.
2. Run `swift build`. Expected: exit 0 and build completion. Record failures without silently updating dependencies.
3. Run `swift test`. Expected: exit 0; record actual test count, not a guessed count.
4. Open every packaged reference and the live onboarding. Capture the existing app before editing. Note current 588×648 borderless dark window versus proposed 760×580 native light/dark content.
5. Record the known first-span extraction and stored-candidate behavior in the implementation checkpoint. This plan does not authorize rewriting the engine.

**Done:** baseline evidence recorded, references accessible, uncommitted user work identified.

## Task 2: Native shell and shared styling

**Modify:** `Sources/CueKit/CueApp.swift` (`makeWindow(id:)`, onboarding branch only), `Sources/CueKit/Views/Onboarding.swift`.
**Create:** `Sources/CueKit/Views/OnboardingStyle.swift`.

1. Replace onboarding's borderless window construction with native titled/closable full-size-content behavior; preserve key-window support and manual window ownership. Keep other windows unchanged.
2. Set content size to 760×580. Hide title text, keep native controls, disable fullscreen. Remove SwiftUI shadow-room padding and the forced dark color scheme.
3. Add the token values from DESIGN.md in one namespace. No custom token framework or JSON importer.
4. Implement a fold-out pair with two view-builder slots. Render lower first and upper second; 12-point overlap, 16-point lower horizontal inset, shared 16-point corners and layered shadow. Verify no clipping at the seam.
5. Implement shared header/footer spacing. Use the same primary/Back positions on every route. Handle central overflow with ScrollView rather than shrinking text.
6. Add isolated previews with inert sample values; do not initialize the production AppModel for screenshot fixtures.
7. Run `swift build`, then render one static welcome in both themes. Check native titlebar and keyboard focus in the actual window.

Suggested route contract, kept private to onboarding until a second consumer exists:

```swift
enum OnboardingStep: CaseIterable {
    case welcome
    case accessibility
    case trigger
    case models
    case privacy
    case practice
}
```

Use direct route transitions. Do not add a navigation coordinator package or generic workflow engine. Extract a session state type only if asynchronous UI ownership becomes unclear or the behavior tests need that stable boundary.

**Done:** shell renders at target size, fields focus, Return works, both themes readable, no source changes to history/settings styling.

## Task 3: Welcome's single-message demonstration

**Modify:** `Sources/CueKit/Views/Onboarding.swift` (replace `welcomeStep` and `WelcomeDemo`).
**Create if size warrants:** `Sources/CueKit/Views/OnboardingDemo.swift`.
**Test:** `Tests/CueKitTests/DecideTests.swift`.

1. Inspect the existing test framework and fixture conventions.
2. Add one focused test using the full approved sample, asserting Email and Website extraction through `PasteTransform.apply`. Use the actual enum/method signatures from Decide.swift. If tests already cover the exact boundary, extend their fixture rather than duplicating a suite.
3. Run `swift test --filter DecideTests`. Expected: current extraction can return `mira@example.com` and `https://example.com/launch` from the sample. If URL normalization differs, reconcile the fixture and visible preview before coding an animation.
4. Replace the cycling list with one paragraph, native segmented control and a read-only destination preview. Never call monitor/store/provider from this screen.
5. Add substring highlight via native text layout; confirm long-line wrapping and font-size changes.
6. Add the static fold, then optional bounded transfer. Honor Reduced Motion and hide duplicate animation text from accessibility.
7. Capture Email and Website at canonical size in both themes; compare against reference 01. The real paragraph may wrap differently from the generated image, but the selected span and target must align without clipping.

Sample fixture:

```swift
let onboardingSample = "Hey, here are the details for the launch. Reach Mira at mira@example.com or +44 7700 900123. The brief is at https://example.com/launch. Let’s review everything on Friday."
let expectedEmail = "mira@example.com"
let expectedWebsite = "https://example.com/launch"
```

Keep fixture data at the demo/practice boundary; do not duplicate hardcoded sample paragraphs across unrelated screens.

**Done:** one-source interaction works with pointer and keyboard, no clipboard side effects, screenshot matches visual hierarchy.

## Task 4: Accessibility setup

**Modify:** `Sources/CueKit/Views/Onboarding.swift` (`permissionStep`, poll lifecycle).
**Reuse:** `Sources/CueKit/Context.swift` trust APIs.

1. Replace the focused-field illustration with the noninteractive OS settings guide from reference 02.
2. Read actual trust on entry and app activation. Own one polling task while the route is visible; cancel on exit.
3. Wire Open System Settings to requestTrust and the existing URL. Render waiting/granted/open-failure states from spec.
4. Change granted behavior to explicit Continue instead of delayed automatic advance. Keep the next route gated by actual trust.
5. Keyboard/VoiceOver review: pictured switch is not operable; the real button is named; status changes announced once.
6. Render waiting and granted fixtures. Verify one actual permission round-trip without resetting a working grant solely for convenience.

**Done:** user understands exactly where to enable Cue; button action cannot counterfeit success; no orphaned timer.

## Task 5: Trigger selection and recorder

**Modify:** `Sources/CueKit/Views/Onboarding.swift`, `Sources/CueKit/Views/SettingsView.swift` (`HotkeyRecorder` only if its behavior needs improvement).
**Reuse:** `Sources/CueKit/Hotkeys.swift`, `Sources/CueKit/Settings.swift`.

1. Render two native radio choices from reference 03, using actual configured displayString.
2. Bind selection through AppSettings and existing registration path. Keep recorder and radio as sibling controls.
3. Add keyboard recorder entry, cancel/restore behavior, accessible label/value and focus indicator. Keep Settings use working.
4. Detect conflicts against other Cue bindings; show an inline error without overwriting prior valid shortcut. Verify registration error behavior before claiming a shortcut is usable.
5. Test dedicated mode: normal ⌘V unchanged. Test intercept: only registered with Accessibility, generated paste not recursively intercepted.
6. Render dedicated/recording/intercept. Verify tab order, Return capture and Escape cancellation.

**Done:** selected trigger and recorder persist, ordinary paste contract intact, Settings recorder remains functional.

## Task 6: Dedicated model picker with real metadata

**Modify:** `Sources/CueKit/Views/Onboarding.swift`.
**Create:** `Sources/CueKit/Views/OnboardingModelPicker.swift`.
**Read/reuse:** `Sources/CueKit/Views/ProviderPicker.swift`, `Sources/CueKit/Models.swift`, `Sources/CueKit/Settings.swift`.

1. Implement local/hosted tabs and the selected-detail fold-out panel. Keep presentation separate from the long Settings provider cards.
2. Build the local list from `ModelCatalog.all`, sorting by rank and deduplicating by id. Use title/reason/support from catalog; neutral monogram tiles. More models exposes remaining unique choices.
3. Reuse selection and variant resolution semantics from ProviderPicker. Do not change ModelCatalog defaults to match the image.
4. Wire selected-model status to ModelManager.State. Render notInstalled/installing/installed/starting/running/failed and unsupported. Use actual progress phases.
5. Wire setup to install then start; wire installed to start. Prevent duplicate/conflicting operations. Show variant mismatch rather than silently pretending selected weights are installed.
6. Add variant and disk/RAM detail using actual WeightSpec values. At large text size, scroll the panel.
7. Implement hosted provider selection and SecureField bindings; empty keys remain empty, existing credentials retained.
8. Keep custom/off in an Advanced disclosure; preserve normalized URL and Keychain behavior.
9. Render local states and hosted fixtures without triggering downloads. Run one actual setup/connection using existing configured resources where available; record unavailable branches.

A small presentation mapping from real manager state is sufficient. Do not introduce a second model-installation state machine, duplicate process launcher, downloader or provider factory.

**Done:** layout matches reference 04 while all metadata and readiness come from live code; user can choose every existing provider path.

## Task 7: Typed provider-test result

**Modify:** `Sources/CueKit/CueApp.swift` (`testProvider` boundary), `Sources/CueKit/Views/ProviderPicker.swift` (formatting caller), `Sources/CueKit/Views/OnboardingModelPicker.swift`.
**Test:** `Tests/CueKitTests/JevTests.swift` or one `OnboardingTests.swift` if an existing fixture cannot own the use case.

1. Add a typed success/failure result rather than parsing UI strings. A bounded shape is sufficient:

```swift
enum ProviderConnectionResult {
    case connected(model: String)
    case failed(message: String)
}
```

2. Put request execution in one place. Keep the current benign test payload. Map the typed result into the Settings string and onboarding status; do not execute two requests.
3. Invalidate a previous result when the selected provider, endpoint, model or key changes. Capture the tested configuration at request start and discard a late result if it no longer matches current configuration.
4. Add a behavioral test where a stale success arrives after a provider change; Continue must remain unavailable. Use existing provider test doubles rather than mocking SwiftUI.
5. Run `swift test --filter JevTests` and the relevant new test filter. Expected: failed/missing provider never enables Continue, valid result does.

**Done:** connection gate is typed, stale responses cannot mark a different provider connected, Settings status still works.

## Task 8: Separate privacy route

**Modify:** `Sources/CueKit/Views/Onboarding.swift` (`privacyStep`).
**Reuse:** `Sources/CueKit/Redaction.swift`, `Sources/CueKit/Jev.swift` locality, `Sources/CueKit/Settings.swift` tri-state.
**Test:** existing redaction/endpoint tests in `DecideTests.swift` and `JevTests.swift`.

1. Choose local/remote presentation from actual configured endpoint locality. Preserve Auto unless user changes the control.
2. Build sample before/after fold from reference 05. Label static placeholders Example; live preview only uses real redactor output on the fixed sample.
3. Wire idle/downloading/ready/failed to PIIRedactor.status; prepare only on explicit setup action when needed. Existing background readiness is respected.
4. Add explicit Off and reset-to-Auto behavior. Failure retains effective-on and offers Retry, not automatic disabling.
5. Render local branch without cloud masking imagery; preserve any stored explicit override under disclosure.
6. Run existing fail-closed and loopback tests. Add only missing behavior tests for onboarding state/progression, not duplicate engine tests.
7. Capture remote auto/on/off/download/error and local views; verify actual fraction and no clipping.

**Done:** independent privacy screen, accurate locality, tri-state retained, fail-closed fallback unchanged.

## Task 9: Truthful practice session

**Create:** `Sources/CueKit/OnboardingPractice.swift` and, if needed, `Sources/CueKit/Views/OnboardingPracticeField.swift`.
**Modify:** `Sources/CueKit/Views/Onboarding.swift`, `Sources/CueKit/CueApp.swift` (narrow practice dispatch), possibly `Sources/CueKit/Controller.swift` only if a existing decision/paste seam can be reused cleanly.
**Read:** `Sources/CueKit/Paste.swift`, `Sources/CueKit/SelfCheck.swift`, `Sources/CueKit/Context.swift`, `Sources/CueKit/Decide.swift`.
**Create test:** `Tests/CueKitTests/OnboardingPracticeTests.swift`.

1. Sketch the call flow before editing: Copy sample → focus labeled field → configured trigger → capture context → decide with one sample candidate → execute outcome → observe field → compare expected value. Document which part reuses production code and which is sample-scoped.
2. Add a narrow practice hook to the existing smart-paste dispatch. It consumes actions only for the active practice field; otherwise normal controller dispatch remains unchanged. Remove hook on exit. Do not duplicate Carbon registration.
3. Use an explicit sample-copy action. Avoid writing sample to history yourself; never clear or replace user history. Keep practice candidates sample-only so no personal clips reach a provider during this test.
4. Implement provider/redaction decision with existing engine types and preserve fallback outcomes. Use actual PasteExecutor and actual labeled native field.
5. Observe the field after paste; never directly assign expected text to complete the test. Require expected value and a real extraction outcome. A field containing the whole paragraph is a fallback state.
6. Implement retry, permission loss, model error, Website retry with recopy, Finish setup later, and Start using Cue. Persist completion only on explicit finish.
7. Add tests at the practice boundary: correct extraction succeeds; whole-sample fallback fails; unrelated text fails; no provider call sees real history; leaving practice restores normal dispatch. Build simple existing-style fakes for provider/executor observation only where needed.
8. Run `swift test --filter OnboardingPracticeTests`. Then verify in the real bundled app with the configured trigger.

Suggested mutually exclusive UI states, owned by the practice session rather than parallel booleans:

```swift
enum PracticeState: Equatable {
    case readyToCopy
    case waitingForPaste
    case deciding
    case succeeded
    case failed(String)
}
```

Use engine outcome types to carry decision evidence separately; do not flatten them into success strings. Cancellation and stale-result handling should be bounded to the one active attempt, not a generic task orchestration framework.

**Done:** observed real field proves the expected substring, failure cannot produce success UI, external hotkeys work normally after exit.

## Task 10: Complete state coverage and motion

**Modify:** onboarding view files only where needed.

1. Exercise each branch in SPEC's state tables. Check Back, reopen, changed provider, changed variant and revoked permission.
2. Add fold/highlight motion only after static geometry passes. Do not animate real paste delivery or delay the button for an entrance animation.
3. Verify Reduce Motion, Increase Contrast, Reduce Transparency and large text. Record native focus/VoiceOver behavior.
4. Remove visual leftovers from the old dark onboarding: dots, black overlays, giant step icons and the cycling clip list.
5. Re-read all visible text; remove generated model claims/icons and ensure error strings do not expose credentials or clipboard text.

**Done:** every state has readable content and recovery, accessibility alternatives are present, consistent shell remains stable.

## Task 11: Build, native visual review and handoff

1. Run `swift build` and `swift test`; record actual outcomes.
2. Run `Scripts/bundle.sh`, then `open build/Cue.app`. Use certificate-aware signing behavior from current script. Do not reset TCC as a routine command.
3. Capture all required states in SPEC to `docs/design/onboarding/verification/` or a clearly linked artifact directory. Never include real credentials or personal clipboard data.
4. Compare canonical screens to references at matched content bounds. Inspect the images yourself. Record actionable defects, fix them in one pass, then confirm once more.
5. Run real sample practice and existing menu self-check. Record exactly what each proves; do not substitute one for the other.
6. Review diff with code-deslop and prose gates. Run structural review only if changes expanded into substantial orchestration. Preserve existing unrelated changes.
7. Update HANDOFF with changed files, commands, screenshot links, verified/unverified states and any scope deviations. Provide the next user a concise completion report.
8. Create scoped commits only if repository/session instructions authorize them; suggested boundaries are shell/demo, setup, practice and verification. Never stage unrelated `output/` files.

**Done:** acceptance matrix has evidence for each required behavior and screenshot, no hidden placeholder assets, tests pass or a specific external blocker is documented. An unfinished runtime/product mismatch is reported rather than disguised by a successful demo.
