---
agent: devin-local
session: colossal-sloth
created: 2026-09-20T21:04:05Z
---
# SmartCopyPaste — Jev-powered smart paste for macOS

A local, background macOS app that keeps clipboard history (text + URLs), reads the focused field's context via the Accessibility API, and asks TypeSafe AI's Jev model which clip to paste — with top-3/HUD fallbacks, auto form-fill, a paste queue, and learning from undos. Zero external dependencies; Swift 6 / SwiftUI, non-sandboxed local build.

## Context

Tweet: `@marcus_lowe` demoed "smart copy/paste" — clipboard history + context of the field you're pasting into → Jev picks what to paste. We're rebuilding it locally as a real macOS app, more feature-rich.

**Jev facts (verified):** Jev is TypeSafe AI's structured-decision model. One endpoint, no free text — answers typed questions (`choice` ≤255 options, `noul` yes/no probability, `score` 2–10 scale) with calibrated probabilities + confidence, all questions evaluated in parallel in one call.

- Direct: `POST https://api.typesafe.ai/v1/systemone`, `Authorization: Bearer $TYPESAFE_API_KEY`, model `jev-latest` (or pin `jev-1.13.0`)
- Vercel AI Gateway (TypeSafe-compatible): `POST https://ai-gateway.vercel.sh/typesafe/v1/systemone`, `Authorization: Bearer $AI_GATEWAY_API_KEY`, model `typesafe-ai/jev`
- Same request/response shape both routes → **one client, two configs**
- `state`: string | JSON object | array; ~64k tokens total. Rate limits far above our needs.

## Decisions (grilled, settled)

| Decision | Answer |
|---|---|
| Jev access | Both providers via one client: configurable base URL + key + model string |
| Trigger | Configurable; default separate hotkey; onboarding asks "intercept ⌘V?" |
| Scope | Everything: history, HUD, form-fill, queue, transforms, learning |
| Distribution | Local dev build, non-sandboxed (AX + hotkeys + CGEvent need it) |
| Form factor | Background HUD-first app + lightweight menu bar item |
| Privacy | Send everything for now; exclusion-list structure in place, empty by default |
| Content | Text + URLs only |
| Low confidence | Default top-3 toast; user-selectable: picker HUD / top-3 / paste-best / paste-latest |
| Form fill | Auto-detect via `noul` during smart paste |
| Queue | Toggleable queue mode (copies enqueue, pastes pop FIFO) |
| Retention | Persist JSON, cap 1000 (configurable), pins exempt |
| Name | Placeholder module `SmartCopyPaste`; display name TBD by user |

## Architecture

Single SwiftUI app, `LSUIElement=YES` (no Dock), macOS 15+ target, Swift 6.3, **zero SPM dependencies**. Everything is in-process.

```
Hotkey (Carbon) ──► SmartPasteController
                        │
        ┌───────────────┼──────────────────┐
        ▼               ▼                  ▼
 ContextCaptor    ClipStore/Queue    DecisionEngine
 (AX focused         │               ├─ JevClient (URLSession+Codable)
  element, app,      │               ├─ HeuristicRanker (offline/no-key)
  window, field)     │               └─ FeedbackTracker (re-rank)
                        │                  │ outcome: autoPaste | top3 | picker | pasteLatest
                        ▼                  ▼
                  NSPasteboard ◄── PasteExecutor ──► CGEvent ⌘V (+ Tab loop for forms)
                        │
                   HUD panels (top-3 / picker / status toast near caret)
```

### The one Jev call per paste

```
POST {base}/v1/systemone
{ "model": "<configured>",
  "state": {
    "app": "Google Chrome", "window": "Sign up — Example",
    "field": {"role":"AXTextField","label":"Email","placeholder":"you@…","value":""},
    "mode": "smart-paste", "queue_depth": 0
  },
  "questions": {
    "pick":       choice over candidate ids c1..cN (+ "latest"), criteria = preview + kind + source app + age
    "form":       noul  "is this field part of a multi-field form the user is filling?"
    "transform":  choice over {as_is, trim, lowercase, digits_only, strip_url_tracking}
    "use_latest": noul  "is the most recently copied item the right paste here?"  ← gates ⌘V-intercept mode
  } }
```

