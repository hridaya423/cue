"""Blind A/B packets from a CueDay run: each paste step as two unlabeled transcripts.

python3 -I Evals/days/blind.py <results dir> <out dir>
Writes <persona>.md (what the critic reads) and <persona>.key.json (which side is Cue).
"""
import json
import random
import sys
from pathlib import Path


def side(keys, wait_ms, landed, seconds):
    shown = landed if len(landed) <= 160 else landed[:157] + "…"
    return (f"pressed {' '.join(keys)}; waited {wait_ms:.0f} ms for the app; "
            f"total ≈ {seconds:.2f} s; landed: {json.dumps(shown)}")


def main(src, out):
    out.mkdir(parents=True, exist_ok=True)
    rng = random.Random(7)
    for path in sorted(src.glob("*.jsonl")):
        persona = path.stem
        lines, key = [f"# {persona}: one workday, paste by paste\n"], {}
        for raw in path.read_text().splitlines():
            r = json.loads(raw)
            if "cue" not in r:
                continue
            c, b = r["cue"], r["bar"]
            keys, final = list(c["keys"]), c["landed"]
            # The harness reads text back out of WebKit, which renders quotes and indents typographically;
            # what the person got is the text that was pasted.
            if c["correct"]:
                final = b["landed"]
            elif c.get("trimmed"):
                keys.append("trim×4")
                final = b["landed"]
            elif c.get("undo"):
                keys += ["then:"] + b["keys"]
                final = b["landed"]
            cue = side(keys, c["decision_ms"], final, c["est_s"])
            bar = side(b["keys"], 0, b["landed"], b["est_s"])
            a_is_cue = rng.random() < 0.5
            a, bb = (cue, bar) if a_is_cue else (bar, cue)
            key[str(r["step"])] = "A" if a_is_cue else "B"
            want = r["want"]
            lines.append(
                f"## step {r['step']} — {r['why']}\n"
                f"Field: {r['into']} · wanted: {json.dumps(want)}\n"
                f"- **A**: {a}\n- **B**: {bb}\n")
        (out / f"{persona}.md").write_text("\n".join(lines))
        (out / f"{persona}.key.json").write_text(json.dumps(key, indent=0))




def unblind(out):
    """python3 -I Evals/days/blind.py --score <out dir>: critic verdicts → Cue wins / ties / losses."""
    total = {"cue": 0, "bar": 0, "tie": 0}
    for v in sorted(out.glob("*.verdict.json")):
        persona = v.name.split(".")[0]
        key = json.loads((out / f"{persona}.key.json").read_text())
        steps = json.loads(v.read_text())["steps"]
        n = {"cue": 0, "bar": 0, "tie": 0}
        losses = []
        for step, pick in steps.items():
            who = "tie" if pick == "tie" else ("cue" if pick == key.get(step) else "bar")
            n[who] += 1
            if who == "bar":
                losses.append(step)
        for k in total:
            total[k] += n[k]
        print(f"{persona}: cue {n['cue']} · tie {n['tie']} · bar {n['bar']}  losses: {' '.join(losses)}")
    print(f"total: cue {total['cue']} · tie {total['tie']} · bar {total['bar']}")


if __name__ == "__main__":
    if sys.argv[1] == "--score":
        unblind(Path(sys.argv[2]))
    else:
        main(Path(sys.argv[1]), Path(sys.argv[2]))
