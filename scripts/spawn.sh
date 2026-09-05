#!/usr/bin/env bash
# Spawn a one-shot harness subagent. Parents must invoke this file, not copy it.
# Usage: spawn.sh --backend claude|codex|grok|agy [--mode review|implement|visual] \
#                 --project DIR --run DIR [--model TOKEN] [--effort TOKEN] [--image PATH]...
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: spawn.sh --backend claude|codex|grok|agy [--mode review|implement|visual] \
                --project DIR --run DIR [--model TOKEN] [--effort TOKEN] [--image PATH]...
                [--resume-id UUID] [--dry-run] [--help]

Requires a non-empty $RUN/brief.md written by the parent.
Writes $RUN/stdout.md (human child text), prefers $RUN/report.md when it contains VERDICT,
normalizes into $RUN/last.md, and records $RUN/capture-status.txt (ok|ok-report|usage-limit|no-verdict).
Python 3 (python or python3) is required for session.json and JSONL event decoding.
Resume requires matching session-id + session.json copied into a new attempt run;
its brief.md is the short continuation. No most-recent selection or fresh fallback.
Do not interpolate untrusted config into a wrapper; pass --model / --effort only.
EOF
}

die() { echo "spawn.sh: $*" >&2; exit 2; }

need_val() {
  if [[ -z "${2-}" || "${2-}" == --* ]]; then
    die "missing value for $1"
  fi
}

ok_token() {
  [[ "$1" =~ ^[A-Za-z0-9._+-]+$ ]]
}

BACKEND=""
MODE="review"
PROJECT=""
RUN=""
MODEL=""
EFFORT=""
RESUME_ID=""
DRY=0
IMAGES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend) need_val "$1" "${2-}"; BACKEND="$2"; shift 2 ;;
    --mode) need_val "$1" "${2-}"; MODE="$2"; shift 2 ;;
    --project) need_val "$1" "${2-}"; PROJECT="$2"; shift 2 ;;
    --run) need_val "$1" "${2-}"; RUN="$2"; shift 2 ;;
    --model) need_val "$1" "${2-}"; MODEL="$2"; shift 2 ;;
    --effort) need_val "$1" "${2-}"; EFFORT="$2"; shift 2 ;;
    --resume-id) need_val "$1" "${2-}"; RESUME_ID="$2"; shift 2 ;;
    --image) need_val "$1" "${2-}"; IMAGES+=("$2"); shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$BACKEND" ]] || die "missing --backend"
[[ -n "$PROJECT" ]] || die "missing --project"
[[ -n "$RUN" ]] || die "missing --run"

case "$BACKEND" in
  claude|codex|grok|agy) ;;
  *) die "backend must be claude|codex|grok|agy (extra CLIs: see references/more-clis.md)" ;;
esac
case "$MODE" in
  review|implement|visual) ;;
  *) die "mode must be review|implement|visual" ;;
esac
[[ "$MODE" == "visual" ]] && MODE="review"

[[ -d "$PROJECT" ]] || die "project dir not found: $PROJECT"
[[ -d "$RUN" ]] || die "run dir not found: $RUN"
PROJECT="$(cd "$PROJECT" && pwd -P)"
RUN="$(cd "$RUN" && pwd -P)"
BRIEF="$RUN/brief.md"
[[ -s "$BRIEF" ]] || die "brief.md missing or empty — refusing to spawn: $BRIEF"

# L2 children must not re-enter this script (parent relaunch arrives with the var unset).
if [[ -n "${HARNESS_SUBAGENT_RUN-}" ]]; then
  die "nested spawn refused (already inside HARNESS_SUBAGENT_RUN=$HARNESS_SUBAGENT_RUN)"
fi
export HARNESS_SUBAGENT_RUN="$RUN"
# Official Claude knob: "1" disables nested Agent spawns in the child.
export CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1

if [[ -n "$MODEL" ]] && ! ok_token "$MODEL"; then
  die "invalid --model (allowlisted charset A-Za-z0-9._+-)"
fi
if [[ -n "$EFFORT" ]] && ! ok_token "$EFFORT"; then
  die "invalid --effort (allowlisted charset A-Za-z0-9._+-)"
