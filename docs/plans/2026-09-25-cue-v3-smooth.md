---
agent: devin-local
session: turquoise-starfish
created: 2026-09-25T19:59:04Z
---
# Cue v3: onboarding that matches the references, a benchmark, and a smoother engine

Build a real benchmark first. Use it to rebuild how Cue picks what to paste: span-level options from the last 20 clips, richer field context, rewritten prompts, and a caret-anchored top-3 chooser when several options fit. Rename the model picker to benchmark-backed roles (Best balance / Most accurate / Fastest), and bring the onboarding to match the six reference images as closely as possible.

## Decisions locked with the user

| Topic | Decision |
|---|---|
| Ambiguity (e.g. 100s of emails) | Split clips into **span options** (whole clip + every email/phone/URL). Offer only the **last 20 clips + pins**. Use **richer field context**. When several options fit, show a **caret-anchored top-3 chooser** at the field. |
| Model call | **Always** call the model (no deterministic skip). The model ranks; the chooser shows its top 3. |
| ⌘V intercept | If the latest clip fits (`use_latest`), paste it instantly. If it doesn't fit and several options fit, show the chooser. Otherwise plain paste. |
| Chooser style | Native vibrancy list under the caret, 3 rows: value in bold, then quiet context (source app · age / snippet). Keys 1/2/3 or ↑↓+Return; Esc = plain paste. |
| Benchmark models | Von, Kev 0.8B, Laya, Jevons, jev-lite, Jev hosted (direct + gateway if keys exist). |
| Speed bar | Hotkey → paste or chooser visible: **p50 ≤ 500 ms, p95 ≤ 1.2 s** for the default model. |
| Model rows | Three **role rows**: *Best balance / Most accurate / Fastest*. Each is filled by the benchmark winner for that role and explained in plain words; the model name is secondary. |
| Visual fidelity | **Images as closely as possible.** Images win on looks: fold, colors, buttons, radios, Back, in-panel primary on Access/Models, colored tiles. Truth rules stay: real catalog data, real hotkey string, observed success only. |
| Onboarding teaches chooser | Yes. After first success, Practice offers a "Try another" round that shows the real chooser. |
| Baseline | Commit the current ~770-line uncommitted polish pass first. |

## Why (root causes found)

- **Ambiguity is unsolvable today.** `SmartPasteController.smartPaste` sends `store.candidates()`, which is **40 clips** as 80-character previews. `Transform.extractEmail` returns the **first** email only. `pick` and `transform` are separate parallel questions, so the transform doesn't know the pick. The context is just label/placeholder/value/window title (`ContextCaptor.capture`). Web fields often have an empty `AXTitle`.
- **Sluggish.** It sends 40 candidates every time. Remote redaction runs per line with no cache. There's a 10 s provider timeout, and a top-of-screen "Deciding…" toast at 400 ms.
- **Inaccurate, but unmeasured.** `Scripts/eval_systemone.py` has 7 easy cases, and its prompts are not the shipped ones (`DecisionEngine.questions`). `WeightSpec.accuracy/speed` are editorial guesses.
- **Onboarding vs references** (compared the refs with `output/onboarding/n*.png` / `06-practice-result-dark.png`):
  - Fold is a coral "smile" (`FoldArrowShape`). The refs show the lower sheet's top corners flaring outward plus a thin coral curl dropping from the highlight into the seam, with no arrowhead.
  - The highlight sits too low and too tall. `ParagraphNSView.highlightRects` uses `enumerateEnclosingRects` (the full 1.4× line box), not the glyph bounds.
  - The canvas is too grey; the refs are near-white with a subtle off-white upper sheet.
  - The primary renders grey (disabled opacity / inactive window) instead of a blue gradient.
  - Back is a chevron pill; the ref is a bordered rounded rect with the text "Back".
  - Radios are outline rings; the refs are filled blue with a white dot. The segmented control is native grey; the ref is a white pill on a light track.
  - There's big dead space above the footer. Title/wordmark sit too low. The window is 760×620 vs the spec's 760×580.
  - Models: the lower panel is clipped by the footer, and a real error "The file 'repo' doesn't exist" appears. `ModelManager.start` is called on an uninstalled repo-kind model: `cwd` is `models/kev/repo`, which doesn't exist.
  - Trigger: the copied message is not in a grey inset box, the lower caption is centered (the ref is left-aligned), and the recorder shows a focus ring by default.
  - Practice success: the ref puts "✓ Email pasted" inside the field on the right, "Try Website" as a bordered button beside the field, and a centered hint below.

