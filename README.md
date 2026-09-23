# harness-subagent

**Hand a bounded task to another coding-agent CLI, then judge what comes back.**

[![License: MIT][mit-badge]][mit]
[![Agent Skills][skills-badge]][agentskills]
[![Claude Code][claude-badge]][claude]
[![Codex][codex-badge]][codex]
[![Grok Build][grok-badge]][grok]
[![Cursor CLI][cursor-badge]][cursor]

Ever wanted to call **Codex** from **Claude Code**?  
Ever wanted **Grok Build** to invoke **Claude Code**?  
Ever wanted **Claude Code** to send a diff to **GPT** for a second opinion?

That is this skill. You stay in the agent you already use. It becomes the parent: it writes a short brief, starts another CLI in the background, reads that CLI's report, and tells you what it agrees with, what it does not, and what it will do next.

The child is not an oracle. A model that reviews its own work repeats its own blind spots. A model trained by a different vendor may not. That value is lost if the parent forwards the answer without judging it.

Supported child CLIs: Claude Code (`claude`), Codex (`codex`), Grok Build (`grok`), Antigravity (`agy`), and the Cursor CLI (`cursor-agent`). The host picks the CLI, the model, and the effort. The skill does not rank jobs or assign personas.

This is a [Claude skill](https://code.claude.com/docs/en/skills) in the [Agent Skills](https://agentskills.io) format. Any agent that can run a shell command in the background can use it.

**Do not use it** to install those CLIs, for questions the parent can answer from its own context, or inside a child it launched. A child never delegates again.

## Installation

```bash
npx skills add ptmrio/harness-subagent -g
```

That is the [skills.sh](https://skills.sh) installer. `-g` installs at user level, for example `~/.claude/skills/harness-subagent` for Claude Code or `~/.cursor/skills/harness-subagent` for Cursor ([paths](https://github.com/vercel-labs/skills#supported-agents)). Update later with `npx skills update -g`.

Without npx, clone it into your agent's skills folder:

```bash
git clone https://github.com/ptmrio/harness-subagent.git ~/.claude/skills/harness-subagent
```

**Requirements**

- At least one of `claude`, `codex`, `grok`, `agy`, or `cursor-agent` on `PATH` and logged in.
- Python 3 (`python` or `python3`).
- Windows: Git Bash. The parent runs `scripts/spawn.sh` through Git Bash. [SKILL.md](SKILL.md) has the exact invocation.

### Health check

From the installed skill folder:

```bash
scripts/health.sh            # one row per CLI: name, version, login, update
scripts/health.sh --update   # same, and runs each CLI's own update command
```

Example output (tab-separated):

```text
claude   2.1.280 (Claude Code)   logged-in       -
codex    codex-cli 0.155.1       logged-in       -
grok     missing                 -               -
agy      present                 login-unknown   -
cursor   2026.09.08-6caf4ff      logged-in       -
```

The exit code is 0 only when every CLI is present, every CLI with a login check is logged in, and (with `--update`) every update succeeded. A CLI you never use shows up as `missing` and makes the exit code 1. Read the rows. `agy` has no login command, so it always reports `login-unknown`. The per-CLI login and update commands are in the Health section of [SKILL.md](SKILL.md#health).

## Use it

The protocol is [SKILL.md](SKILL.md). This is the short version.

1. **You name the CLI and the model.** Spoken names such as Opus 5.5, Fable, Sonnet, Astra, Sol, Terra, Luna, and Grok 4.7 resolve to exact ids in [references/models.md](references/models.md), which also lists prices and effort levels. For Antigravity and Cursor, pass the id that CLI accepts. If you name neither CLI nor model, the parent asks once.
2. **The parent writes a brief.** It creates `brief.md` in a new temp run directory: one task sentence, where to look, what was already tried, and when it is done. It names paths. It does not paste the repo.
3. **The parent runs `scripts/spawn.sh` in the background** and waits for it to exit.
4. **The parent judges the report.** It reads `report.md` (or `last.md`) and `capture-status.txt`, then says what it agrees with, what it does not, and what it will do. A pasted report is not an answer.

```text
you ──> parent ──brief.md──> spawn.sh ──> child CLI
             ^                               │
             └──────── report.md ────────────┘
parent judges ──> you
```

Things you can say:

- *Ask Codex with Astra, effort high, to review the diff on this branch.*
- *Have Claude Code with Opus 5.5 build the settings page layout in `src/ui/settings/`.*
- *Ask Grok 4.7 to try to refute the plan in `docs/plan.md`.*
- *Use harness-subagent: Sol, medium effort. Find out why `tests/api` flakes on CI. Report only, no edits.*
- *Get Fable 5.1 to review this migration before I merge it.*

One job per spawn. "Implement and then review it" is two spawns, or one spawn plus the parent's own review.

If the child hits a usage limit that resets within 24 hours, `spawn.sh` waits and resumes that same session once. Any other stop ends the run. The parent reports it and waits for you. It does not switch CLI or model on its own.

## With Superpowers

[Superpowers](https://github.com/obra/superpowers) is a development methodology built from skills. Several of its skills dispatch subagents through the host's own subagent tool:

- `requesting-code-review` sends a reviewer subagent the base and head commits.
- `subagent-driven-development` runs an implementer and a task reviewer per plan task, then a whole-branch review at the end.
- `dispatching-parallel-agents` runs one agent per independent problem.

Superpowers says user instructions (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`) take precedence over its skills. So the routing goes in your host instructions. This skill does not load Superpowers, and Superpowers does not need to know about this skill.

**Best practice:** route the review steps, not every subagent. Superpowers already runs a review after each task. The whole-branch review at the end of `subagent-driven-development`, and `requesting-code-review` before a merge, are the points where a different vendor's model adds the most. Keep implementer subagents native. A CLI spawn per task costs a fresh process and a fresh context.

Example `CLAUDE.md` lines:

```markdown
## Reviews
- When a Superpowers skill asks for a whole-branch review or a pre-merge code
  review, run that review with harness-subagent: Codex, model Sol, effort high.
- Keep implementer and per-task reviewer subagents native.
- Treat the report like any reviewer's: fix what holds up, push back with reasons.
```

The brief the parent writes then looks like this:

```markdown
# YOU ARE THE WORKER. DO NOT SPAWN.
Do not load harness-subagent. Do not run scripts/spawn.sh.

## Task
Review the branch diff a7981ec..3df7661 against the plan. Report issues by severity.

## Where to look
docs/superpowers/plans/deployment-plan.md, then `git diff a7981ec..3df7661`.

## Already tried
Per-task reviews passed for tasks 1–4.

## Done when
Every Critical and Important issue names a file and line, or the report says there are none.
```

If the child CLI also has Superpowers installed, its `using-superpowers` bootstrap tells a dispatched subagent to skip it. The brief's first line already says the child is a worker.

## With pstack `poteto-mode`

[pstack](https://github.com/cursor/plugins/tree/main/pstack) is poteto's skill set for Cursor, installed with `/add-plugin pstack`. [`/poteto-mode`](https://github.com/cursor/plugins/blob/main/pstack/skills/poteto-mode/SKILL.md) is its entry point. It matches a task to one of twenty-three playbooks and runs the other skills as the steps need them. You start it by name, and it stays on across turns.

Its subagent rules already fit this skill's protocol. It runs subagents in the background, passes file pointers instead of pasted context, sets an explicit model per role, and says: "You own every subagent's work. Review the diff and write your own summary, don't pass through what it said." So harness-subagent only changes where a delegate runs: in another vendor's CLI instead of a Cursor `Task`.

**Best practice:** put the routing in its own always-applied Cursor rule. `/setup-pstack` writes per-role models to `~/.cursor/rules/pstack-models.mdc` and overwrites the whole file each time it runs, so lines you add there get lost. Leave pstack's multi-model skills (`interrogate`, `arena`, `architect`, `swarm`) on their configured panels unless you want to replace them.

Example `~/.cursor/rules/harness-subagent.mdc`:

```markdown
---
description: Route larger poteto-mode delegates through harness-subagent
alwaysApply: true
---
When poteto-mode would spawn a subagent for a medium-to-demanding task,
use the harness-subagent skill instead.
Use Opus for UI work.
Use a named Codex model, such as Sol or Astra, for visual testing.
Leave interrogate, arena, architect, and swarm panels as configured.
```

### This is how I use it.

This is my setup, not the protocol. The skill does not enforce these model choices.

I run pstack `poteto-mode` in the Cursor GUI, locally. I tell the parent: whenever you would spawn a subagent for a medium-to-demanding task, use harness-subagent instead. Use Opus for UI work. Use Codex for visual testing.

Opus is the spoken name for Opus 5.5. Codex is the CLI, so the visual-testing line still needs a model from [references/models.md](references/models.md), such as Sol or Astra. Those picks are mine. They are not a ranking the skill enforces. Put your own in your rule.

## License

[MIT](LICENSE). Gerhard Petermeir / [ptmrio](https://github.com/ptmrio). Issues welcome; PRs are not the default.

[mit-badge]: https://img.shields.io/badge/License-MIT-blue.svg
[mit]: LICENSE
[skills-badge]: https://img.shields.io/badge/Agent%20Skills-compatible-111111
[agentskills]: https://agentskills.io
[claude-badge]: https://img.shields.io/badge/Claude%20Code-headless-d97706
[claude]: https://code.claude.com/docs/en/headless
[codex-badge]: https://img.shields.io/badge/Codex-exec-10a37f
[codex]: https://github.com/openai/codex
[grok-badge]: https://img.shields.io/badge/Grok%20Build-CLI-000000
[grok]: https://docs.x.ai
[cursor-badge]: https://img.shields.io/badge/Cursor-CLI-000000
[cursor]: https://cursor.com/docs/cli/overview
