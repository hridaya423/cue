#!/usr/bin/env python3
"""Render onboarding steps of the debug Cue build and compare each against the
approved design reference PNG.

Usage:
    python3 Scripts/ob_compare.py <step-index|all> [--appearance light|dark] [--launch]

  step-index   0 welcome · 1 accessibility · 2 trigger · 3 models · 4 privacy · 5 practice
               'another' captures the practice "Try another" round
               (OB_PRACTICE=another) and compares it against 06.
  --launch     kill any running debug Cue, relaunch .build/debug/Cue with
               OB_STEP/OB_APPEARANCE set, screenshot the onboarding window to
               output/onboarding/compare/<step>-<appearance>-app.png, then quit it.
               Without --launch the existing app capture is reused.

Every invocation (re)writes
  output/onboarding/compare/<step>-<appearance>-compare.png
= [ reference | app capture | 50% overlay ] laid out horizontally, labelled.

Stdlib + Pillow only.
"""

import argparse
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / ".build" / "debug" / "Cue"
REF_DIR = ROOT / "docs" / "design" / "onboarding" / "references"
OUT_DIR = ROOT / "output" / "onboarding" / "compare"

# step index -> approved reference file (Step.allCases order in Onboarding.swift)
REFERENCES = [
    "01-welcome.png",
    "02-accessibility.png",
    "03-trigger.png",
    "04-models.png",
    "05-privacy.png",
    "06-practice-success.png",
]
STEP_NAMES = ["welcome", "accessibility", "trigger", "models", "privacy", "practice"]

# Polls CGWindowList for a window owned by the given pid: layer 0, at least
# 300pt tall, preferring one whose title contains "Welcome" (the title is only
# visible to callers that already hold Screen Recording permission). Prints
# "<windowID>\t<title>" on success, exits 2 on timeout.
# ponytail: 120s budget, not ~5s — on this box a fresh launch intermittently
# stalls for tens of seconds inside dyld's synchronous load notification
# (sampled: AppKit dlopening WritingToolsUILibraryCore →
# dyld4::RemoteNotificationResponder::blockOnSynchronousEvent). The window
# always arrives eventually; the stall is environmental, not the app's.
FIND_WINDOW_SWIFT = r"""
import CoreGraphics
import Darwin
import Foundation

let pid = Int(CommandLine.arguments[1])!
let deadline = Date().addingTimeInterval(120)
while Date() < deadline {
    let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
        as? [[String: Any]]) ?? []
    let mine = list.filter { w in
        guard (w[kCGWindowOwnerPID as String] as? Int) == pid,
              (w[kCGWindowLayer as String] as? Int) == 0,
              let b = w[kCGWindowBounds as String] as? [String: Any],
              (b["Height"] as? Double ?? 0) > 300
        else { return false }
        return true
    }
    if let w = mine.first(where: {
        ($0[kCGWindowName as String] as? String ?? "").contains("Welcome")
    }) ?? mine.first {
        let num = w[kCGWindowNumber as String] as? Int ?? 0
        let name = w[kCGWindowName as String] as? String ?? "<redacted>"
        print("\(num)\t\(name)")
        exit(0)
    }
    if kill(Int32(pid), 0) != 0 { exit(3) }  // app died before showing a window
    usleep(150_000)
}
fputs("ob_compare: no onboarding window for pid \(pid) within 120s\n", stderr)
exit(2)
"""


def fail(msg: str):
    print(f"ob_compare: error: {msg}", file=sys.stderr)
    sys.exit(1)


def find_window(pid: int) -> tuple[int, str]:
    """Return (CGWindowID, title) of the app's onboarding window, or fail."""
    try:
        r = subprocess.run(
            ["swift", "-e", FIND_WINDOW_SWIFT, str(pid)],
            capture_output=True, text=True, timeout=150,
        )
    except subprocess.TimeoutExpired:
        fail("timed out while polling CGWindowList (swift -e)")
    if r.returncode == 3:
        fail(f"app process {pid} exited before the onboarding window appeared")
    if r.returncode != 0 or not r.stdout.strip():
        fail("onboarding window not found within 120s — run "
             "`.build/debug/Cue` manually and check that the 'Welcome to Cue' "
             "window opens")
    num, _, title = r.stdout.strip().partition("\t")
    return int(num), title


