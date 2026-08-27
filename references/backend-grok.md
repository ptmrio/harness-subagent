# Backend: Grok Build

Read this after the user (or config) selected Grok. Official headless: `-p` / `--prompt-file`. **Does not** treat piped stdin as the prompt. The spawn script still closes stdin (`< /dev/null`) so a parent pipe cannot hang the process.

Parents must spawn via [scripts/spawn.sh](../scripts/spawn.sh) (`--backend grok --mode review|implement`). Do not spawn `grok` from a Grok parent (Bot, Cursor Grok, or Grok CLI) unless the user named it this turn.

| Part | Why |
|---|---|
| `--prompt-file` | Official file prompt; implies headless. |
| `--permission-mode auto` | Classifier verifies, then allows. Headless: a blocked tool is reported to the model. |
| `dontAsk` + `--allow` | Headless deny-by-default. Not the spawn.sh default. |
| `-m grok-4.6` | CLI default. List: `grok models`. |
| `--effort xhigh` | `none` `minimal` `low` `medium` `high` `xhigh` `max`. |
| `--output-format plain` | Final text. |
| `< /dev/null` | Hang insurance (stdin is not the prompt). |

Grok often narrates before the verdict and loads process skills — the brief’s “first line = VERDICT” and “do not load process skills” lines are **required**. Process still running → wait. Process exited with a preamble → strip to the first `VERDICT` line; do not relaunch.

Do **not** use `--always-approve` / `bypassPermissions` for routine work. Auth: `grok login` or `XAI_API_KEY`.
