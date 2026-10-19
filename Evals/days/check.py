#!/usr/bin/env python3
"""Validates the persona day traces: python3 -I Evals/days/check.py

History model: each copy moves its text to the front; a repeated copy dedupes
(Clip ids are a hash of the text). `k` counts distinct clips back, latest = 1.
"""
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path

HERE = Path(__file__).resolve().parent
PERSONAS = ["recruiter", "engineer", "founder"]
KINDS = {"web", "native-text", "native-field"}
NON_TEXT_INPUT = {"hidden", "button", "submit", "checkbox", "radio", "file", "image", "reset", "range", "color"}
CUE_WINDOW = 20  # OptionBuilder.recentWindow

errors: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.title = ""
        self._in_title = False
        self.fields: dict[str, dict] = {}   # id -> {tag, type, editable}
        self.external: list[str] = []
        self.scripts = 0

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "title":
            self._in_title = True
        if tag == "script":
            self.scripts += 1
        for key in ("src", "href"):
            v = a.get(key, "") or ""
            if tag in ("script", "img", "iframe", "source", "video", "audio", "embed") and key == "src" and v:
                self.external.append(f"<{tag} src={v}>")
            if tag == "link" and key == "href" and v:
                self.external.append(f"<link href={v}>")
        for v in a.values():
            if v and ("url(http" in v or "@import" in v):
                self.external.append(v)
        fid = a.get("id")
        if fid:
            typ = (a.get("type") or "text").lower()
            ce = a.get("contenteditable")
            editable = (
                (tag == "input" and typ not in NON_TEXT_INPUT)
                or tag == "textarea"
                or (ce is not None and ce.lower() != "false")
            )
            if fid in self.fields:
                err(f"duplicate id {fid!r}")
            self.fields[fid] = {"tag": tag, "type": typ, "editable": editable}

    def handle_endtag(self, tag):
        if tag == "title":
            self._in_title = False

    def handle_data(self, data):
        if self._in_title:
            self.title += data


def load_surfaces():
    surfaces = json.loads((HERE / "surfaces.json").read_text())
    if isinstance(surfaces, dict):
        surfaces = surfaces.get("surfaces", [])
    by_id: dict[str, dict] = {}
    pages: dict[str, Page] = {}
    for s in surfaces:
        sid = s.get("id", "?")
        if sid in by_id:
            err(f"surface {sid}: duplicate id")
        by_id[sid] = s
        for key in ("id", "app", "bundle", "window", "kind"):
            if not s.get(key):
                err(f"surface {sid}: missing {key}")
        kind = s.get("kind")
        if kind not in KINDS:
            err(f"surface {sid}: bad kind {kind!r}")
        elif kind == "web":
            if not s.get("host"):
                err(f"surface {sid}: web surface needs host")
            rel = s.get("page")
            if not rel:
                err(f"surface {sid}: web surface needs page")
                continue
            p = HERE / "pages" / rel
            if not p.is_file():
                err(f"surface {sid}: page {rel} missing")
                continue
            pg = Page()
            pg.feed(p.read_text())
            if not pg.title.strip():
                err(f"page {rel}: empty <title>")
            if pg.scripts:
                err(f"page {rel}: contains <script>")
            for x in pg.external:
                err(f"page {rel}: external reference {x}")
            pages[sid] = pg
        else:
            f = s.get("field")
            if not isinstance(f, dict) or not all(k in f for k in ("role", "label", "placeholder")):
                err(f"surface {sid}: native surface needs field{{role,label,placeholder}}")
    return by_id, pages


def parse_target(target, by_id, pages, ctx, secure=False):
    if "#" not in target:
        err(f"{ctx}: target {target!r} lacks #field")
        return
    sid, fid = target.split("#", 1)
    s = by_id.get(sid)
    if not s:
        err(f"{ctx}: unknown surface {sid!r}")
        return
    if s["kind"] == "web":
        pg = pages.get(sid)
        f = pg.fields.get(fid) if pg else None
        if f is None:
            err(f"{ctx}: id {fid!r} not in page of {sid}")
        elif not f["editable"]:
            err(f"{ctx}: {sid}#{fid} is not an input/textarea/contenteditable")
        elif secure and f["type"] != "password":
            err(f"{ctx}: secure target {target} is not type=password")
        elif not secure and f["type"] == "password":
            err(f"{ctx}: paste into password field {target} must be a secure event")
    elif fid != "main":
        err(f"{ctx}: native surface {sid} only has field 'main'")