fi
if ((${#IMAGES[@]})); then
  for img in "${IMAGES[@]}"; do
    [[ -f "$img" ]] || die "image not found: $img"
  done
fi

# Defaults match SKILL.md table.
case "$BACKEND" in
  claude)
    MODEL="${MODEL:-opus}"
    EFFORT="${EFFORT:-xhigh}"
    ;;
  codex)
    MODEL="${MODEL:-gpt-5.6-sol}"
    EFFORT="${EFFORT:-xhigh}"
    ;;
  grok)
    MODEL="${MODEL:-grok-4.6}"
    EFFORT="${EFFORT:-xhigh}"
    ;;
  agy)
    # Vendor default model unless pinned. Effort is low|medium|high only.
    MODEL="${MODEL:-}"
    EFFORT="${EFFORT:-high}"
    case "$EFFORT" in
      xhigh|max|ultra) EFFORT="high" ;;
    esac
    ;;
esac

LAST="$RUN/last.md"
STDOUT="$RUN/stdout.md"
REPORT="$RUN/report.md"
STATUS="$RUN/capture-status.txt"
ERR="$RUN/stderr.log"
EVENTS="$RUN/events.jsonl"
PROVIDER_ERRORS="$RUN/provider-errors.log"
DIAG="$RUN/capture-errors.log"
CMD=()

# Python 3 is the checked JSON consumer; no jq dependency. Keep it inline so
# identity validation and event decoding share one schema on Git Bash/Windows.
PYTHON=""
for candidate in python python3; do
  if command -v "$candidate" >/dev/null && "$candidate" -c 'import sys; assert sys.version_info.major == 3' 2>/dev/null; then
    PYTHON="$candidate"; break
  fi
done

blocked_capture() {
  printf 'VERDICT — BLOCKED: %s\n\nEvidence: %s\n' "$1" "$2" >"$LAST"
  printf 'no-verdict\n' >"$STATUS"
  printf 'spawn.sh: %s: %s\n' "$1" "$2" >&2
}
if [[ -z "$PYTHON" ]]; then
  blocked_capture 'capture dependency unavailable' 'Python 3 (python or python3) is required for session.json and JSONL decoding; no provider launched.'
  exit 2
fi

