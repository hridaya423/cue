# Cue

Smart clipboard for macOS. Watches the pasteboard (text + URLs), and on a
hotkey — or every ⌘V if intercept mode is on — asks a System One decision
model which clip fits the focused field, then pastes it. No model, no answer,
unreachable endpoint: the paste degrades to a plain ⌘V, silently.

Providers all speak the same `POST {base}/v1/systemone` contract — the
difference is only `(url, model, key)`:

- `jevDirect` — TypeSafe hosted Jev (`api.typesafe.ai`, `jev-latest`)
- `jevGateway` — Jev via Vercel AI Gateway (`ai-gateway.vercel.sh/typesafe`, `typesafe-ai/jev`)
- `local` — a managed on-device model server; `localModelID`/`localVariantID`
  resolve through `ModelCatalog` (kev, laya, von, jevons, jevlite, decider)
- `custom` — any System One endpoint; bare host, `host:port`, or full URL
- `off` — no model; every smart-paste is a plain paste

## Commands

- `swift build` / `swift test` — compile and run the test suite (all logic tests live in `Tests/CueKitTests`)
- `Scripts/bundle.sh` — builds `build/Cue.app` (ad-hoc signed, LSUIElement background app, ships `laya_server.py` in Resources)
- `Scripts/eval_systemone.py <base>...` — accuracy/latency table for one or more endpoints
- `open build/Cue.app` — run it
- `tccutil reset Accessibility com.local.cue` — required after rebuilds that invalidate the TCC grant

## Layout

`Sources/Cue/main.swift` is a one-line trampoline; everything lives
in `Sources/CueKit`:

- `Clip.swift`, `ClipStore.swift` — model + JSON history at `~/Library/Application Support/Cue/history.json` (cap from settings, pins exempt)
- `ClipboardMonitor.swift` — polls `NSPasteboard.changeCount`; `PasteboardGate` — image/file pasteboards pass through before any model call
- `Context.swift` — `ContextCaptor`: frontmost app + focused AX element (role/label/placeholder/value/rect). Secure fields are flagged, never read.
- `Hotkeys.swift` — Carbon `RegisterEventHotKey`; `isSynthesizing` guards our own ⌘V. All bindings rebindable in Settings.
- `Jev.swift` — `JSONValue`, `Question`/`Answer` contract, `JevClient` (one POST `{base}/v1/systemone`), `JevEndpoint.custom` URL normalization + `isRemote` loopback check, `StatusTrackingProvider`/`ProviderStatus` for reachability UI.
- `Models.swift` — `ModelCatalog` (benchmark-ranked local model specs: variants, disk/RAM, support tier) + `ModelManager` (uv bootstrap, install via venv/repo/shim, start/stop, health). Absolute tool paths; pipes drained.
- `Redaction.swift` — `Redacting` protocol + `PIIRedactor` wrapping the desert-ant `redact` CoreML model (downloads on demand, ~12 MB).
- `Decide.swift` — `DecisionEngine.decide(context:candidates:mode:feedback:) -> PasteOutcome`. The only thing the controller branches on.
- `Scripts/laya_server.py` — stdlib-only local server that adapts laya's Python API to `/v1/systemone`.
- `Paste.swift` — `PasteExecutor` (pasteboard write + synthesized ⌘V/Tab) and `FormFiller` (paste→Tab→decide loop, max 20 steps, Esc aborts).
- `Controller.swift` — `SmartPasteController` orchestrates; `FeedbackTracker` learns from ⌘Z-within-2.5s.
- `HUD.swift` — non-activating panels near the caret: top-3, full picker, status toast.
- `Views/` — menu bar, history, settings (+hotkey recorder), onboarding; `ProviderPicker.swift` is the shared provider/model UI.
- `SelfCheck.swift` — real end-to-end check: labeled NSTextField → real capture → real decision → real ⌘V → assert field got the pasteboard's content. Menu bar → "Run self-check".

## Invariants — don't break these

- **Secure fields**: `AXSecureTextField` → plain paste of latest, no provider call, value is never read.
- **Never no-op a paste**: every failure path ends in `.pasteLatest`, not silence. Cold-starting local models included — a paste never waits on a server.
- **Non-text passthrough**: image/file pasteboards skip the decision entirely — a model pick would overwrite a copied image with stale text.
- **Model chooses, we execute**: transforms are deterministic local functions; the model only picks (it can't generate strings).
- **Fail-closed redaction**: `piiRedaction` is tri-state (auto = remote on, local off). When effective-on and the provider `isRemote`, clip text is scrubbed first — if scrubbing throws, the paste degrades to `.pasteLatest` rather than send raw text. Loopback endpoints skip redaction by definition. Redaction only affects what the model sees; the paste executes on the raw clip.
- **One dependency**: `desert-ant-core` (the Redact PII model). Otherwise SPM stdlib + AppKit + Carbon + SwiftUI only — add nothing else without need.
- Keys live in Keychain only; history is plain JSON — never log clip contents.
- One provider call per decision; all questions batch into it (they run parallel, share state cost).