JOB_LABEL = "com.cue.obcompare"


def launch_app(step: int, appearance: str, variant: str = "") -> int:
    """Launch the debug binary at `step` via launchctl submit, return its pid.

    launchd, not Popen: TCC attributes an unbundled binary to its responsible
    (bundled) ancestor — a terminal-spawned Cue inherits the terminal's
    Accessibility grant, which makes the accessibility step auto-advance to
    trigger before it ever paints (permissionStep's .task, Onboarding.swift).
    A launchd-submitted process has no bundled ancestor, so it evaluates its
    own — ungranted — TCC identity and every step renders as on first run.
    """
    subprocess.run(["launchctl", "remove", JOB_LABEL], capture_output=True)
    r = subprocess.run(
        ["launchctl", "submit", "-l", JOB_LABEL, "--",
         "/usr/bin/env", f"OB_STEP={step}", f"OB_APPEARANCE={appearance}",
         f"OB_PRACTICE={variant}" if variant else "OB_PRACTICE=",
         str(BIN),
         # NSArgumentDomain overrides only (in-memory, nothing persisted):
         # force onboarding open even where onboardingDone was left true.
         "-onboardingDone", "NO", "-ApplePersistenceIgnoreState", "YES"],
        capture_output=True, text=True)
    if r.returncode != 0:
        fail(f"launchctl submit failed: {r.stderr.strip() or r.stdout.strip()}")
    for _ in range(40):
        lst = subprocess.run(["launchctl", "list", JOB_LABEL],
                             capture_output=True, text=True).stdout
        m = re.search(r'"PID"\s*=\s*(\d+)', lst)
        if m:
            return int(m.group(1))
        time.sleep(0.25)
    fail(f"launchctl job {JOB_LABEL} never reported a pid\n{lst}")


def capture(step: int, appearance: str, out_png: Path, variant: str = "") -> str:
    """Launch the debug app at `step`, screenshot its window to `out_png`.
    Returns a short description of what was captured."""
    if not BIN.exists():
        fail(f"debug binary missing: {BIN} — run `swift build` first")
    # Kill only the debug binary (pattern matches both "./.build/debug/Cue"
    # and absolute argv[0]); bundled Cue.app lives elsewhere.
    subprocess.run(["pkill", "-9", "-f", "debug/Cue"], capture_output=True)

    pid = launch_app(step, appearance, variant)
    try:
        wid, title = find_window(pid)
        time.sleep(0.8)  # let SwiftUI finish its first layout + transition
        out_png.parent.mkdir(parents=True, exist_ok=True)
        r = subprocess.run(
            ["screencapture", "-x", "-o", "-l", str(wid), str(out_png)],
            capture_output=True, text=True,
        )
        if r.returncode != 0 or not out_png.exists() or out_png.stat().st_size == 0:
            fail(f"screencapture failed ({r.stderr.strip() or 'no output'}). "
                 "Grant Screen Recording to this terminal in System Settings → "
                 "Privacy & Security → Screen Recording, then retry.")
        try:
            with Image.open(out_png) as im:
                im.verify()
        except Exception:
            fail(f"screencapture produced an unreadable image at {out_png} "
                 "— Screen Recording permission is likely denied for this terminal.")
        return f"window {wid} ({title}) pid {pid}"
    finally:
        subprocess.run(["launchctl", "remove", JOB_LABEL], capture_output=True)
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def label_font() -> ImageFont.ImageFont:
    try:
        return ImageFont.load_default(size=28)
    except TypeError:  # very old Pillow without sized default font
        return ImageFont.load_default()


