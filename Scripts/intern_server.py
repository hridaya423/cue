#!/usr/bin/env python3
"""Intern-Decision behind TypeSafe's System One contract, for Cue.

    python3 Scripts/intern_server.py <port> <hf-repo> <serve-model> <snapshot>

The weight snapshot ships `inference.py` with `DecisionEngine`, whose `predict`
takes one Jev-style request dict and returns the JSON-serializable response.
"""
import sys
from s1http import serve

SNAPSHOT = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] else None
if not SNAPSHOT:
    print("intern_server: a downloaded snapshot is required", file=sys.stderr)
    sys.exit(2)
sys.path.insert(0, SNAPSHOT)


def pick_device():
    import torch
    if torch.cuda.is_available():
        return "cuda", "bfloat16"
    if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
        return "mps", "bfloat16"
    return "cpu", "float32"


def main():
    from inference import DecisionEngine

    device, dtype = pick_device()
    print(f"loading {SNAPSHOT} on {device} ({dtype})…", flush=True)
    engine = DecisionEngine(checkpoint=SNAPSHOT, device=device, dtype=dtype)
    port = int(sys.argv[1])
    serve_model = sys.argv[3] if len(sys.argv) > 3 else "intern-decision"

    def answer(req):
        req.setdefault("model", serve_model)
        return engine.predict(req)

    serve("intern-decision", port, answer, {"model": serve_model, "device": device})


if __name__ == "__main__":
    main()
