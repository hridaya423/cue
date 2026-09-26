#!/bin/bash
# One-shot CueEval run detached under launchd (survives shell teardown).
# `launchctl submit` jobs are KeepAlive, so the job removes itself on exit —
# otherwise launchd re-runs the benchmark forever.
#   Scripts/eval_run.sh <tag> --endpoint name=base,model [...more CueEval args]
# Output: Evals/results/<tag>.log, <tag>.json, <tag>-raw.jsonl
set -eu
tag="$1"; shift
R="$(cd "$(dirname "$0")/.." && pwd)"
bin="$R/.build/arm64-apple-macosx/release/CueEval"
[ -x "$bin" ] || { echo "build first: swift build -c release --product CueEval" >&2; exit 1; }
out="$R/Evals/results"
args=""
for a in "$@"; do args="$args '$a'"; done
launchctl remove cue.eval.runner 2>/dev/null && sleep 1 || true
launchctl submit -l cue.eval.runner -o "$out/$tag.log" -e "$out/$tag.log" -- /bin/sh -c \
  "cd '$R' && '$bin' --cases Evals/cases.jsonl --repeats 3 --record '$out/$tag-raw.jsonl' --json '$out/$tag.json' $args; launchctl remove cue.eval.runner"
echo "running → $out/$tag.log"