def label_panel(img: Image.Image, text: str, font) -> Image.Image:
    """Return img with a white label bar above it."""
    bar = 48
    out = Image.new("RGB", (img.width, img.height + bar), "white")
    out.paste(img.convert("RGB"), (0, bar))
    d = ImageDraw.Draw(out)
    d.text((12, (bar - getattr(font, "size", 12)) // 2),
           text, fill="black", font=font)
    return out


def compare(step: int, appearance: str, app_png: Path, cmp_png: Path) -> None:
    ref_path = REF_DIR / REFERENCES[step]
    if not ref_path.exists():
        fail(f"reference missing: {ref_path}")
    if not app_png.exists():
        fail(f"app capture missing: {app_png} — rerun with --launch")

    ref = Image.open(ref_path).convert("RGBA")
    app = Image.open(app_png).convert("RGBA")
    bbox = app.getbbox()
    if bbox:
        app = app.crop(bbox)  # drop any residual transparent border

    # Scale the app capture so its height matches the reference's.
    scale = ref.height / app.height
    app = app.resize((round(app.width * scale), ref.height), Image.LANCZOS)

    # 50% overlay on a shared canvas sized to the wider of the two.
    w = max(ref.width, app.width)
    c_ref = Image.new("RGBA", (w, ref.height), (255, 255, 255, 255))
    c_app = c_ref.copy()
    c_ref.paste(ref, ((w - ref.width) // 2, 0))
    c_app.paste(app, ((w - app.width) // 2, 0))
    overlay = Image.blend(c_ref, c_app, 0.5)

    font = label_font()
    panels = [
        label_panel(ref, f"reference · {ref_path.name}", font),
        label_panel(app, f"app · {app_png.name}", font),
        label_panel(overlay, "overlay @ 50%", font),
    ]
    gap, margin = 16, 16
    W = sum(p.width for p in panels) + gap * 2 + margin * 2
    H = max(p.height for p in panels) + margin * 2
    sheet = Image.new("RGB", (W, H), (235, 235, 235))
    x = margin
    for p in panels:
        sheet.paste(p, (x, margin))
        x += p.width + gap
    cmp_png.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(cmp_png)


def main() -> None:
    ap = argparse.ArgumentParser(description="Onboarding screenshot comparer")
    ap.add_argument("step", help="0-5 or 'all'")
    ap.add_argument("--appearance", choices=["light", "dark"], default="light")
    ap.add_argument("--launch", action="store_true",
                    help="launch .build/debug/Cue and capture its window first")
    args = ap.parse_args()

    # step -> variant ("another" is the practice screen's second round)
    variants: dict[int, str] = {}
    if args.step == "all":
        steps = list(range(len(REFERENCES)))
    elif args.step == "another":
        steps = [5]
        variants[5] = "another"
    else:
        try:
            steps = [int(args.step)]
        except ValueError:
            fail(f"bad step {args.step!r}: use 0-5, 'another' or 'all'")
        if not 0 <= steps[0] < len(REFERENCES):
            fail(f"step {steps[0]} out of range 0-{len(REFERENCES) - 1}")

    if args.appearance == "dark":
        print("ob_compare: note — reference PNGs are light appearance; "
              "dark captures will differ by design.", file=sys.stderr)

    for step in steps:
        variant = variants.get(step, "")
        tag = f"{step}-{variant}" if variant else str(step)
        app_png = OUT_DIR / f"{tag}-{args.appearance}-app.png"
        cmp_png = OUT_DIR / f"{tag}-{args.appearance}-compare.png"
        if args.launch:
            info = capture(step, args.appearance, app_png, variant)
            print(f"captured {info} -> {app_png}")
        compare(step, args.appearance, app_png, cmp_png)
        print(f"compare[{tag} {STEP_NAMES[step]}] -> {cmp_png}")


if __name__ == "__main__":
    main()
