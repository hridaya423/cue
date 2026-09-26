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
