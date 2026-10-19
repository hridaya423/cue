#!/usr/bin/env python3
"""System One server for decider checkpoints on Apple Silicon via MLX (mlx-lm qwen3_5).

Same wire contract as `decider.serve` POST /v1/systemone: prompt rows are built by
decider.prompt_fast / decider.systemone, answer slots are read by projecting the hidden
state on the option-letter rows of the (tied) LM head, temperatures come from
decider.temperature, and the response is decider.systemone.assemble — unchanged.  Only
the forward pass is MLX instead of torch/MPS.  Binds 127.0.0.1 only.

    DECIDER_MODEL=Mapika/decider-0.8b python Scripts/decider_mlx_server.py

Env (default):  DECIDER_MODEL (Mapika/decider-0.8b)  DECIDER_PORT (8791)  DECIDER_MLX_DTYPE (float16|bfloat16|float32)
  DECIDER_SHARED (1)  DECIDER_SHARED_MIN_TOKENS (768)  DECIDER_SHARED_FORK_GB (8)  DECIDER_SHARED_SUFFIX_TOKENS (65536)
  DECIDER_PREFILL_CHUNK (1024)  DECIDER_MAX_STATE_TOKENS (32768)  DECIDER_WARMUP (1)  DECIDER_TEMPERATURE (unset)
  DECIDER_LAYOUT (unset: the layout of decider_config.json)
"""
import asyncio
import importlib.util
import json
import os
import sys
import time


class _NoTorch:
    """decider-ai pulls torch into the venv and transformers 5 imports it whenever it is installed (~0.5 GB),
    though this server runs on MLX and never calls it. Report it as absent so transformers takes its torch-free path."""

    def find_spec(self, name, path=None, target=None):
        if name == "torch" or name.startswith("torch."):
            raise ModuleNotFoundError(f"No module named {name!r}", name=name)
        return None


sys.meta_path.insert(0, _NoTorch())
_find_spec = importlib.util.find_spec
importlib.util.find_spec = lambda name, *a: None if name == "torch" or name.startswith("torch.") else _find_spec(name, *a)
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from pathlib import Path

import mlx.core as mx
import numpy as np
from fastapi import FastAPI, HTTPException, Request
from mlx.utils import tree_flatten
from mlx_lm.models import qwen3_5
from mlx_lm.models.cache import make_prompt_cache
from pydantic import BaseModel

from decider import systemone as S1
from decider import temperature as TT
from decider.prompt import MAX_OPTIONS, chat_template, letter_ids, resolve_layout, with_layout
from decider.prompt_fast import build_rows, unique_tokens


def _env_int(name, default):
    return int(os.environ.get(name, default))


# Cue's model manager launches shims as `<script> <port> <weights> <serveModel> <snapshot>`; env covers manual runs.
_ARGV = sys.argv[1:]
MODEL = _ARGV[1] if len(_ARGV) > 1 and _ARGV[1] else os.environ.get("DECIDER_MODEL", "Mapika/decider-0.8b")
PORT = int(_ARGV[0]) if _ARGV else _env_int("DECIDER_PORT", 8791)
MLX_DTYPE = os.environ.get("DECIDER_MLX_DTYPE", "float16")   # decider's own MPS dtype (infer.default_dtype): closest parity vs torch
DTYPES = {"bfloat16": mx.bfloat16, "float16": mx.float16, "float32": mx.float32}
MAX_STATE_TOKENS = _env_int("DECIDER_MAX_STATE_TOKENS", 32768)
MAX_ROWS = _env_int("DECIDER_MAX_ROWS", 1024)
MAX_ROW_TOKENS = _env_int("DECIDER_MAX_ROW_TOKENS", MAX_STATE_TOKENS + 4096)
MAX_REQUEST_TOKENS = _env_int("DECIDER_MAX_REQUEST_TOKENS", 1 << 20)
SHARED = os.environ.get("DECIDER_SHARED", "1") == "1"
SHARED_MIN_TOKENS = _env_int("DECIDER_SHARED_MIN_TOKENS", 768)
SHARED_FORK_GB = float(os.environ.get("DECIDER_SHARED_FORK_GB", "8"))
SHARED_SUFFIX_TOKENS = _env_int("DECIDER_SHARED_SUFFIX_TOKENS", 65536)
PREFILL_CHUNK = _env_int("DECIDER_PREFILL_CHUNK", 1024)
WARMUP = os.environ.get("DECIDER_WARMUP", "1") == "1"
TOKENIZE_THREADS = _env_int("DECIDER_TOKENIZE_THREADS", 8)
# MLX's buffer cache keeps a buffer per new request shape; kev measured 1.0 GB cached vs 3.7 GB unbounded, same latency.
# An 8 GB Mac can't spare the gigabyte, so there it holds 256 MB and trades some speed for memory.
_RAM = os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES")
CACHE_LIMIT = (1 << 30) if _RAM > 8 * (1 << 30) else (256 << 20)

