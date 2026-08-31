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

Requires a non-empty $RUN/brief.md written by the parent. Writes $RUN/last.md and $RUN/stderr.log.
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
ERR="$RUN/stderr.log"
CMD=()

case "$BACKEND" in
  claude)
    if [[ "$MODE" == "implement" ]]; then
      TOOLS="Bash,Read,Edit,Write,Glob,Grep"
    else
      TOOLS="Bash,Read,Glob,Grep"
    fi
    CMD=(claude -p --permission-mode auto --tools "$TOOLS"
      --output-format text --model "$MODEL" --effort "$EFFORT"
      --no-session-persistence --add-dir "$RUN")
    ;;
  codex)
    # All modes: --approve-for-me (classifier Auto). Do not pass --sandbox
    # (0.147 mutex with --approve-for-me; read-only also blocks temp/report writes).
    CMD=(codex exec --ephemeral --approve-for-me -m "$MODEL"
      -c "model_reasoning_effort=$EFFORT" --skip-git-repo-check
      -C "$PROJECT")
    if ((${#IMAGES[@]})); then
      for img in "${IMAGES[@]}"; do
        CMD+=(-i "$img")
      done
    fi
    CMD+=(-o "$LAST" -)
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

# After a real child exit: drop preamble so last.md starts at VERDICT when present.
normalize_verdict() {
  local f="$1" tmp first
  [[ -s "$f" ]] || return 0
  first="$(awk 'NF { print; exit }' "$f" || true)"
  case "$first" in
    VERDICT|"VERDICT —"*|VERDICT—*|VERDICT\ -*) return 0 ;;
  esac
  grep -q '^VERDICT' "$f" || return 0
  tmp="${f}.norm.$$"
  awk 'BEGIN{p=0} /^VERDICT/{p=1} p{print}' "$f" >"$tmp"
  mv "$tmp" "$f"
}

if [[ "$DRY" -eq 1 ]]; then
  printf 'cd %q &&' "$PROJECT"
  printf ' %q' "${CMD[@]}"
  case "$BACKEND" in
    claude) printf ' < %q > %q 2> %q' "$BRIEF" "$LAST" "$ERR" ;;
    codex) printf ' < %q 2> %q' "$BRIEF" "$ERR" ;;
    grok) printf ' < /dev/null > %q 2> %q' "$LAST" "$ERR" ;;
    agy) printf ' -p "$(cat %q)" < /dev/null > %q 2> %q' "$BRIEF" "$LAST" "$ERR" ;;
  esac
  printf '\n'
  exit 0
fi

cd "$PROJECT"
case "$BACKEND" in
  claude)
    "${CMD[@]}" < "$BRIEF" > "$LAST" 2> "$ERR"
    ;;
  codex)
    "${CMD[@]}" < "$BRIEF" 2> "$ERR"
    ;;
  grok)
    "${CMD[@]}" < /dev/null > "$LAST" 2> "$ERR"
    ;;
  agy)
    "${CMD[@]}" -p "$(cat "$BRIEF")" < /dev/null > "$LAST" 2> "$ERR"
    ;;
esac

normalize_verdict "$LAST"