new_uuid() {
  local id
  if command -v uuidgen >/dev/null; then
    id="$(uuidgen)" || return
  elif command -v python >/dev/null && python -c 'import uuid' 2>/dev/null; then
    id="$(python -c 'import uuid; print(uuid.uuid4())')" || return
  elif command -v python3 >/dev/null && python3 -c 'import uuid' 2>/dev/null; then
    id="$(python3 -c 'import uuid; print(uuid.uuid4())')" || return
  elif command -v powershell.exe >/dev/null; then
    id="$(powershell.exe -NoProfile -NonInteractive -Command '[guid]::NewGuid().ToString()')" || return
  else
    echo 'spawn.sh: no UUID source (uuidgen, Python, or PowerShell)' >&2
    return 2
  fi
  id="${id//$'\r'/}"
  id="${id,,}"
  [[ "$id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] || {
    echo 'spawn.sh: UUID source returned invalid identity' >&2; return 2;
  }
  printf '%s\n' "$id"
}

SESSION_PY="$(mktemp "${TMPDIR:-/tmp}/hs-sess.XXXXXX.py")"
trap 'rm -f "$SESSION_PY"' EXIT
cat >"$SESSION_PY" <<'PY'
import json, pathlib, re, sys
action, run, project, backend, model, effort, mode, sid, skip, resume = sys.argv[1:]
run = pathlib.Path(run).resolve()
key = {'claude': 'session_id', 'grok': 'session_id', 'codex': 'thread_id', 'agy': 'conversation_id'}[backend]
uuid = re.compile(r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')

def load_identity():
    return json.loads((run / 'session.json').read_text(encoding='utf-8'))

def validate_resume():
    if not uuid.fullmatch(resume):
        raise ValueError('resume ID must be a full lowercase canonical UUID, with no extra text')
    if (run / 'session-id').read_bytes() != (resume + '\n').encode():
        raise ValueError('session-id must contain exactly the requested UUID plus one newline')
    d = load_identity()
    expected = dict(backend=backend, native_key=key, id=resume, model=model, effort=effort, mode=mode)
    expected[key] = resume
    for field, value in expected.items():
        if d.get(field) != value:
            raise ValueError('identity mismatch: ' + field)
    if d.get('persistence_available') is not True or (backend == 'claude' and skip):
        raise ValueError('persistence unavailable: ' + (d.get('unavailable_reason') or 'CLAUDE_CODE_SKIP_PROMPT_HISTORY is set'))
    if type(d.get('preassigned')) is not bool:
        raise ValueError('identity missing preassigned flag')
    for field in ('cwd', 'origin_run', 'attempt_run'):
        if not isinstance(d.get(field), str) or not pathlib.Path(d[field]).is_absolute():
            raise ValueError('identity missing resolved path: ' + field)
    if pathlib.Path(d['cwd']).resolve() != pathlib.Path(project).resolve():
        raise ValueError('identity mismatch: resolved cwd')
    if run in (pathlib.Path(d['attempt_run']).resolve(), pathlib.Path(d['origin_run']).resolve()):
        raise ValueError('resume requires a separate attempt directory; preserve prior artifacts')
    return d

def write_metadata(d):
    (run / 'session.json').write_text(json.dumps(d, indent=2) + '\n', encoding='utf-8')

def persist(identity, preassigned):
    if identity and not uuid.fullmatch(identity):
        raise ValueError('provider identity is not a canonical lowercase UUID')
    unavailable = 'CLAUDE_CODE_SKIP_PROMPT_HISTORY is set' if backend == 'claude' and skip else ''
    d = dict(backend=backend, native_key=key, id=identity, cwd=str(pathlib.Path(project).resolve()),
             origin_run=str(run), attempt_run=str(run), preassigned=preassigned,
             model=model, effort=effort, mode=mode,
             persistence_available=bool(identity) and not unavailable,
             unavailable_reason=unavailable or ('' if identity else 'provider ID unavailable'))
    d[key] = identity
    if resume:
        if identity != resume:
            raise ValueError('observed ' + key + ' does not match requested resume ID')
        d['origin_run'] = load_identity()['origin_run']
    if identity:
        (run / 'session-id').write_bytes((identity + '\n').encode())
    write_metadata(d)

try:
    if action == 'validate':
        validate_resume()
    elif action == 'attempt':
        d = validate_resume()
        d['attempt_run'] = str(run)
        write_metadata(d)
    elif action == 'preassign':
        persist(sid, True)
    elif action == 'events':
        observed = None
        deltas = []
        response = None
        single_turn = False
        parse_error = None
        # Labeled decoded-error source, never a grep of tool payloads.
        # Consume JSONL from the live CLI pipe so identity is persisted as soon
        # as thread.started/init arrives; drain remaining stdin after a parse
        # error so the CLI is not SIGPIPEd and events.jsonl stays complete.
        # Read stdin as bytes: locale text mode (cp1252) mojibakes UTF-8 and
        # collapses CRLF. Decode UTF-8 per record for parse only.
        with (run / 'provider-errors.log').open('w', encoding='utf-8', newline='\n') as errors:
            with (run / 'events.jsonl').open('wb') as events_out:
                for raw in sys.stdin.buffer:
                    events_out.write(raw)
                    events_out.flush()
                    if not raw.strip():
                        continue
                    try:
                        line = raw.decode('utf-8')
                    except UnicodeDecodeError as exc:
                        if parse_error is None:
                            parse_error = exc
                        continue
                    try:
                        event = json.loads(line)
                        if not isinstance(event, dict):
                            raise ValueError('event must be a JSON object')
                    except Exception as exc:
                        if parse_error is None:
                            parse_error = exc
                        continue
                    try:
                        kind = event.get('type')
                        # A later identity must not prove resume after a parse/identity failure.
                        if parse_error is None:
                            if (backend == 'codex' and kind == 'thread.started') or (backend == 'agy' and kind == 'init'):
                                identity = event.get(key)
                                if resume and identity != resume:
                                    raise ValueError('observed ' + key + ' missing or different from requested resume ID')
                                if identity:
                                    if observed and identity != observed:
                                        raise ValueError('provider emitted conflicting identities')
                                    observed = identity
                                    persist(observed, False)  # Before processing any final response.
                        # Only provider result events carry the final assistant answer.
                        result = event.get('result') if kind == 'result' else None
                        result = result if isinstance(result, dict) else (event if kind == 'result' else {})
                        if backend == 'agy':
                            if result.get('num_turns') == 1 or event.get('num_turns') == 1:
                                single_turn = True
                            if isinstance(result.get('response'), str):
                                response = result['response']
                            if kind == 'text_delta':
                                delta = event.get('text', event.get('delta', ''))
                                if isinstance(delta, str):
                                    deltas.append(delta)
                            elif kind == 'content_block_delta' and isinstance(event.get('delta'), dict):
                                delta = event['delta']
                                if delta.get('type') == 'text_delta' and isinstance(delta.get('text'), str):
                                    deltas.append(delta['text'])
                        error = None
                        if kind in ('error', 'thread.failed', 'turn.failed'):
                            error = event.get('error', event.get('message'))
                        elif kind == 'result' and (result.get('error') or result.get('is_error')):
                            error = result.get('error', result.get('response'))
                        if error is not None:
                            errors.write((error if isinstance(error, str) else json.dumps(error, ensure_ascii=False)) + '\n')
                            errors.flush()
                    except Exception as exc:
                        if parse_error is None:
                            parse_error = exc
        if backend == 'agy':
            (run / 'stdout.md').write_bytes((response if response is not None else ''.join(deltas)).encode('utf-8'))
        if parse_error is not None:
            raise parse_error
        if resume and observed != resume:
            raise ValueError('resume did not emit matching ' + key)
        if resume and backend == 'agy' and single_turn:
            raise ValueError('agy resume reported num_turns == 1; possible fresh conversation')
        if not observed and not resume:
            persist(None, False)
    else:
        raise ValueError('unknown session action')
except Exception as exc:
    print('session capture: ' + str(exc), file=sys.stderr)
    sys.exit(2)
PY
session_data() {
  "$PYTHON" -u "$SESSION_PY" "$1" "$RUN" "$PROJECT" "$BACKEND" "$MODEL" "$EFFORT" "$MODE" "${SID-}" "${CLAUDE_CODE_SKIP_PROMPT_HISTORY+x}" "$RESUME_ID"
}

SID=""
if [[ -n "$RESUME_ID" ]]; then
  validation_error=''
  if validation_error="$(session_data validate 2>&1)"; then :; else
    printf '%s\n' "$validation_error" >>"$ERR"
    blocked_capture 'resume unavailable' "$validation_error; no provider launched."
    exit 2
  fi
elif [[ "$BACKEND" == claude || "$BACKEND" == grok ]]; then
  SID="$(new_uuid)"
fi

# Claude: final -p text is last turn only; require report.md so cleanup turns cannot wipe the verdict.
CLAUDE_REPORT_HINT='Deliverable: write the complete VERDICT report to report.md in the --add-dir run directory (same folder as brief.md) via a shell redirect BEFORE any cleanup. First line must be VERDICT (no markdown bold). Do not edit application files.'

case "$BACKEND" in
  claude)
    if [[ "$MODE" == "implement" ]]; then
      TOOLS="Bash,Read,Edit,Write,Glob,Grep"
    else
      TOOLS="Bash,Read,Glob,Grep"
    fi
    CMD=(claude -p --permission-mode auto --tools "$TOOLS"
      --output-format text --model "$MODEL" --effort "$EFFORT"
      --add-dir "$RUN"
      --append-system-prompt "$CLAUDE_REPORT_HINT")
    if [[ -n "$RESUME_ID" ]]; then CMD+=(--resume "$RESUME_ID"); else CMD+=(--session-id "$SID"); fi
    ;;
  codex)
    # All modes: --approve-for-me (classifier Auto). Do not pass --sandbox
    # (0.147 mutex with --approve-for-me; read-only also blocks temp/report writes).
    # Write raw child text to stdout.md; finalize_capture prefers report.md.
    CMD=(codex exec --approve-for-me -C "$PROJECT")
    if [[ -n "$RESUME_ID" ]]; then CMD+=(resume); fi
    CMD+=(-m "$MODEL" -c "model_reasoning_effort=$EFFORT" --skip-git-repo-check --json)
    if ((${#IMAGES[@]})); then
      for img in "${IMAGES[@]}"; do
        CMD+=(-i "$img")
      done
    fi
    CMD+=(-o "$STDOUT")
    if [[ -n "$RESUME_ID" ]]; then CMD+=("$RESUME_ID"); fi
    CMD+=(-)
    ;;
  grok)
    CMD=(grok --permission-mode auto -m "$MODEL" --effort "$EFFORT"
      --cwd "$PROJECT" --prompt-file "$BRIEF" --output-format plain)
    if [[ -n "$RESUME_ID" ]]; then CMD+=(--resume "$RESUME_ID"); else CMD+=(--session-id "$SID"); fi
    ;;
  agy)
    # Flags before -p. Do not pass --project (that is a Google project id).
    # --add-dir makes RUN a writable workspace. Implement must not get it
    # (2026-08-31 weather UI: app landed in $RUN, --project stayed empty).
    # Review/Visual still add RUN so screenshots are visible. Brief is in -p.
    CMD=(agy --output-format stream-json --effort "$EFFORT"
      --print-timeout 15m --disable-slash-commands --mode accept-edits)
    if [[ "$MODE" != "implement" ]]; then
      CMD+=(--add-dir "$RUN")
    fi
    if [[ -n "$MODEL" ]]; then
      CMD+=(--model "$MODEL")
    fi
    if [[ "$MODE" == "implement" ]]; then
      CMD+=(--dangerously-skip-permissions)
    fi
    if [[ -n "$RESUME_ID" ]]; then CMD+=(--conversation "$RESUME_ID"); fi
    ;;
esac

# True if file has a VERDICT line (plain, bold, or VERDICT:).
has_verdict() {
  local f="$1"
  [[ -s "$f" ]] || return 1
  grep -qE '^\*{0,2}VERDICT([: —–-]|$)' "$f"
}

# Drop preamble so last.md starts at VERDICT when present. Accept **VERDICT / VERDICT:.
normalize_verdict() {
  local f="$1" tmp first
  [[ -s "$f" ]] || return 0
  # Unwrap a leading markdown-bold VERDICT line.
  tmp="${f}.unwrap.$$"
  sed -E '1,/[^[:space:]]/ { s/^\*\*[[:space:]]*(VERDICT)/\1/; s/(VERDICT[^*:]*)\*\*/\1/; }' "$f" >"$tmp" || cp "$f" "$tmp"
  mv "$tmp" "$f"

  first="$(awk 'NF { print; exit }' "$f" || true)"
  case "$first" in
    VERDICT|"VERDICT —"*|VERDICT—*|VERDICT\ -*|VERDICT:*) return 0 ;;
  esac
  grep -qE '^\*{0,2}VERDICT([: —–-]|$)' "$f" || return 0
  tmp="${f}.norm.$$"
  awk 'BEGIN{p=0} /^\*{0,2}VERDICT([: —–-]|$)/{p=1} p{print}' "$f" >"$tmp"
  # Unwrap bold on the first kept line if still present.
  sed -E '1s/^\*\*[[:space:]]*(VERDICT)/\1/;1s/(VERDICT[^*:]*)\*\*/\1/' "$tmp" >"${tmp}.2"
  mv "${tmp}.2" "$f"
  rm -f "$tmp"
}

