#!/usr/bin/env bash
# Spawn a one-shot harness subagent. Parents must invoke this file, not copy it.
# Usage: spawn.sh --backend claude|codex|grok --mode review|implement|visual \
#                 --project DIR --run DIR [--model TOKEN] [--effort TOKEN] [--image PATH]...
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: spawn.sh --backend claude|codex|grok --mode review|implement|visual \
                --project DIR --run DIR [--model TOKEN] [--effort TOKEN] [--image PATH]...
                [--dry-run] [--help]

Requires a non-empty $RUN/brief.md written by the parent. Writes $RUN/last.md and $RUN/stderr.log.
Do not interpolate untrusted config into a wrapper; pass --model / --effort only.
EOF
}

die() { echo "spawn.sh: $*" >&2; exit 2; }

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
    --backend) BACKEND="${2-}"; shift 2 ;;
    --mode) MODE="${2-}"; shift 2 ;;
    --project) PROJECT="${2-}"; shift 2 ;;
    --run) RUN="${2-}"; shift 2 ;;
    --model) MODEL="${2-}"; shift 2 ;;
    --effort) EFFORT="${2-}"; shift 2 ;;
    --image) IMAGES+=("${2-}"); shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$BACKEND" ]] || die "missing --backend"
[[ -n "$PROJECT" ]] || die "missing --project"
[[ -n "$RUN" ]] || die "missing --run"

case "$BACKEND" in
  claude|codex|grok) ;;
  *) die "backend must be claude|codex|grok (extra CLIs: see references/more-clis.md)" ;;
esac
case "$MODE" in
  review|implement|visual) ;;
  *) die "mode must be review|implement|visual" ;;
esac
[[ "$MODE" == "visual" && "$BACKEND" != "codex" ]] && die "visual images are Codex-only in this script"
[[ "$MODE" == "visual" && "$BACKEND" == "codex" ]] && MODE="review"

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
esac

LAST="$RUN/last.md"
ERR="$RUN/stderr.log"
CMD=()

case "$BACKEND" in
  claude)
    if [[ "$MODE" == "implement" ]]; then
      PERM="acceptEdits"
      TOOLS="Bash,Read,Edit,Write,Glob,Grep"
    else
      PERM="plan"
      TOOLS="Bash,Read,Glob,Grep"
    fi
    CMD=(claude -p --permission-mode "$PERM" --tools "$TOOLS"
      --output-format text --model "$MODEL" --effort "$EFFORT"
      --no-session-persistence --add-dir "$RUN")
    ;;
  codex)
    if [[ "$MODE" == "implement" ]]; then
      SB="workspace-write"
    else
      SB="read-only"
    fi
    CMD=(codex exec --ephemeral --sandbox "$SB" -m "$MODEL"
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
    if [[ "$MODE" == "implement" ]]; then
      PERM="acceptEdits"
    else
      PERM="plan"
    fi
    CMD=(grok --permission-mode "$PERM" -m "$MODEL" --effort "$EFFORT"
      --cwd "$PROJECT" --prompt-file "$BRIEF" --output-format plain)
    ;;
esac

if [[ "$DRY" -eq 1 ]]; then
  printf 'cd %q &&' "$PROJECT"
  printf ' %q' "${CMD[@]}"
  case "$BACKEND" in
    claude) printf ' < %q > %q 2> %q' "$BRIEF" "$LAST" "$ERR" ;;
    codex) printf ' < %q 2> %q' "$BRIEF" "$ERR" ;;
    grok) printf ' < /dev/null > %q 2> %q' "$LAST" "$ERR" ;;
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
esac