MODEL_NAME = "decider"; TEMP = 1.0; TEMP_BY_TYPE = {}
RELEASE_DATE = "2026-09-17"; ISOLATED = False
LAYOUT = "plain"; CHAT = None
eng = None; gpu = None; cpu = None
gpu_turn = asyncio.Lock()
stats = dict(dropped_disconnected=0, requests=0, decisions=0, rows=0, shared_prefix_requests=0, errors=0, rejected_too_large=0)


# ---- model loading (kev/mlx_model.py's load_full, reduced to what a qwen3_5_text checkpoint needs) ----
def _snapshot_dir(model):
    """Local directory of a Hub repo id (or the directory itself)."""
    if os.path.isdir(model):
        return Path(model)
    from huggingface_hub import snapshot_download
    return Path(snapshot_download(model))


def load_backbone(ckpt_dir, dtype_name):
    """mlx-lm's qwen3_5.Model holding a full-weight qwen3_5_text checkpoint (decider's own config.json and
    safetensors shards, transformers naming).  Strict on names, shapes and dtype like kev.mlx_model.load_full;
    tensors stored in another dtype are cast to `dtype_name` (bf16 -> fp16/fp32 are the useful cases)."""
    ckpt_dir = Path(ckpt_dir)
    config = json.loads((ckpt_dir / "config.json").read_text(encoding="utf-8"))
    if config.get("model_type") != "qwen3_5_text" or "text_config" in config:
        raise ValueError(f"{ckpt_dir}: expected a qwen3_5_text checkpoint (transformers' Qwen3_5TextModel config); "
                         f"config.json has model_type {config.get('model_type')!r}")
    if dtype_name not in DTYPES:
        raise ValueError(f"DECIDER_MLX_DTYPE={dtype_name!r}: expected one of {', '.join(DTYPES)}")
    want = DTYPES[dtype_name]
    args = qwen3_5.ModelArgs.from_dict(config)
    text = qwen3_5.TextModelArgs.from_dict(args.text_config)
    pattern = ["full_attention" if (i + 1) % text.full_attention_interval == 0 else "linear_attention"
               for i in range(text.num_hidden_layers)]
    if config.get("layer_types", pattern) != pattern:
        raise ValueError(f"{ckpt_dir}: config.json's layer_types are not every {text.full_attention_interval}th layer "
                         "full attention, the only layout mlx-lm's qwen3_5 builds")
    mx.set_cache_limit(CACHE_LIMIT)
    lm = qwen3_5.Model(args)
    weights = {}
    for shard in sorted(ckpt_dir.glob("*.safetensors")):
        for name, value in mx.load(str(shard)).items():
            if name in weights:
                raise ValueError(f"{ckpt_dir}: tensor {name} is in more than one shard")
            weights[name] = value
    conv = [k for k in weights if k.endswith("linear_attn.conv1d.weight")]
    if not conv or any(weights[k].ndim != 3 or weights[k].shape[1] != 1 for k in conv):
        # sanitize infers "transformers layout, shift the norms" from the conv kernels; anything else would load wrong norms silently
        raise ValueError(f"{ckpt_dir}: expected transformers' DeltaNet conv kernels [channels, 1, width]")
    weights = lm.sanitize(weights)   # model.language_model.X -> language_model.model.X, conv to MLX layout, 1+w norms
    expected = {k: v.shape for k, v in tree_flatten(lm.parameters())}
    missing = sorted(set(expected) - set(weights)); unexpected = sorted(set(weights) - set(expected))
    wrong = sorted(k for k in set(expected) & set(weights) if tuple(weights[k].shape) != tuple(expected[k]))
    if missing or unexpected or wrong:
        strip = lambda names: [n.removeprefix("language_model.model.") for n in names[:2]]
        raise ValueError(f"{ckpt_dir} does not match mlx-lm's Qwen3.5 text model: {len(missing)} tensors missing "
                         f"(e.g. {strip(missing)}), {len(unexpected)} unexpected (e.g. {strip(unexpected)}), "
                         f"{len(wrong)} with another shape (e.g. {strip(wrong)})")
    if dtype_name != "bfloat16":   # the released checkpoints are bf16; cast once at load
        weights = {k: (v.astype(want) if v.dtype != want else v) for k, v in weights.items()}
    elif any(v.dtype != want for v in weights.values()):
        raise ValueError(f"{ckpt_dir}: checkpoint tensors are not all bfloat16")
    lm.load_weights(list(weights.items()), strict=True)
    del weights
    lm.eval()
    mx.eval(lm.parameters())
    mx.clear_cache()
    return lm, config