# Usage/rate-limit text is not a report — synthesize a blocked VERDICT.
detect_usage_limit() {
  local f="$1" source raw evidence='' grep_ec
  local pattern='session limit|rate[[:space:]-]?limit|usage[[:space:]-]?limit|hit your (session )?limit|you.ve hit your'
  pattern+='|(^|[^[:alnum:]_])(http(/[0-9.]+)?|http status|status([[:space:]_-]+code)?|error)[[:space:]:=]+429([^[:digit:]]|$)|too many requests'
  pattern+='|(quota[[:space:]_:=-]+((has been|is)[[:space:]]+)?(exhausted|exceeded))|((exhausted|exceeded)[[:space:]_:=-]+(paid[[:space:]]+)?quota)'
  pattern+='|((insufficient|exhausted)[[:space:]_:=-]+credits)|(credits[[:space:]_:=-]+((are|have been)[[:space:]]+)?(insufficient|exhausted))'
  pattern+='|((spend(ing)?[[:space:]_-]+(limit|cap))[[:space:]:=-]+((has been|is)[[:space:]]+)?(reached|exceeded|exhausted))'
  has_verdict "$f" && return 0
  for source in "$STDOUT" "$ERR" "$PROVIDER_ERRORS" "$f"; do
    [[ -s "$source" ]] || continue
    if [[ "$source" == "$f" && -s "$STDOUT" ]]; then continue; fi
    if grep -qiE "$pattern" "$source"; then
      raw="$(cat "$source")"
      evidence+=$'\n--- '"${source##*/}"$' ---\n'"$raw"$'\n'
    else
      grep_ec=$?
      if [[ "$grep_ec" -gt 1 ]]; then return "$grep_ec"; fi
    fi
  done
  [[ -n "$evidence" ]] || return 0
  printf '%s\n' \
    'VERDICT — BLOCKED: usage/rate limit' \
    '' \
    'UNVERIFIED — Child returned limit evidence, not a completed report. Keep the selected backend/model and route pins (sticky route). The parent owns waiting and any retry decision. For a subscription/session window, wait for the stated reset and preserve its timezone. For a transient HTTP 429 / Too Many Requests without stronger spend/quota evidence, use a short backoff and honor any retry hint. Explicit insufficient credits, spend cap, or exhausted paid quota takes precedence over generic 429: ask the human; do not enable spend or change billing automatically. For ambiguous quota evidence without a reliable cause/reset, report it and ask once. Do not invent a reset or retry indefinitely. Spawn does not sleep, launch a sleeper, or change routes.' \
    "$evidence" >"$f"
  printf 'usage-limit\n' >"$STATUS"
}

