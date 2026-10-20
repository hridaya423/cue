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
from s1http import serve

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

    def respond(req):
        state = req["state"]
        if not isinstance(state, str):
            state = json.dumps(state, ensure_ascii=False)
        with torch.inference_mode():
            return normalize(model.system_one(tok, state=state, questions=req["questions"]))

    serve("truetype", port, respond, {"model": SERVE_MODEL})


if __name__ == "__main__":
    main()
