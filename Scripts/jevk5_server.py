#!/usr/bin/env python3
"""JevK5 behind TypeSafe's System One contract, for Cue — the llama.cpp path.

    python3 Scripts/jevk5_server.py <port> <gguf-repo> <gguf-file> <snapshot>

Spawns `llama_cpp.server` on an ephemeral port with the chosen GGUF, then serves
/v1/systemone through the `jevk5` package's JevK5GGUF client — the documented
macOS path: the same option-letter readout as the CUDA runtime.
"""
import json
import socket
import subprocess
import sys
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1])
GGUF_REPO = sys.argv[2] if len(sys.argv) > 2 else "alibiserikbay/JevK5-GGUF"
GGUF_FILE = sys.argv[3] if len(sys.argv) > 3 else "jevk5-4b-v0.3-Q8_0.gguf"

# Calibration temperatures per release file (from the JevK5-GGUF card table).
# v0.3.3 must precede v0.3 — its filenames also start with "jevk5-9b-v0.3".
TEMPERATURES = {
    "jevk5-9b-v0.3.3": (1.316, 1.05),
    "jevk5-4b-v0.3": (1.22, 0.93),
    "jevk5-9b-v0.3": (1.049, 1.2),
    "jevk5-2b-v0.2": (1.42, 0.77),
    "jevk5-4b-v0.2": (1.532, 0.77),
}


def temperatures(filename):
    for stem, temps in TEMPERATURES.items():
        if filename.startswith(stem):
            return temps
    return 1.22, 0.93


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def wait_ready(port, proc, timeout=600):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if proc.poll() is not None:
            raise RuntimeError("llama-server exited during startup")
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=2) as r:
                if r.status < 500:
                    return
        except Exception:
            pass
        time.sleep(2)
    raise TimeoutError("llama-server did not become ready")


def main():
    llama_port = free_port()
    backend = [sys.executable, "-m", "llama_cpp.server",
               "--hf_model_repo_id", GGUF_REPO, "--model", GGUF_FILE,
               "--n_gpu_layers", "-1", "--host", "127.0.0.1", "--port", str(llama_port)]
    print("spawning:", " ".join(backend), flush=True)
    proc = subprocess.Popen(backend)
    try:
        wait_ready(llama_port, proc)
    except Exception:
        proc.terminate()
        raise

    from jevk5 import JevK5GGUF

    temp, knockout = temperatures(GGUF_FILE)
    engine = JevK5GGUF(url=f"http://127.0.0.1:{llama_port}",
                       temperature=temp, knockout_temperature=knockout)
    print(f"jevk5 client ready (T={temp}, knockT={knockout})", flush=True)

    def to_answer(question, result):
        qtype = question.get("type")
        probs = result.get("probabilities") or {}
        if qtype == "noul":
            p = result.get("noul", probs.get("true", probs.get("yes", 0.0)))
            return {"type": "noul", "noul": p}
        if qtype == "score":
            levels = [str(i) for i in range(len(question["criteria"]))]
            score = result.get("score")
            if score is None:
                score = sum(int(lvl) * probs.get(lvl, 0.0) for lvl in levels)
            return {"type": "score", "score": score,
                    "confidence": max(probs.values()) if probs else 0.0,
                    "legend": dict(zip(levels, question["criteria"])),
                    "probabilities": probs}
        choice = result.get("choice") or (max(probs, key=probs.get) if probs else None)
        return {"type": "choice", "choice": choice,
                "confidence": probs.get(choice, 0.0), "probabilities": probs}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            if self.path == "/health":
                return self._send(200, {"ok": True, "model": GGUF_FILE})
            self._send(404, {"detail": "not found"})

        def do_POST(self):  # noqa: N802
            if self.path != "/v1/systemone":
                return self._send(404, {"detail": "not found"})
            try:
                req = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
                answers = {}
                for qid, q in req["questions"].items():
                    res = engine.decide(req["state"], q)
                    answers[qid] = to_answer(q, res if isinstance(res, dict) else {"probabilities": res})
                self._send(200, {"model": req.get("model") or GGUF_FILE,
                                 "usage": {"input_tokens": 0, "output_tokens": 0},
                                 "answers": answers})
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

    try:
        print(f"jevk5 serving on http://127.0.0.1:{PORT}/v1/systemone", flush=True)
        HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
    finally:
        proc.terminate()


if __name__ == "__main__":
    main()
