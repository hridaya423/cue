#!/usr/bin/env python3
"""Laya behind TypeSafe's System One contract, for SmartCopyPaste.

    pip install laya
    python3 Scripts/laya_server.py          # POST http://127.0.0.1:8765/v1/systemone

The app sends {"state": ..., "model": "laya"|"multilingual"|"typed-decisions",
"questions": {id: {type, instructions, criteria}}} and gets the standard
{model, usage, answers} shape back. "laya" (or anything unrecognized) lets the
Router auto-pick the checkpoint; the other two pin it.
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

import laya  # noqa: F401  — a clear ImportError here means: pip install laya
from laya import Router

MODELS = {"multilingual": "multilingual", "typed-decisions": "typed-decisions"}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802 — stdlib naming
        if self.path == "/health":
            return self._send(200, {"ok": True})
        self._send(404, {"detail": "not found"})

    def do_POST(self):  # noqa: N802
        if self.path != "/v1/systemone":
            return self._send(404, {"detail": "not found"})
        try:
            req = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
            model = MODELS.get(req.get("model") or "")
            if model:
                res = router.predict(req["state"], req["questions"], model=model)
            else:
                res = router.predict(req["state"], req["questions"])
            answers = res["answers"] if "answers" in res else res
            for qid, q in req["questions"].items():
                if q.get("type") == "score" and qid in answers and "legend" not in answers[qid]:
                    answers[qid]["legend"] = {str(i): lvl for i, lvl in enumerate(q["criteria"])}
            self._send(200, {"model": req.get("model") or "laya",
                             "usage": res.get("usage", {"input_tokens": 0, "output_tokens": 0}),
                             "answers": answers})
        except (KeyError, ValueError) as exc:
            self._send(422, {"detail": f"{type(exc).__name__}: {exc}"})
        except Exception as exc:  # noqa: BLE001 — surface anything the model raises
            self._send(500, {"detail": f"{type(exc).__name__}: {exc}"})

    def _send(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):  # quiet per-request noise
        pass


if __name__ == "__main__":
    port = int(os.environ.get("LAYA_PORT", sys.argv[1] if len(sys.argv) > 1 else "8765"))
    print("loading laya checkpoints…", flush=True)
    router = Router(preload=True)
    print(f"laya serving on http://127.0.0.1:{port}/v1/systemone", flush=True)
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()