# ---- request preparation (CPU): decider.serve.prepare, verbatim ------------------
def prepare(tok, state, questions, independent, isolated=False, max_state_tokens=32768, chat=None):
    ctx = S1.render_state(state)
    rqs = {k: S1.render_question(v) for k, v in questions.items()}
    flat, index = S1.plan_rows(rqs, isolated and independent)
    pairs = [(r["question"], list(r["options"])) for r in flat]
    rows = [[p] for p in pairs] if independent else [pairs]
    items, ctx_len = build_rows(tok, ctx, rows, max_ctx_tokens=max_state_tokens, chat=chat)
    types = S1.row_types(rqs, index)
    for it, ts in zip(items, [[t] for t in types] if independent else [types]):
        it["types"] = ts
    return rqs, index, items, ctx_len


def _prepare_s1(state, questions, independent):
    return prepare(eng.tok, state, questions, independent, ISOLATED, MAX_STATE_TOKENS, chat=CHAT)


def check_size(row_lengths):
    n, total, longest = len(row_lengths), sum(row_lengths), max(row_lengths, default=0)
    if n > MAX_ROWS:
        msg = f"too many questions: the request expands to {n} scoring rows, the limit is {MAX_ROWS} (DECIDER_MAX_ROWS)"
    elif longest > MAX_ROW_TOKENS:
        msg = f"too many tokens: one row has {longest} tokens, the limit is {MAX_ROW_TOKENS} per row (DECIDER_MAX_ROW_TOKENS)"
    elif total > MAX_REQUEST_TOKENS:
        msg = f"too many tokens: the request has {total} tokens over {n} rows, the limit is {MAX_REQUEST_TOKENS} (DECIDER_MAX_REQUEST_TOKENS)"
    else:
        return
    stats["rejected_too_large"] += 1
    raise HTTPException(413, msg)


# ---- the MLX engine: hidden states from mlx-lm, the decider readout over option letters ----
def _common_prefix_len(ids):
    """Length of the longest common prefix of the rows, capped one token below the shortest row (decider.shared_prefix)."""
    lcp = 0
    short = min(len(x) for x in ids) - 1
    while lcp < short and all(x[lcp] == ids[0][lcp] for x in ids):
        lcp += 1
    return lcp


def _plan_chunks(suffix_lens, m, tokens):
    """Contiguous (start, end) chunks: at most m rows each, rows x the chunk's longest suffix within `tokens`
    (decider.shared_prefix.plan_chunks)."""
    out, i, n = [], 0, len(suffix_lens)
    while i < n:
        j, longest = i + 1, suffix_lens[i]
        while j < n and j - i < m and (j - i + 1) * max(longest, suffix_lens[j]) <= tokens:
            longest = max(longest, suffix_lens[j]); j += 1
        out.append((i, j)); i = j
    return out


