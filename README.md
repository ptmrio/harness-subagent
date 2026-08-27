# harness-subagent

**Dispatch another coding-agent CLI as a one-shot subagent, then synthesize.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Agent Skills](https://img.shields.io/badge/Agent%20Skills-compatible-111111)](https://agentskills.io)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-headless-d97706)](https://code.claude.com/docs/en/headless)
[![Codex](https://img.shields.io/badge/Codex-exec-10a37f)](https://github.com/openai/codex)
[![Grok Build](https://img.shields.io/badge/Grok%20Build-CLI-000000)](https://docs.x.ai)

Ever wanted to call **Codex** from **Claude Code**?  
Ever wanted **Grok Build** to invoke **Claude Code**?  
Ever wanted **Claude Code** to send a diff to **GPT** for a second opinion?

That's this skill. Stay in the parent you are already in — Cursor Agent, **cursor-agent**, Claude Code, Codex, Grok Build, or **Grok Bot**. It writes a brief, dispatches another coding-agent harness as a **one-shot subagent**, then the parent synthesizes.

The other harness is not an oracle. A model reviewing its own work reproduces its own blind spots; a differently-trained harness does not. That worth is destroyed the moment you forward its answer without judging it.

This is a [Claude skill](https://code.claude.com/docs/en/skills) in the [Agent Skills](https://agentskills.io) format. The same protocol works from any agent that can run a CLI in the background.

## Why I use it this way

These are **my** defaults, not the protocol. The skill will not pick a harness from the job type. You name the CLI, or you pin defaults in a **user config file** the parent is instructed to read, or it asks once.

I find **Opus** (Claude Code) superior at **UI work** — layout, interaction, the thing on the screen. I find **GPT / Codex** superior at **reviewing**, especially **visual review**: screenshots plus the named CSS/JS, then a verdict on whether the defect is real.

So my default loop is: ship the UI with Opus, capture shots, dispatch Codex to confirm or refute, then the parent decides. Not the other way around, and never a paste-through of the subagent's report.

Going the other direction is the same idea. If you are already in Codex or Grok Build and the job is a UI slice, dispatch Claude Code / Opus to implement it.

If the parent is metered (for example Cursor **Grok Bot**), outsource the long run to CLIs that bill their own accounts. Same protocol; **cursor-agent** is Cursor’s CLI, a different parent from Grok Bot.

## How to prompt

Name the harness when you know it. **One job per spawn.** One `/harness-subagent` (or “orchestrate this”) is enough — do not paste this skill into every message.

**Good**

- *Orchestrate this — outsource the slice to Codex.*
- *Ask Codex to review this diff.*
- *Have Claude Code implement only the named UI paths, then review.*
- *You write the spec; ask Codex to pressure-test the plan.*
- *Get a visual review from Codex of the screenshots I just took.*
- *Ask Grok Build to try to refute this plan.*
- *Ask Codex from Claude Code* / *have Grok Build invoke Claude Code.*

**Avoid**

- “Self review” and “spawn Claude” in the same breath — pick one.
- spec + plan + implement + review as one utterance unless you want four paid runs (or say “spec and plan together, then implement, then review”).
- Pasting diffs or whole files when named paths suffice.
- Interrupting a wait unless you intend to cancel the child.

## Recommended use

Author defaults (not the protocol):

| Job | I dispatch |
|---|---|
| Heavy slice on a metered parent (e.g. Grok Bot) | Claude Code, Codex, or Grok Build CLI — brief, then synthesize |
| UI implementation, layout, interaction | Claude Code (Opus) |
| Sustained writing (README, skill copy, About) | Grok Build CLI (name it this turn if the parent is already Grok) |
| Research (docs, competitive, GitHub inventory) | Codex |
| Diff / correctness review | Codex |
| Visual review (screenshots + named sources) | Codex |
| Pressure-test a plan (assume it is flawed) | a *different* harness than the one that wrote it |
| Stuck bug, two fixes already failed | a *different* harness than the parent |

**Worth a run:** second opinions, adversarial review of plans, visual confirmation, unstuck diagnosis, sustained writing, research lookups, a bounded implement slice assigned to that harness.

**Not worth a run:** naming, style, formatting, or anything the parent can already answer from context.

The parent writes a **bounded brief** (named paths and a tight investigation — not a pasted dump), runs `scripts/spawn.sh` in the background, then reports:

1. What was asked
2. The harness verdict (quoted)
3. Where it agrees and disagrees, with reasons
4. A recommendation

If you only paste the subagent's answer, you wasted the run.

## Install

```bash
npx skills add ptmrio/harness-subagent -g
```

That is the [skills.sh](https://skills.sh) installer: one command, copies the whole skill (`SKILL.md`, `references/`, `scripts/`, `assets/`, `evals/`, `tests/`) into the agents on this machine — Cursor Agent, Claude Code, Codex, and the rest the CLI detects. `-g` is user-level. It may fan out **identical copies**; always run `scripts/spawn.sh` from the `SKILL.md` you loaded. Do not keep a second hand-copied tree.

Grok Bot is a separate app; it only uses this skill if that Bot can run a CLI and can load the skill (or you point it at `SKILL.md`).

### Pin defaults (optional)

The CLIs do not load this file. The **skill** tells the parent to read it when you did not name a harness (utterance → this file → ask once). It lives **outside** the skill clone so updates cannot overwrite it.

```text
~/.config/harness-subagent/config.toml
```

Copy `assets/config.example.toml` there (`spec`, `plan`, `implement`, `writer`, `research`, `code-review-*`, …). Values may be a CLI or `self` (parent does that job). `cursor` from a Cursor parent is skipped (same family), not treated as `self`. Override path: `$HARNESS_SUBAGENT_CONFIG`. Schema: `references/user-config.md`.

Git clone if you do not want `npx`:

```bash
git clone https://github.com/ptmrio/harness-subagent.git ~/.claude/skills/harness-subagent
```

Windows PowerShell:

```powershell
git clone https://github.com/ptmrio/harness-subagent.git "$HOME\.claude\skills\harness-subagent"
```

Cursor also loads `~/.claude/skills/`. Native Cursor path if you prefer: `~/.cursor/skills/harness-subagent`.

Already have a checkout? Copy the skill root, not just `SKILL.md`:

```bash
mkdir -p ~/.claude/skills/harness-subagent
cp SKILL.md LICENSE README.md ~/.claude/skills/harness-subagent/
cp -r references scripts assets evals tests ~/.claude/skills/harness-subagent/
```

Then ask in those words: orchestrate this, get a second opinion, pressure-test a plan or diff, or call Codex / Claude Code / Grok as a subagent.

## Requirements

At least one of `claude`, `codex`, `grok`, or `cursor-agent` on `PATH` and logged in. Optional extras: `gemini`, `opencode`, `droid` (not in `scripts/spawn.sh` yet) — see `references/more-clis.md`. Windows, WSL, Linux, and macOS.

On native Windows the parent must run `scripts/spawn.sh` through Git Bash (`%ProgramFiles%\Git\bin\bash.exe`) as a **file argument**. WSL `bash.exe` and a PowerShell-quoted `bash -lc` one-liner will not work.

## Test

Git Bash, from a checkout. No extra tools. Does not call real CLIs (dry-run plus PATH-isolated stubs):

```bash
bash tests/spawn_test.sh
```

## License

[MIT](LICENSE) — Gerhard Petermeir / [ptmrio](https://github.com/ptmrio). Issues welcome; PRs are not the default.
