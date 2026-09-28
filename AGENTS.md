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
- `Scripts/eval_servers.sh` — (re)starts installed model servers detached under launchd (labels `cue.eval.*`; `JEVLITE=1` to include jevlite, which starves the GPU while loading). `Scripts/eval_run.sh <tag> --endpoint ...` — one-shot detached CueEval run (a bare `launchctl submit` job is KeepAlive and re-runs forever). Results + roles rationale: `Evals/results/summary.md`
- `swift build -c release --product CueEval` then `CueEval --cases Evals/cases.jsonl --endpoint name=base,model --repeats 3 --json <out>` — the smart-paste benchmark (110 synthetic cases: extraction, ambiguity→chooser, no-fit→plain). Offline: `--replay <raw.jsonl>` re-scores recorded answers through the current engine for instant threshold/policy sweeps; `--diag` adds a per-case model-leader vs ContextSignal line. Run live sweeps under `launchctl submit` if the invoking shell might go away.
- `Scripts/ob_compare.py <0-5|all> --appearance light|dark --launch` — captures native onboarding windows and builds reference/app/blend comparisons into `output/onboarding/compare/`
- `open build/Cue.app` — run it
- `tccutil reset Accessibility com.local.cue` — clears the grant (cert-signed builds keep it across rebuilds; only needed after ad-hoc rebuilds or to re-test onboarding)

## Layout

`Sources/Cue/main.swift` is a one-line trampoline; everything lives
in `Sources/CueKit`:

- `Clip.swift`, `ClipStore.swift` — model + JSON history at `~/Library/Application Support/Cue/history.json` (cap from settings, pins exempt)
- `ClipboardMonitor.swift` — polls `NSPasteboard.changeCount`; `PasteboardGate` — image/file pasteboards pass through before any model call
- `Context.swift` — `ContextCaptor`: frontmost app + focused AX element (role/label/placeholder/value/rect/caret rect/nearby text/web host), 50 ms AX messaging cap. Secure fields are flagged, never read.
- `Hotkeys.swift` — Carbon `RegisterEventHotKey`; `isSynthesizing` guards our own ⌘V. ⌘V interception only registers while Accessibility-trusted (a swallowed keystroke we can't repost is worse than none) — a 1s poll re-registers on grant. `suspendIntercept()`/`resumeIntercept()` lift the ⌘V registration around synthetic pastes — RegisterEventHotKey consumes the event wholesale, so without suspension our own reposted ⌘V is eaten before the target app sees it. All bindings rebindable in Settings.
- `Jev.swift` — `JSONValue`, `Question`/`Answer` contract, `JevClient` (one POST `{base}/v1/systemone`), `JevEndpoint.custom` URL normalization + `isRemote` loopback check, `StatusTrackingProvider`/`ProviderStatus` for reachability UI.
- `Models.swift` — `ModelCatalog` (benchmark-ranked local model specs: variants, disk/RAM, support tier) + `ModelManager` (uv bootstrap, install via venv/repo/shim, start/stop, health). Absolute tool paths; pipes drained.
- `Redaction.swift` — `Redacting` protocol + `PIIRedactor` wrapping the desert-ant `redact` CoreML model (downloads on demand, ~12 MB).
- `Options.swift` — `OptionBuilder`: candidates are the last 20 clips plus all pins, capped at 30 options; each clip contributes its whole text plus extracted email/phone/URL spans (exact-text dedupe, newest wins). `ContextSignal` finds the one option whose words appear in the field label/window/nearby text — it reorders the chooser so Return takes it, but never auto-pastes or annotates (word overlap can't tell "Reply to Priya" from "Nadia's wedding · Your email"; a criteria-line hint was evaluated and reverted — it nudged confident pastes into message fields).
- `Decide.swift` — `DecisionEngine.decide(context:candidates:mode:feedback:) -> PasteOutcome`. The only thing the controller branches on. `DecisionPolicy.outcome` is pure and testable: a pick is decisive when the leader's share of non-`none` mass clears `confidenceThreshold` with `decisivenessMargin` over the runner-up; `none` ends the paste only when dominant (≥0.7 AND ahead of the leader) — a plurality `none` beside real candidates goes to the chooser. Typed fields (email/phone/URL): one matching option pastes, several choose — even over a model `none`, because small models over-abstain on obvious cases. `SpanExtractor` detects email/phone/URL spans (advertised in pick criteria past the 80-char preview) for the extract transforms.
- `Scripts/laya_server.py` — stdlib-only local server that adapts laya's Python API to `/v1/systemone`.
- `Paste.swift` — `PasteExecutor` (pasteboard write + synthesized ⌘V/Tab) and `FormFiller` (paste→Tab→decide loop, max 20 steps, Esc aborts).
- `Controller.swift` — `SmartPasteController` orchestrates; `FeedbackTracker` learns from ⌘Z-within-2.5s.
- `HUD.swift` — non-activating panels near the caret: chooser (clickable rows, 1–9/arrows/Return to pick, Esc or ⌘V = plain paste, source-app icons, caret-anchored entrance), full picker, deciding dots after 250 ms, status toast, nothing-fits notice.
- `ModelRoles.swift` + `Resources/benchmarks.json` — frozen benchmark numbers drive catalog rank/reason via a pure `roles(from:)` formula (quality = resolved − 2·wrong; accuracy → speed → balance; latency budget required).
- `Views/` — menu bar, history, settings (+hotkey recorder), onboarding; `ProviderPicker.swift` is the shared provider/model UI.
- `SelfCheck.swift` — real end-to-end check: labeled NSTextField → real capture → real decision → real pasteboard write → assert the field got the pasteboard's content. An LSUIElement app can't self-activate from a synthetic driver, so the keystroke leg rides `PasteExecutor.onWouldPost` → real `performKeyEquivalent`/`paste:` on the field editor (the HID-tap leg only ever reaches the system-frontmost app). Menu bar → "Run self-check".

## Invariants — don't break these

- **Secure fields**: `AXSecureTextField` → plain paste of latest, no provider call, value is never read.
- **Never no-op a paste**: every failure path ends in `.pasteLatest`, not silence. Cold-starting local models included — a paste never waits on a server.
- **Non-text passthrough**: image/file pasteboards skip the decision entirely — a model pick would overwrite a copied image with stale text.
- **Model chooses, we execute**: transforms are deterministic local functions; the model only picks (it can't generate strings).
- **Fail-closed redaction**: `piiRedaction` is tri-state (auto = remote on, local off). When effective-on and the provider `isRemote`, clip text is scrubbed first — if scrubbing throws, the paste degrades to `.pasteLatest` rather than send raw text. Loopback endpoints skip redaction by definition. Redaction only affects what the model sees; the paste executes on the raw clip.
- **One dependency**: `desert-ant-core` (the Redact PII model). Otherwise SPM stdlib + AppKit + Carbon + SwiftUI only — add nothing else without need.
- Keys live in Keychain only; history is plain JSON — never log clip contents.
- One provider call per decision; all questions batch into it (they run parallel, share state cost).
