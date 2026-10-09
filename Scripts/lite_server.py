#!/usr/bin/env python3
"""JevK5-Lite behind TypeSafe's System One contract, for Cue.

    python3 Scripts/lite_server.py <port> <hf-repo> <serve-model> <snapshot>

437M DeBERTa-v3 CPU classifier (jevk5[lite] extra): each question becomes one
single-label "head" whose labels are the option descriptions; the head's
calibrated probabilities map back to option IDs. The model's label budget is
512 tokens total, so long criteria get truncated to short keys.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

REPO = sys.argv[2] if len(sys.argv) > 2 else "alibiserikbay/JevK5-Lite"
SERVE_MODEL = sys.argv[3] if len(sys.argv) > 3 else "JevK5-Lite"
MAX_LABEL = 60  # labels share the 512-token read budget with the text


def render_state(state):
    return state if isinstance(state, str) else json.dumps(state, ensure_ascii=False)


def labels_of(question):
    """(option_key, label) pairs — label is the criteria text, shortened and
    deduped so it round-trips through the probabilities dict."""
    if question.get("type") == "noul":
        return [("false", "does not fit"), ("true", "fits")]
    if question.get("type") == "score":
        pairs = [(str(i), str(lvl)) for i, lvl in enumerate(question["criteria"])]
    else:
        pairs = [(k, str(v)) for k, v in question["criteria"].items()]
    out, seen = [], {}
    for key, desc in pairs:
        label = desc[:MAX_LABEL]
        if label in seen:  # identical criteria: disambiguate by option id
            label = f"{key}: {desc[:MAX_LABEL - len(key) - 2]}"
        seen[label] = key
        out.append((key, label))
    return out


def main():
    import torch
    from jevk5 import JevK5Lite

    print(f"loading {REPO}…", flush=True)
    # fp32 + a small thread count is fastest on Apple Silicon CPU here;
    # the card's bf16 claim targets x86 AMX/AVX512-BF16, not M-series.
    lite = JevK5Lite.from_pretrained(REPO, dtype=torch.float32, threads=4)
    port = int(sys.argv[1])

    def decide(state, questions):
        """One encoder pass per request: every question's labels ride the
        same classify call as its own task head."""
        heads = {qid: [label for _, label in labels_of(q)]
                 for qid, q in questions.items()}
        tasks = "; ".join(f"{qid}: {q.get('instructions', '')}"
                          for qid, q in questions.items())
        text = f"Tasks: {tasks}\nContext: {state}"
        raw = lite.classify(text, heads)
        out = {}
        for qid, q in questions.items():
            probs = raw.get(qid, {}).get("probabilities", {})
            out[qid] = {key: probs.get(label, 0.0)
                        for key, label in labels_of(q)}
        return out

    def answer(question, probs):
        qtype = question.get("type")
        if qtype == "noul":
            return {"type": "noul", "noul": round(probs["true"], 4)}
        if qtype == "choice":
            choice = max(probs, key=probs.get)
            return {"type": "choice", "choice": choice, "confidence": round(probs[choice], 4),
                    "probabilities": {k: round(p, 4) for k, p in probs.items()}}
        levels = [str(i) for i in range(len(question["criteria"]))]
        return {"type": "score",
                "score": round(sum(int(i) * probs.get(i, 0.0) for i in levels), 4),
                "confidence": round(max(probs.values()), 4) if probs else 0.0,
                "legend": dict(zip(levels, question["criteria"])),
                "probabilities": {k: round(p, 4) for k, p in probs.items()}}

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
                state = render_state(req["state"])
                answers = {qid: answer(req["questions"][qid], probs)
                           for qid, probs in decide(state, req["questions"]).items()}
                self._send(200, {"model": req.get("model") or SERVE_MODEL,
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

    print(f"jevk5-lite serving on http://127.0.0.1:{port}/v1/systemone", flush=True)
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
