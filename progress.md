# Engine hill-climb — progress

Goal: ⌘V lands the right thing instantly, or behaves exactly like plain ⌘V.
Bar: Spotlight clipboard history (⌘Space, ⌘4) plus plain ⌘V on this Mac.

## Gates (measured every round)

| gate | target |
|---|---|
| chooser on clear cases | ≤ 20% |
| wrong pastes | ≤ 2% |
| p95 decision latency | ≤ 1.2 s, no cold-start stall |
| idle CPU and energy (Cue + model server) | near zero |
| persona steps | Cue wins or ties blind on every step (a tie = the same text landed in the same time) |

## Protocol

- Three personas, one full day each: `Evals/days/<persona>.jsonl`. Surfaces: `Evals/days/surfaces.json`, local pages: `Evals/days/pages/`.
- Live lane: drive real apps on this Mac (Safari, Chrome, Terminal running `cat`, TextEdit, VS Code). Nothing is sent to any external service. Bar side: plain ⌘V, and Spotlight ⌘4 driven for real when the wanted item isn't the latest.
- Replay lane: the contexts captured live are replayed through CueEval for fast metric sweeps.
- Per part: a builder changes code; a fresh critic compares step transcripts blind (A/B labels shuffled) and names the biggest gap. A change ships only if it wins and moves a number.
- Builders: Devin `swe-2-high` drafts, the lead reviews and improves. Critics: `claude-sonnet-5-5`, fresh context.

## Live lane — real apps, real keystrokes (2026-10-19, user approved driving the screen while away)

`Sources/CueLive` drives each persona day in the real apps with real CGEvent keystrokes: web surfaces in a Chrome tab / Safari document of its own (local pages, nothing sent anywhere), Terminal running `cat`, TextEdit for other native fields. The Cue side is the real Cue app (release build, own bundle id `com.local.cue.live`, history under `/tmp/cuehome`) with ⌘V intercepted and the ⌃⌥V hotkey; the driver answers the real chooser by reading its rows through Accessibility and typing digits/letters. Read-back is the field's real AX value.

Real-app bugs the harness had hidden, all fixed:
1. **Hotkey = ⌘V in intercept mode.** Both fired `.smartPaste` and the controller chose the mode from the setting, so ⌃⌥V never opened the chooser while ⌘V was intercepted. ⌘V now has its own handler (`onIntercept`), and `smartPaste(intercepted:)` takes the mode from the key.
2. **Chooser digits by key code.** `kVK_ANSI_1…9` aren't contiguous (pressing 6 picked row 5) and AZERTY digits need Shift. Digits are now read as typed characters.
3. **The chooser stole focus.** The keyable panel (an uncommitted change found in the tree) took key focus from the browser, the web field blurred, and the paste after a pick landed nowhere. The chooser now never becomes key: a session event tap consumes its keys while it's up (Cue already holds Accessibility), and switching apps closes it.
Harness lessons: Chrome rebuilds AX nodes, so fields are re-found by DOM id on every read; typed keys must not inherit the hotkey's ⌃⌥ modifier state; `make new window` in Chrome landed in the user's window — the driver now owns a tab created for it and navigates nothing else.
Live results (real Chrome/Safari/TextEdit/Terminal, real Cue app, real keystrokes; bar side not yet driven — see below):

| day | steps | correct | trimmed | wrong/missed | ⌘V wait max | hotkey wait p50 |
|---|---|---|---|---|---|---|
| recruiter | 45 | 43 | 1 | 1 | 21 ms | 107 ms |
| engineer | 44 | 42 | 0 | 2 | 20 ms | 116 ms |
| founder | — | — | — | — | — | — |

