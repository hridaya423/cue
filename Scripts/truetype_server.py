#!/usr/bin/env python3
"""stephenlb/system-one-model (Gemma 4 12B "truetype") behind /v1/systemone.

    python3 Scripts/truetype_server.py <port> <hf-repo> <serve-model> <snapshot>

The repo ships `model.system_one(tokenizer, state=..., questions=...)` via
trust_remote_code (transformers >= 5.17). ~24 GB bf16 — heavyweight but the
publisher's own numbers are from Apple Silicon MPS. Gated: the download needs
an HF account that accepted the Gemma licence.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

REPO = sys.argv[2] if len(sys.argv) > 2 else "stephenlb/system-one-model"
SERVE_MODEL = sys.argv[3] if len(sys.argv) > 3 else "system-one-model"


def main():
    import torch
    from transformers import AutoModelForMultimodalLM, AutoTokenizer

    print(f"loading {REPO}…", flush=True)
    tok = AutoTokenizer.from_pretrained(REPO)
    model = AutoModelForMultimodalLM.from_pretrained(
        REPO, trust_remote_code=True, dtype=torch.bfloat16, device_map="auto")
    model.eval()
    port = int(sys.argv[1])

    def normalize(result):
        if isinstance(result, dict) and "answers" in result:
            result.setdefault("model", SERVE_MODEL)
            result.setdefault("usage", {"input_tokens": 0, "output_tokens": 0})
            return result
        return {"model": SERVE_MODEL,
                "usage": {"input_tokens": 0, "output_tokens": 0},
                "answers": result}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            if self.path == "/health":
                return self._send(200, {"ok": True, "model": SERVE_MODEL})
            self._send(404, {"detail": "not found"})

        def do_POST(self):  # noqa: N802
            if self.path != "/v1/systemone":
                return self._send(404, {"detail": "not found"})
            try:
                req = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
                state = req["state"]
                if not isinstance(state, str):
                    state = json.dumps(state, ensure_ascii=False)
                with torch.inference_mode():
                    result = model.system_one(tok, state=state,
                                              questions=req["questions"])
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

    print(f"truetype serving on http://127.0.0.1:{port}/v1/systemone", flush=True)
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
