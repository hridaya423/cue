#!/usr/bin/env python3
"""Replay captured /v1/systemone request bodies against two servers and report answer parity and warm latency.

    python3 Scripts/decider_mlx_parity.py <requests.jsonl> <urlA> <urlB> [--repeat N]

requests.jsonl: lines of {"path": ..., "body": "<the POST body as a JSON string>"} as written by a logging
proxy in front of CueEval (or plain request objects).  Every body is POSTed to both servers, interleaved,
`--repeat` times (default 1); the second pass onward is warm and timed.

Report: per-question max |Δp| over the option probabilities (choice/score `probabilities`, noul `noul`),
the number of argmax flips (choice winner, noul >= 0.5, score argmax), and per-server p50/p95 warm latency.
"""
import json
import statistics
import sys
import time
import urllib.error
import urllib.request


def post(url, body, timeout=120):
    req = urllib.request.Request(url, data=body.encode(), headers={"Content-Type": "application/json"})
    t = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return time.perf_counter() - t, json.loads(r.read())
    except urllib.error.HTTPError as e:
        try:
            return time.perf_counter() - t, json.loads(e.read())
        except Exception:
            return time.perf_counter() - t, {"answers": {}, "error": str(e)}


def prob_vector(ans):
    """(kind, {key: p}) for one answer: choice -> option probabilities, noul -> {false,true}, score -> level probs."""
    t = ans.get("type")
    if t == "noul":
        return "noul", {"no": 1.0 - ans["noul"], "yes": ans["noul"]}
    if t == "score":
        return "score", dict(ans.get("probabilities", {}))
    return "choice", dict(ans.get("probabilities", {}))


def main():
    path, url_a, url_b = sys.argv[1:4]
    repeat = int(sys.argv[sys.argv.index("--repeat") + 1]) if "--repeat" in sys.argv else 1
    bodies = []
    seen = set()
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        d = json.loads(line)
        body = d["body"] if isinstance(d, dict) and "body" in d else line
        if body not in seen:
            seen.add(body)
            bodies.append(body)
    print(f"{len(bodies)} unique request bodies")

    ans_a, ans_b = [], []
    lat_a, lat_b = [], []
    for rep in range(repeat):
        for i, body in enumerate(bodies):
            dt, r = post(url_a + "/v1/systemone", body)
            if rep > 0 or i >= 3:
                lat_a.append(dt)          # first 3 of pass 1 = warm-up, untimed
            ans_a.append((i, r["answers"]))
            dt, r = post(url_b + "/v1/systemone", body)
            if rep > 0 or i >= 3:
                lat_b.append(dt)
            ans_b.append((i, r["answers"]))

    max_dp, max_where, flips, compared = 0.0, None, 0, 0
    for (i, a), (j, b) in zip(ans_a, ans_b):
        assert i == j
        for qid in set(a) | set(b):
            if qid not in a or qid not in b:
                flips += 1
                continue
            ka, pa = prob_vector(a[qid]); kb, pb = prob_vector(b[qid])
            for k in set(pa) | set(pb):
                compared += 1
                d = abs(pa.get(k, 0.0) - pb.get(k, 0.0))
                if d > max_dp:
                    max_dp, max_where = d, (i, qid, k, pa.get(k, 0.0), pb.get(k, 0.0))
            wa, wb = max(pa, key=pa.get), max(pb, key=pb.get)
            if wa != wb:
                flips += 1
                print(f"  argmax flip req {i} q {qid}: {url_a} -> {wa} ({pa[wa]:.4f}), {url_b} -> {wb} ({pb[wb]:.4f})")

    q = lambda xs, p: (statistics.quantiles(xs, n=100)[p - 1] if xs else 0) * 1000
    print(f"\nparity over {len(bodies)} requests x{repeat}, {compared} option probabilities compared")
    print(f"  max |dp| = {max_dp:.4f}   at {max_where}")
    print(f"  argmax flips = {flips}")
    print(f"latency (warm, ms):  A {url_a}: p50 {q(lat_a,50):.0f}  p95 {q(lat_a,95):.0f}  n={len(lat_a)}")
    print(f"                     B {url_b}: p50 {q(lat_b,50):.0f}  p95 {q(lat_b,95):.0f}  n={len(lat_b)}")


if __name__ == "__main__":
    main()
