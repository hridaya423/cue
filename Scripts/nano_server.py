#!/usr/bin/env python3
"""tasksource-jev-nano behind TypeSafe's System One contract, for Cue.

    python3 Scripts/nano_server.py <port> <hf-repo> <serve-model> <snapshot>

149M ColBERT (PyLate) decision model: context = state + question, options are
scored by MaxSim late interaction, softmaxed at the checkpoint's temperature.
Recipe exactly as the model card documents.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

REPO = sys.argv[2] if len(sys.argv) > 2 else "tasksource/tasksource-jev-nano-v1"
SERVE_MODEL = sys.argv[3] if len(sys.argv) > 3 else "tasksource-jev-nano-v1"
TEMPERATURE = 0.31683406233787537  # decision_meta.json: init_temperature


def render_state(state):
    return state if isinstance(state, str) else json.dumps(state, ensure_ascii=False)


def option_label(key, desc):
    """The card's rendering: 'key: description', or the description alone for
    placeholder keys (A, option_1, ...)."""
    if desc and str(key).lower() not in {"a", "b", "c"} and not str(key).startswith("option"):
        return f"{key}: {desc}"
    return str(desc) if desc else str(key)


def main():
    import torch
    from pylate import models
    from pylate.scores import colbert_scores

    print(f"loading {REPO}…", flush=True)
    model = models.ColBERT(REPO)
    port = int(sys.argv[1])

    def decide(state, question):
        qtype = question.get("type")
        instructions = question.get("instructions", "")
        if qtype == "noul":
            options = [("false", "false"), ("true", "true")]
        elif qtype == "choice":
            options = [(k, option_label(k, v)) for k, v in question["criteria"].items()]
        else:  # score — ordered levels are the options
            options = [(str(i), lvl) for i, lvl in enumerate(question["criteria"])]
        ctx = model.encode([f"{state}\nQuestion: {instructions}"], is_query=False)[0]
        opts = model.encode([label for _, label in options], is_query=True)
        scores = torch.stack([
            colbert_scores(torch.as_tensor(o)[None], torch.as_tensor(ctx)[None])[0, 0]
            for o in opts
        ])
        probs = torch.softmax(scores / TEMPERATURE, 0).tolist()
        return dict(zip([k for k, _ in options], probs))

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
                "score": round(sum(int(i) * probs[i] for i in levels), 4),
                "confidence": round(max(probs.values()), 4),
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
                answers = {qid: answer(q, decide(state, q))
                           for qid, q in req["questions"].items()}
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

    print(f"jev-nano serving on http://127.0.0.1:{port}/v1/systemone", flush=True)
    HTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
