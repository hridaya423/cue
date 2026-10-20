<p align="center"><img src="docs/banner.svg" alt="Cue" width="100%"></p>

# Cue

Cue is a clipboard for macOS that pastes the part of your clipboard that fits the field. It keeps your clipboard history. When you press the smart-paste hotkey, Cue reads the focused field and asks a decision model which clip fits. You can also let Cue handle every ⌘V.

The model only chooses among your real clips. It never writes text. If no model runs, or the endpoint does not answer, the paste is a plain ⌘V.

Inspired by [@marcus_lowe's demo](https://x.com/marcus_lowe/status/2101476399488160013), rebuilt as a real background app.

## Build and run

```sh
Scripts/bundle.sh        # builds build/Cue.app
open build/Cue.app
```

Cue needs macOS 15 or later and Xcode 26. It has one dependency, `desert-ant-core`, for on-device PII redaction.

Grant Accessibility when macOS asks. Cue uses it to read the focused field and to post the paste keystroke. If an ad-hoc rebuild loses the grant, run `tccutil reset Accessibility com.hridyaagrawal.cue`.

`Scripts/release.sh` builds a signed, notarized DMG at `build/Cue-<version>.dmg`.

## How it works

1. Cue polls `NSPasteboard` for text and URLs. History is a JSON file with a cap; pinned clips stay.
2. On a smart paste, Cue reads the focused element through the Accessibility API: the app, the window title, the field's role, label, placeholder and value, the caret and nearby text.
3. Cue builds the options: the last 20 clips plus pins. An email, phone number, URL or code inside a clip becomes its own option.
4. One call to `POST {base}/v1/systemone` asks all questions in parallel: which option fits, whether the field is part of a form, and the gates for ⌘V and form steps.
5. A decisive pick pastes. If the model has no clear leader, a chooser opens at the caret with up to nine rows. Esc or ⌘V gives a plain paste.

Some decisions need no model call. If the field asks for an email, a phone number or a URL and exactly one option matches, Cue pastes that option. On ⌘V, if the latest clip already fits the field, Cue pastes it directly.

## Providers

Every provider uses the same client with a different URL, model and key. Choose one in onboarding or in Settings.

- **Jev, TypeSafe direct**: `api.typesafe.ai` with `TYPESAFE_API_KEY`, model `jev-latest`.
- **Jev, AI Gateway**: `ai-gateway.vercel.sh/typesafe` with `AI_GATEWAY_API_KEY`, model `typesafe-ai/jev`.
- **Local models**: a catalog ranked by benchmark, with disk size and memory for each variant. JevK5-Lite is the recommended model. Cue installs the model, downloads the weights and runs the server. Examples:
  - [Kev](https://github.com/jaredpalmer/kev): LoRA adapters on Qwen3.5 in four sizes (0.8B to 9B), served on port 8009.
  - [Laya](https://github.com/convaiinnovations/laya): a 421M encoder at about 33 ms, served by a bundled stdlib shim on port 8765.
- **Custom endpoint**: any server that answers `POST {base}/v1/systemone`. The field accepts `host:port`, `scheme://host` or the full URL.
- **Off**: Cue makes no model calls. Every smart paste is a plain paste. History, the queue and the picker still work.

## Privacy

- Cue never reads password fields and never sends them anywhere.
- Before clip text goes to a remote provider, an on-device model (desert-ant `redact`, about 12 MB of Core ML) replaces names, emails, phone numbers, cards and IDs with placeholders. This is on by default for remote providers and off for local ones.
- If redaction fails, Cue does a plain paste. It never sends raw text instead.
- Redaction changes only what the model sees. The paste uses your real clip.
- Image and file copies pass through. Cue reasons only about text.
- API keys stay in the Keychain. History is plain JSON in `~/Library/Application Support/Cue/`.

## Shortcuts

All shortcuts can be changed in Settings.

| Shortcut | Action |
|---|---|
| ⌃⌥V | Smart paste |
| ⌃⌥⇧V | Plain paste |
| ⌃⌥C | Search history |
| ⌃⌥Q | Turn the queue on or off |
| ⌃⌥, | Open Settings |

With ⌘V interception on, every ⌘V is a smart paste. Cue registers ⌘V only while it has Accessibility access.

Other features:

- **Form fill**: Cue pastes, presses Tab and decides again, until the form is complete. Esc stops it.
- **Queue**: copies go into a queue, and each paste takes the oldest one.
- **Menu bar**: recent clips, search and one-click paste.

## Development

```sh
swift build
swift test
```

The tests cover the store, the System One contract, transforms, the decision engine and policy, the model catalog, the pasteboard gate and settings.

`CueEval` runs 110 synthetic cases through the real decision engine:

```sh
swift build -c release --product CueEval
CueEval --cases Evals/cases.jsonl --endpoint name=base,model --repeats 3 --json out.json
```

`--replay <raw.jsonl>` scores recorded answers again with the current policy, with no server. `--diag` prints the model's leader beside the context signal for each case. `Scripts/eval_servers.sh` starts the installed local model servers under launchd.

`Sources/CueKit/` holds the app. `Sources/Cue/main.swift` only starts it. In Settings, General, **Run self-check** pastes into a real text field and checks the result. `AGENTS.md` lists the invariants.

The website lives in `web/`.
