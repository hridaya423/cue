#!/bin/bash
# (Re)start all installed local model servers detached under launchd —
# survives the shell session ending. Labels: cue.eval.<model>.
set -u
M="$HOME/Library/Application Support/Cue/models"
R="$(cd "$(dirname "$0")/.." && pwd)"
UV="${UV:-$HOME/.local/bin/uv}"

submit() { # label dir cmd...
    local label="cue.eval.$1" dir="$2"; shift 2
    # remove is async — wait for the old process to release its port.
    launchctl remove "$label" 2>/dev/null && sleep 2
    launchctl submit -l "$label" -o "$dir/eval-server.log" -e "$dir/eval-server.log" \
        -- /bin/sh -c "cd \"$dir\" && exec \"\$@\"" -- "$@"
    echo "submitted $label"
}

[ -d "$M/von" ]     && submit von "$M/von" "$M/von/venv/bin/von" serve --host 127.0.0.1 --port 8766
[ -d "$M/laya" ]    && submit laya "$M/laya" "$M/laya/venv/bin/python" "$R/Scripts/laya_server.py" 8765
[ -d "$M/kev" ]     && submit kev "$M/kev/repo" env KEV_DTYPE=bf16 PATH=$HOME/.local/bin:/opt/homebrew/bin:$PATH uv run --extra serve python -m kev.serve --run jaredpalmer/kev-0.8b --port 8009
[ -d "$M/jevons" ]  && submit jevons "$M/jevons/repo" env JEVONS_MODEL=models/LFM2.5-1.2B-Instruct-8bit JEVONS_ADAPTER=adapters/lfm25-1.2b-systemone JEVONS_TEMPERATURE=1 JEVONS_CALIBRATION=off PATH=$HOME/.local/bin:/opt/homebrew/bin:$PATH uv run --extra mlx jevons serve --host 127.0.0.1 --port 8767
# jevlite (Gemma 4 E4B) saturates the GPU while loading and takes >2.5s per
# call — it starves every other server's latency. Opt in: JEVLITE=1.
[ "${JEVLITE:-0}" = 1 ] && [ -d "$M/jevlite" ] && submit jevlite "$M/jevlite/repo" env PATH=$HOME/.local/bin:/opt/homebrew/bin:$PATH uv run python serve.py --host 127.0.0.1 --port 8768

sleep 3
launchctl list | grep cue.eval || true
