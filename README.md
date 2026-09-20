# SmartCopyPaste

What if copy/paste was smart? A local macOS app that keeps your clipboard
history and — on a hotkey, or every ⌘V if you enable interception — asks
TypeSafe AI's **Jev** model which clip fits the field you're pasting into.
Context-aware picks, calibrated confidence, no hallucinated text: Jev only
ever *chooses* among your real clips.

Inspired by [@marcus_lowe's demo](https://x.com/marcus_lowe/status/2101476399488160013), rebuilt as a real background app.

## Build & run

```sh
Scripts/bundle.sh        # → build/SmartCopyPaste.app
open build/SmartCopyPaste.app
```

Requires macOS 15+, Xcode 26. No dependencies — SwiftPM + system frameworks only.
Grant **Accessibility** when prompted (needed to read the focused field and
post the paste keystroke). After rebuilding, if the permission grant sticks to
the old binary: `tccutil reset Accessibility com.local.smartcopypaste`.

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

Both Jev routes work with one client — pick in Settings:
- **TypeSafe direct**: `api.typesafe.ai` + `TYPESAFE_API_KEY`, model `jev-latest`
- **AI Gateway**: `ai-gateway.vercel.sh/typesafe` + `AI_GATEWAY_API_KEY`, model `typesafe-ai/jev`
- **None**: local heuristic ranking (shape-matching against the field label)
  covers the same UX offline; Jev drops in whenever you add a key.

## Features

- Smart paste hotkey (`⌃⌥V`) or full ⌘V interception — your call during onboarding
- Auto form-fill: paste → Tab → next field → repeat until the form is done
- Queue mode: copies enqueue, pastes pop in FIFO order
- Top-3 toast, filterable picker, per-app raw-paste hotkey (`⌃⌥⇧V`)
- Learns from undos: ⌘Z right after a pick demotes it for that context
- Password fields are never analyzed and never sent anywhere
- Keys in Keychain; history is plain JSON in `~/Library/Application Support/SmartCopyPaste/`

## Development

```sh
swift test   # 26 tests: store, Jev contract, transforms, heuristic, engine
```

`Sources/SCPKit/` is the whole app; `Sources/SmartCopyPaste/main.swift` is a
trampoline. Menu bar → "Run self-check" drives a real end-to-end paste into a
live text field and asserts the result. See `AGENTS.md` for invariants.