def check_persona(name, by_id, pages):
    path = HERE / f"{name}.jsonl"
    if not path.is_file():
        err(f"{name}: {path.name} missing")
        return None
    hist: list[str] = []
    counts = dict(latest=0, earlier=0, part=0, plain=0, ambiguous=0, secure=0)
    copies = 0
    distances: list[int] = []
    part_kinds = []
    last_t = "00:00"
    n = 0
    first_t = last_seen = None
    for ln, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip():
            continue
        n += 1
        ctx = f"{name}:{ln}"
        try:
            e = json.loads(line)
        except json.JSONDecodeError as ex:
            err(f"{ctx}: bad JSON ({ex})")
            continue
        t = e.get("t", "")
        if not re.fullmatch(r"\d\d:\d\d", t):
            err(f"{ctx}: bad time {t!r}")
            continue
        if t < last_t:
            err(f"{ctx}: time {t} before {last_t}")
        last_t = t
        if not ("09:00" <= t <= "18:30"):
            err(f"{ctx}: {t} outside 09:00-18:30")
        first_t = first_t or t
        last_seen = t
        kinds = [k for k in ("copy", "paste", "secure") if k in e]
        if len(kinds) != 1:
            err(f"{ctx}: need exactly one of copy/paste/secure")
            continue
        if "copy" in e:
            c = e["copy"]
            text, frm = c.get("text"), c.get("from")
            if not text:
                err(f"{ctx}: empty copy text")
                continue
            if frm not in by_id:
                err(f"{ctx}: copy from unknown surface {frm!r}")
            copies += 1
            if text in hist:
                hist.remove(text)
            hist.insert(0, text)
        elif "secure" in e:
            parse_target(e["secure"].get("into", ""), by_id, pages, ctx, secure=True)
            counts["secure"] += 1
        else:
            p = e["paste"]
            parse_target(p.get("into", ""), by_id, pages, ctx)
            if not isinstance(p.get("value_before", ""), str):
                err(f"{ctx}: value_before must be a string")
            if not p.get("why"):
                err(f"{ctx}: missing why")
            want = p.get("want", {})
            if not hist:
                err(f"{ctx}: paste before any copy")
                continue
            if want.get("plain") is True:
                counts["plain"] += 1
            elif "choose" in want:
                opts = want["choose"]
                if len(opts) < 2:
                    err(f"{ctx}: choose needs 2+ strings")
                for o in opts:
                    if not any(o in h for h in hist):
                        err(f"{ctx}: choose string not in history: {o[:50]!r}")
                counts["ambiguous"] += 1
            elif "paste" in want:
                w = want["paste"]
                if w in hist:
                    k = hist.index(w) + 1
                    if k == 1:
                        counts["latest"] += 1
                    else:
                        counts["earlier"] += 1
                        distances.append(k)
                elif any(w in h for h in hist):
                    counts["part"] += 1
                    src = next(i for i, h in enumerate(hist) if w in h) + 1
                    part_kinds.append((w, src))
                else:
                    err(f"{ctx}: want.paste is neither a clip nor a substring of one: {w[:60]!r}")
            else:
                err(f"{ctx}: want must have paste, choose or plain")
    return dict(n=n, copies=copies, counts=counts, distances=distances, parts=part_kinds,
                span=(first_t, last_seen))


def main():
    by_id, pages = load_surfaces()
    for sid, s in by_id.items():
        if s["kind"] == "web" and sid not in pages:
            continue
    results = {p: check_persona(p, by_id, pages) for p in PERSONAS}

    used = set()
    for p in PERSONAS:
        path = HERE / f"{p}.jsonl"
        if path.is_file():
            for line in path.read_text().splitlines():
                if not line.strip():
                    continue
                e = json.loads(line)
                if "copy" in e:
                    used.add(e["copy"]["from"])
                elif "paste" in e:
                    used.add(e["paste"]["into"].split("#")[0])
                elif "secure" in e:
                    used.add(e["secure"]["into"].split("#")[0])
    for sid in by_id:
        if sid not in used:
            print(f"warn: surface {sid} is never used")
    pages_dir = HERE / "pages"
    referenced = {s.get("page") for s in by_id.values()}
    for f in sorted(pages_dir.glob("*.html")):
        if f.name not in referenced:
            print(f"warn: page {f.name} is not referenced by any surface")

    for p, r in results.items():
        if not r:
            continue
        c = r["counts"]
        pastes = sum(c.values())
        pct = lambda v: f"{100 * v / pastes:.0f}%" if pastes else "-"
        print(f"\n{p}: {r['n']} events {r['span'][0]}-{r['span'][1]}, {r['copies']} copies, {pastes} pastes")
        print("  latest {latest} ({a})  earlier {earlier} ({b})  part {part} ({d})  "
              "nothing-fits {plain} ({e})  ambiguous {ambiguous}  secure {secure}".format(
                  a=pct(c["latest"]), b=pct(c["earlier"]), d=pct(c["part"]), e=pct(c["plain"]), **c))
        if r["distances"]:
            far = [k for k in r["distances"] if k > CUE_WINDOW]
            print(f"  earlier distances (clips back): {sorted(r['distances'])}"
                  f"  beyond Cue's {CUE_WINDOW}-clip window: {len(far)}")
        if r["parts"]:
            print("  parts: " + "; ".join(f"{w[:28]!r}@k{k}" for w, k in r["parts"]))

    if errors:
        print(f"\n{len(errors)} error(s):")
        for x in errors[:80]:
            print("  -", x)
        sys.exit(1)
    print("\nOK")


if __name__ == "__main__":
    main()