Response → `answers.pick.choice` + `confidence` + `probabilities` drive the outcome branch. Transforms are deterministic local string ops — Jev chooses, we execute (it can't generate strings, only pick).

## File layout (new Xcode project in cwd)

```
SmartCopyPaste/
  SmartCopyPaste.xcodeproj
  SmartCopyPaste/
    App.swift                  — @main, MenuBarExtra, window routing, LSUIElement
    Info.plist                 — LSUIElement, no sandbox entitlements
    Models/Clip.swift          — Codable clip {id,text,kind,sourceApp,bundleID,copiedAt,pinned,timesPasted}
    Store/ClipStore.swift      — in-memory + JSON at ~/Library/Application Support/SmartCopyPaste/history.json; cap; dedup; atomic writes
    Store/Settings.swift       — UserDefaults-backed AppSettings (all knobs below)
    Store/Keychain.swift       — API keys (kSecClassGenericPassword), never in defaults/logs
    Clipboard/ClipboardMonitor.swift — poll changeCount @250ms; capture string/URL + source app; queue-mode routing
    Context/ContextCaptor.swift — AX: frontmost app, window title, focused element {role,label,desc,placeholder,value}; secure-field flag; caret bounds for HUD
    Context/Permissions.swift  — AXIsProcessTrusted + prompt loop
    Hotkeys/HotkeyManager.swift — Carbon RegisterEventHotKey wrapper; binding registry; reentrancy guard
    Jev/JevClient.swift        — one Codable client; Endpoint{baseURL,key,model}; 5s timeout; typed errors
    Jev/JevTypes.swift         — Question/Answer enums (choice|noul|score), request/response Codable
    Decide/DecisionEngine.swift — build state+questions, call provider, blend feedback stats, produce PasteOutcome
    Decide/HeuristicRanker.swift— no-key/offline fallback: field-keyword/type match + recency decay scoring
    Decide/Transforms.swift    — as_is/trim/lowercase/digits_only/strip_url_tracking (pure functions)
    Paste/PasteExecutor.swift  — set NSPasteboard, post CGEvent ⌘V to HID tap; isSynthesizing flag; Tab poster for form-fill
    Paste/FormFiller.swift     — paste→Tab→re-capture→decide loop; stops on noul-done/non-text-role/submit/max-20/Esc
    Paste/SmartPasteController.swift — orchestrates one paste: gate → decide → outcome → execute → toast
    Feedback/FeedbackTracker.swift — ⌘Z-within-2s = bad pick; outcomes JSON; boost/penalty multiplier into ranking
    HUD/HUDPanel.swift         — borderless non-activating NSPanel; positions near caret (AXBounds) w/ screen-center fallback
    HUD/Top3Toast.swift        — top-3 quick pick (1/2/3 keys)
    HUD/PickerHUD.swift        — full filterable candidate list (arrows/typing, Enter, Esc)
    HUD/StatusToast.swift      — "pasted: email ✓ 0.97" flash, toggleable
    UI/MenuBar.swift           — MenuBarExtra: status, queue toggle+depth, pause, settings/history/onboarding entries
    UI/HistoryWindow.swift     — searchable list, pin/delete/copy, stats, "exclude this app"
    UI/SettingsWindow.swift    — all settings + hotkey recorder + provider config + "Test Jev" button
    UI/HotkeyRecorder.swift    — minimal key-capture NSViewRepresentable (~80 lines, no dep)
    UI/Onboarding.swift        — AX permission → trigger-mode choice ("intercept ⌘V?") → provider+key → test call
  SmartCopyPasteTests/
    JevTypesTests.swift        — encode/decode against doc fixtures (mock URLProtocol for client)
    ClipStoreTests.swift       — dedup, cap, pin-exempt eviction, JSON round-trip
    TransformsTests.swift      — each transform's table of cases
    HeuristicRankerTests.swift — email-field-picks-email-clip style cases
    DecisionEngineTests.swift  — state/questions construction, outcome branching on canned answers
  AGENTS.md                    — execution contract (build/test cmds, TCC gotchas, where things live)
  docs/plans/2026-09-20-smartcopypaste.md — this plan saved into repo (writing-plans convention)
```

## Key implementation details

- **Hotkeys** (all rebindable): Smart Paste `⌃⌥V`; History Picker `⌃⌥C`; Settings `⌃⌥,`; Queue toggle `⌃⌥Q`; Raw-paste-latest `⌃⌥⇧V`; optional ⌘V interception via Carbon hotkey (consumes the event so the target app never sees it).
- **⌘V-intercept safety**: synthesized ⌘V sets `isSynthesizing` flag → hotkey handler ignores it; `AXSecureTextField` role → always plain paste of latest, Jev never called, field value never sent; `use_latest` noul ≥ threshold → just paste latest (keeps dumb pastes dumb).
- **Candidates**: latest + up to 40 recent unique clips → `pick` criteria labels like `"c7": "email · h@x.com · from Safari · 3m ago"`. Well under the 255 cap, keeps state small.
- **Queue mode**: toggle → new copies enqueue (badge depth in menu bar); smart paste pops front. Non-queue copies still land in history.
- **Form fill**: on `form.noul` ≥ threshold after a paste → Tab → re-capture → re-decide with remaining candidates → loop until noul flips, non-text role, submit-ish field, 20 steps, or Esc.
- **Learning**: ⌘Z within 2s of our paste → record `(app, fieldLabelHash, clipHash, bad)`. Ranking applies a decayed penalty; repeated bad picks sink a clip for that context. Purely local stats.
- **Heuristic fallback** (no key / offline / error): keyword maps (`email→regex`, `phone→digits`, `name`, `url→has scheme`, `address`, `code`) + recency decay + source-app bonus. Same outcome contract as Jev so nothing downstream changes.
- **Errors**: Jev timeout/5xx → heuristic → if that fails → paste latest. Never leave the user with no paste.
- **Launch at login**: SMAppService toggle in settings.

## Build order (each task = tests where pure, then commit)

1. **Scaffold** — Xcode project, LSUIElement, sandbox off, runs as menu-bar ghost app. Verify: builds, icon in menu bar.
2. **Models + ClipStore + ClipboardMonitor** — TDD store (dedup/cap/pins/JSON). Verify: `xcodebuild test` green; copy text → lands in store.
3. **HotkeyManager + PasteExecutor** — Carbon wrapper, CGEvent ⌘V + Tab, reentrancy flag. Verify: manual — hotkey pastes into TextEdit.
4. **ContextCaptor + Permissions** — AX read of focused element + permission prompt loop. Verify: log dump shows role/label from Safari + TextEdit fields.
5. **JevClient + JevTypes** — Codable contract vs doc fixtures, mock URLProtocol. Verify: tests decode real response shapes; "Test Jev" curl-equivalent works with real key.
6. **Transforms + HeuristicRanker + DecisionEngine** — question construction, outcome branching, blending. Verify: unit tests incl. confidence-threshold branches.
7. **HUDs + SmartPasteController** — top-3 toast, full picker, status toast, caret positioning. Verify: force-low-threshold → each low-conf mode renders + pastes selection.
8. **FormFiller** — auto-detect loop. Verify: fill a 3-field form (name/email/site) from 3 clips.
9. **Queue mode** — enqueue/pop + menu badge. Verify: copy 3, paste 3 in order.
10. **FeedbackTracker** — undo detection, stats file, ranking penalty. Verify: unit test + manual undo demotes clip.
11. **Settings + Onboarding + HistoryWindow + MenuBar polish** — all knobs live, hotkey recorder, "Test Jev" button, AX walkthrough, intercept-⌘V question screen.
12. **Docs + self-check** — `AGENTS.md` (writing-for-agents: build/test commands, TCC reset instructions `tccutil reset Accessibility <bundle-id>`, architecture map), `docs/plans/` copy, README, hidden menu item "Run self-check" (opens TextEdit, seeds clips, drives a smart paste, asserts result — the one runnable end-to-end check).

## Settings surface

Hotkeys (5 rebindable) · intercept-⌘V toggle · provider (Direct | AI Gateway) + key + model string · confidence threshold (default 0.7) · low-confidence mode (top3 | picker | pasteBest | pasteLatest) · status-toast toggle · history cap (1000) · excluded-apps list (empty) · launch-at-login · queue toggle · "reset learning stats" · "test Jev connection"

## Acceptance criteria

- [ ] Copy text/URL → persisted history (survives restart), dedup, cap honored
- [ ] Smart-paste hotkey in a field → Jev picks the right clip and it lands via ⌘V
- [ ] Confidence below threshold → configured UX (default top-3) appears near caret
- [ ] ⌘V-intercept mode optional via onboarding; secure fields always plain-paste latest
- [ ] Multi-field form auto-fills: paste → Tab → next clip → done
- [ ] Queue mode pastes FIFO
- [ ] Works end-to-end with no API key (heuristic) and with either provider
- [ ] API keys only in Keychain; history is plain JSON in Application Support
- [ ] ⌘Z right after a smart paste demotes that pick for that context
- [ ] `xcodebuild test` green; self-check menu item passes

## Risks / notes

- **AX field labels are best-effort** — Electron/web apps vary wildly. We send whatever exists (role/placeholder/value/window title); Jev handles sparse state; heuristic covers failure.
- **⌘V interception** relies on Carbon hotkey consuming the event; secure fields + `use_latest` noul keep it sane. If an app eats our synthesized ⌘V (rare — Citrix/VMs), fallback: pasteboard already holds the pick, user can ⌘V manually.
- **Latency**: Jev is ~100x faster than LLM gen but it's still a network call — status toast shows a subtle spinner past ~300ms; heuristic keeps working if the call is slow/dead.
- **No key yet**: if neither TYPESAFE_API_KEY nor AI_GATEWAY_API_KEY is available at build time, the heuristic path still delivers the full UX loop; Jev drops in via settings.
- **Naming**: module stays `SmartCopyPaste`; `CFBundleDisplayName` is a one-line rename whenever the clever name lands.
