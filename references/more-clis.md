# Additional harness CLIs

Read this only when the user named one of these backends. Majors (Claude / Codex / Grok / agy) use [scripts/spawn.sh](../scripts/spawn.sh) and `references/backend-*.md`. Recipes below follow vendor headless docs. **Hello-worlded on this author’s machine: Cursor Agent and agy (Windows, 2026-08-31).** OpenCode and Droid are documented from official sources and must be smoke-tested (`HELLO_WORLD`) on the target machine before you rely on them.

Same shared protocol as `SKILL.md`. These extras are **not** in `spawn.sh`. On Windows PowerShell: Write a tiny `.sh` next to `brief.md` that contains the recipe, then invoke Git Bash with that **file path as argv** (same as `scripts/spawn.sh`). Never nest `"$(cat …)"` or `$RUN` in a PowerShell double-quoted `-lc` string. Prefer file stdin / `--prompt-file` / `-f` over argv `$(cat brief)`.

## Cursor Agent

Official: [Headless CLI](https://cursor.com/docs/cli/headless) — `agent -p`. On many machines the binary is **`cursor-agent`**. The name `agent` often collides with **Grok Build**. Always invoke `cursor-agent` unless you have verified `Get-Command agent` / `command -v agent` is Cursor.

List models: `cursor-agent --list-models` (thinking is often in the id, e.g. `gpt-5.6-sol-xhigh`). Default: `--model auto` unless the user pins.

### Review (no writes)

```bash
cursor-agent -p --trust --mode ask --output-format text \
  --workspace "<project-dir>" --add-dir "$RUN" \
  < "$RUN/brief.md" > "$RUN/last.md" \
  2> "$RUN/stderr.log"
```

`--mode plan` is also read-only (planning). `--trust` skips the workspace trust prompt in print mode.

### Implement

```bash
cursor-agent -p --trust --force --output-format text \
  --workspace "<project-dir>" --add-dir "$RUN" \
  < "$RUN/brief.md" > "$RUN/last.md" \
  2> "$RUN/stderr.log"
```

`--yolo` is an alias of `--force`. Without `--force`, print mode proposes and does not apply writes.

Images: put paths in the prompt; `--add-dir "$RUN"` if shots live in the temp run dir. Auth for scripts: `CURSOR_API_KEY`.

Proven: `cursor-agent -p --mode ask` → `HELLO_WORLD` (Windows, 2026-08-23). `--trust` / `--add-dir` are from current `--help` (same date); wrap stdin/stdout like the majors.

## Legacy Gemini CLI

Consumer Gemini CLI stopped serving individuals on 2026-06-18 (`IneligibleTierError` / migrate to Antigravity). The spawn backend is **`agy`** ([backend-agy.md](backend-agy.md), `scripts/spawn.sh --backend agy`).

`gemini` remains a **separate** config token and family for Standard/Enterprise or paid Gemini API keys. Do not alias stored `gemini` to `agy`. Official: [Headless reference](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/headless.md). Not hello-worlded here (consumer `gemini -p` exited 55 on 2026-08-31).

```bash
# Review-ish (do not pass --yolo). Invoke from a .sh file, not PowerShell -lc.
gemini -p "$(cat "$RUN/brief.md")" --output-format text

# Implement (unattended approval)
gemini --yolo -p "$(cat "$RUN/brief.md")"
```

If `gemini -p` fails with `UNSUPPORTED_CLIENT`, spawn `agy` instead (utterance “Gemini” already routes there).

## OpenCode

Official: [`opencode run`](https://opencode.ai/docs/cli) (non-interactive). TUI `opencode` is not a spawn.

```bash
# Review — plan agent is permission-restricted
opencode run --agent plan --dir "<project-dir>" "$(cat "$RUN/brief.md")"

# Implement — auto-approve permissions not explicitly denied
opencode run --auto --dir "<project-dir>" "$(cat "$RUN/brief.md")"
```

`--file path` attaches files (repeatable). `--model provider/model`. `--variant` is provider-specific reasoning effort.

List models: `opencode models` (optional `--refresh`). Not hello-worlded here.

## Factory Droid

Official: [`droid exec`](https://docs.factory.ai/cli/droid-exec/overview). Default is spec/read-only. Writes need `--auto`.

```bash
# Review
droid exec -f "$RUN/brief.md" --output-format text

# Implement
droid exec -f "$RUN/brief.md" --auto medium --output-format text
```

`--auto` tiers: `low` `medium` `high`. List tools: `droid exec --list-tools`. Not hello-worlded here.

## Adding another CLI later

Do not invent flags. Require: vendor headless command, file or argv prompt, read vs write switch, model-list command, binary name on PATH, stdin behavior, one `HELLO_WORLD` smoke on that OS. Prefer adding the binary to `scripts/spawn.sh` over leaving a `$(cat)` recipe.
