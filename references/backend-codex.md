# Backend: Codex (GPT)

Read this after the user (or config) selected Codex. Official: `codex exec`. Prompt from file with `-`. Progress on stderr; final message on stdout. Pin `--sandbox`; user `~/.codex/config.toml` can change approval.

Parents must spawn via [scripts/spawn.sh](../scripts/spawn.sh) (`--backend codex --mode review|implement|visual`). Visual: one `--image "$RUN/<shot>"` per screenshot **before** the CLI runs (the script places `-i` before `-o`).

Do **not** use `--full-auto` (deprecated) or `--dangerously-bypass-approvals-and-sandbox` for ordinary Implement.

| Part | Why |
|---|---|
| `--sandbox read-only` | Review — writes refused. |
| `--sandbox workspace-write` | Implement — edit inside `-C` only. |
| `-m gpt-5.6-sol` | Current bundled default series. List: `codex debug models --bundled`. |
| `-c model_reasoning_effort=xhigh` | `minimal` `low` `medium` `high` `xhigh`. |
| `--skip-git-repo-check` | Always in this protocol (temp dirs, odd checkouts). |
| `--ephemeral` | No session files. |
| `-o` | Last message to file (also printed on stdout). |
| `- < brief.md` | Official prompt-from-file. Do **not** also pass an argv prompt. |

`--ignore-user-config` when you must not inherit a drifted `~/.codex/config.toml`. Auth still uses `CODEX_HOME`.

**Network:** `--sandbox read-only` on Windows may block outbound sockets (`connectex` to `api.github.com`). If the parent already ran `gh`/`curl`, put that output in the brief under **What was already tried** and forbid re-running those commands. Do not treat sandbox-blocked `gh` as a hang.

### Codex `review` subcommand

Ranked `P1`–`P3` on a diff, no custom rubric. Not wrapped by `spawn.sh` — only for an uninstructed diff sweep:

```bash
codex exec -C "<project-dir>" --sandbox read-only -m gpt-5.6-sol \
  -c model_reasoning_effort=xhigh --ephemeral \
  review --uncommitted
```

Shared flags go **before** `review`. Scope: `--uncommitted`, `--base <branch>`, `--commit <sha>`. A scope flag and a custom prompt are mutually exclusive — for instructed review, use `scripts/spawn.sh --backend codex`.