## Architecture

```
hotkey/⌘V ─► ContextCaptor.capture()  (+ nearby text, AX label elements, web host; 50 ms AX timeout)
          ─► OptionBuilder.options(clips: last 20 + pins)  → [PasteOption]  (spans, deduped, ≤ 30)
          ─► DecisionEngine.request(...) → provider.evaluate  (one call: pick [+ use_latest])
          ─► DecisionPolicy.outcome(ranked, useLatest, mode, threshold, margin)   ← pure, offline-rescorable
          ─► .paste(option) | .choose(top3) | .pasteLatest(reason)
          ─► PasteExecutor / ChooserPanel (caret-anchored)
```

- **Model chooses, we execute** still holds. Options are deterministic spans; the model only picks an option key. The `transform` question is **removed**. Extraction happens during option construction; `digits_only`/`lowercase`/`strip_url_tracking` are dropped from the model's job.
- There is one prompt source (`Prompts` in `Decide.swift`). The eval calls the same `DecisionEngine`, so **measured prompts = shipped prompts**.
- There are no new dependencies. The eval is a new SwiftPM executable target inside this package.

## Phase 0 — Baseline (sidekick)

1. `git add -A Sources Tests Package.swift docs/design/onboarding/*.md` (not `output/`), then commit "Onboarding polish pass (baseline before v3)". Run `swift build && swift test` first; record the test count.
2. Copy this plan to `docs/plans/2026-09-25-cue-v3-smooth.md` (writing-plans location) and commit.

## Phase 1 — Benchmark (lead authors dataset + scoring + runs; sidekick does plumbing)

**Files:** Create `Sources/CueEval/main.swift`, `Evals/cases.jsonl`, `Evals/results/` (gitignored except `summary.md`). Modify `Package.swift` (add `.executableTarget(name: "CueEval", dependencies: ["CueKit"], path: "Sources/CueEval")`). Test: `Tests/CueKitTests/EvalScoringTests.swift`. Delete `Scripts/eval_systemone.py` once parity is shown, and update the AGENTS.md command.

**Case schema (JSONL, one per line):**
```json
{"id":"amb-mail-thread-01","category":"ambiguous-signal","mode":"hotkey",
 "context":{"app":"Mail","bundle":"com.apple.mail","window":"Re: Q3 roadmap — Priya Shah",
            "field":{"role":"AXTextField","label":"To:","placeholder":"","value":""},
            "nearby":"From: Priya Shah · Subject: Q3 roadmap"},
 "clips":[{"text":"priya.shah@acme.com","app":"Slack","age_s":90},
          {"text":"me@gmail.com","app":"Notes","age_s":400},
          {"text":"random@shop.io","app":"Safari","age_s":30}],
 "expect":{"paste":"priya.shah@acme.com"}}
```
The `expect` kinds are `{"paste": X}`, `{"choose": [X, Y, ...]}` (true ambiguity; any of them is acceptable), and `{"plain": true}`.

**Categories (~110 cases, lead-authored, synthetic data only, no real history):**

