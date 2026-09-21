# Cue

Your clipboard is a queue; Cue sends the right clip on stage. A local macOS
app that keeps your clipboard history and — on a hotkey, or every ⌘V if you
enable interception — asks a typed decision model which clip fits the field
you're pasting into. Context-aware picks, calibrated confidence, no
hallucinated text: the model only ever *chooses* among your real clips.

Runs against TypeSafe's hosted **Jev**, Jev via **AI Gateway**, fully local
open-weight models (**Kev**, **Laya**), or **any self-hosted endpoint** that
speaks the System One contract — or no model at all (local heuristics).

Inspired by [@marcus_lowe's demo](https://x.com/marcus_lowe/status/2101476399488160013), rebuilt as a real background app.

## Build & run

```sh
Scripts/bundle.sh        # → build/Cue.app
open build/Cue.app
```

Requires macOS 15+, Xcode 26. One dependency: `desert-ant-core` (on-device
PII redaction). Grant **Accessibility** when prompted (needed to read the
focused field and post the paste keystroke). After rebuilding, if the
permission grant sticks to the old binary:
`tccutil reset Accessibility com.local.cue`.

## How it works

1. `NSPasteboard` is polled for text/URLs → history (JSON, capped, pinned items kept).
2. On smart paste, the focused UI element is read via the Accessibility API:
   app, window title, field role, label, placeholder, current value.
3. One Jev call (`POST {base}/v1/systemone`) evaluates, in parallel:
   - `pick` — choice over up to 40 recent clips
   - `form` — is this a multi-field form? (triggers the Tab-walking auto-fill)
   - `transform` — should the pick be adjusted? (trim / lowercase / digits-only / strip-utm)
   - `use_latest` / `form_field` — gating for ⌘V-intercept and mid-form steps
4. Confidence ≥ threshold → paste directly. Below → your chosen fallback
   (top-3 toast / full picker / paste best / paste latest).

Every provider is the same client with a different `(url, model, key)` —
pick in Settings or onboarding:

- **Jev · TypeSafe direct**: `api.typesafe.ai` + `TYPESAFE_API_KEY`, model `jev-latest`
- **Jev · AI Gateway**: `ai-gateway.vercel.sh/typesafe` + `AI_GATEWAY_API_KEY`, model `typesafe-ai/jev`
- **Kev · local**: [jaredpalmer/kev](https://github.com/jaredpalmer/kev) — open
  weights serving the same contract. `uv run --extra serve python -m kev.serve --run jaredpalmer/kev-4b --port 8009`
- **Laya · local**: [convaiinnovations/laya](https://github.com/convaiinnovations/laya) —
  open-weight System 1 model. `pip install laya`, then `python3 Scripts/laya_server.py`
- **Custom endpoint**: anything answering `POST {base}/v1/systemone`; the URL
  field takes `host:port`, `scheme://host`, or a full `…/v1/systemone` URL
- **None · offline**: local heuristic ranking (shape-matching against the
  field label) covers the same UX; a provider drops in whenever you add one.

### Privacy

Optional on-device PII redaction (desert-ant `redact`, ~12 MB Core ML,
downloads on first use) masks names, emails, phones, cards and IDs in clip
text before it reaches a remote provider. Fail-closed: if the model isn't
usable, the engine falls back to local heuristics instead of sending raw
text. Loopback providers (Kev, Laya, localhost custom) skip it entirely —
that data never leaves the device anyway.

## Features

- Smart paste hotkey (`⌃⌥V`) or full ⌘V interception — your call during onboarding
- Auto form-fill: paste → Tab → next field → repeat until the form is done
- Queue mode: copies enqueue, pastes pop in FIFO order
- Top-3 toast, filterable picker, per-app raw-paste hotkey (`⌃⌥⇧V`)
- Menu bar shows recent clips for one-click re-paste; history window can paste into the previous app
- On-device PII redaction before any cloud call (opt-out, off for local providers)
- Learns from undos: ⌘Z right after a pick demotes it for that context
- Password fields are never analyzed and never sent anywhere
- Keys in Keychain; history is plain JSON in `~/Library/Application Support/Cue/`

## Development

```sh
swift test   # 39 tests: store, Jev contract, transforms, heuristic, engine, redaction gating
```

`Sources/CueKit/` is the whole app; `Sources/Cue/main.swift` is a
trampoline. Menu bar → "Run self-check" drives a real end-to-end paste into a
live text field and asserts the result. See `AGENTS.md` for invariants.
