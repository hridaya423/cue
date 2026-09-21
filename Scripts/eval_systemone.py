#!/usr/bin/env python3
"""Cue eval harness: point at one or more System One endpoints, get an
accuracy/latency table for the decision cases that matter to smart paste.

Usage:
    python3 Scripts/eval_systemone.py http://127.0.0.1:8009 http://127.0.0.1:8765
    python3 Scripts/eval_systemone.py https://api.typesafe.ai --key $TYPESAFE_API_KEY --model jev-latest

Each case posts the same questions Cue sends (pick + transform). Accuracy is
whether the winning key matches; extraction cases also assert the transform.
Latency is wall time.
"""
import argparse
import json
import sys
import time
import urllib.request
import urllib.error

# state, clip candidates, expected pick key, optional expected transform.
CASES = [
    {
        "name": "email field",
        "state": {"app": "Safari", "window": "Sign up", "field": {"role": "AXTextField", "label": "Email", "placeholder": "you@example.com", "current_value": ""}},
        "clips": ["me@example.com", "https://github.com/foo", "call dentist tuesday", "+1 (415) 555-0132"],
        "want": "c1",
    },
    {
        "name": "phone field",
        "state": {"app": "Safari", "window": "Checkout", "field": {"role": "AXTextField", "label": "Phone number", "placeholder": "(___) ___-____", "current_value": ""}},
        "clips": ["me@example.com", "+1 (415) 555-0132", "order confirmation #4821"],
        "want": "c2",
    },
    {
        "name": "url field",
        "state": {"app": "Messages", "window": "Chat", "field": {"role": "AXTextArea", "label": "Message", "placeholder": "", "current_value": "here's that link:"}},
        "clips": ["sure, send it over", "https://github.com/jaredpalmer/kev", "me@example.com"],
        "want": "c2",
    },
    {
        "name": "first name field",
        "state": {"app": "Safari", "window": "Checkout", "field": {"role": "AXTextField", "label": "First name", "placeholder": "Jane", "current_value": ""}},
        "clips": ["Jane", "me@example.com", "94105"],
        "want": "c1",
    },
    {
        "name": "zip field",
        "state": {"app": "Safari", "window": "Checkout", "field": {"role": "AXTextField", "label": "ZIP code", "placeholder": "94105", "current_value": ""}},
        "clips": ["Jane", "94105", "me@example.com"],
        "want": "c2",
    },
    {
        "name": "notes body",
        "state": {"app": "Notes", "window": "Shopping", "field": {"role": "AXTextArea", "label": "", "placeholder": "", "current_value": "groceries:\n"}},
        "clips": ["94105", "eggs, milk, coffee, oat milk", "https://example.com"],
        "want": "c2",
    },
    {
        # The contact-card case: the right pick AND the extraction transform.
        "name": "extract email",
        "state": {"app": "Mail", "window": "New Message", "field": {"role": "AXTextField", "label": "To:", "placeholder": "", "current_value": ""}},
        "clips": ["Jane Doe jane@example.com", "call dentist tuesday"],
        "want": "c1",
        "want_transform": "extract_email",
    },
]

TRANSFORMS = {
    "as_is": "paste exactly as copied",
    "trim": "remove leading and trailing whitespace",
    "lowercase": "lowercase all text (emails, usernames)",
    "digits_only": "keep digits only (phone/number fields)",
    "strip_url_tracking": "strip tracking parameters from a URL (utm_*, fbclid, gclid)",
    "extract_email": "paste only the email address inside the clip (e.g. a copied contact card for an email/To field)",
    "extract_phone": "paste only the phone number inside the clip",
    "extract_url": "paste only the URL inside the clip",
}


def evaluate(base: str, case: dict, model: str, key: str | None,
             timeout: float) -> tuple[str | None, str | None, float]:
    criteria = {f"c{i + 1}": f'text · "{clip}"' for i, clip in enumerate(case["clips"])}
    body = {
        "model": model,
        "state": {"task": "smart-paste", **case["state"]},
        "questions": {
            "pick": {
                "type": "choice",
                "instructions": "The user invoked smart-paste. Which clipboard item best fits the focused field?",
                "criteria": criteria,
            },
            "transform": {
                "type": "choice",
                "instructions": "Does the picked item need adjustment to fit this field (e.g. digits-only phone fields, lowercase emails)?",
                "criteria": TRANSFORMS,
            },
        },
    }
    url = base.rstrip("/") + "/v1/systemone"
    req = urllib.request.Request(
        url, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", **({"Authorization": f"Bearer {key}"} if key else {})},
    )
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            payload = json.loads(r.read())
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        return None, None, (time.monotonic() - t0) * 1000
    ms = (time.monotonic() - t0) * 1000
    answers = payload.get("answers") or {}
    pick = (answers.get("pick") or {}).get("choice")
    transform = (answers.get("transform") or {}).get("choice")
    return pick, transform, ms


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("endpoints", nargs="+", help="base URLs (path /v1/systemone is appended)")
    p.add_argument("--model", default="jev-latest", help="model name sent in each request")
    p.add_argument("--key", default=None, help="Bearer token for hosted endpoints")
    p.add_argument("--timeout", type=float, default=30.0)
    args = p.parse_args()

    print(f"{'endpoint':<38} {'case':<18} {'pick':<5} {'want':<5} {'transform':<22} {'ms':>7}  ok")
    print("-" * 102)
    for base in args.endpoints:
        wins = 0
        latencies = []
        for case in CASES:
            got, transform, ms = evaluate(base, case, args.model, args.key, args.timeout)
            ok = got == case["want"] and transform == case.get("want_transform", "as_is")
            wins += ok
            if got is not None:
                latencies.append(ms)
            print(f"{base[:36]:<38} {case['name']:<18} {str(got):<5} {case['want']:<5} "
                  f"{str(transform):<22} {ms:>7.0f}  {'✓' if ok else '✗'}")
        avg = sum(latencies) / len(latencies) if latencies else float("nan")
        print(f"{base[:36]:<38} {'TOTAL':<18} {wins}/{len(CASES):<3} {'':<5} {'':<22} {avg:>7.0f}")
        print("-" * 102)
    return 0


if __name__ == "__main__":
    sys.exit(main())