# Prefer durable report.md (survives Claude cleanup turns) over final stdout.
finalize_capture() {
  if [[ -s "$REPORT" ]] && has_verdict "$REPORT"; then
    cp "$REPORT" "$LAST"
    printf 'ok-report\n' >"$STATUS"
  elif [[ -s "$STDOUT" ]]; then
    cp "$STDOUT" "$LAST"
    printf 'ok\n' >"$STATUS"
  elif [[ -s "$LAST" ]]; then
    printf 'ok\n' >"$STATUS"
  else
    : >"$LAST"
    printf 'no-verdict\n' >"$STATUS"
  fi
  normalize_verdict "$LAST"
  detect_usage_limit "$LAST"
  if grep -qx 'usage-limit' "$STATUS"; then return 0; fi
  if has_verdict "$LAST"; then
    if [[ -s "$REPORT" ]] && has_verdict "$REPORT"; then
      printf 'ok-report\n' >"$STATUS"
    else
      printf 'ok\n' >"$STATUS"
    fi
  else
    printf 'no-verdict\n' >"$STATUS"
  fi
}

if [[ "$DRY" -eq 1 ]]; then
  printf 'cd %q &&' "$PROJECT"
  printf ' %q' "${CMD[@]}"
  case "$BACKEND" in
    claude) printf ' < %q > %q 2> %q' "$BRIEF" "$STDOUT" "$ERR" ;;
    codex) printf ' < %q > %q 2> %q' "$BRIEF" "$EVENTS" "$ERR" ;;
    grok) printf ' < /dev/null > %q 2> %q' "$STDOUT" "$ERR" ;;
    agy) printf ' -p "$(cat %q)" < /dev/null > %q 2> %q' "$BRIEF" "$EVENTS" "$ERR" ;;
  esac
  printf '\n'
  exit 0