Misses: rec 29 — the persona searched "0143" and the "1" picked row 1 (fourth real bug, fixed: once a search has started, digits extend it, Return/arrows pick; the row badges hide and the footer reads "↑↓ ↩ paste" — rendered and checked); eng 5 — Cue's history wasn't reset between persona days (harness setup); eng 39 — the model said "nothing fits" on the real Chrome context (`file://` page, no web host) where the harness context had passed.
The founder day (Safari) couldn't run: the screen locked after an hour without real HID input (synthetic keystrokes don't count as activity), and GUI driving stopped there. Cleanup done: live Cue app stopped, `com.local.cue.live` defaults deleted, driver-owned Chrome tab, Safari document and TextEdit document closed, `cat` stopped, clipboard restored, real `com.local.cue` defaults verified unchanged.
**Side effect to report:** before that fix, the driver navigated the first tab of the user's Chrome window (a "Luma" tab next to it was untouched); its original page fell out of Chrome's 50-entry back history and could not be restored automatically (Chrome's History DB is TCC-protected).

## Bar calibration (2026-10-19 01:21, user idle 2.9 h)

Surprise: on this Mac the stated bar is unreachable without changing the user's settings. Spotlight's ⌘Space is disabled (`com.apple.symbolichotkeys` 64 → enabled false), ⌘Space opens a third-party launcher instead, and `open -a Spotlight` fails (launchd spawn error 162). The launcher has its own clipboard history (1000 items, source tagged "Foundry"); a scripted open → query → Return did not land text in TextEdit, so it was not timed. The bar stays the computed Keystroke-Level-Model route for Spotlight ⌘4 (⌘Space, ⌘4, 4-letter query, Return, ⌘V ≈ 4.2 s), which is the fastest the built-in could be. Second attempt (07:46, user approved enabling Spotlight briefly): quit the launcher, set hotkey 64 enabled + `activateSettings -u` → ⌘Space still opened nothing. Root cause: on macOS 27 the classic Spotlight UI agent (`/System/Library/LaunchAgents/com.apple.Spotlight.plist`) is disabled by the feature flag `IntelligenceFlow/Campo`; system search moved to "Siri AI" (Campo), whose app opens a conversation window, not a clipboard list. The specified bar does not exist on this OS build. Everything was restored (hotkey plist from backup, launcher relaunched, clipboard restored). The bar's plain-⌘V route is driven for real in the live lane; its Spotlight route stays the computed ~4.2 s.
Side effect to tell the user: the launcher's clipboard history now holds 6 test strings ("alpha-clip-one…", "gamma-three https://cal.example.com/…"); the user's own clipboard was restored after each test.

## Environment (2026-10-18)

- M4 Pro, 48 GB, macOS 27.0.1, 16 GB disk free.
- Models had been deleted from `~/Library/Application Support/Cue/models` on Oct 13. Reinstalled: kev (repo env), decider 1.9.0 venv.
- Servers under launchd: `cue.eval.kev` → :8009 (kev-0.8b), `cue.eval.decider` → :8790 (`Mapika/decider-0.8b`, MPS).
- Surprise: the catalog says decider needs NVIDIA/Triton. decider 1.9.0 ships an MPS path (`decider/mps_ops.py`); verifying.
- Port 8769 (decider's catalog default) is held by an unrelated `tools/serve.py`; left alone.
- No hosted Jev key in envsync.

## Rounds

### R0 — baseline (working tree as found, 110 CueEval cases × 3)

| model | resolved | wrong | chooser on clear | p50 | p95 | idle CPU | RSS |
|---|---|---|---|---|---|---|---|
| kev-0.8b (MLX bf16) | 92% | 0% | 48% | 150 ms | 566 ms | 0.3% | 3.2 GB |
| decider-0.8b (MPS torch, eager) | 84% | 1% | **20%** | 514 ms | 1027 ms | 0.1% | 3.3 GB |

Raw: `Evals/results/hill/r0-raw.jsonl`, `r0.json`. decider meets the chooser gate on its own; kev meets wrong and latency. Neither meets all gates.
kev vs decider on clear cases: decider pastes outright on 10 amb-signal cases where kev shows the chooser (1 wrong: amb-17). decider is the better decider; latency is its only gap → MLX port in progress (`Scripts/decider_mlx_server.py`).
Replay gotcha: `--replay` keys answers by case id only — split raw files per model first (`r0-kev-raw.jsonl`, `r0-decider-raw.jsonl`).

Candidate (pending persona verdict): field understanding — whole-word label matching in `FieldKind` ("Tell us about yourself" read as phone, "Username" as name). CueEval unchanged (kev 92/0/48, decider 84/1/20 on replay): its labels never hit the bug, so it must prove itself on the traces or be reverted.

### R1 — decision policy + field understanding (lead, CueEval replay of R0 answers)

Changes:
1. Deleted the intercept `use_latest` question. The model is only called on ⌘V after the local check has proved the latest clip does not fit, so the question could only contradict a known fact: decider answered use_latest ≈0.51–0.54 and plain-pasted "lunch tomorrow?" into Email/Phone fields (iv-06, iv-12). One fewer question row per intercept call. Code: −1 question, −1 policy parameter, −1 test.
2. `FieldKind`: whole-word matching; "To" (whole label), "Cc", "Bcc", "Recipient(s)" read as email. decider abstained (none ≈0.93) on To/Cc/Bcc fields because nothing told it they want an address.

| model (replay) | resolved | wrong | chooser on clear |
|---|---|---|---|
| decider-0.8b | 84 → **87%** | 1 → 1% | 20 → **18%** |
| kev-0.8b | 92 → 91% | 0 → 0% | 48 → 47% |

kev's −1: nz-01 (Mail To:, two emails in history) now shows an emails-only chooser instead of a weak lucky pick; amb-14 (Messages To:, phone or email both acceptable) pastes the one email. Both acceptable. Persona-trace verdict pending.

### R2 — model runtime (decider on MLX) + contested-signal policy

Runtime parity (builder report, `Scripts/decider_mlx_parity.py`, 101 real request bodies): fp16 max |Δp| 0.0099, 0/643 argmax flips (bf16: 0.038, 3 flips, rejected). Warm p50 136 ms / p95 232 ms vs torch 317/479 on the same bodies. Idle 0.0% CPU, 3.1 GB RSS. Cold start 4.1 s (warm-up request at start). No torch import.
Runtime: `Scripts/decider_mlx_server.py` (Devin swe-2-high build) serves decider-0.8b through mlx-lm on :8791, launchd `cue.eval.decidermlx`. Live CueEval, R1 engine, 3 repeats:

| decider-0.8b | resolved | wrong | chooser on clear | p50 | p95 |
|---|---|---|---|---|---|
| MPS torch eager (R0) | 84% | 1% | 20% | 514 ms | 1027 ms |
| MLX, R1 engine (live) | 85% | 2% | 17% | **146 ms** | **293 ms** |
| MLX, R2 engine (replay) | 85% | **1%** | 18% | — | — |

Policy: when ContextSignal uniquely points at a different option than the model's leader, a decisive or weak-unopposed leader no longer pastes: the chooser shows, signal first. Fixes ms-07 (Cc field, model sure of finance@, label points at legal@), which R1's Cc→email change had turned from a miss into a wrong paste. kev and decider-torch replays unchanged (91/0/47, 87/1/18). Remaining wrong: amb-17 ("Your email" on "RSVP — Nadia's wedding": model and signal both point at Nadia).

### R3 candidate — decision policy: ⌘V in generic fields consults the model (pending persona verdict)

Trace analysis: of 47 non-latest persona steps, almost all go into generic fields (message, comment, body, terminal). Intercept used to plain-paste every generic ⌘V without a model call, so all of those were guaranteed losses to Spotlight. Change: generic ⌘V calls the model; a decisive, uncontested pick of something other than the latest clip pastes; anything else is a plain paste, never a chooser.
Live CueEval (decider MLX): 85% / 1% / 18%, p50 134 ms, p95 231 ms. Generic intercept cases (iv-03/07/09/13/14) still plain: no regression. Cost: ~65 ms model call per generic ⌘V (to be removed by precompute). 122 tests pass.
Field understanding, same round: `nearby` only decides the field kind when the field has no label. A labelled "Message body" under an email thread was read as an email field, so the typed rescue pasted an address without a chooser (found by the harness builder on its fixture). CueEval replays unchanged (kev 91/0/47, decider 87/1/18, decider-MLX 85/1/18).

### First persona runs (recruiter, intercept, R3 engine, harness still WIP: 9/46 steps lack AX capture)

| model | cue correct | bar correct | cue s | bar s | p50 / p95 decision |
|---|---|---|---|---|---|
| decider-0.8b MLX | 72% | 100% | 82.0 | 76.1 | 289 / 417 ms |
| decider-2b MLX | 70% | 100% | 92.5 | 76.1 | 554 / 723 ms |

decider-2b: no better on a real day and 2× slower → rejected, weights deleted.
Failures: every miss is a generic-field ⌘V where the model abstains or spreads mass (Guests: none 0.54–0.69; Slack DM: leader 0.19). On real 20–30-option histories the 0.8B is much less sure than on CueEval.
Findings for the next rounds: (1) on latest steps Cue can only tie the bar if the decision is precomputed before ⌘V; (2) harness `wrong_pastes` counts plain pastes of the latest clip, which must be split into wrong (Cue overrode) vs miss (plain); (3) 3 steps sit beyond the 20-clip window, 5 "part" steps need spans Cue can't extract (salary, SHA, request id, constraint, account no.).

### R4 — model runtime: decision precompute (built, persona run P1 in progress)

`Sources/CueKit/Prefetch.swift` (Devin swe-2-high; lead review): `DecisionPrefetch` caches one decision keyed by field identity (bundle, window, role, label, placeholder, host) + newest clip id + history count + mode; `PrefetchTriggers` warms on app activation, AXObserver focus change, and new clips, coalesced ≤1/100 ms, no timers. ⌘V serves the warm result (awaiting it if in flight). Lead change: warming only for on-device providers — warming sends clip text before the user pastes, so a remote endpoint must not see it. 131 tests pass.
Harness fixes (lead): surfaces found by window identifier, not title (Gmail compose shared its title with the inbox → 9–17 steps had empty captures; the first identifier fix didn't compile and the run silently used the old binary). Scoring: Cue's ⌘V keystroke now counted (was free, bar's wasn't); wrong (Cue pasted something else) vs miss (plain paste of the wrong latest) split; ties within 10 ms. Harness uses the real `DecisionPrefetch` with a 300 ms focus-to-⌘V gap (`--gap-ms`, 0 = no precompute).

### P1 — full persona days, live (decider-0.8b MLX, R3 + precompute, fair scoring v1)

| | steps | cue correct | wrong | missed | p50 / p95 wait at ⌘V | better / tied / worse | cue s vs bar s |
|---|---|---|---|---|---|---|---|
| total | 134 | 72% | 4 (3%) | 33 | **0 / 105 ms** | 4 / 73 / 54 | 221.5 vs 215.3 |

Precompute turned the decision wait from 278/422 ms (P0) into 0/105 ms: 73 steps now tie plain ⌘V exactly.
**R3 verdict: lose → reverted.** Generic-field model overrides were right once and wrong 4 times (3 of the 4 overwrote a "paste what I just copied" step). On real days the 0.8B ranks the wanted older clip first among alternatives only 6/30 times, top-3 12/30; a lexical context-overlap ranker does no better (6/30). Neither signal is strong enough to override ⌘V in a message box.
Miss anatomy (33): ~17 want part of the latest clip (a URL inside a Slack message, a line of a log, an email in a signature), ~16 want an older clip.
Scoring v2 (lead): when the wanted text sits inside the latest clip the bar is ⌘V + trim (was charged a Spotlight trip); when Cue lands a clip that holds the wanted text the persona trims (was charged ⌘Z + the bar's route).

### P2 — replay of P1 answers, R3 reverted, scoring v2

| steps | cue correct | wrong | missed | better / tied / worse | cue s vs bar s |
|---|---|---|---|---|---|
| 134 | 74% | **0** | 25 | 4 / **101** / 26 | 174.0 vs 164.5 |

(Replay latencies read 0: recorded answers return instantly. Live runs are the latency source of truth.)
Cue now never makes things worse than plain ⌘V on its own, but it only beats the bar on 4 steps. The 26 losses are steps where the persona knows the latest clip isn't it: the bar opens Spotlight, the Cue persona pressed ⌘V and had to undo.
P3 (running): "aware" persona — when the latest clip isn't what they want, the Cue persona presses the smart-paste hotkey (caret chooser, model-ranked, spans as their own rows), exactly where the bar persona opens Spotlight.

### R5 — decision policy (hotkey) + candidates (chooser search)

P3 live (aware persona, old hotkey policy): 77% correct, 5 wrong (4%) — 4 of 5 from the hotkey "weak unopposed leader" paste (shares 0.37–0.58), and the top-3 chooser rarely held the wanted clip (it sat at rank 2–14).
Changes:
1. Hotkey policy: deleted the weak-leader paste and the one-row chooser; an undecided hotkey shows up to 9 model-ranked rows (prob ≥ 0.02). CueEval replay: decider 87/1/18, decider-MLX 85/1/18 (unchanged); kev 91/2/48 (kev not the target).
2. `ChooserRows` (Options.swift) + chooser key handling (HUD.swift): letters filter *all* of history — every clip and every email/phone/URL span, beyond the model's 20-clip window — digits pick, Return takes the selection. Model ranking orders the rows; typing rescues a bad ranking. One pure function shared by the HUD and the harness.
3. Harness: whitespace-normalised comparison (single-line inputs reflow newlines; three plain pastes and one correct chooser pick were scored wrong).

| run | correct | wrong | missed | better / tied / worse | cue s vs bar s |
|---|---|---|---|---|---|
| P4 replay (policy 1 only) | 85% | 1 | 3 | 19 / 86 / 26 | 173.0 vs 164.5 |
| P5 replay (1+2+3) | **91%** | **1** | 3 | **29** / 86 / 16 | **136.3** vs 164.5 |

P6 live run in progress (replay leaves out the ~0.55 s live hotkey decision).

### P6 — live, R5 (aware persona, 9-row hotkey chooser with search)

| steps | cue correct | wrong | missed | wait p50 / p95 | better / tied / worse | cue s vs bar s |
|---|---|---|---|---|---|---|
| 134 | 91% | 1 (1%) | 3 | 0 / 598 ms | 29 / 91 / 11 | **153.1 vs 164.5** |

First run where Cue beats the bar on total time. Engineer still loses (61.7 vs 56.2 s). Blind critics dispatched on P6 (Sonnet 5.5, one per persona; packets `Evals/results/hill/blind-p6/`, A/B shuffled per step, keys withheld; scored by `blind.py --score`). Packet fix before dispatch: Cue's side now shows its trim keys and its after-undo route like the bar's side does.
Chooser visual check: rendered off-screen light/dark (`/tmp/cue-ui/`), search state gained a magnifying-glass header.

### R6 — field understanding + candidates (on P6's losses)

- Harness: WebKit's insertText applies smart quotes and non-breaking spaces (a real paste doesn't); comparison normalises them. Fixes 3 "plain paste scored wrong" steps and 2 chooser picks.
- Field understanding: a comma/semicolon list of addresses fits a To/Cc/Bcc field verbatim (founder pasted 8 investors into Bcc and got a chooser).
- Candidates: new `code` span kind — hex SHAs (7–40, not inside UUIDs/URLs), prefixed ids (`req_…`, `txn_…`), quoted/backticked names, amounts with thousands separators. Spotlight can't lift these out of a line; ⌘V + trim was beating Cue on 4 engineer/recruiter steps. Typed-field checks ignore code spans. 132 tests pass.
P7 live run (CueEval + persona days) in progress.

**P6 blind verdict (3 Sonnet 5.5 critics, unblinded with `blind.py --score`): Cue 28 · tie 95 · bar 11.**
- recruiter 12/33/1 (loss: 21 salary needed trim), founder 9/33/1 (loss: 33 Bcc list chooser), engineer 7/29/9 (losses 4 6 31: smart-quote artifact; 5 14 26: unextractable token; 8 19 45: wrong pick).
- 10 of 11 losses map to R6 changes already made; eng 8 (confident wrong hotkey pick) remains.
- Gap all three critics named: the hotkey path waits 277–735 ms before the chooser — noticeable every time. Next: one warm model call per field that serves both ⌘V and the hotkey (cache the model's answer, fold the mode's policy at use time).

### P7 — live, R6 (code spans, email lists, harness typography fix)

CueEval (decider MLX, live, 3×): 85% / 1% / 18% chooser on clear, p50 114 ms, p95 196 ms — code spans cost nothing on the synthetic suite.

| steps | cue correct | wrong | missed | wait p50 / p95 | better / tied / worse | cue s vs bar s |
|---|---|---|---|---|---|---|
| 134 | **99%** | **0** | **0** | 0 / 836 ms | **36 / 95 / 0** | **138.2 vs 164.5** |

No step slower than the bar. Remaining gap from the P6 critics: the hotkey waits for a live decision (p95 836 ms).

### R7 — model runtime: one warmed answer for ⌘V and the hotkey

`DecisionEngine.fetch` asks the hotkey's questions (pick + form) once; `decide(..., answer:)` folds any mode's policy over it. `DecisionPrefetch` now caches the model's answer (key: field identity + newest clip + history count, no mode) instead of a finished outcome, so the chooser-served-once bookkeeping is gone. Triggers warm in both trigger modes (local providers only). PrefetchTests: new `oneAnswerServesCmdVAndTheHotkey` (3 decisions, 1 provider call). 132 tests pass. P8 live in progress.

### P8 — live, R7 (shared warm answer)

| steps | correct | wrong | missed | ⌘V wait p50/p95 | hotkey wait p50/p95 | better / tied / worse | cue s vs bar s |
|---|---|---|---|---|---|---|---|
| 134 | 99% | 0 | 0 | 8 / 20 ms | 445 / 946 ms (P7: 725 / 995) | 35 / 63 / 33 | 129.8 vs 164.5 |

Fastest total yet, but 33 ⌘V steps lost their tie by 8–20 ms: `decide()` now ran before the instant-paste check, building every option and span (two `NSDataDetector`s created per call).

### R8 — model call + runtime: latency on real histories

- `decide()`: the "latest clip fits" check runs before any option is built (typed-field span check of one clip only). Data detectors built once (static), and the extract helpers route through them (−1 helper).
- Model latency on real days grows with history (hotkey decisions on the 134 persona contexts, decider MLX): <5 clips p50 123 ms; 15+ clips p50 720 ms, max 1229 ms — over the 1.2 s gate.
- Options cap 30 → 20 (typing in the chooser reaches the rest): 15+ clips p50 566 ms, max 735 ms.
- MLX server: a short yes/no row was padded to the 20-option pick row's length in one batch; rows now run separately past 50% padding waste: all-steps p50 552 → 486 ms, max 792 → 660 ms.
- Next lever: decider-0.8b is trained for a schema-first layout (options before the field state), so the options' KV prefix could be cached across fields until a new clip arrives; the MLX server doesn't implement it yet.
P9 live:

| run | correct | wrong | missed | ⌘V wait p50/p95 | hotkey wait p50/p95 | better / tied / worse | cue s vs bar s |
|---|---|---|---|---|---|---|---|
| CueEval 110×3 | 85% resolved | 1% | — | — | p50 112 / p95 192 ms | chooser on clear 18% | — |
| P9 days | 97% | 0 | 1 | **0.4 / 2.8 ms** | **220 / 542 ms** | 34 / 95 / 2 | **124.6 vs 164.5** |

Non-exact P9 steps: eng 38 (hotkey → model "nothing fits" → plain; the wanted Sentry link fell out of the 20-option cap — P7 at 30 options got it) and rec 23 (calendar "Guests" field not read as an email field → "nothing fits"). Fixes: "guests/attendees/invitees" read as email fields; the cap now drops only unpinned options (pins are always candidates — `last20PlusPins` caught it). Schema-first prefix cache dispatched (Devin) to make long option lists cheap again. P9 blind critics dispatched.

**P9 blind verdict: Cue 32 · tie 96 · bar 6** (recruiter 12/33/1, founder 10/33/0, engineer 10/30/5).
- rec 23: Guests field → fixed above. eng 38: option cap → schema cache pending.
- eng 4 6 19 45: the packet showed the text as WebKit re-rendered it (curly quotes, non-breaking indents), and the critic charged Cue with altering a stack trace / curl command — on 19 and 45 Cue was also faster (2.1 vs 4.2 s, 3.4 vs 4.2 s). Packet fix: a correct paste shows the text that was pasted. Fresh engineer critic re-dispatched on the corrected packet (`blind-p9b`).
- **Corrected (fresh engineer critic on `blind-p9b`, same shuffle keys): Cue 34 · tie 98 · bar 2** — engineer 12/32/1 (loss 38), founder 10/33/0, recruiter 12/33/1 (loss 23). Both remaining losses have fixes in the tree (R9: guests→email; schema cache to lift the option cap).
- R9 candidates also add standalone 6+-digit runs (account/order numbers) as rows — founder 28's account number inside a wire block needed a hand trim.
- Model choice on the current engine (P10-kev, live, GPU shared with a builder): kev-0.8b 97% correct, 0 wrong, 32/95/4, 123.6 s vs bar 164.5 — the same as decider-0.8b on the days (124.6 s). The engine now carries the persona days; the model decides the CueEval chooser gate, where kev shows the chooser on 48% of clear cases and decider on 18%. Default model: decider-0.8b on MLX.
- Model runtime shipped to the app (R9): `ModelCatalog.decider` is now a supported MLX shim (`decider_mlx_server.py`, decider-0.8b recommended, 2b listed; 35B MoE dropped). `ModelBenchmark.chooser` added and roles require `meetsGates` (p50 ≤ 500, p95 ≤ 1200, chooser on clear ≤ 20%); `benchmarks.json` gains decider (85/1, 112/192 ms, chooser 18%) and kev's row is refreshed to this session's numbers (92/0, 150/566 ms, chooser 48%). Result: decider is Recommended ("Most accurate"); kev no longer holds a role. The picker's top-level rows are now the role holders, not hard-coded kev/laya. New test `aModelThatLeansOnTheChooserGetsNoRole`. 133 tests pass. Pending: the shim passes `<port> <weights> <serveModel> <snapshot>` as argv; the server reads env — wire argv after the schema-cache builder releases the file.
- Gap named by recruiter/founder critics: a fragment that isn't an email/phone/URL/code token (e.g. an account number inside a wire block) still needs a hand trim.

### P10 — live, R9 (guests, digit runs, pin-safe cap) — latency contaminated

CueEval 85% / 1% / chooser 18% (p50 225, p95 466 ms — the schema-cache builder's parity runs shared the GPU, and it restarted :8791 near the end). Days: **99% correct, 0 wrong, 2 missed, 34 / 95 / 2, 121.6 vs 164.5 s.** Quality valid; latency not.

### R10 — model runtime: schema-first prefix cache (Devin swe-2-high; lead review)

`decider_mlx_server.py` mirrors decider's schema path: options/questions first, their prefix (attention KV + Qwen3.5 linear-attention state) cached LRU 8 / ≤1 GB, suffix-only forward for the field state; auto-on for `schema_first_trained` checkpoints, no knobs. Builder's measurements on 137 real request bodies: parity vs decider's torch schema path max |Δp| 0.0123, 0 flips; latency p50/p95/max 256/476/734 → **126/264/312 ms**, cache hits p50 **39 ms**, max 154 ms; idle 0.1% CPU, 386 MB; cold start 4.6 s. Note: schema-first answers differ from the old layout (26/232 pick flips, mostly none → decisive), so quality is re-measured in P11.
Lead: removed the builder's leftover launchd jobs (dev server :8793, proxy :8799, torch :8790); the server now also takes the model manager's argv (`<port> <weights> <serveModel> <snapshot>`), verified on a spare port. P11 (clean, live, schema-first server):

| run | correct | wrong | missed | ⌘V wait p50/p95 | hotkey wait p50/p95/max | better / tied / worse | cue s vs bar s |
|---|---|---|---|---|---|---|---|
| CueEval 110×3 | 85% resolved | 1% | — | — | p50 108 / p95 177 ms | chooser on clear 18% | — |
| P11 days | 99% | 0 | 1 (eng 38) | 0.4 / 2.7 ms | 239 / 458 / 901 ms | 35 / 95 / 1 | **116.9 vs 164.5** |

Server stats over the run: 116 schema hits / 118 prepares. The harness warms a fresh `DecisionPrefetch` per step, and most persona steps follow a new copy, so the schema prefix is usually new; in the app consecutive fields share a clipboard state and hit. P12 (option cap back to 30 for eng 38) and P11 blind critics running.

**P11 blind verdict: Cue 35 · tie 98 · bar 1** (recruiter 13/33/0, founder 10/33/0, engineer 12/32/1 — loss: eng 38). Critics' remaining gap: the hotkey still waits 90–460 ms before the chooser.

P12 — options cap 30 (live): CueEval 82% / 2% / 17%, days 97% correct, 1 wrong, 1 missed, 127.4 s, hotkey p50 378 ms. **Lose → reverted to 20.**
P13 — hotkey shows rows even when the model says nothing fits (replay): days 99% / 0 / 0 misses, 109.1 s, but CueEval wrong 3%, chooser on clear 43% → gates broken. **Lose → reverted.**

### R11 — eng 38 root cause (candidates + field understanding)

The person typed "Sentry:" and pressed the hotkey; the Sentry link was 12 clips back, but the code spans of newer clips (a log line, a JSON blob) filled the 20-option cap, and the context signal never looked at what the person had typed. Changes: (1) over the cap, the oldest code spans go first, then whole clips; (2) `ContextSignal` also reads the last 40 characters of the field's value; (3) hotkey "nothing fits" yields to a unique context signal (chooser, signal first). CueEval replay on R10 answers: 85% / 1% / chooser 20%. 133 tests pass (one racy prefetch assertion fixed).

P14 (live, all three R11 changes): CueEval 82% / 2% / 17%; days 95% correct, 2 wrong (eng 7, rec 30), 1 missed, 31/95/5, 125.7 s; hotkey wait p50 211 / p95 314 ms. Regression.
P15 (isolation, replay of P11 answers, code-span-first trimming reverted, signal changes kept): CueEval 85% / 1% / chooser 20%; **days 99% correct, 0 wrong, 0 missed, 36 / 95 / 0, 109.1 vs 164.5 s** — eng 38 now solved by the caret text. Verdict: (1) code-span-first trimming **loses → reverted**; (2)+(3) value-aware signal and signal-over-nothing-fits **win**. P16 live confirmation: CueEval 82% / 2% / 17%; days **91% correct**, 1 wrong, 7 missed (mostly hotkey → "nothing fits"), 25/95/11, 130.9 s; hotkey wait p50 45 ms.
Diagnosis: the schema-first cache changes the *answer*, not just the speed. The server serves a schema state-first on first sighting and schema-first once seen twice, and the two layouts answer differently (builder measured 26/232 pick flips). P11 ran on a fresh cache (mostly state-first); P16 ran on a cache warmed by P12–P14, so most hotkey answers came from the schema-first layout, which over-abstains on these contexts. The same request answering differently depending on cache history is a correctness bug, whatever the speed. P17: server restarted with `DECIDER_SCHEMA_CACHE=0`, live: CueEval 85% / 1% / 20%, p50 111 / p95 191 ms; days **99% correct, 0 wrong, 1 missed, 35 / 95 / 1, 119.2 vs 164.5 s**, hotkey wait p50 232 / p95 386 ms. Confirmed. **R10 schema-first cache: lose → deleted** (Sonnet 5.5 removing the code path with a byte-identical replay check against the cache-off server).

### R12 — candidates: the caret names a clip the cap dropped

eng 38 live still missed: with the code-span trim reverted, the Sentry link is outside the 20 options, so the caret signal had nothing to point at. Change: words of 4+ letters in the last 40 characters of the field's value pull up to two clips from the recent window back in as options, appended after the regular 20 (ids c1… unchanged); unscored options rank last at probability 0, and the chooser can lead with the signal-named option even when it wasn't among the scored rows. New test `wordsBeforeTheCaretBringBackAClipTheCapDropped`; 134 tests pass.
P18 (replay of P17 answers): CueEval 85% / 1% / 20%; **days 99% correct, 0 wrong, 0 missed, 36 / 95 / 0, 110.7 vs 164.5 s.**
P19 (live, schema code deleted, kev server stopped): CueEval 85% / 1% / 20%, p50 115 / p95 192 ms; days 99%, 0 wrong, 1 missed (eng 38 again), 35/95/1, 118.6 s; ⌘V wait p95 3 ms, hotkey p50 230 / p95 354 ms.
**Surprise (harness bug):** P18's eng 38 "fix" was an artifact. A warm-up whose answer is never used (step 37 is a generic ⌘V) kept running and was recorded under step 38's id, so replays of 38 got 37's answer. Every replay since R7 may have mixed answers this way; live runs were unaffected. Fix: `DecisionPrefetch.settle()` and the harness awaits it after each step (decision time is still measured at the outcome).
Real eng 38 cause: with "Sentry:" typed, the model says none 0.80, and the context signal pooled the caret words with the window title "Active issues - Halyard - Google Chrome" — "halyard"/"issues" match half the history, so no option was unique. Fix: the caret text gets the first say (`uniquePick` on the last 40 characters alone), full context only as a fallback. CueEval replay 85% / 1% / 20%; 134 tests pass.
Harness perf: the window-identifier search was recursive and walked every page's AX tree each step (a run took >80 min); windows are now found among the app's direct children (run: 6.5 min).

**P20 — live, all three days:**

| steps | correct | wrong | missed | ⌘V wait p50/p95 | hotkey wait p50/p95/max | better / tied / worse | cue s vs bar s |
|---|---|---|---|---|---|---|---|
| 134 | 99% (1 trimmed) | **0** | **0** | 0.6 / 2.6 ms | 217 / 351 / 359 ms | **36 / 95 / 0** | **115.6 vs 164.5** |

CueEval (P19, same engine except the caret-first signal, replayed 85/1/20): 85% resolved, 1% wrong, 20% chooser on clear, p95 192 ms. P20 blind critics dispatched.

**P20 blind verdict (3 fresh Sonnet 5.5 critics, A/B shuffled per step, unblinded by `blind.py --score`): Cue 36 · tie 98 · bar 0** — recruiter 13/33/0, engineer 13/32/0, founder 10/33/0. No persona step where the bar wins. Ties are the 95 "paste what I just copied" steps, where Cue lands the same text in the same time as plain ⌘V (the goal's "or plain ⌘V happens exactly as if Cue were not there").
Gaps the critics still name (not losses): the hotkey path waits 190–360 ms before the chooser and asks for a glance and a digit; older clips the model ranks low still need 4 typed letters; a stale clip lands in a password field on a plain paste (same on both sides — the secure-field invariant pastes the latest clip without reading the field).

Gates on the final engine (2026-10-19):

| gate | target | measured |
|---|---|---|
| chooser on clear (CueEval, live, 110×3) | ≤ 20% | **20.0%** (r20) |
| wrong pastes | ≤ 2% | **1%** CueEval, **0%** persona days |
| p95 decision latency | ≤ 1.2 s | CueEval **188 ms**; days: ⌘V **2.6 ms**, hotkey **351 ms** |
| cold-start stall | none | model server down → every ⌘V decides in ≤ 12 ms as a plain paste, 0 wrong (CueEval intercept vs a dead port); server starts with a warm-up request (4.1–4.6 s to first answer) |
| idle CPU / energy | near zero | Cue app 0.0% CPU, 0.0 power, ~28 MB; decider MLX server 0.1% CPU, 0.1 power, 3.0 GB resident |

Cue app idle (measured, release build, isolated `CFFIXED_USER_HOME=/tmp/cuehome`, 60 s, `top -stats cpu,power,idlew`): **0.0% CPU, 0.0 power, ~28 MB**, idle wakeups ≈ 4–5 per 10 s sample. The app is already near zero; the idle cost is the model server (kev 0.3% CPU, 3.2 GB RSS).
Isolation check: the real `com.local.cue` defaults (backup `/tmp/cue-real-defaults-backup.plist`) and `history.json` were unchanged after the run.

### R13 — model runtime, candidates, daily-use gaps (2026-10-19, off-screen; live lane blocked)

- **Runtime (win, ships):** the MLX server batched the 300-token `form` row with the 1450-token `pick` row, padding the short one to full length. Its "split past 50% padding" rule could never fire for two rows. Rule now: split when padded tokens exceed 1.2× real tokens. Same 44 recorded requests: answers byte-identical (88/88); two-question request p50 875 → 450 ms. Days: hotkey wait p50 218 → 147 ms.
- **Candidates (ships):** quoted code spans matched the text between any two quotes, so one JSON blob became 10 options (`status`, `currency`, `:12500,`) that crowded real clips out of the 20 slots. Quotes now pair; JSON keys and punctuation-edged fragments are dropped. Chooser search ranks rows whose own text has the query above spans found only through their clip ("curl" → the curl command, not its URL span). P22 days: 134 steps, 0 missed, 1 wrong (eng 8: model 0.67 on the branch name `kofi/hal-482-…` in the HAL-482 comment box; the PR link was wanted — the junk spans had been diluting that leader below threshold). 35 better / 95 tied / 1 worse (eng 8). CueEval live: 85% / 1% wrong / chooser on clear 20.0% / p95 238 ms. Tried and **deleted**: threshold 0.75 (CueEval chooser 22%), raw-probability floor (32%).
- **Daily-use gaps from the critique (ship, no benchmark needed):** concealed/transient pasteboard copies are no longer recorded; hotkey timeout 10 s → 2.5 s, and a dead model on the hotkey now opens the recent-history chooser instead of pasting the clip the user skipped; unreadable `history.json` is moved aside instead of overwritten; span detection scans at most 20k characters.
- **Live lane:** this Mac was locked 08:30–15:22, then in use. The Mac mini (`ssh mac-tailscale`, M4 16 GB, unlocked) can build and run, but nothing launched over SSH has Accessibility; Cue on the mini needs one grant in System Settings → Privacy → Accessibility. Keystrokes can go through the mini's already-granted CuaDriver daemon.

### R14 — real-app lane on the Mac mini; chooser and policy seams (2026-10-19)

- **Live lane moved to the Mac mini** (`ssh mac-tailscale`): Cue and the driver both run under the user's one Accessibility grant (`com.local.cue`, signed with the same Apple Development cert; the driver is wrapped as an app with that identifier and launched through `open`). Pages open through Launch Services (no Apple Events grant needed), ⌘W closes each step's tab. Model reached through an SSH reverse tunnel to this Mac's :8791. Spotlight steps on the bar side stay computed (no Spotlight clipboard history on macOS 27).
- **live-mini1** (all three days, both sides): cue — recruiter 43/45 (1 trim, 1 X), engineer 42/44 (2 X are Terminal wrap read-back artifacts — the bar side fails the same steps), founder 42/42; ⌘V wait p95 22 ms; hotkey p50 786 / p95 2105 ms.
- **Runtime (win, ships):** the server computed requests Cue had already cancelled, so a paste queued behind stale warm-ups. It now drops a request whose client disconnected before its GPU turn (139 dropped in one run); a paste whose prefetch key misses cancels the stale warm-up. **live-mini2:** hotkey p50 786 → 317 ms; p95 still ~2.0 s (a stale call already on the GPU can't be preempted; the MacBook GPU behind the tunnel was in use).
- **Chooser seam (fixed):** a resting pointer hovered row 9; typing "0143" filtered to one row and Return found the selection out of range → "declined" → pasted the latest clip. Return now takes the nearest row. Found by replaying steps 1–29 with key logging on the mini.
- **Search starting with 1–9 (fixed):** a digit waits 180 ms; a second key in that window makes it a search ("1291"), Return confirms the pick, Esc drops it.
- **Linear comment / eng 8 (fixed):** the model's 0.67 leader was the branch `kofi/hal-482-duplicate-ledger-entries-on-retry`, which restates the page title. A whole-clip leader sharing 4+ words with the window title now goes to the chooser (spans exempt). Replays: CueEval 85% / 1% / chooser on clear 20.0% (unchanged); days 133/134 correct, **0 wrong, 36 better / 95 tied / 0 worse**.
- **Incident:** an external cleanup agent deleted the HF cache, `~/Library/Application Support/Cue` (decider venv, real history) and reset all tracked uncommitted files at 18:16. Code restored from T3 checkpoint `25d8e3b` (18:12); decider weights re-downloaded; the decider venv is gone, so `cue.eval.decidermlx` won't survive a restart until reinstalled.
- **Open:** hotkey p95 on the mini; blind critics on the live traces.

### R15 — user feedback + blind product audit (2026-10-19)

- **Gmail To: pasted "weiuhfhuew hridayahoney@gmail.com" whole (fixed):** a decisive model pick ran before the typed-field rule. In email/phone/URL fields a leader that isn't that kind now loses to the matching span. Two old tests pinned the wrong behaviour and were retargeted.
- **Chooser showed an 18-day-old clip (fixed):** the model now sees only clips from the last 12 h (plus pins and the latest clip); typing still searches all history.
- Replays after both: CueEval 85% / 1% / 20.0% (unchanged); days 133/134, 0 wrong, 0 worse.
- **Blind audit** (screenshots only, Sonnet 5.5): first-run 5, craft 5, chooser 6, settings/history 4. Top defects: model step had no Continue and no default; vendor/plumbing jargon (ports, params, "jev-latest"); salmon chooser selection; 9 pt hints; generic row icons; history dead space; unreadable "Waiting for ⌘V…"; stray coral arc; pink used for two meanings.
- **Shipped this round:** one fixed footer on every step (the clipped Continue: the model/permission steps put it inside scrolling content); model step defaults to On this Mac + recommended model; consistent "‹ Back"; title period; directional step transitions (18 pt, 280 ms strong ease-out, crossfade under Reduce Motion). Verified in `output/audit/v2-sheet.png`.
- **Audit fixes, round 2 (verified in `output/audit/v3-*.png` on the mini):** chooser and picker use the system accent with white text, real source-app icons, 11 pt hints that lead with "↩ paste"; Settings cards say "Runs on this Mac · ~1.6 GB download · ~3 GB memory" (no params/ports), "Selected"/"In use" pill, title-case meters, Decider blurb in plain words; onboarding model card drops the weights picker and duplicate size line; practice step hides the footer button while waiting and shows "Now press ⌘V" as a keycap, success label springs in; History search pinned to the top, empty state names the shortcut; the coral curl and its rect plumbing deleted; redaction placeholders use a neutral chip so coral means only "the detail Cue found"; toggle reads "Hide names and emails from hosted models"; recorder stays live in ⌘V mode (it still opens the chooser there) with copy saying so.
- **Idle (R15 build, release, Mac mini, 30 s after launch):** Cue 0.0–0.1% CPU, power 0.1–0.2, ~3.4 idle wakeups/s (the 4 Hz pasteboard poll + 1 s trust poll), 121 MB. Decider server on this Mac: 0.1–0.2% CPU, 3.1 GB resident.
- **Blind critic on the real-app runs** (live-mini2 Cue side vs the bar; Sonnet 5.5, packets `Evals/results/hill/blind-live2`): **Cue 30 · tie 94 · bar 7.** Bar wins: eng 3 and 25 (Terminal wrap read-back artifact — correct pastes), rec 29 (hover/filter Return, fixed in R14), eng 42 (digit search, fixed in R14), eng 7 and 26 (hotkey waited 1.8–2.0 s — the deferred latency item), eng 39 (hotkey + model "nothing fits" pasted the latest clip). Open design question for eng 39: the hotkey means "not the latest", but CueEval's no-fit cases expect a plain paste and grade a chooser as wrong.
- **UI critic round 2** (fresh Sonnet 5.5, new screenshots only): first-run 5, craft 5, chooser 6.5 (+0.5), settings/history 4.5 (+0.5). New real defects fixed and verified (`output/audit/v4-sheet.png`): highlight chips covered the spaces around words ("toMiraat") → inset narrower than a space; practice step with no model was a dead end → primary "Set up a model" returns to the model step; History empty state names ⌘V in ⌘V mode; chooser icons 16 → 18 pt. Disputed: "^⌥V" is already the ⌃ glyph (U+2303), it reads as a caret at the mini's 1080p. Still open from round 2: Settings has no toolbar sections (General/Shortcuts/Model/Privacy) — a larger restructure; no permission step was captured (the mini was already trusted).

### R16 — the hotkey never answers with the latest (user decision, 2026-10-19)

- eng 39 (live): hotkey + model "nothing fits" pasted the latest clip, the thing the hotkey exists to avoid. Now an unsure or "nothing fits" hotkey shows up to 9 ranked rows; Esc still plain-pastes.
- CueEval triggered nearly every case as a hotkey, including ~20 where the wanted text is the latest clip. User-approved rule change to match the persona days: ⌘V when the wanted text is the latest (or a plain paste), hotkey otherwise; a hotkey no-fit chooser scores as resolved. Replay (r22 answers): **92% resolved / 1% wrong / chooser on clear 15%** (was 85 / 1 / 20 under the old rule and behaviour).

### R17 — Settings as a Mac settings window (2026-10-19, user-chosen next item)

- Inventory → keep / move / delete. **Deleted:** the confidence slider (engine default moved 0.6 → 0.7, the measured value the app was already using) and the "When unsure" picker (it was dead: nothing read `lowConfidenceMode`). **New:** Clear History… (pins kept, confirmation), Ignore copies from = an app list with Add App… instead of a bundle-ID text field.
- Window: `NSTabViewController` in toolbar style, panes General / Shortcuts / Model / Privacy; Model pane fixed at 560 pt and scrolls (it was growing past the screen). Shortcut rows show the live default instead of "Record"; actions renamed (Show choices, Search history, Turn queue on or off, Open Settings, Plain paste). Verified on the mini: `output/audit/settings-v1.png`, `settings-v2.png`, `settings-v3-shortcuts.png`.
- Task clicks, before → after: change a shortcut 2 + scroll → 2; switch to hosted 1 → 2; redaction off 2 + scroll → 3; clear history impossible → 3. Not yet run: a blind critic against a native app's settings window.

### R18 — "weiuhfhuew hridayahoney@gmail.com" went through whole, again (user report, installed build)

- **Root cause 1 (real-world only):** Cue never asked Chromium browsers (Helium, Chrome) to publish web fields over Accessibility. My live driver did, so every test saw labels; the user's browser gave Cue an unlabelled field = "generic" = verbatim paste. Fix: `ContextCaptor.enableWebAccessibility` (`AXManualAccessibility`) at app activation and before capture.
- **Root cause 2:** the model path was the only way to reach the typed-field rule, so a slow/unreachable model meant a plain paste. A typed field with exactly one matching option now pastes it with no model call (the policy already forced that outcome). Reproduced on the mini with real ⌘V and no model reachable: before, whole clip landed; after, `hridayahoney@gmail.com` in 32 ms.
- Tests 138 pass (5 fixtures given a second address or a non-email field so they keep exercising the model/failure paths). Replays: CueEval 92/1/15 (unchanged); days 133/134, 0 wrong. Installed to `/Applications/Cue.app` and relaunched.
- Lesson: the harness must not do work the product doesn't (enabling AX). Keep the live driver's AX enabling off for Cue-side checks on real browsers where possible.
- **R18b — "accessibility is enabled??" (it was; the cause was Helium):** probed Helium over AX from this Mac. Helium (Chromium fork 0.19.4.1) exposes only its own chrome (toolbar, tab strip) — no `AXWebArea` — and rejects `AXManualAccessibility` (-25205, the one switch Cue set). It accepts `AXEnhancedUserInterface` (returns -25208 but works: within 1 s the web area appeared and the focused field became readable). Cue now sets both: `AXManualAccessibility`, then `AXEnhancedUserInterface` only for Chromium-style bundles ("* Framework.framework"), since that one also disables window animations in native apps. Menu-bar breadcrumb for plain pastes now says which field Cue saw ("no field visible to Cue" / "unlabelled field" / "field “To recipients”"). Not verifiable end to end without restarting Helium (the probe left it enabled for this session). 138 tests pass; installed to /Applications.

### R19 — real-machine inputs (2026-10-19, user report: "core barely works, chooser in nowhere")

- Probed the installed app in the user's Helium. Found: system-wide AXFocusedUIElement fails (-25204) while the app element answers; Chromium caret rect is a zero rect at the page corner and the chooser anchored there; a smart paste left its pick on the pasteboard so the next plain ⌘V pasted it while the engine judged the latest copy (CueDay never used PasteExecutor, so no benchmark could see it); the user ran unbenchmarked laya-multi; 9 of 55 history clips were test probes; the in-app decider install lacked fastapi/uvicorn and could never start.
- Fixed all six (`28fdda8`). Verified live in Helium: chooser directly under the To field (`/tmp/cueprobe/shot2.png`), Return pasted the email span, clipboard came back to the original copy. 138 tests pass. User switched to decider (in-app, :8790). History backup: `history.json.bak-20261019-2025`.
- Not verified: ⌘V after a pick in the Message field (the user took the screen back mid-test; no more keystrokes sent). Other shim models may share the missing-dependency bug.
- Next: the real-app gate (installed app, ~20 real fields, top 8 apps, Cue does its own AX work), run on the Mac mini, not the user's live session.

### R20 — learning removed, chooser traps, 15-minute window (2026-10-19, user decisions)

- **Per-clip learning deleted.** It rewarded every paste not undone by ⌘Z within 2.5 s; the user's `feedback.json` had +4 (max 1.5× boost) for `weiuhfhuew hridayahoney@gmail.com` in Gmail To. User: most pastes are new text, so per-clip memory rarely helps. Removed from engine, prefetch, controller, settings, CueDay.
- **Second ⌘V within 1.4 s plain-pasted:** the "Pasted" toast counted as an open chooser. `isShowingChoices` now means a chooser/picker waits for keys.
- **Chooser trapped the keyboard:** a click elsewhere in the same app left it up, eating every key. Any outside click now closes it; ⌘/⌃ shortcuts close it and pass through.
- **Placement in tall editors with no caret:** anchors at the pointer inside the field, else its top-left, not the far edge.
- **Model window 12 h → 15 min** (user: choices make sense for a burst of copies; older is a search). CueEval live (decider, 110×1): 92% / 1% wrong / chooser on clear 13% (unchanged). Replay is unreliable for option-set changes: answers are keyed by option id.
- Not live-verified: outside-click close, shortcut pass-through, tall-editor anchor (no GUI lane used; the user's Mac was in use).

### R21 — catalog re-measured, menu bar panel redesigned (2026-10-19)

- **Benchmarks re-run live under the R20 engine** (CueEval, 110×1). New `CueEval --serve <model[:variant]>` installs and starts a model through the app's own ModelManager, so a broken install fails in the benchmark (the decider missing-deps bug would have shown here). All six installs worked.
  decider 92/1 p95 249 · kev 90/5 249 · kenning 90/4 634 · laya-typed 90/4 319 · von 89/4 204 · jevk5lite 89/4 353 · laya-multi 84/3 102 · s1qwen 83/4 199 · laya-en 82/3 343 (resolved % / wrong % / p95 ms).
  Gotcha: `laya_server.py` picks weights by the request's model name and silently falls back to laya-en for unknown names.
- **Roles rank speed by p95**: p50 is 0 ms for every model now that most pastes never ask it. benchmarks.json holds only these live rows. Roles: Most accurate decider, Best balance von, Fastest laya (laya-multi is now laya's default variant). Runners-up sit within noise of each other (±4 pts) and all paste wrong about 4× as often as decider.
- **Menu bar panel rebuilt** (`MenuBar.swift`): plain status header (last action in its tooltip), clipboard card, Recent (15 min) / Earlier groups, kind glyphs + source icons, link-middle/prose-tail truncation, hover pin/delete, ↩ on the selected row, one ⌘V segmented control (system accent, coral gone), labeled footer + ⋯ menu (Pause, Quit ⌘Q), 18 pt bottom fade. `MenuPanel` draws plain values so it renders off-screen without the live app. Critic (Sonnet 5.5, screenshots only): before 3–5, after 6–7; fixes applied for alignment, contrast, fade, icons, accent, light-mode field.
- Not verified in the live menu bar (the user's Mac was in use): hover actions, keyboard nav, the ⋯ menu.
- **Roles cut to two (user call, R21b):** Most accurate (decider) and Smallest (laya-multi, 0.7 GB). No speed role: every model answers within ~250–650 ms at p95 and most pastes never ask one. No balance role: every mid-size model is less accurate than decider and about as large (1.4–2.0 GB vs 1.6 GB). Onboarding headlines only the role holders; meters use p95. Onboarding model step not re-rendered.

### R22 — panel round 2; measurement corrections (2026-10-19)

- **Panel:** hover no longer scrolls the list (only arrow keys do; hovering a row selected it and `scrollTo(.center)` made the list jump under the pointer — seen on the user's screen). Header removed, search first; status dot + word in the footer (details in its tooltip); rows lead with the source app icon; sections Pinned / Recent (15 min) / Today / Older; one highlight glides between rows (matchedGeometryEffect, off under Reduce Motion); links read host + path, codes and numbers monospaced; dates past a week read "1 Oct". Critic round 2 (Sonnet 5.5): current 4–5 → new 6–7; its point-size and vibrancy notes were misreads of 2× off-screen renders.
- **Correction:** the R20 "15-minute window: 92% / 1%, unchanged" was a stale binary — `swift build --product A --product B` built only the last product. True decider numbers by window (110×1, :8791): 15 min 87/4 · 1 h 88/3 · 2 h 92/1 · 12 h 92/1. Suite clips are at most ~2 h old, so 2 h = 12 h by construction. Other models in R21 were measured on the 15-minute engine.
- **Memory (top footprint, peak while answering):** jevk5lite 0.7 GB · s1qwen 2.7 · kenning 3.2 · decider 3.7 · von 3.8 · kev 4.0 · laya 6.3 (its server loads all three variants). RSS undercounts MLX models (decider read 139 MB); use footprint. Disk size is the wrong "Smallest" measure.
- Removed SEEDED-CLIP-1421 and PASTEMARKER from the user's history (backup kept).
- Open: user to pick the window; then re-measure every model on that engine and set roles on memory (Most accurate / Best balance / Smallest).
