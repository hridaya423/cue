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

# The new decision-model families (recommended variants only) — same shim argv
# as ModelManager: <script> <port> <hfRepo> <serveModel> <snapshot>.
[ -d "$M/jevstyle" ]  && submit jevstyle "$M/jevstyle" "$M/jevstyle/venv/bin/jev-style" serve --host 127.0.0.1 --port 8770 --release 0.8b
[ -d "$M/jevk5" ]     && submit jevk5 "$M/jevk5" "$M/jevk5/venv/bin/python" "$R/Scripts/jevk5_server.py" 8771 alibiserikbay/JevK5-GGUF jevk5-4b-v0.3-Q8_0.gguf ""
[ -d "$M/startlux" ]  && submit startlux "$M/startlux" "$M/startlux/venv/bin/python" "$R/Scripts/startlux_server.py" 8772 startlux-models/StartLux-Decision-4B StartLux-Decision-4B "$M/startlux/snapshot"
[ -d "$M/vsr" ]       && submit vsr "$M/vsr" "$M/vsr/venv/bin/python" "$R/Scripts/vsr_server.py" 8773 vllm-sr/Decision-2.0-Eos-0.8B Decision-2.0-Eos-0.8B ""
[ -d "$M/clef" ]      && submit clef "$M/clef" "$M/clef/venv/bin/python" "$R/Scripts/clef_server.py" 8774 Cloudflare/clef-flash clef-flash "$M/clef/snapshot"
[ -d "$M/intern" ]    && submit intern "$M/intern" "$M/intern/venv/bin/python" "$R/Scripts/intern_server.py" 8775 internlm/Intern-Decision-2B Intern-Decision-2B "$M/intern/snapshot"
[ -d "$M/jevnano" ]   && submit jevnano "$M/jevnano" "$M/jevnano/venv/bin/python" "$R/Scripts/nano_server.py" 8776 tasksource/tasksource-jev-nano-v1 tasksource-jev-nano-v1 ""
[ -d "$M/s1lite" ]    && submit s1lite "$M/s1lite/repo" env PATH=$HOME/.local/bin:/opt/homebrew/bin:$PATH uv run systemone-lite --model dwidlee/systemone-lite-0.5b --port 8778
[ -d "$M/minicpm" ]   && submit minicpm "$M/minicpm/repo" env PATH=$HOME/.local/bin:/opt/homebrew/bin:$PATH uv run python scripts/serve.py --model models/system-one-minicpm5-2b-q8 --temperature temperature-minicpm5-2b-q8.json --host 127.0.0.1 --port 8782
[ -d "$M/s1qwen" ]    && submit s1qwen "$M/s1qwen/repo" env PATH=$HOME/.local/bin:/opt/homebrew/bin:$PATH uv run python scripts/serve.py --model models/qwen3-0.6b --adapter adapters/system-one-qwen3-0.6b --temperature adapters/system-one-qwen3-0.6b/temperature.json --host 127.0.0.1 --port 8783
[ -d "$M/jevk5lite" ] && submit jevk5lite "$M/jevk5lite" "$M/jevk5lite/venv/bin/python" "$R/Scripts/lite_server.py" 8784 alibiserikbay/JevK5-Lite JevK5-Lite ""
[ -d "$M/kenning" ]   && submit kenning "$M/kenning" "$M/kenning/venv/bin/python" "$R/Scripts/kenning_server.py" 8788 systemonedev/kenning-large-v0.6 kenning-large-v0.6 ""
[ -d "$M/truetype" ]  && submit truetype "$M/truetype" "$M/truetype/venv/bin/python" "$R/Scripts/truetype_server.py" 8789 stephenlb/system-one-model system-one-model ""

sleep 3
launchctl list | grep cue.eval || true
