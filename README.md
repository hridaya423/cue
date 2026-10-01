# Cue

Your clipboard is a queue; Cue sends the right clip on stage. A local macOS
app that keeps your clipboard history and — on a hotkey, or every ⌘V if you
enable interception — asks a typed decision model which clip fits the field
you're pasting into. Context-aware picks, calibrated confidence, no
hallucinated text: the model only ever *chooses* among your real clips.

Runs against TypeSafe's hosted **Jev**, Jev via **AI Gateway**, managed local
open-weight models (**Kev**, **Laya**, **Von**, and more — Cue installs,
downloads weights, and runs the server for you), or **any self-hosted
endpoint** that speaks the System One contract. No model at all also works:
every smart paste just becomes a normal one.

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
   app, bundle, window title, field role/label/placeholder/value, caret rect,
   and nearby text — enough for the model to tell an "Email" field from a
   "Search" box. History is searched as *options*: the last 20 clips plus
   pins, each expanded into extractable spans (emails, phones, URLs in a
   multi-value clip each become their own option).
3. One Jev call (`POST {base}/v1/systemone`) evaluates, in parallel:
   - `pick` — probability over the options plus `none`
   - `form` — is this a multi-field form? (triggers the Tab-walking auto-fill)
   - `use_latest` / `form_field` — gating for ⌘V-intercept and mid-form steps
4. A decisive pick pastes directly. When the model reports real ambiguity —
   several plausible candidates with no leader — a caret-anchored chooser
   shows the top three (1/2/3 or arrows; Esc/⌘V = ordinary paste). `none`
   only ends the paste when it's dominant. The fallback mode under low
   confidence is yours (top-3 / full picker / paste best / paste latest).
   A quiet three-dot indicator sits at the caret while the model works —
   fast decisions never flash it.

Every provider is the same client with a different `(url, model, key)` —
pick in Settings or onboarding:

- **Jev · TypeSafe direct**: `api.typesafe.ai` + `TYPESAFE_API_KEY`, model `jev-latest`
- **Jev · AI Gateway**: `ai-gateway.vercel.sh/typesafe` + `AI_GATEWAY_API_KEY`, model `typesafe-ai/jev`
- **Kev · local**: [jaredpalmer/kev](https://github.com/jaredpalmer/kev) —
  LoRA adapters on Qwen3.5, four weight sizes (0.8B–9B). Pick a size, hit
  Install — Cue clones, syncs, downloads weights, and serves on :8009.
- **Laya · local**: [convaiinnovations/laya](https://github.com/convaiinnovations/laya) —
  421M encoder, ~33ms, smallest option. Installs into a managed venv; served
  by a bundled stdlib shim on :8765.
- **Other local models** — benchmark-ranked catalog (Von, Jevons, jev-lite,
  Decider) with params/disk/RAM per variant and support tiers (experimental
  and unavailable entries are labeled, not hidden).
- **Custom endpoint**: anything answering `POST {base}/v1/systemone`; the URL
  field takes `host:port`, `scheme://host`, or a full `…/v1/systemone` URL.
- **Off**: no model calls — smart pastes pass through as normal ⌘Vs; history,
  queue, and the picker still work.

### Privacy

On-device PII redaction (desert-ant `redact`, ~12 MB Core ML, downloads on
first use) masks names, emails, phones, cards and IDs in clip text before it
reaches a remote provider. **Auto by default**: on for cloud providers, off
for local models — scrubbing traffic that never leaves the device only costs
latency. Fail-closed: if the model isn't usable, the paste degrades to a
normal ⌘V instead of sending raw text. Only the scrubbed preview reaches the
model; the real clip is what pastes.

## Features

- Smart paste hotkey (`⌃⌥V`) or full ⌘V interception — your call during onboarding
- Auto form-fill: paste → Tab → next field → repeat until the form is done
- Queue mode: copies enqueue, pastes pop in FIFO order
- Caret-anchored chooser on real ambiguity (top-3 spans or clips), filterable picker, per-app raw-paste hotkey (`⌃⌥⇧V`)
- Menu bar shows recent clips for one-click re-paste; history window can paste into the previous app
- On-device PII redaction before any cloud call (auto-on remote, auto-off local, overridable)
- Managed local models: install, weights download, start/stop, health, and uninstall from the picker — no terminal needed
- Unreachable endpoint? Pastes pass through normally until it recovers — nothing blocks or errors mid-paste
- Image/file copies untouched: smart paste only ever reasons about text
- Learns from undos: ⌘Z right after a pick demotes it for that context
- Password fields are never analyzed and never sent anywhere
- Keys in Keychain; history is plain JSON in `~/Library/Application Support/Cue/`

## Development

```sh
swift test   # 105 tests: store, Jev contract, transforms, engine + policy,
             # model catalog + roles, pasteboard gate, settings, provider status
```

`CueEval --cases Evals/cases.jsonl --endpoint name=base,model` runs the
110-case synthetic benchmark end-to-end through the real decision engine;
`--replay <raw.jsonl>` re-scores recorded answers through the current policy
(no server needed) and `--diag` prints model-leader vs context-signal
agreement per case. `Scripts/eval_servers.sh` brings up all installed local
model servers detached under launchd so the sweep survives the shell;
`Scripts/eval_run.sh <tag> --endpoint …` runs one detached pass.

`Sources/CueKit/` is the whole app; `Sources/Cue/main.swift` is a
trampoline. Settings → General → Run self-check drives a real end-to-end paste into a
live text field and asserts the result. See `AGENTS.md` for invariants.
