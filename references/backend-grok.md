# Backend: Grok Build

Read this after the user (or config) selected Grok. Official headless: `-p` / `--prompt-file`. **Does not** treat piped stdin as the prompt. The spawn script still closes stdin (`< /dev/null`) so a parent pipe cannot hang the process.

Parents must spawn via [scripts/spawn.sh](../scripts/spawn.sh) (`--backend grok --mode review|implement`). Do not spawn `grok` from a Grok parent (Bot, Cursor Grok, or Grok CLI) unless the user named it this turn.

| Part | Why |
|---|---|
| `--prompt-file` | Official file prompt; implies headless. |
| `--permission-mode auto` | Classifier verifies, then allows. Headless: a blocked tool is reported to the model. All modes; no `--sandbox`. |
| `dontAsk` + `--allow` | Headless deny-by-default. Not the spawn.sh default. |
| `-m grok-4.6` | CLI default. List: `grok models`. |
| `--effort xhigh` | `none` `minimal` `low` `medium` `high` `xhigh` `max`. |
| `--output-format plain` | Final text. |
| `--session-id "$SID"` | Fresh launch only (Grok 1.0.13 create-only flag). Preassign and save UUID before launch; keep plain output. |
| `< /dev/null` | Hang insurance (stdin is not the prompt). |

Grok often narrates before the verdict and loads process skills — the brief’s “first line = VERDICT” and “do not load process skills” lines are **required**. Process still running → wait. Process exited with a preamble → strip to the first `VERDICT` line; do not relaunch.

Do **not** use `--always-approve` / `bypassPermissions` for routine work. Auth: `grok login` or `XAI_API_KEY`.

`session-id` and `session.json` bind native `session_id`, resolved cwd, originating/attempt run, mode, model, and effort. `preassigned: true` is intent, not proof of persisted history. Spawn checks Python 3 for JSON metadata; UUID generation tries `uuidgen`, Python uuid4, then PowerShell `[guid]::NewGuid()`. Dry-run publishes no identity files. Returned failures still finalize; evaluate the exit status and verdict together. Parent owns reset/backoff and keeps the route sticky (see SKILL.md).

Exact resume: `spawn.sh --resume-id "$SID"` validates copied identity records in a separate attempt and emits **`--resume "$SID"`**, with the ID mandatory. Grok's `--session-id` is create-only and is omitted on resume. Keep plain output, `--prompt-file` pointing at the short continuation `brief.md`, original cwd, permission-mode, model, and effort. No bare `--resume` (most-recent selection), `--continue`, `-c`, or `--fork-session`. Missing/mismatched metadata blocks before launch; provider rejection stays BLOCKED/nonzero with no fresh fallback. Parent preserves the original checkpoint, owns the wait, and directs the worker to write a new complete report before cleanup.
