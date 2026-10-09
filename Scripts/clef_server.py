#!/usr/bin/env python3
"""Cloudflare Clef behind TypeSafe's System One contract, for Cue.

    python3 Scripts/clef_server.py <port> <hf-repo> <serve-model> <snapshot>

Clef ships `joint_schema_model.py` inside the weight snapshot; it provides
`load_release_model` and a `systemone` function that already answers the exact
Jev/SystemOne request shape. This shim only does HTTP and device selection.
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

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

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            if self.path == "/health":
                return self._send(200, {"ok": True, "model": serve_model, "device": device})
            self._send(404, {"detail": "not found"})

        def do_POST(self):  # noqa: N802
            if self.path != "/v1/systemone":
                return self._send(404, {"detail": "not found"})
            try:
                req = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
                self._send(200, systemone(model, processor, req))
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

    print(f"clef serving on http://127.0.0.1:{port}/v1/systemone", flush=True)
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
    main()
