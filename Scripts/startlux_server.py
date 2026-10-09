#!/usr/bin/env python3
"""StartLux-Decision native server launcher, for Cue.

    python3 Scripts/startlux_server.py <port> <hf-repo> <serve-model> <snapshot>

The snapshot ships `startlux_decision/` with its own /v1/systemone server
(`python -m startlux_decision.server --model <snapshot>`). On Apple Silicon it
auto-selects the MLX backend when mlx-lm is installed — requirements.txt in the
snapshot carries that marker. We just exec into it.
"""
import os
import sys

SNAPSHOT = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] else None
if not SNAPSHOT or not os.path.isdir(os.path.join(SNAPSHOT, "startlux_decision")):
    print("startlux_server: snapshot with startlux_decision/ required", file=sys.stderr)
    sys.exit(2)

env = dict(os.environ)
env["PYTHONPATH"] = SNAPSHOT + os.pathsep + env.get("PYTHONPATH", "")
argv = [sys.executable, "-m", "startlux_decision.server",
        "--model", SNAPSHOT, "--host", "127.0.0.1", "--port", sys.argv[1]]
print("exec:", " ".join(argv), flush=True)
os.execve(sys.executable, argv, env)
