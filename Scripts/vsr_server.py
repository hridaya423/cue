#!/usr/bin/env python3
"""vLLM Semantic Router Decision models behind /v1/systemone, for Cue.

    python3 Scripts/vsr_server.py <port> <hf-repo> <serve-model> <snapshot>

vllm-sr/Decision-2.0-* models expose `model.system_one(state=..., questions=...)`
via trust_remote_code, so the shim is thin: load, translate, serve.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

REPO = sys.argv[2] if len(sys.argv) > 2 else None
SERVE_MODEL = sys.argv[3] if len(sys.argv) > 3 else "decision"


def pick_device():
    import torch
    if torch.cuda.is_available():
        return "cuda"
    if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def normalize(result):
    """vllm-sr returns a systemone-shaped dict; pass it through, ensuring `model`/`answers`."""
    if isinstance(result, dict) and "answers" in result:
        result.setdefault("model", SERVE_MODEL)
        result.setdefault("usage", {"input_tokens": 0, "output_tokens": 0})
        return result
    return {"model": SERVE_MODEL, "usage": {"input_tokens": 0, "output_tokens": 0},
            "answers": result}


def main():
    import torch
    from transformers import AutoModel

    if not REPO:
        print("vsr_server: hf repo required", file=sys.stderr)
        sys.exit(2)
    device = pick_device()
    dtype = torch.bfloat16 if device != "cpu" else torch.float32
    print(f"loading {REPO} on {device}…", flush=True)
    model = AutoModel.from_pretrained(REPO, trust_remote_code=True, torch_dtype=dtype)
    model.to(device).eval()
    port = int(sys.argv[1])

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            if self.path == "/health":
                return self._send(200, {"ok": True, "model": SERVE_MODEL, "device": device})
            self._send(404, {"detail": "not found"})

        def do_POST(self):  # noqa: N802
            if self.path != "/v1/systemone":
                return self._send(404, {"detail": "not found"})
            try:
                req = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
                with torch.inference_mode():
                    result = model.system_one(state=req["state"], questions=req["questions"])
                self._send(200, normalize(result))
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

    print(f"vsr decision serving on http://127.0.0.1:{port}/v1/systemone", flush=True)
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
