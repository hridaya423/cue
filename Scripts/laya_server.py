#!/usr/bin/env python3
"""Laya behind TypeSafe's System One contract, for Cue.

    pip install laya
    python3 Scripts/laya_server.py 8765 <hfRepo> <variant>   # POST http://127.0.0.1:8765/v1/systemone

The app launches it with the chosen variant ("laya" | "multilingual" | "typed-decisions") and only
that checkpoint is loaded: preloading all three cost 6.3 GB, one costs about a third of that.
Every request is answered by that checkpoint. With no variant given, the Router auto-picks per request.
"""
import os
import sys
from s1http import serve

import laya  # noqa: F401  — a clear ImportError here means: pip install laya
from laya import Router

MODELS = {"laya": "english", "multilingual": "multilingual", "typed-decisions": "typed-decisions"}


def answer(req):
    model = pinned or MODELS.get(req.get("model") or "")
    if model:
        res = router.predict(req["state"], req["questions"], model=model)
    else:
        res = router.predict(req["state"], req["questions"])
    answers = res["answers"] if "answers" in res else res
    for qid, q in req["questions"].items():
        if q.get("type") == "score" and qid in answers and "legend" not in answers[qid]:
            answers[qid]["legend"] = {str(i): lvl for i, lvl in enumerate(q["criteria"])}
    return {"model": req.get("model") or "laya",
            "usage": res.get("usage", {"input_tokens": 0, "output_tokens": 0}),
            "answers": answers}


if __name__ == "__main__":
    port = int(os.environ.get("LAYA_PORT", sys.argv[1] if len(sys.argv) > 1 else "8765"))
    pinned = MODELS.get(sys.argv[3]) if len(sys.argv) > 3 else None
    print(f"loading laya checkpoint {pinned or 'all'}…", flush=True)
    if pinned:
        router = Router(max_loaded=1)
        router.preload([pinned])
    else:
        router = Router(preload=True)
    serve("laya", port, answer)