def _cache_nbytes(cache):
    total = 0
    for c in cache:
        s = c.state if isinstance(getattr(c, "state", None), (list, tuple)) else []
        for a in s:
            if a is not None:
                total += a.nbytes
    return total


def _padded(ids_list, T, pad):
    a = np.full((len(ids_list), T), pad, dtype=np.int32)
    for b, x in enumerate(ids_list):
        a[b, :len(x)] = x
    return mx.array(a)


class MLXEngine:
    """drop-in for decider.engine.Engine's score_items / score_shared on Metal."""

    def __init__(self, model):
        from transformers import AutoTokenizer
        ckpt = _snapshot_dir(model)
        self.tok = AutoTokenizer.from_pretrained(model)
        self.pad = self.tok.pad_token_id if self.tok.pad_token_id is not None else (self.tok.eos_token_id or 0)
        self.lm, config = load_backbone(ckpt, MLX_DTYPE)
        self.text = self.lm.language_model.model          # embeddings -> layers -> final norm = last_hidden_state
        letters = letter_ids(self.tok)
        self.W = self.text.embed_tokens.weight[letters].astype(mx.float32)   # tied LM head: embed rows ARE lm_head rows
        mx.eval(self.W)
        cap = config.get("final_logit_softcapping")
        self.softcap = float(cap) if cap else None
        self.dev = "mlx"; self.cfg = dict(backend="mlx", dtype=MLX_DTYPE, model=model)
        self.stats = dict(forwards=0, shared_prefix_calls=0, shared_chunks=0)

    def _letter_probs(self, h, rows, slots, nopts, temps, n_per_item):
        """h [B,T,H]; flat per-slot rows/slots/nopts/temps. -> one [n_q, MAX_OPTIONS] prob array per item."""
        idx = mx.array(rows, dtype=mx.int32), mx.array(slots, dtype=mx.int32)
        lg = (h[idx[0], idx[1]].astype(mx.float32) @ self.W.T)
        if self.softcap:
            lg = mx.tanh(lg / self.softcap) * self.softcap
        lg = np.asarray(lg)                                # [N, K] fp32, as the torch path's .float()
        lg[np.arange(MAX_OPTIONS)[None, :] >= np.asarray(nopts)[:, None]] = -np.inf
        if isinstance(temps, (list, tuple, np.ndarray)):
            lg = lg / np.asarray(temps, dtype=np.float32)[:, None]
        else:
            lg = lg / temps
        lg -= lg.max(axis=-1, keepdims=True)
        p = np.exp(lg); p /= p.sum(axis=-1, keepdims=True)
        bounds = np.cumsum(n_per_item)[:-1]
        return [x for x in np.split(p, bounds)]

    def score_items(self, items, temperature=1.0):
        """items: dicts from prompt_fast.build_rows -> per item a [n_slots, MAX_OPTIONS] prob array (Engine.score_items)."""
        if not items:
            return []
        lens = [len(it["ids"]) for it in items]
        # Padding a short row (a yes/no question) to a long one (a 20-option pick) costs more than a second
        # forward: a 1450-token pick batched with a 300-token form row took 875 ms, the two alone 373 + 55 ms.
        if len(items) > 1 and max(lens) * len(items) > 1.2 * sum(lens):
            return [p for i, it in enumerate(items)
                    for p in self.score_items([it], temperature=TT.item_slice(temperature, i, i + 1))]
        T = max(lens)
        ids = _padded([it["ids"] for it in items], T, self.pad)
        h = self.text(ids)
        self.stats["forwards"] += 1
        return self._letter_probs(
            h,
            [b for b, it in enumerate(items) for _ in it["slots"]],
            [s for it in items for s in it["slots"]],
            [n for it in items for n in it["nopts"]],
            TT.slot_temperatures(temperature, items),
            [len(it["slots"]) for it in items])

    def score_shared(self, items, temperature=1.0, min_prefix=192):
        """Rows that start with the same tokens (one state, one question per row): the prefix runs once into an
        mlx-lm prompt cache, the suffixes run on batched copies (decider.shared_prefix.score_shared's contract;
        returns None when the request does not qualify)."""
        ids = [it["ids"] for it in items]
        n = len(ids)
        if n < 2:
            return None
        lcp = _common_prefix_len(ids)
        if lcp < min_prefix:
            return None
        cache = make_prompt_cache(self.lm)
        pre = ids[0][:lcp]
        for start in range(0, lcp, PREFILL_CHUNK):
            self.text(mx.array([pre[start:start + PREFILL_CHUNK]], dtype=mx.int32), cache=cache)
            mx.eval([c.state for c in cache])              # keep each pass's cache materialized: bounded peak, as kev's prefix()
        self.stats["forwards"] += 1
        prefix_bytes = _cache_nbytes(cache)
        m = max(1, min(n, int(SHARED_FORK_GB * (1 << 30) // max(prefix_bytes, 1))))
        temps = TT.slot_temperatures(temperature, items)   # flat per-slot list or scalar; validates lengths early
        bounds = np.cumsum([0] + [len(it["slots"]) for it in items])
        out = []
        for i, j in _plan_chunks([len(x) - lcp for x in ids], m, SHARED_SUFFIX_TOKENS):
            part = items[i:j]
            b = len(part)
            forked = [type(c).merge([c] * b) for c in cache]     # copies the prefix state; `cache` is not mutated
            Ts = max(len(it["ids"]) for it in part) - lcp
            suf = _padded([it["ids"][lcp:] for it in part], Ts, self.pad)
            h = self.text(suf, cache=forked)
            self.stats["forwards"] += 1
            out += self._letter_probs(
                h,
                [r for r, it in enumerate(part) for _ in it["slots"]],
                [s - lcp for it in part for s in it["slots"]],
                [n_ for it in part for n_ in it["nopts"]],
                temps[bounds[i]:bounds[j]] if isinstance(temps, (list, tuple)) else temps,
                [len(it["slots"]) for it in part])
            del forked, h, suf
        self.stats["shared_prefix_calls"] += 1
        return out


# ---- start-up --------------------------------------------------------------------
def _apply_config(cfg):
    global MODEL_NAME, TEMP, TEMP_BY_TYPE, RELEASE_DATE, ISOLATED, LAYOUT, CHAT
    cfg = with_layout(cfg, os.environ.get("DECIDER_LAYOUT"))
    LAYOUT = resolve_layout(cfg)
    MODEL_NAME = "decider-" + str(cfg.get("version", "dev"))
    (TEMP, TEMP_BY_TYPE), _ = TT.from_config(cfg, os.environ.get("DECIDER_TEMPERATURE"))
    RELEASE_DATE = str(cfg.get("release_date", RELEASE_DATE))
    ISOLATED = bool(cfg.get("isolated_levels", False))


def _load_config(model):
    try:
        if os.path.isdir(model):
            return json.load(open(os.path.join(model, "decider_config.json")))
        from huggingface_hub import hf_hub_download
        return json.load(open(hf_hub_download(model, "decider_config.json")))
    except Exception:
        return {}


def _warmup():
    """One real request through the whole path (plus one shared-prefix fork when eligible) so the first real
    request does not pay Metal kernel compilation."""
    t = time.time()
    state = {"task": "smart-paste", "app": "Warmup", "window": "warm up the kernels " * 60,
             "field": {"role": "AXTextField", "label": "Email", "placeholder": "you@example.com"}}
    questions = {"pick": {"type": "choice", "instructions": "Choose the option that fits the field.",
                          "criteria": {f"c{i}": f"option {i} text · copied from Notes · 1m ago" for i in range(1, 7)}},
                 "form": {"type": "noul", "instructions": "Is the focused field part of a multi-field form?"}}
    _, _, items, _ = _prepare_s1(state, questions, True)
    if SHARED and len(items) > 1 and min(len(it["ids"]) for it in items) >= SHARED_MIN_TOKENS:
        eng.score_shared(items, temperature=TEMP)
    else:
        eng.score_items(items, temperature=TEMP)
    eng.score_items(items[:1], temperature=TEMP)           # single-row shape as well
    return time.time() - t


@asynccontextmanager
async def lifespan(app):
    global eng, gpu, cpu, CHAT
    _apply_config(_load_config(MODEL))
    gpu = ThreadPoolExecutor(max_workers=1, thread_name_prefix="gpu")
    cpu = ThreadPoolExecutor(max_workers=TOKENIZE_THREADS, thread_name_prefix="tok")
    loop = asyncio.get_running_loop()
    eng = await loop.run_in_executor(gpu, lambda: MLXEngine(MODEL))
    CHAT = chat_template(eng.tok) if LAYOUT == "chat" else None
    if WARMUP:
        t = await loop.run_in_executor(gpu, _warmup)
        print(f"[decider-mlx] warmup {t:.1f}s", flush=True)
    print("[decider-mlx] ready", json.dumps(dict(model=MODEL_NAME, layout=LAYOUT, dtype=MLX_DTYPE, temperature=TEMP,
                                               temperature_by_type=TT.effective(TEMP, TEMP_BY_TYPE),
                                               isolated_levels=ISOLATED, shared=SHARED)), flush=True)
    yield
    for ex in (gpu, cpu):
        if ex is not None:
            ex.shutdown(wait=False, cancel_futures=True)


app = FastAPI(title="decider-mlx", lifespan=lifespan)


# ---- routes -----------------------------------------------------------------------
class S1Req(BaseModel):
    state: object
    questions: dict
    model: str | None = None
    independent: bool = True
    layout: str | None = None


@app.post("/v1/systemone")
async def systemone(r: S1Req, request: Request):
    loop = asyncio.get_running_loop()
    try:
        rqs, index, items, ctx_len = await loop.run_in_executor(cpu, _prepare_s1, r.state, r.questions, r.independent)
    except ValueError as e:
        stats["errors"] += 1
        raise HTTPException(422, str(e))
    check_size([len(it["ids"]) for it in items])

    def _score(its):
        t = TT.for_items(TEMP, TEMP_BY_TYPE, its)
        if SHARED and len(its) > 1 and min(len(it["ids"]) for it in its) >= SHARED_MIN_TOKENS:
            out = eng.score_shared(its, temperature=t)
            if out is not None:
                stats["shared_prefix_requests"] += 1
                return out
        return eng.score_items(its, temperature=t)
    try:
        # Cue warms an answer on every focus change and cancels the stale one; a cancelled request still
        # queued here would hold the one GPU worker while the paste that replaced it waits behind it.
        async with gpu_turn:
            if await request.is_disconnected():
                stats["dropped_disconnected"] += 1
                raise HTTPException(499, "client went away")
            res = await loop.run_in_executor(gpu, _score, items)
    except Exception:
        stats["errors"] += 1
        raise
    probs = [p for ps in res for p in ps]
    stats["requests"] += 1; stats["decisions"] += len(rqs); stats["rows"] += len(items)
    return {"model": MODEL_NAME, "answers": S1.assemble(rqs, index, [p.tolist() for p in probs]),
            "usage": {"input_tokens": unique_tokens(items, ctx_len), "output_tokens": 0}}


@app.get("/v1/models")
async def models():
    return {"models": [{"name": MODEL_NAME, "description": "decider (MLX): one-pass typed decisions with calibrated probabilities",
                        "release_date": RELEASE_DATE}]}


@app.get("/health")
async def health():
    return {"ok": eng is not None, "model": MODEL, "device": "mlx", "dtype": MLX_DTYPE, "layout": LAYOUT,
            "temperature": TEMP, "temperature_by_type": TT.effective(TEMP, TEMP_BY_TYPE)}


@app.get("/stats")
async def get_stats():
    return dict(stats, engine=eng.stats if eng else None)


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=PORT, log_level="warning")
