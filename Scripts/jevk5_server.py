#!/usr/bin/env python3
"""JevK5 behind TypeSafe's System One contract, for Cue — the llama.cpp path.

    python3 Scripts/jevk5_server.py <port> <gguf-repo> <gguf-file> <snapshot>

Loads the GGUF in-process via llama_cpp.Llama (Metal on Apple Silicon) and does
the documented option-letter readout locally: the jevk5 package's pure-python
prompt/spread/answer helpers give the exact calibration math — only the
top-logprob fetch differs from their HTTP client, and a softmax over letter
logits with a renormalised top-k slice is mathematically identical either way.
"""
import json
import math
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(sys.argv[1])
GGUF_REPO = sys.argv[2] if len(sys.argv) > 2 else "alibiserikbay/JevK5-GGUF"
GGUF_FILE = sys.argv[3] if len(sys.argv) > 3 else "jevk5-4b-v0.3-Q4_K_M.gguf"

MISSING_MARGIN = 2.0  # a letter outside top-k sits at least this far below the last
TOP_K = 40            # llama-server's default n_probs; must cover 16 letters

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


def main():
    import numpy as np
    from huggingface_hub import hf_hub_download
    from jevk5.prompt import LETTERS, decision_options, prompt_text, spread
    from llama_cpp import Llama

    weights = hf_hub_download(GGUF_REPO, GGUF_FILE)
    llm = Llama(model_path=weights, n_ctx=8192, n_gpu_layers=-1,
                logits_all=True, verbose=False)
    temp, knockout = temperatures(GGUF_FILE)
    print(f"jevk5 ready: {GGUF_FILE} (T={temp}, knockT={knockout})", flush=True)

    def logprobs(prompt):
        ids = llm.tokenize(prompt.encode(), add_bos=False, special=True)
        llm.reset()
        llm.eval(ids)
        lps = Llama.logits_to_logprobs(llm.scores[len(ids) - 1])
        top = np.argpartition(-lps, TOP_K)[:TOP_K]
        seen = {llm.detokenize([int(i)]).decode("utf-8", "replace"): float(lps[i])
                for i in top}
        return seen, len(ids)

    def probabilities(state, question):
        """The same readout as jevk5.gguf.JevK5GGUF.probabilities, in-process."""
        options = decision_options(question)
        tokens = 0

        def read(texts):
            nonlocal tokens
            seen, count = logprobs(prompt_text(state, question["instructions"], texts))
            tokens += count
            floor = min(seen.values(), default=0.0) - MISSING_MARGIN
            lps = [seen.get(LETTERS[i], floor) for i in range(len(texts))]
            top = max(lps)
            weights = [math.exp((z - top) / temp) for z in lps]
            total = sum(weights)
            return [w / total for w in weights]

        second = knockout
        probs = spread(read, [text for _, text in options], "knockout", second)
        return {key: v for (key, _), v in zip(options, probs)}, tokens

    def to_answer(question, result, tokens):
        qtype = question.get("type")
        probs = result or {}
        if qtype == "noul":
            return {"type": "noul", "noul": probs.get("true", 0.0),
                    "confidence": max(probs.values(), default=0.0),
                    "input_tokens": tokens}
        if qtype == "score":
            levels = [str(i) for i in range(len(question["criteria"]))]
            return {"type": "score",
                    "score": sum(int(k) * v for k, v in probs.items()),
                    "confidence": max(probs.values()) if probs else 0.0,
                    "legend": dict(zip(levels, question["criteria"])),
                    "probabilities": probs}
        choice = max(probs, key=probs.get) if probs else None
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
                usage = 0
                for qid, q in req["questions"].items():
                    probs, tokens = probabilities(req["state"], q)
                    answers[qid] = to_answer(q, probs, tokens)
                    usage += tokens
                self._send(200, {"model": req.get("model") or GGUF_FILE,
                                 "usage": {"input_tokens": usage, "output_tokens": 0},
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

    print(f"jevk5 serving on http://127.0.0.1:{PORT}/v1/systemone", flush=True)
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
