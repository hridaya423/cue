#!/usr/bin/env python3
"""Intern-Decision behind TypeSafe's System One contract, for Cue.

    python3 Scripts/intern_server.py <port> <hf-repo> <serve-model> <snapshot>

The weight snapshot ships `inference.py` with `DecisionEngine`, whose `predict`
takes one Jev-style request dict and returns the JSON-serializable response.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

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
                req.setdefault("model", serve_model)
                self._send(200, engine.predict(req))
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

    print(f"intern-decision serving on http://127.0.0.1:{port}/v1/systemone", flush=True)
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
