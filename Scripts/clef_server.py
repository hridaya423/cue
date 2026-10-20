#!/usr/bin/env python3
"""Cloudflare Clef behind TypeSafe's System One contract, for Cue.

    python3 Scripts/clef_server.py <port> <hf-repo> <serve-model> <snapshot>

Clef ships `joint_schema_model.py` inside the weight snapshot; it provides
`load_release_model` and a `systemone` function that already answers the exact
Jev/SystemOne request shape. This shim only does HTTP and device selection.
"""
import os
import sys
from s1http import serve

SNAPSHOT = sys.argv[4] if len(sys.argv) > 4 and sys.argv[4] else None
if not SNAPSHOT:
    print("clef_server: a downloaded snapshot is required", file=sys.stderr)
    sys.exit(2)
sys.path.insert(0, SNAPSHOT)


def pick_device():
    import torch
    if torch.cuda.is_available():
        return "cuda", torch.bfloat16
    if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
        return "mps", torch.bfloat16
    return "cpu", torch.float32


def main():
    import torch  # noqa: F401
    from joint_schema_model import load_release_model, systemone

    device, dtype = pick_device()
    print(f"loading {SNAPSHOT} on {device} ({dtype})…", flush=True)
    model, processor = load_release_model(SNAPSHOT, device=device, dtype=dtype)
    port = int(sys.argv[1])
    serve_model = sys.argv[3] if len(sys.argv) > 3 else "clef"

    serve("clef", port, lambda req: systemone(model, processor, req),
          {"model": serve_model, "device": device})


if __name__ == "__main__":
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
    main()
