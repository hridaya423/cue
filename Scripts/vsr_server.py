#!/usr/bin/env python3
"""vLLM Semantic Router Decision models behind /v1/systemone, for Cue.

    python3 Scripts/vsr_server.py <port> <hf-repo> <serve-model> <snapshot>

vllm-sr/Decision-2.0-* models expose `model.system_one(state=..., questions=...)`
via trust_remote_code, so the shim is thin: load, translate, serve.
"""
import json
import sys
from s1http import serve

REPO = sys.argv[2] if len(sys.argv) > 2 else None
SERVE_MODEL = sys.argv[3] if len(sys.argv) > 3 else "decision"


def pick_revision(repo):
    """The vendored runtime sha256-verifies the whole bundle against
    MODEL_MANIFEST.json — but upstream has edited README/card metadata after a
    release, which breaks verification at HEAD. Release commits co-commit
    weights+manifest, so a revision whose README hash matches its own manifest
    is self-consistent. Newest match wins; None = try HEAD anyway. Offline:
    None too — cached weights may still load."""
    import hashlib
    from huggingface_hub import HfApi, hf_hub_download
    try:
        commits = HfApi().list_repo_commits(repo)
    except Exception:
        return None
    for commit in commits:
        try:
            man = json.loads(open(hf_hub_download(repo, "MODEL_MANIFEST.json",
                                                  revision=commit.commit_id)).read())
            want = (man.get("files_sha256") or {}).get("README.md")
            got = hashlib.sha256(open(hf_hub_download(repo, "README.md",
                                                      revision=commit.commit_id), "rb").read()).hexdigest()
            if want and want == got:
                return commit.commit_id
        except Exception:
            continue
    return None


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
    revision = pick_revision(REPO)
    print(f"loading {REPO}@{revision or 'main'} on {device}…", flush=True)
    # Decision 2.0 fixes its own numerics (FP32 CPU / BF16 GPU): no dtype kwarg,
    # and `device` is a load-time option, not a post-load .to().
    kwargs = {"trust_remote_code": True, "device": device}
    if revision:
        kwargs["revision"] = revision
    model = AutoModel.from_pretrained(REPO, **kwargs)
    model.eval()
    port = int(sys.argv[1])

    def respond(req):
        with torch.inference_mode():
            return normalize(model.system_one(state=req["state"], questions=req["questions"]))

    serve("vsr decision", port, respond, {"model": SERVE_MODEL, "device": device})


if __name__ == "__main__":
    main()