| Category | ~n | Purpose |
|---|---|---|
| single-message extraction (email/phone/URL from one paragraph, incl. onboarding samples) | 15 | the core story |
| multi-span in one message (2 emails; pick by field + nearby text) | 10 | old first-span bug |
| ambiguous-with-signal (Mail thread / Slack DM / Jira work form vs personal signup) | 20 | richer context payoff |
| ambiguous-no-signal (3 emails, bare "Email" field) | 10 | must **choose**, never confidently guess |
| typed fields (name, zip, address, order #, tracking #, code → editor, prose → chat body) | 20 | breadth |
| 20-clip noisy history | 10 | scale/latency |
| intercept: latest fits → plain; latest doesn't fit → pick/choose | 15 | ⌘V contract |
| none fits (terminal, search box, captcha-ish) | 10 | abstain |

**Scoring (pure `EvalScore.score(outcome:expect:latest:)`, unit-tested):**
- `paste` expected: `.paste(X)` = **exact**. `.choose` containing X = **resolved-by-chooser**. `.paste(other)` = **wrong** (worst). `.pasteLatest` = **miss** (unless X == latest text → exact).
- `choose` expected: `.choose` whose top 3 contains any expected = **exact**. `.paste(x ∈ set)` = **lucky guess**, counted separately. `.paste(other)` = **wrong**. Plain = miss.
- `plain` expected: `.pasteLatest` or `.paste(latest)` = exact. Else wrong.

**Metrics per endpoint × config:**
- exact %, resolved % (exact + resolved-by-chooser)
- **wrong-paste %** (the smoothness killer)
- chooser rate on unambiguous cases, lucky guesses
- p50 / p95 / max latency of `decide()` (includes redaction for remote, as shipped), errors
- Each case runs 3× for latency.

**Runner:**
```
swift run -c release CueEval --cases Evals/cases.jsonl \
  --endpoint von=http://127.0.0.1:8766,von-1.0 \
  --endpoint jev=https://api.typesafe.ai,jev-latest,env:TYPESAFE_API_KEY \
  --engine baseline|v3 [--prompt A|B|C] [--record Evals/results/raw-<date>.jsonl]
swift run CueEval --rescore Evals/results/raw-<date>.jsonl --threshold 0.5...0.8 --margin 0.1...0.4
```
- `--record` saves the raw answers so thresholds and margins can be swept offline without re-querying.
- Output: a markdown table to stdout and `Evals/results/summary.md`.
- Keys are only read via `env:`; they are never printed or written.

**Model servers (sidekick, one at a time, RAM):**
- Von is already installed.
- Kev 0.8B, Laya, Jevons, and jev-lite go through `ModelManager`'s exact argv (or the app UI).
- Record any install failure verbatim; Decider is unsupported and skipped.
- **Lead-only:** ask the user to `export TYPESAFE_API_KEY=…` (and the gateway key if wanted) in the eval shell.

**Step order:**
1. Scoring test (red) → scoring impl (green).
2. Harness against a stub provider (unit test: a canned response scored correctly).
3. Dataset.
4. Run the **baseline** engine on every reachable model.
5. Commit results as `Evals/results/summary.md` ("before" numbers).

## Phase 2 — Engine v3 (sidekick implements; lead writes prompts + reviews eval deltas)

### 2a. Options — `Sources/CueKit/Options.swift` (Create)
```swift
public struct PasteOption: Sendable, Equatable {
    public enum Kind: String, Sendable { case email, phone, url, text }
    public var key: String          // "c1"… in recency order
    public var text: String         // exact string that will be pasted
    public var kind: Kind
    public var clip: Clip
    public var snippet: String      // ±40 chars around the span (whole-clip: preview)
}
public enum OptionBuilder {
    /// Newest first. Last `recent` clips + all pins. Each clip → every detected
    /// email/phone/URL span + the whole clip (skipped when the clip IS one span).
    /// Dedupe by exact text keeping the newest. Cap `maxOptions`.
    public static func options(from clips: [Clip], recent: Int = 20, maxOptions: Int = 30) -> [PasteOption]
}
```
- `SpanExtractor` already returns all spans. Add a `ranges` variant so snippets come from real ranges.
- `ClipStore.candidates(limit:)` becomes `recent(20) + pins`.
- `Transform.extract*` stay only for onboarding sample expectations. Drop the rest if unused (grep callers).

**Tests** (`OptionsTests.swift`):
- two emails in one clip → 2 email options + 1 text option
- a clip that is exactly an email → 1 option
- the same email in 2 clips → 1 option, newest clip kept
- a pin at position 60 is included
- 25 clips → only 20 + pins
- the cap is respected

### 2b. Richer context — `Context.swift`
Add `ContextSnapshot.nearby: String` (≤ 300 chars) and `webHost: String`. These are filled from:
- the AX title/label elements
- `AXHelp`
- `AXDOMIdentifier`
- the preceding sibling `AXStaticText` values
- the parent group title
- the `AXURL` host of the enclosing `AXWebArea`

Call `AXUIElementSetMessagingTimeout(el, 0.05)` so a hung app can't stall a paste. Secure fields: none of this is read (the invariant stays). Keep the `Field.label` fallback chain, and prepend the title-element value when `AXTitle` is empty.

**Test:** a pure `nearbyText(fromSiblings:)` join/truncate helper. The AX parts are verified manually in Safari + Mail.

### 2c. Request + prompts — `Decide.swift`
- There is one `pick` choice over options plus an abstain key `none`, and `use_latest` (noul with yes/no criteria) in intercept mode. `form`/`form_field` are unchanged.
- Criteria line per option: `"{kind} · {text} · in: “…{snippet}…” · from {app} · {age}"`, redacted as a whole line when remote.
- State: `{task, app, window, web_host, field{role,label,placeholder,current_value}, nearby}`.
- Prompt wording follows writing-for-agents: a positive target, one leading idea per question, no negations.

  **Prompt A (ship candidate):**
  - pick: "The user is pasting into the focused field described in `field`. Choose the option a person would type into this field. Weigh, in order: the field's purpose (`field.label`, `field.placeholder`, `nearby`); who or what the surrounding conversation or page is about (`window`, `nearby`, `web_host`); then recency, where c1 is newest. Choose `none` when no option belongs in this field."
  - use_latest: "The user pressed ⌘V. Does c1, exactly as copied, belong in this field?" with criteria true="c1 fits as-is" and false="another option or none fits better".
- Prompt B: terser. Prompt C: A plus explicit "prefer the option matching a person named in `window`/`nearby`".
- The eval picks the winner. The losers are deleted, not kept behind flags.

### 2d. Policy — pure `DecisionPolicy` in `Decide.swift`
```swift
public enum PasteOutcome { case paste(Decision); case choose([ScoredOption]); case pasteLatest(PlainReason) }
static func outcome(ranked: [ScoredOption], noneProb: Double, useLatest: Double?,
                    mode: DecisionEngine.Mode, threshold: Double, margin: Double) -> PasteOutcome
```
**Rules:**
- **Intercept:** if `useLatest ≥ 0.5`, plain. Otherwise, if decisive, paste. Otherwise, if at least 2 options have prob ≥ 0.1, choose. Otherwise plain.
- **Hotkey:** if `none` leads, plain paste plus the toast "Nothing here fits this field". Otherwise, if decisive, paste. Otherwise, if at least 2 plausible options, choose. Otherwise paste the top option.
- **formFill:** decisive (0.5) or stop.
- *decisive* = `top.p ≥ threshold && top.p − second.p ≥ margin`.
- The defaults (threshold 0.6, margin 0.25) are then **set from the Phase-1 rescore sweep**.
- `.top3`/`.picker` merge into `.choose`. `LowConfidenceMode` shrinks to what the chooser needs (grep Settings UI callers).

**Tests** (`DecideTests.swift`) cover every rule branch, including "3 near-equal emails → .choose(3)", "none leads → plain", and "intercept + use_latest 0.7 → plain".

### 2e. Latency
- `PIIRedactor`: an in-memory LRU cache (256 entries) keyed by `Clip.hash(text)`, so clips are scrubbed once.
- Timeouts: hotkey 2.5 s, intercept 1.2 s.
- On a hotkey timeout, **choose** the recency top 3 of options whose kind matches `FieldKind.infer` (label/placeholder keywords); if there are none, plain. On an intercept timeout, plain. The local server not running is an immediate fallback, as today.
- Instrumentation: `lastAction` gains `· 412 ms` (capture / redact / model split in a debug-only `os_log`, **never content**).

**Test:** a cache hit avoids a second `redact` call (counting stub).

### 2f. Eval gate
Rerun Phase 1 with `--engine v3` across prompts A/B/C on every model. **Accept v3 when**, on the best-balance model:
- resolved ≥ 95 %
- **wrong-paste ≤ 3 %**
- chooser rate on unambiguous cases ≤ 20 %
- every ambiguous-no-signal case ends in `.choose`
- p50 ≤ 500 ms, p95 ≤ 1.2 s

If a model misses, iterate the prompt/policy (max 3 rounds), then report honestly. Commit `summary.md` with before/after.

## Phase 3 — Caret-anchored chooser (sidekick)

**Files:** `HUD.swift` (replace `Top3View`/`showTop3` with `ChooserView`/`showChooser`; keep `PickerView` for the full-history shortcut), `Context.swift` (caret rect).
- **Anchor:** caret rect via `AXSelectedTextRange` → `AXBoundsForRange`, falling back to the field's bottom-left, then the mouse. Place it below; flip above near the screen bottom.
- **Look:** `NSVisualEffectView(.popover)`, radius 12, width 280–420.
  - Each row: key badge `1`–`3`, the value (13 pt medium, middle-truncated), and a second line (11 pt secondary) with the source-app icon (`NSWorkspace.icon(forFile:)` from the bundle ID) plus "Slack · 2m ago" or the snippet with the span bolded.
  - Accent selection; hover selects; click picks.
- **Keys:** 1/2/3, ↑↓, Return, Esc = plain paste, ⌘V = plain paste (as today).
- **Motion:** 120 ms fade + 0.98→1 scale from the anchor edge; Reduce Motion = fade only.
- **A11y:** each row is a button with label "Paste {value}, from {app}", and an announcement on appear.
- **Deciding indicator:** replace the top-of-screen "Deciding…" toast with a small caret-anchored pill (three pulsing dots) after **250 ms**. The chooser/paste replaces it.
- **Controller:** `.choose(opts)` → `hud.showChooser`. The pick calls `paste(option.text, clip: option.clip, …)`, so feedback tracking still works.

**Manual verification:** TextEdit, Safari (form), and Mail To: with 3 seeded emails. Screenshot each.

## Phase 4 — Benchmark-backed model roles (lead sets formula + data; sidekick wires UI)

- `Sources/CueKit/Resources/benchmarks.json` is **frozen output** of Phase 2f (never recomputed at runtime): `[{model, variant, resolved, wrong, p50, p95, diskGB, ramGB}]`.
- `ModelCatalog.roles(from:)` is pure:
  - **Fastest** = lowest p50 with resolved ≥ 85 %.
  - **Most accurate** = highest resolved, then lowest wrong.
  - **Best balance** = argmax(`resolved − 0.10·p50/500 − 0.05·diskGB/2`) subject to p50 ≤ 500, p95 ≤ 1200.
  - If one model wins twice, the next best fills the later role. Order: balance, accuracy, speed.
- Remove `WeightSpec.accuracy/speed` (editorial). `ModelSpec.reason` comes from the role.
- **Rows** (Local tab): the title is the role ("Best balance"); the subtitle is plain words ("Quick and accurate. Good for most Macs.") plus "Von · 1.5 GB · 0.4 s" in tertiary. The balance row carries a "Recommended" tag. Everything else goes under "More models".
- The Hosted tab gets the same treatment for Jev direct/gateway, with measured latency.
- **Tests:**
  - roles from a fixture JSON (tie-breaks; a double-winner fills the next role)
  - the existing `vonIsTheTopRecommendation` is replaced by a data-driven assertion

## Phase 5 — Onboarding fidelity to the references (sidekick; can start in parallel with Phase 1)

**Feedback tool first (agent-laboratory):** `Scripts/ob_compare.py` (PIL is installed).
- Launch the debug bundle with `OB_STEP=<step> OB_APPEARANCE=light`.
- Capture the window (`screencapture -l <id>`) and scale it to the reference's content size.
- Write `output/onboarding/compare/<step>.png` as reference | app | 50 % overlay.
- Every visual step below is done only when its compare image has been inspected.

**Global (`OnboardingStyle.swift`, `CueApp.swift`, `Onboarding.swift`):**
1. Tokens resampled from the reference PNGs (the sidekick samples pixel colors): canvas near-white, upper sheet off-white, lower sheet white, softer separators. Update `DESIGN.md`'s table to match the code.
2. Fold: delete `FoldArrowShape`, and add `FoldSeam`:
   - The lower sheet's top edge flares ~6 pt outward at each corner over ~14 pt (a trapezoid tab visible under the upper sheet), with a soft shadow band.
   - A 1.5 pt coral curl starts under the highlighted span (`arrowX`), drops ~22 pt, and bends right into the seam, fading out with no arrowhead.
   - The plain setup screens get the flare only.
3. Highlight rect: in `ParagraphNSView.highlightRects`, derive each rect from the glyph baseline (`lineFragmentRect` + `location(forGlyphAt:)` + font ascender/descender), padded 3 × 2. Stop using the line box. Text on coral stays `#242124` in both themes.
4. Typography: title 28 semibold, tracking −0.4; paragraph 17 with a 1.3× line height.
5. Primary: always a blue gradient, radius 10, 38 h. Disabled = the same blue at 40 %, never grey. Back: a bordered rounded rect with the text "Back" (no chevron), 36 h.
6. `OBRadio`: filled blue with a white 8 pt dot. Segmented: a custom white pill on a light track (Welcome, Models).
7. Window 760×580 (content). Vertical rhythm per SPEC coordinates, with no dead space.
8. Footer: outside the panels on Welcome/Trigger/Privacy/Practice. **Inside the lower sheet** on Accessibility (primary) and Models (Back + primary), matching refs 02/04.

**Per screen (checklist, compare each against its reference):**
- **01 Welcome:** caption, paragraph, curl from highlight; lower "Email" bold title + "Try a different field:" + segmented; field preview.
- **02 Accessibility:** app row in a bordered inset with the real app icon; heading; centered numbered badges ① ②; helper + status; primary inside the lower sheet.
- **03 Trigger:** grey inset "copied message" box with caption above; left-aligned lower caption; filled radios; the recorder has no focus ring until clicked.
- **04 Models:**
  - Role rows (Phase 4) with tinted SF Symbol tiles: balance `scale.3d` purple, accuracy `scope` green, speed `bolt.fill` orange. Hosted keeps the TypeSafe/Vercel marks. "More models ›" row.
  - The detail panel must never be clipped.
  - **Fix the `repo` bug:** `start` on a not-installed model must route to install. Guard in `ModelManager.start` (`manifestExists`, else set `.notInstalled`) and fix the primary-label state mapping. Add a test: `start` on an uninstalled spec does not throw a cwd error.
- **05 Privacy:** example with coral name/email highlights; lower "Example sent to the model" with placeholder chips; toggle row; helper; title without a period, per the ref.
- **06 Practice:**
  - Success layout per the ref: "✓ Email pasted" inside the field on the right; "Try Website" bordered button beside it; centered "Find Cue in your Mac's menu bar."
  - **New "Try another" round:** seed a second labeled sample with 3 emails (Priya / Mira / billing) and a field labeled "Reply to Priya". The real engine path produces `.choose`, the real chooser appears at the practice field, the user picks, and success is observed as today (`OnboardingPractice.classify` extended: chooser pick + exact text = success).
  - Update `SPEC.md` for this state.
9. Dark mode: derived; screenshot every step once.

## Phase 6 — Smoothness sweep + docs (sidekick; lead reviews)

- First-run walk-through on a clean defaults suite (`defaults delete com.local.cue` **only with user OK**; otherwise use `-AppleLanguages`-style isolated suite via env). Check every error path ends in a clear next action.
- Update `AGENTS.md`:
  - options pipeline, `.choose`/chooser, eval command
  - removed transform question
  - candidate window 20 + pins
  - AX messaging timeout
- Delete stale lines: the `eval_systemone.py` pointer, "all questions batch".
- Update `SPEC.md`/`HANDOFF.md` precedence: "images win on looks".
- README: one paragraph on the chooser.

## Execution / delegation

| Phase | Owner | Notes |
|---|---|---|
| 0 | sidekick | |
| 1 dataset, scoring rules, runs, reading numbers | **lead** | correctness-critical |
| 1 server installs, CLI plumbing | sidekick | |
| 2 implementation | sidekick | lead writes prompt text, reviews diffs + eval deltas |
| 3 | sidekick | |
| 4 formula + benchmarks.json values | **lead** | UI wiring: sidekick |
| 5 | sidekick | starts in parallel with Phase 1 |
| 6 | sidekick | lead final review |

One commit per task, on the current branch, no push.

## Verification

- [ ] `swift build && swift test`: all green. New suites: EvalScoring, Options, DecisionPolicy, RedactionCache, ModelRoles, ModelManager-start guard.
- [ ] `swift run -c release CueEval …`: before/after table in `Evals/results/summary.md`; the Phase 2f gates met (or honest miss documented).
- [ ] `Scripts/bundle.sh && open build/Cue.app`: chooser in TextEdit/Safari/Mail with 3 seeded emails; ⌘V intercept both branches; screenshots saved.
- [ ] `Scripts/ob_compare.py` compare images for all 6 steps (light) plus dark captures, inspected. Practice "Try another" chooser round observed end to end.
- [ ] Menu self-check still passes.

## Risks / considerations

- **Hosted Jev needs your key in the eval shell.** Without it, the hosted rows are "not measured".
- Local installs are several GB. jev-lite/Jevons may fail on macOS; failures are recorded, not hidden.
- Removing the `transform` question drops lowercase/digits-only/URL-tracking stripping. It was rarely correct; if the eval shows a need, it comes back as a deterministic per-kind formatter, not a model question.
- AX richness varies by app (Chrome/Electron expose less). The chooser is the safety net, so ambiguity never becomes a wrong paste.
- The chooser adds a decision step for truly ambiguous cases. That is intended: a wrong confident paste is worse than one keypress.
- Images-over-spec changes previously documented corrections (footer inside panels on 02/04, colored tiles). `SPEC.md` gets updated so docs and code agree.
