#!/usr/bin/env python3
"""Kenning (systemone-builder) behind Cue's /v1/systemone contract.

    python3 Scripts/kenning_server.py <port> <hf-repo> <serve-model> <snapshot>

The builder ships two engines: the cross-encoder `Kenning` (kenning-large-*)
and the decoder `KenningXL` (kenning-xl-*), which escalates to a short
reasoning trace on low-confidence structured questions. The stock servers
bind 0.0.0.0 and never select MPS, so this shim drives the model classes
directly on a loopback stdlib server with Metal enabled.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

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

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            if self.path == "/health":
                return self._send(200, {"ok": True, "model": SERVE_MODEL,
                                        "engine": "xl" if XL else "cross-encoder"})
            self._send(404, {"detail": "not found"})

        def do_POST(self):  # noqa: N802
            if self.path != "/v1/systemone":
                return self._send(404, {"detail": "not found"})
            try:
                req = SystemOneRequest.model_validate(
                    json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0)))))
                resp = answer(req)
                body = resp.model_dump(exclude_none=True)
                body["model"] = req.model or SERVE_MODEL
                self._send(200, body)
            except (KeyError, ValueError) as exc:
                self._send(422, {"detail": f"{type(exc).__name__}: {exc}"})
            except Exception as exc:  # noqa: BLE001
                self._send(500, {"detail": f"{type(exc).__name__}: {exc}"})

        def _send(self, code, obj):
            body = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    print(f"kenning serving on http://127.0.0.1:{port}/v1/systemone", flush=True)
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
