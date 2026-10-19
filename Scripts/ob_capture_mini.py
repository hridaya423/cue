#!/usr/bin/env python3
"""Capture onboarding steps of the debug Cue build on the Mac mini, never on this Mac's screen.

    python3 Scripts/ob_capture_mini.py --build --steps 0,1,2 --appearances light,dark --out DIR [--burst 6] [--env K=V] [--tag NAME]

--build   swift build here, wrap .build/debug/Cue in a copy of build/Cue.app (run Scripts/bundle.sh once first),
          ad-hoc sign it and sync it to the mini as ~/cue-live/CueDebug[-TAG].app. A worktree without its own
          build/Cue.app borrows the main checkout's.
--tag     separates parallel builders: each gets its own bundle on the mini and its own temp files.
Each capture launches the app at OB_STEP with onboarding forced open (in-memory defaults only), waits, screenshots
the desktop through cua-driver, crops the Cue window by its reported bounds and writes
DIR/<step>-<appearance>[-<frame>].png at 1x. --burst N takes N frames back to back from launch (~0.3 s apart).
A lock directory on the mini serialises captures from parallel builders.
"""
import argparse
import json
import shlex
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
HOST = "mac-tailscale"
TEMPLATE = Path.home() / "Honey/smartcopypaste/build/Cue.app"
DRIVER = "~/.local/bin/cua-driver"
LOCK = "~/cue-live/.capture-lock"


def sh(cmd, **kw):
    return subprocess.run(cmd, shell=True, check=True, text=True, capture_output=True, **kw).stdout


def remote(cmd):
    return sh(f"ssh {HOST} {shlex.quote(cmd)}")


def build(app):
    sh("swift build --product Cue", cwd=ROOT)
    tmp = f"/tmp/{app}"
    template = ROOT / "build/Cue.app" if (ROOT / "build/Cue.app").exists() else TEMPLATE
    sh(f"rm -rf {tmp} && ditto {template} {tmp} && cp .build/debug/Cue {tmp}/Contents/MacOS/Cue"
       f" && rm -rf {tmp}/Contents/Resources/Cue_CueKit.bundle"
       f" && ditto .build/debug/Cue_CueKit.bundle {tmp}/Contents/Resources/Cue_CueKit.bundle"
       f" && codesign --force --deep -s - {tmp}", cwd=ROOT)
    sh(f"rsync -az --delete {tmp}/ {HOST}:cue-live/{app}/")


def capture(app, step, appearance, out, burst, env, wait):
    tag = app.removesuffix(".app")
    proc = f"{app}/Contents/MacOS/Cue"
    envs = " ".join(f"--env {shlex.quote(e)}" for e in [f"OB_STEP={step}", f"OB_APPEARANCE={appearance}", *env])
    frames = max(burst, 1)
    script = f"""
until mkdir {LOCK} 2>/dev/null; do sleep 1; done
trap 'rmdir {LOCK}; pkill -f {proc}' EXIT
pkill -f CueDebug; sleep 0.5
open -n {envs} ~/cue-live/{app} --args -onboardingDone NO -ApplePersistenceIgnoreState YES
for i in $(seq 1 40); do P=$(pgrep -f {proc}) && {DRIVER} call list_windows "{{\\"pid\\":$P}}" | grep -q Welcome && break; sleep 0.25; done
{'sleep ' + str(wait) if burst <= 1 else ''}
{DRIVER} call list_windows "{{\\"pid\\":$P}}" > /tmp/obwin-{tag}.json
for i in $(seq 1 {frames}); do {DRIVER} call get_desktop_state "{{\\"screenshot_out_file\\":\\"/tmp/obcap-{tag}-$i.png\\"}}" >/dev/null; done
"""
    remote(script)
    win = next(w for w in json.loads(remote(f"cat /tmp/obwin-{tag}.json"))["windows"] if w["title"] == "Welcome to Cue")
    b = win["bounds"]
    out.mkdir(parents=True, exist_ok=True)
    for i in range(1, frames + 1):
        local = Path(f"/tmp/obcap-{tag}-{i}.png")
        sh(f"scp -q {HOST}:{local} {local}")
        im = Image.open(local)
        s = im.width / 1920
        c = im.crop((round(b["x"] * s), round(b["y"] * s), round((b["x"] + b["width"]) * s), round((b["y"] + b["height"]) * s)))
        c = c.resize((round(b["width"]), round(b["height"])), Image.LANCZOS)
        name = f"{step}-{appearance}" + (f"-{i}" if burst > 1 else "") + ".png"
        c.save(out / name)
        print(out / name)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", action="store_true")
    ap.add_argument("--steps", default="0,1,2,3,4,5")
    ap.add_argument("--appearances", default="light,dark")
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--burst", type=int, default=0)
    ap.add_argument("--wait", type=float, default=2.5)
    ap.add_argument("--env", action="append", default=[])
    ap.add_argument("--tag", default="")
    a = ap.parse_args()
    app = f"CueDebug-{a.tag}.app" if a.tag else "CueDebug.app"
    if a.build:
        build(app)
    for st in a.steps.split(","):
        for ap_ in a.appearances.split(","):
            capture(app, st, ap_, a.out, a.burst, a.env, a.wait)


if __name__ == "__main__":
    sys.exit(main())
