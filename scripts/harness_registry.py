#!/usr/bin/env python3
"""Resolve model aliases, decide a usage-limit wait, and run health checks."""

import argparse
import json
import re
import shutil
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REGISTRY = json.loads((ROOT / "registry.json").read_text(encoding="utf-8"))
HARNESSES = REGISTRY["harnesses"]
WAIT_LIMIT = int(REGISTRY["wait_limit_seconds"])
WAIT_BUFFER = int(REGISTRY["wait_buffer_seconds"])
DOW = {"mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6}


def die(msg):
    print(msg, file=sys.stderr)
    raise SystemExit(2)


def norm(text):
    return re.sub(r"\s+", " ", text.strip().casefold())


def model_record(backend, model_id):
    for rec in HARNESSES[backend]["models"]:
        if rec["id"] == model_id:
            return rec
    return None


def resolve(model, backend):
    key = norm(model)
    hits = []
    for name, spec in HARNESSES.items():
        if backend and name != backend:
            continue
        for rec in spec["models"]:
            names = [rec["id"], *rec.get("say", [])]
            if any(norm(item) == key for item in names):
                hits.append((name, rec["id"]))
    if len(hits) == 1:
        return hits[0]
    if len(hits) > 1:
        die("model %r matches more than one CLI" % model)
    if backend and not HARNESSES[backend]["models"]:
        if re.fullmatch(r"[A-Za-z0-9._+-]+", model):
            return backend, model
        die("model %r is not a known id" % model)
    if backend:
        die("%s is not a %s model" % (model, backend))
    die("unknown model %r" % model)


def allowed_efforts(backend, model_id):
    spec = HARNESSES[backend]
    if spec.get("effort_style") == "bracket":
        return None
    rec = model_record(backend, model_id)
    if rec is not None and "efforts" in rec:
        return rec["efforts"]
    if "efforts" in spec:
        return spec["efforts"]
    return None


def check_effort(backend, model_id, effort):
    if not re.fullmatch(r"[A-Za-z0-9._+-]+", effort):
        die("invalid effort")
    allowed = allowed_efforts(backend, model_id)
    if allowed is None:
        return
    if effort not in allowed:
        if not allowed:
            die("%s does not take --effort" % model_id)
        die("%s effort must be one of %s" % (model_id, ", ".join(allowed)))


def parse_now(text):
    if text is None:
        return datetime.now().astimezone().replace(tzinfo=None)
    raw = text.strip()
    if raw.endswith("Z"):
        raw = raw[:-1]
    raw = re.sub(r"[+-]\d{2}:?\d{2}$", "", raw)
    raw = raw.replace("T", " ")
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M"):
        try:
            return datetime.strptime(raw, fmt)
        except ValueError:
            pass
    die("invalid --now")


def parse_clock(hour, minute, ampm, dow, now):
    hour = int(hour)
    minute = int(minute)
    if ampm:
        mark = ampm.casefold()
        if mark == "pm" and hour != 12:
            hour += 12
        if mark == "am" and hour == 12:
            hour = 0
    if hour > 23 or minute > 59:
        return None
    target = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if dow is not None:
        want = DOW[dow.casefold()[:3]]
        delta = (want - target.weekday()) % 7
        target = target + timedelta(days=delta)
        if target <= now:
            target = target + timedelta(days=7)
        return target
    if target <= now:
        target = target + timedelta(days=1)
    return target


def parse_iso_stamp(text, now):
    raw = text.strip().rstrip(".")
    if raw.endswith("Z"):
        raw = raw[:-1]
    raw = re.sub(r"[+-]\d{2}:?\d{2}$", "", raw)
    raw = raw.replace("T", " ")
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M"):
        try:
            return datetime.strptime(raw, fmt)
        except ValueError:
            pass
    return None


def limit_decision(text, now):
    deltas = []
    for match in re.finditer(r"Retry-After:\s*(\d+)", text, re.I):
        deltas.append(float(match.group(1)))
    for match in re.finditer(
        r"(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(?::\d{2})?(?:Z|[+-]\d{2}:?\d{2})?)",
        text,
    ):
        stamp = parse_iso_stamp(match.group(1), now)
        if stamp is not None:
            deltas.append((stamp - now).total_seconds())
    clock = re.compile(
        r"(?i)(?:resets|try again at)\s+"
        r"(?:(mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|thu(?:rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)\s+)?"
        r"(\d{1,2}):(\d{2})\s*(am|pm)?"
    )
    for match in clock.finditer(text):
        start = match.start()
        window = text[max(0, start - 12): match.end()]
        if re.search(r"\d{4}-\d{2}-\d{2}[T ]\d{1,2}:\d{2}", window):
            continue
        target = parse_clock(match.group(2), match.group(3), match.group(4), match.group(1), now)
        if target is not None:
            deltas.append((target - now).total_seconds())
    future = [item for item in deltas if item > 0]
    if not future:
        return "stop"
    seconds = int(min(future)) + WAIT_BUFFER
    if seconds > WAIT_LIMIT:
        return "stop"
    return "wait %d" % seconds


def run_checked(argv, timeout):
    try:
        proc = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            timeout=timeout,
            encoding="utf-8",
            errors="replace",
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 1, "", str(exc)
    return proc.returncode, proc.stdout or "", proc.stderr or ""


def health(do_update):
    failed = False
    for name, spec in HARNESSES.items():
        binary = shutil.which(spec["bin"])
        if not binary:
            print("%s\tmissing\t-\t-" % name)
            failed = True
            continue
        version = ""
        if spec.get("version"):
            code, out, err = run_checked([binary, *spec["version"]], 30)
            version = (out or err).strip().splitlines()[0] if (out or err).strip() else ("ok" if code == 0 else "unknown")
        else:
            version = "present"
        auth_args = spec.get("auth") or []
        if not auth_args:
            login = "login-unknown"
        else:
            code, out, err = run_checked([binary, *auth_args], 120)
            blob = (out + "\n" + err).casefold()
            expect = (spec.get("auth_expect") or "").casefold()
            if expect:
                login = "logged-in" if expect in blob else "not-logged-in"
            else:
                login = "logged-in" if code == 0 else "not-logged-in"
            if login != "logged-in":
                failed = True
        updated = "-"
        if do_update and spec.get("update"):
            code, out, err = run_checked([binary, *spec["update"]], 300)
            updated = "updated" if code == 0 else "update-failed"
            if code != 0:
                failed = True
        print("%s\t%s\t%s\t%s" % (name, version, login, updated))
    raise SystemExit(1 if failed else 0)


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="cmd", required=True)

    res = sub.add_parser("resolve")
    res.add_argument("--model", required=True)
    res.add_argument("--backend")

    eff = sub.add_parser("check-effort")
    eff.add_argument("--backend", required=True)
    eff.add_argument("--model", required=True)
    eff.add_argument("--effort", required=True)

    lim = sub.add_parser("limit")
    lim.add_argument("--now")
    lim.add_argument("files", nargs="*")

    hea = sub.add_parser("health")
    hea.add_argument("--update", action="store_true")

    args = parser.parse_args()
    if args.cmd == "resolve":
        if args.backend and args.backend not in HARNESSES:
            die("unknown backend %r" % args.backend)
        backend, model_id = resolve(args.model, args.backend)
        print(backend)
        print(model_id)
        return
    if args.cmd == "check-effort":
        if args.backend not in HARNESSES:
            die("unknown backend %r" % args.backend)
        check_effort(args.backend, args.model, args.effort)
        return
    if args.cmd == "limit":
        chunks = []
        for name in args.files:
            path = Path(name)
            if path.is_file():
                chunks.append(path.read_text(encoding="utf-8", errors="replace"))
        if not chunks and not sys.stdin.isatty():
            chunks.append(sys.stdin.read())
        print(limit_decision("\n".join(chunks), parse_now(args.now)))
        return
    if args.cmd == "health":
        health(args.update)


if __name__ == "__main__":
    main()
