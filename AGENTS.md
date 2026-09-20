# SmartCopyPaste

Smart clipboard for macOS. Watches the pasteboard (text + URLs), and on a
hotkey — or every ⌘V if intercept mode is on — asks TypeSafe AI's **Jev**
model which clip fits the focused field, then pastes it. Falls back to local
heuristics when no API key is configured or the call fails.

## Commands

- `swift build` / `swift test` — compile and run the test suite (all logic tests live in `Tests/SCPKitTests`)
- `Scripts/bundle.sh` — builds `build/SmartCopyPaste.app` (ad-hoc signed, LSUIElement background app)
- `open build/SmartCopyPaste.app` — run it
- `tccutil reset Accessibility com.local.smartcopypaste` — required after rebuilds that invalidate the TCC grant

## Layout

`Sources/SmartCopyPaste/main.swift` is a one-line trampoline; everything lives
in `Sources/SCPKit`:

- `Clip.swift`, `ClipStore.swift` — model + JSON history at `~/Library/Application Support/SmartCopyPaste/history.json` (cap from settings, pins exempt)
- `ClipboardMonitor.swift` — polls `NSPasteboard.changeCount`
- `Context.swift` — `ContextCaptor`: frontmost app + focused AX element (role/label/placeholder/value/rect). Secure fields are flagged, never read.
- `Hotkeys.swift` — Carbon `RegisterEventHotKey`; `isSynthesizing` guards our own ⌘V. All bindings rebindable in Settings.
- `Jev.swift` — `JSONValue`, `Question`/`Answer` contract, `JevClient` (one POST `{base}/v1/systemone`). Direct and AI Gateway are the same client with different `(url, model, key)`.
- `Decide.swift` — `DecisionEngine.decide(context:candidates:mode:feedback:) -> PasteOutcome`. The only thing the controller branches on. `HeuristicRanker` is the offline path behind the same outcome type.
- `Paste.swift` — `PasteExecutor` (pasteboard write + synthesized ⌘V/Tab) and `FormFiller` (paste→Tab→decide loop, max 20 steps, Esc aborts).
- `Controller.swift` — `SmartPasteController` orchestrates; `FeedbackTracker` learns from ⌘Z-within-2.5s.
- `HUD.swift` — non-activating panels near the caret: top-3, full picker, status toast.
- `Views/` — menu bar, history, settings (+hotkey recorder), onboarding.
- `SelfCheck.swift` — real end-to-end check: labeled NSTextField → real capture → real decision → real ⌘V → assert field got the pasteboard's content. Menu bar → "Run self-check".

## Invariants — don't break these

- **Secure fields**: `AXSecureTextField` → plain paste of latest, Jev is never called, value is never read.
- **Never no-op a paste**: every failure path ends in `.pasteLatest`, not silence.
- **Jev chooses, we execute**: transforms are deterministic local functions; the model only picks (it can't generate strings).
- **No new dependencies.** SPM stdlib + AppKit + Carbon + SwiftUI only.
- Keys live in Keychain only; history is plain JSON — never log clip contents.
- One Jev call per decision; all questions batch into it (they run parallel, share state cost).
