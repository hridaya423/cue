# CueEval — smart-paste benchmark summary

110 synthetic cases (`Evals/cases.jsonl`): extract (15), multispan (10),
amb-signal (20), amb-plain (10), typed (20), noisy (10), intercept (15),
none (10). Each case runs 3× through the real `DecisionEngine`; the verdict
scores the exact text that would land in the field. Threshold 0.7 (the app
default). Machine: Apple Silicon, all servers local.

- **resolved** = exact paste, or the right answer inside a shown chooser
- **wrong** = a confident wrong paste, or a popup where plain paste was right
- Targets: p50 ≤ 500 ms, p95 ≤ 1.2 s

## Before → after

| | resolved | wrong | p50 | p95 |
|---|---|---|---|---|
| Von, old engine (whole clips, no chooser policy) | 69% | 23% | 326 ms | 518 ms |
| Von, v3 engine (spans + policy C) | 88% | 10% | 215 ms | 408 ms |
| Kev 0.8B, v3 engine | 84% | **1%** | 248 ms | 479 ms |
| Laya, v3 engine | 80% | 3% | 308 ms | 506 ms |
| Jevons, v3 engine | 47% | 1% | 959 ms | 2552 ms |
| JevLite, v3 engine (policy B) | 62% | 0% | ~2630 ms | ~2670 ms |

Von/Kev: `v3-policyC-warm.log`; Laya: `v3-policyC-laya.log`; Jevons:
`v3-policyC.log`; JevLite: `v3-policyB.log`. Hosted Jev not run (no key in
this environment).

## What moved the numbers

1. **Span options** (v3): every email/phone/URL inside a clip is its own
   option, so a pasted message yields "just the email". Extraction cases
   went from mostly-wrong whole-clip pastes to 60–93% exact.
2. **Policy B — `none` must be dominant**: a plurality `none` (≈0.47–0.53)
   beside real candidates used to end in a plain paste; it now shows the
   chooser. amb-* resolution went from ~50% to 95–100% for von/kev.
3. **Policy C — ⌘V only interrupts when the latest clip doesn't fit**:
   `FieldKind.acceptsVerbatim` — generic fields take anything, typed fields
   need the clip to be exactly one span of that type. When it fits, no model
   call is made (instant). Intercept wrong-rate: von 49% → 0%, kev 21% → 0%,
   laya 19% → 0%.

## Stability

Policy B ran unattended 18 complete times (launchd KeepAlive re-ran it
overnight). Per-model spread across runs: resolved ±4 pts, wrong ±2 pts,
steady-state p50 ±30 ms. Single-run differences under ~4 pts are noise.

## Per-category (policy C, resolved/wrong %)

| model | amb-plain | amb-signal | extract | intercept | multispan | noisy | none | typed |
|---|---|---|---|---|---|---|---|---|
| von | 100/0 | 100/0 | 93/7 | 93/0 | 80/20 | 60/30 | 40/60 | 100/0 |
| laya | 70/0 | 95/0 | 67/0 | 80/0 | 100/0 | 40/0 | 60/30 | 100/0 |
| kev | 100/0 | 100/0 | 60/0 | 87/0 | 80/10 | 30/0 | 90/0 | 90/0 |
| jevons | 0/0 | 60/0 | 20/0 | 60/0 | 0/0 | 10/0 | 90/0 | 90/5 |

Open weaknesses: **noisy** (20-clip histories with one right answer) is weak
for every model; **von on `none`** pops a chooser on fields nothing fits
(verification codes, age) — mostly popups, not pastes, but still noise.

## Final policy (committed) + the chooser-friction gate

Recorded answers re-scored through the committed policy
(`--replay`, deterministic — latency columns below stay live-measured):

| | resolved | wrong | chooser-on-clear |
|---|---|---|---|
| kev | 91% | 1% | 45% |
| laya | 81% | 5% | 50% |
| von | 88% | 8% | 78% |

**The plan's chooser-on-unambiguous ≤ 20% gate is NOT met at 0.8B** — and
the evidence says it can't be met with these weights:

- Threshold/margin sweep (replay): friction 20% appears only at
  t≈0.4/m≈0.05, where wrong-paste rises to 6%. Every wrong-free point
  sits at ≥33% friction. The wall is a tradeoff curve, not a tunable gap.
- The residual friction is `no-*`/`nz-*` cases where Kev spreads mass
  thinly (`none`≈0.4–0.6, options 0.1–0.2 each) — genuine model
  uncertainty, and the chooser is the *designed* answer for it.
- ContextSignal ∩ model-leader agreement was tested as an auto-paste
  trigger: `--diag` shows it would paste **wrong 4 of 13 times** — unsafe.
- A criteria-line hint ("mentions something from the window") was tried
  live (`hint1` run): +4 resolved but new confident wrong-route pastes
  (e.g. an email pasted into a Slack *message* field) — reverted.

Product call, per plan: a wrong confident paste is worse than one chooser
interaction. Current policy keeps wrong at ~1% and spends chooser friction
on it. Closing the ≤20% gate needs a more decisive model (hosted Jev —
unbenchmarked here, needs a key — or bigger local weights).

## Model roles (onboarding + settings)

- **Kev 0.8B — Most accurate (Recommended)**: 1% wrong, 84% resolved, 248 ms.
- **Laya — Best balance**: under 1 GB, 3% wrong, 80% resolved, 308 ms.
- **Von — Fastest**: 215 ms p50, resolves the most (88%) but 10% wrong.

Jevons and JevLite stay in "More models": below the resolution bar and over
the latency budget (JevLite hits the 2.5 s decision ceiling on every call).

## Reproduce

```sh
Scripts/eval_servers.sh                      # JEVLITE=1 to include jevlite
swift build -c release --product CueEval
Scripts/eval_run.sh <tag> --endpoint kev=http://127.0.0.1:8009,kev-latest ...
```

Gotchas: run one heavy server load at a time (jevlite loading starves the
GPU and turns every other model's call into a 2.5 s timeout); after a reboot,
warm laya with a few requests first (its first-shape kernel compile blocks
its single-threaded shim).

## 2026-10-10 — new catalogue families (live CueEval, 303 recorded responses each)

Four more catalogue families benchmarked end-to-end through `JevClient`
(raw answers in `*-raw.jsonl`):

| model | resolved | wrong | p50 | p95 | quality |
|---|---|---|---|---|---|
| minicpm (2B q8, MLX) | 92% | 3% | 693 | 1101 | 0.86 — best quality measured; over the p50 budget, no role |
| kenning v0.6 (400M CE, MPS) | 88% | 6% | 452 | 1106 | 0.76 — in budget; over-picks email on no-fit cases |
| jevk5lite (437M CPU) | 86% | 5% | 331 | 483 | 0.76 — in budget |
| s1qwen (0.6B LoRA, MLX) | 80% | 5% | 234 | 384 | 0.70 — in budget |

Roles unchanged: kev stays Most accurate (0.82) + Best balance, von stays
Fastest (215 ms, resolved ≥ 80 gate passes at 88%).

Watch out: an earlier jevk5lite run reported 72%/0%/14 ms — that was a
stale broken shim 500ing every call (fail-closed fallbacks scoring, zero
records written). Verify `*-raw.jsonl` line counts before trusting a row.