fi

cd "$PROJECT"
if [[ -n "$SID" ]]; then session_data preassign; fi
if [[ -n "$RESUME_ID" ]]; then session_data attempt; fi
cli_ec=0
capture_ec=0
case "$BACKEND" in
  claude)
    "${CMD[@]}" < "$BRIEF" > "$STDOUT" 2> "$ERR" || cli_ec=$?
    ;;
  grok)
    "${CMD[@]}" < /dev/null > "$STDOUT" 2> "$ERR" || cli_ec=$?
    ;;
  codex)
    "${CMD[@]}" < "$BRIEF" 2> "$ERR" | session_data events 2>"$DIAG" && ps=("${PIPESTATUS[@]}") || ps=("${PIPESTATUS[@]}")
    cli_ec="${ps[0]}"
    capture_ec="${ps[1]}"
    ;;
  agy)
    "${CMD[@]}" -p "$(cat "$BRIEF")" < /dev/null 2> "$ERR" | session_data events 2>"$DIAG" && ps=("${PIPESTATUS[@]}") || ps=("${PIPESTATUS[@]}")
    cli_ec="${ps[0]}"
    capture_ec="${ps[1]}"
    ;;
esac
finalize_capture
if [[ "$capture_ec" -ne 0 ]]; then
  if ! grep -qx 'usage-limit' "$STATUS"; then
    blocked_capture 'session capture failed' "$(cat "$DIAG")"
  fi
  if [[ "$cli_ec" -eq 0 ]]; then cli_ec="$capture_ec"; fi
elif [[ -n "$RESUME_ID" && "$cli_ec" -ne 0 ]] && ! grep -qx 'usage-limit' "$STATUS"; then
  blocked_capture 'exact resume failed' "CLI exit $cli_ec. $(cat "$ERR") Read preserved stdout.md/events.jsonl and the prior checkpoint; no fresh-thread fallback was launched."
fi
exit "$cli_ec"
