# Backend: Codex (GPT)

Read this after the user (or config) selected Codex. Official: `codex exec`. Prompt from file with `-`. Spawn captures `--json` process stdout into `events.jsonl`; `-o stdout.md` remains the human last message. `codex exec` has no `--ask-for-approval` (that flag is interactive `codex -a`). Spawn pins `--approve-for-me` on every mode (classifier Auto; implies workspace-write so Review can write temp/report files). **Do not** also pass `--sandbox` (0.147.0 mutex: `cannot be used with '--approve-for-me'`). App-edit restraint is the brief, not a sandbox. Do **not** use `--full-auto` (deprecated) or `--dangerously-bypass-approvals-and-sandbox`.

Parents must spawn via [scripts/spawn.sh](../scripts/spawn.sh) (`--backend codex --mode review|implement|visual`). Visual: one `--image "$RUN/<shot>"` per screenshot **before** the CLI runs (the script places `-i` before `-o`).

| Part | Why |
|---|---|
| `--approve-for-me` | All modes — classifier Auto. Do not also pass `--sandbox`. |
| `-m gpt-5.6-sol` | Skill policy default. List what this CLI has: `codex debug models --bundled`. |
| `-c model_reasoning_effort=xhigh` | `minimal` `low` `medium` `high` `xhigh` (`max` on Astra). |
| `--skip-git-repo-check` | Always in this protocol (temp dirs, odd checkouts). |
| `--json` | Raw events to `events.jsonl`; persistence enabled (no `--ephemeral`). |
| `-o` | Last message to file (also printed on stdout). |
| `- < brief.md` | Official prompt-from-file. Do **not** also pass an argv prompt. |

**Optional Astra:** utterance `Astra` (or config / `--model`) pins `-m gpt-6-astra`. Do not gate the pin on this machine’s bundled list. Do not silently fall back to Sol. Codex CLI **0.153.1+** adds first-class metadata (picker + bundled default on **0.153.4+**); older CLIs still forward the slug and may warn / attach generic metadata, then fail at the API if the account/rollout does not include Astra. Official: [Codex Models](https://learn.chatgpt.com/docs/models), [GPT-6 Astra](https://developers.openai.com/api/docs/models/gpt-6-astra), changelog 0.153.1 / 0.153.4 (accessed 2026-09-05).

`--ignore-user-config` when you must not inherit a drifted `~/.codex/config.toml`. Auth still uses `CODEX_HOME`.

**Network:** if the parent already ran `gh`/`curl`, put that output in the brief under **What was already tried** and forbid re-running those commands. Do not treat a permission-declined `gh` as a hang.

### Codex `review` subcommand

Ranked `P1`–`P3` on a diff, no custom rubric. Not wrapped by `spawn.sh` — only for an uninstructed diff sweep:

```bash
codex exec -C "<project-dir>" --approve-for-me -m gpt-5.6-sol \
  -c model_reasoning_effort=xhigh --ephemeral \
  review --uncommitted
```

Shared flags go **before** `review`. Scope: `--uncommitted`, `--base <branch>`, `--commit <sha>`. A scope flag and a custom prompt are mutually exclusive — for instructed review, use `scripts/spawn.sh --backend codex`.

Spawn checks Python 3 (`python` or `python3`; no jq dependency) to decode JSONL. The first `thread.started.thread_id` writes `session-id` and `session.json` before parsing any final message, including on CLI exit 1. Metadata binds backend/native `thread_id`, resolved cwd, origin/attempt runs, model, effort, and mode; observed IDs have `preassigned: false`. Missing ID means resume unavailable. Parser failure finalizes a BLOCKED capture and exits nonzero; it does not replace a `usage-limit` classification. Raw envelopes never replace `last.md`. Decoded provider error events are labeled `provider-errors.log` for limit detection only when selected text has no verdict; tool payloads are not scanned. A returned CLI failure retains its status. Capture `ok` / `ok-report` is not job success.

Exact resume uses the parent-verified 0.153.4 grammar, through `spawn.sh --resume-id "$SID"`:

```bash
codex exec --approve-for-me -C "$PROJECT" resume -m "$MODEL" \
  -c "model_reasoning_effort=$EFFORT" --skip-git-repo-check --json \
  -o "$STDOUT" "$RESUME_ID" -
```

Exec flags `--approve-for-me` and `-C` precede `resume`; continuation `brief.md` is stdin. No `--ephemeral`, `--sandbox`, or `--last`. Parent copies the two matching identity records to a separate attempt and retains original cwd/route/role pins. Require the resumed `thread.started.thread_id` to equal the requested ID before accepting a successful resume, including when the event stream is empty or whitespace; missing/different identity blocks even if the CLI claimed success. A classified usage-limit is not replaced by this identity failure. The original report remains the checkpoint; do not copy it onto this attempt's report slot. Parent owns waiting, with no implicit fresh-thread fallback.
