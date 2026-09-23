---
name: harness-subagent
description: >
  Delegate a bounded task to another coding-agent CLI the way a parent agent
  delegates to a subagent. CLIs are Claude Code, Codex, Grok Build, Antigravity
  (agy), and the Cursor CLI (cursor-agent). Use when the user says
  harness-subagent, or names a CLI or a model such as Astra, Sol, Opus, Opus 5.5,
  Fable, Sonnet, Haiku, or Grok 4.7. Do not use to install those CLIs. Do not use
  if this session was launched by this skill (the prompt starts with YOU ARE THE
  WORKER, or HARNESS_SUBAGENT_RUN is set). Do that job. Do not delegate again.
license: MIT
compatibility: Requires claude, codex, grok, agy, and/or cursor-agent on PATH. Windows needs Git Bash. Python 3.
metadata:
  author: ptmrio
  version: "0.4.0"
---

# Harness subagent

You are the parent. A child CLI does one bounded task and returns a report. You judge the report. The child is not an oracle.

The host decides which CLI, which model, and which effort. This skill does not rank jobs or pick a persona.

## Delegate

1. Take the CLI and model from the user. Spoken names are in [references/models.md](references/models.md). If they named neither, ask once. Do not launch your own CLI family unless they named it this turn. Cursor, cursor-agent, and Grok Bot are the `cursor` family. Grok Build is `grok`. Claude Code is `claude`. Codex is `codex`. Antigravity is `agy`.
2. Pick `--effort` from the tables in [references/models.md](references/models.md) when the task is large enough that the vendor default is a guess. Omit `--effort` to keep the CLI default. Prices are per token. Higher effort spends more tokens at the same rate.
3. Write `brief.md` in a new temp run directory. Use the shape below.
4. Run `scripts/spawn.sh` in the background. On Windows, invoke Git Bash with the script path as an argument. Do not put the brief inside a PowerShell double-quoted string. Write `brief.md` as UTF-8.
5. Wait until that process exits. Read `report.md` or `last.md`, plus `capture-status.txt`, plus the exit code.
6. Say what you agree with, what you do not, and what you will do. Do not paste the report as your whole answer.

```powershell
& "$env:ProgramFiles\Git\bin\bash.exe" -- "<skill-dir>\scripts\spawn.sh" --backend codex --model Astra --effort high --project "D:/Code/app" --run "C:/Users/<you>/AppData/Local/Temp/harness-subagent/<id>"
```

`--backend` may be omitted when the model name belongs to one CLI. `--resume-id` continues that same child. Do not use `--continue` or `--last`.

A child must not delegate. `spawn.sh` sets `HARNESS_SUBAGENT_RUN` and refuses a second launch.

## Brief

```
# YOU ARE THE WORKER. DO NOT SPAWN.
Do not load harness-subagent. Do not run scripts/spawn.sh.

## Task
One sentence.

## Where to look
Paths, commands, and exclusions.

## Already tried

## Done when
```

Name paths. Do not paste the repo. `spawn.sh` appends the `report.md` path. The child writes that file before it exits. The first line states the result.

Grok cannot be relied on to read the temp run directory. `spawn.sh` copies the prompt into the project for that launch and deletes the copy on exit.

## When the child hits a limit

`spawn.sh` reads the CLI text for a reset time.

- The reset is known and within 24 hours. The script waits, then resumes that same session once. Claude Code's own auto-continue refuses waits longer than 24 hours (docs accessed 2026-09-22). This skill uses that cutoff for every CLI.
- There is no reset time, the reset is further away, the message is a credit or spend block, or a second limit arrives. The script stops. Stop with it. Tell the user the evidence and the time, if any. Wait for instructions. Do not switch CLI or model. Do not invent a reset time.

## Health

`scripts/health.sh` prints one row per CLI. Columns are name, version, login, update. `--update` runs each vendor update command. Exit 0 when every installed CLI with a login check is logged in. A missing CLI is a failed row.

| CLI | Login check | Update |
|---|---|---|
| claude | `claude auth status` | `claude update` |
| codex | `codex login status` | `codex update` |
| grok | `grok models` must say logged in | `grok update` |
| agy | no login command | `agy update` |
| cursor-agent | `cursor-agent status` | `cursor-agent update` |

## Capture

`spawn.sh` writes `last.md`, `capture-status.txt` (`ok`, `ok-report`, `usage-limit`, or `no-verdict`), and `session.json`. A report containing `VERDICT` wins over the final stdout, because Claude's last message is only the last turn. `ok` means text was captured. It does not mean the task succeeded. Exit 0 with `no-verdict` is not success.

Resume needs the session id from that run. Copy `session-id` and `session.json` into a new run directory, write a short continuation `brief.md`, and pass `--resume-id`. The auto-wait path does this itself once.
