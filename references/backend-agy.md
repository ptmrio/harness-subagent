# Backend: Antigravity CLI (`agy`)

Read this after the user (or config) selected Antigravity / `agy`. Consumer **Gemini CLI** (`gemini` on npm) stopped serving individuals on 2026-06-18; the successor binary is **`agy`**. Official headless: [Headless mode](https://antigravity.google/docs/cli/headless/).

Parents must spawn via [scripts/spawn.sh](../scripts/spawn.sh) (`--backend agy --mode review|implement`). Do not assemble these flags in PowerShell. Do not spawn `agy` from an Antigravity parent unless the user named it this turn.

Utterance **Gemini** / **Antigravity** / **agy** → this backend. Config token `gemini` is **not** an alias; that is the legacy CLI in [more-clis.md](more-clis.md) (enterprise / paid API keys).

| Part | Why |
|---|---|
| `-p` / `--print` / `--prompt` | Headless one-shot. Without it you get the TUI. Prompt is argv (`-p "$(cat "$BRIEF")"` inside spawn.sh). No `--prompt-file`. `--print -` plus stdin is **not** the prompt (live: it ignored the file). |
| `--output-format stream-json` | Raw NDJSON to `events.jsonl`. Python extracts `.result.response`, else concatenates `text_delta`, into `stdout.md` even when a later parse or resume identity check fails; `last.md` stays human text. |
| `--mode accept-edits` | Overrides a persisted `agentMode: plan` (which prepends `/plan` and pollutes a VERDICT brief). Not a read-only sandbox. Headless workspace file R/W is auto-allowed anyway. |
| `--dangerously-skip-permissions` | Implement only. agy has no classifier Auto; this is `always-proceed` (YOLO). Review omits it: shell is soft-denied (exit 0, notice on stderr). |
| `--add-dir "$RUN"` | Review/Visual only. agy adds the dir to the **writable workspace**. Implement must omit it: the brief is already in `-p`, and `--add-dir` dumps the app into `$RUN`. Proven 2026-08-31 (weather UI): `--project` stayed empty; files appeared next to `brief.md`. |
| `--print-timeout 15m` | Vendor default is 5m; too short for a real review. |
| `--disable-slash-commands` | Briefs must not be expanded as `/plan` and friends. |
| `--effort high` | `low` `medium` `high` only. Map spawn `xhigh` / `max` / `ultra` → `high`. |
| omit `--model` | Vendor default unless the user or `[models].agy` pins a slug (`agy models`). Unknown slugs fail loud. |
| `< /dev/null` | `-p` is the prompt; close inherited stdin. |
| no `--sandbox` | Same as Codex/Grok spawn. |
| no `--project` | That flag is a Google project id/name, not the repo path. `cd "$PROJECT"` instead. |

`--mode plan` is wrong for Review: it prepends `/plan`. `--mode accept-edits` is not a shell grant; `run_command` still follows permissions.

Review is brief-restrained (`Do not edit application files.`). A bounded `git diff` in the brief may be soft-denied; treat that as UNVERIFIED unless stderr shows the command ran.

List models: `agy models`. Auth: interactive `agy` once (keyring), or `GEMINI_API_KEY` plus `modelProvider: "gemini"` in `~/.gemini/antigravity-cli/settings.json`. Headless with no credentials exits `authentication required` rather than hanging.

Proven: `agy -p` → `HELLO_WORLD` (Windows Git Bash, 1.1.22, 2026-08-31). `--print - < brief.md` did **not** pass the file as the prompt. Implement with `--add-dir "$RUN"` wrote the app into the temp run dir (same date); spawn.sh now omits `--add-dir` on Implement.

Spawn checks Python 3 (`python` or `python3`; no jq dependency). `init.conversation_id` is saved to `session-id` and `session.json` before parsing final response events, including after CLI exit 1. Empty IDs mean persistence unavailable; there is no client create-ID flag. Metadata binds native `conversation_id`, resolved cwd, origin/attempt runs, mode/model/effort, and `preassigned: false`. Parser failures finalize BLOCKED artifacts and fail visibly; they do not replace a `usage-limit` classification. Decoded provider error events form the labeled `provider-errors.log` source when selected text has no verdict; tool payloads are not limit evidence. Done means exit plus capture; success also requires the exit status and verdict to support it. Parent owns reset/backoff and retains the sticky route.

Exact resume: `spawn.sh --resume-id "$SID"` validates both copied records in a separate attempt, then adds `--conversation "$SID"` before `-p`. Preserve original cwd, mode, add-dir/permission behavior, model, and effort; `-p` receives the new attempt's short continuation `brief.md`. Require observed `init.conversation_id` to equal the requested ID; empty/missing/different IDs or reported `num_turns == 1` produce BLOCKED/nonzero even on CLI exit 0. No `--continue` or silent fresh-thread fallback. Raw events remain available for parent review. Follow SKILL.md's durable wait record, original checkpoint, and new report-before-cleanup protocol.
