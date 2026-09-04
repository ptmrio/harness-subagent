#!/usr/bin/env bash
# Spawn a one-shot harness subagent. Parents must invoke this file, not copy it.
# Usage: spawn.sh --backend claude|codex|grok|agy [--mode review|implement|visual] \
#                 --project DIR --run DIR [--model TOKEN] [--effort TOKEN] [--image PATH]...
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: spawn.sh --backend claude|codex|grok|agy [--mode review|implement|visual] \
                --project DIR --run DIR [--model TOKEN] [--effort TOKEN] [--image PATH]...
                [--dry-run] [--help]

Requires a non-empty $RUN/brief.md written by the parent.
Writes $RUN/stdout.md (raw child text), prefers $RUN/report.md when it contains VERDICT,
normalizes into $RUN/last.md, and records $RUN/capture-status.txt (ok|ok-report|usage-limit|no-verdict).
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
CMD=()

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
      --no-session-persistence --add-dir "$RUN"
      --append-system-prompt "$CLAUDE_REPORT_HINT")
    ;;
  codex)
    # All modes: --approve-for-me (classifier Auto). Do not pass --sandbox
    # (0.147 mutex with --approve-for-me; read-only also blocks temp/report writes).
    # Write raw child text to stdout.md; finalize_capture prefers report.md.
    CMD=(codex exec --ephemeral --approve-for-me -m "$MODEL"
      -c "model_reasoning_effort=$EFFORT" --skip-git-repo-check
      -C "$PROJECT")
    if ((${#IMAGES[@]})); then
      for img in "${IMAGES[@]}"; do
        CMD+=(-i "$img")
      done
    fi
    CMD+=(-o "$STDOUT" -)
    ;;
  grok)
    CMD=(grok --permission-mode auto -m "$MODEL" --effort "$EFFORT"
      --cwd "$PROJECT" --prompt-file "$BRIEF" --output-format plain)
    ;;
  agy)
    # Flags before -p. Do not pass --project (that is a Google project id).
    # --add-dir makes RUN a writable workspace. Implement must not get it
    # (2026-08-31 weather UI: app landed in $RUN, --project stayed empty).
    # Review/Visual still add RUN so screenshots are visible. Brief is in -p.
    CMD=(agy --output-format text --effort "$EFFORT"
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
  local f="$1" raw
  [[ -s "$f" ]] || return 0
  has_verdict "$f" && return 0
  if grep -qiE 'session limit|rate[[:space:]-]?limit|usage[[:space:]-]?limit|hit your (session )?limit|you.ve hit your' "$f"; then
    raw="$(cat "$f")"
    printf '%s\n' \
      'VERDICT — BLOCKED: usage/rate limit' \
      '' \
      'UNVERIFIED — Child returned a limit message, not a report. Do not retarget backends (sticky route). Wait for reset or ask the human.' \
      '' \
      '--- original ---' \
      "$raw" >"$f"
    printf 'usage-limit\n' >"$STATUS"
  fi
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
    return 0
  fi

  normalize_verdict "$LAST"
  detect_usage_limit "$LAST"
  if [[ -f "$STATUS" ]] && grep -qx 'usage-limit' "$STATUS"; then
    return 0
  fi
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
    codex) printf ' < %q 2> %q' "$BRIEF" "$ERR" ;;
    grok) printf ' < /dev/null > %q 2> %q' "$STDOUT" "$ERR" ;;
    agy) printf ' -p "$(cat %q)" < /dev/null > %q 2> %q' "$BRIEF" "$STDOUT" "$ERR" ;;
  esac
  printf '\n'
  exit 0
fi

cd "$PROJECT"
case "$BACKEND" in
  claude)
    "${CMD[@]}" < "$BRIEF" > "$STDOUT" 2> "$ERR"
    ;;
  codex)
    "${CMD[@]}" < "$BRIEF" 2> "$ERR"
    ;;
  grok)
    "${CMD[@]}" < /dev/null > "$STDOUT" 2> "$ERR"
    ;;
  agy)
    "${CMD[@]}" -p "$(cat "$BRIEF")" < /dev/null > "$STDOUT" 2> "$ERR"
    ;;
esac

finalize_capture
