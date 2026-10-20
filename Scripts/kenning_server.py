#!/usr/bin/env python3
"""Kenning (systemone-builder) behind Cue's /v1/systemone contract.

    python3 Scripts/kenning_server.py <port> <hf-repo> <serve-model> <snapshot>

The builder ships two engines: the cross-encoder `Kenning` (kenning-large-*)
and the decoder `KenningXL` (kenning-xl-*), which escalates to a short
reasoning trace on low-confidence structured questions. The stock servers
bind 0.0.0.0 and never select MPS, so this shim drives the model classes
directly on a loopback stdlib server with Metal enabled.
"""
import sys
from s1http import serve

REPO = sys.argv[2] if len(sys.argv) > 2 else "systemonedev/kenning-large-v0.6"
SERVE_MODEL = sys.argv[3] if len(sys.argv) > 3 else "kenning-large-v0.6"
XL = "-xl" in REPO


def main():
    import torch
    from systemone_builder.system_one.contract import SystemOneRequest

    device = "mps" if torch.backends.mps.is_available() else "cpu"
    print(f"loading {REPO} on {device}…", flush=True)
    if XL:
        from systemone_builder.kenning import xl_serve
        from systemone_builder.kenning.xl import KenningXL

        # xl_serve.answer wraps the model with confidence-gated deliberate
        # escalation — the published serving behaviour — so drive it through
        # the module the way its lifespan would.
        xl_serve._model = KenningXL(REPO, device=device)
        answer = xl_serve.answer
    else:
        from systemone_builder.kenning.model import Kenning

        kn = Kenning(REPO, device=device)
        answer = kn.answer
    port = int(sys.argv[1])

    def respond(raw):
        req = SystemOneRequest.model_validate(raw)
        body = answer(req).model_dump(exclude_none=True)
        body["model"] = req.model or SERVE_MODEL
        return body

    serve("kenning", port, respond, {"model": SERVE_MODEL, "engine": "xl" if XL else "cross-encoder"})


if __name__ == "__main__":
    main()
