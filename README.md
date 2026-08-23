# harness-subagent

**Orchestration for coding agents — stay in the parent, outsource to other harnesses, then synthesize.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Agent Skills](https://img.shields.io/badge/Agent%20Skills-compatible-111111)](https://agentskills.io)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-headless-d97706)](https://code.claude.com/docs/en/headless)
[![Codex](https://img.shields.io/badge/Codex-exec-10a37f)](https://github.com/openai/codex)
[![Grok Build](https://img.shields.io/badge/Grok%20Build-CLI-000000)](https://docs.x.ai)

Ever wanted to call **Codex** from **Claude Code**?  
Ever wanted **Grok Build** to invoke **Claude Code**?  
Ever wanted **Claude Code** to send a diff to **GPT** for a second opinion?  
Ever ran out of **Grok Bot** usage after heavy tasks?

That's this skill. You have an **orchestrator** — **Grok Bot**, **Cursor Agent** / **cursor-agent**, Claude Code, Codex, whoever you are already in. It writes a brief, dispatches another coding-agent harness as a **one-shot subagent**, then the parent synthesizes.

The other harness is not an oracle. A model reviewing its own work reproduces its own blind spots; a differently-trained harness does not. That worth is destroyed the moment you forward its answer without judging it.

This is a [Claude skill](https://code.claude.com/docs/en/skills) in the [Agent Skills](https://agentskills.io) format. The same protocol works from Cursor Agent, **cursor-agent**, **Grok Bot** (if that Bot can run a CLI), and any other agent that can run a CLI in the background.

## Why this exists

I built it as **orchestration for Grok Bot**.

**Grok Bot** is Cursor’s persistent-agent product — its own weekly usage meter on your Cursor account. That meter is not Cursor Agent’s Grok 4.6 pool, and it is not Grok Build CLI. It resets weekly. It is drawn down by agent steps and tokens, not by message count: one heavy task can burn a large share of the week, even on Ultra.

This skill is how I stop spending that meter on the heavy slice. While the Bot still has usage, it writes a short brief and **outsources** the long run to Claude Code, Codex, or Grok Build CLI (those CLIs bill their own accounts). The Bot synthesizes. That is conservation.

If Grok Bot weekly usage is already gone, the Bot cannot orchestrate. Wait for the weekly reset, use on-demand if you have it, or switch the parent to Cursor Agent / Claude Code / Codex.

**cursor-agent** is a different parent (Cursor’s CLI). Same protocol, separate product from Grok Bot.

## Why I use it this way

These are **my** defaults, not the protocol. The skill will not pick a harness from the job type. You name the CLI, or you pin defaults in a **user config file** the parent is instructed to read, or it asks once.

I find **Opus** (Claude Code) superior at **UI work** — layout, interaction, the thing on the screen. I find **GPT / Codex** superior at **reviewing**, especially **visual review**: screenshots plus the named CSS/JS, then a verdict on whether the defect is real.

So my default loop is: ship the UI with Opus, capture shots, dispatch Codex to confirm or refute, then the parent decides. Not the other way around, and never a paste-through of the subagent's report.

Going the other direction is the same idea. If you are already in Codex or Grok Build and the job is a UI slice, dispatch Claude Code / Opus to implement it.

## Recommended use

Author defaults (not the protocol):

| Job | I dispatch |
|---|---|
| Heavy slice while I am still in Grok Bot (save Bot usage) | Claude Code, Codex, or Grok Build CLI — brief, then synthesize |
| UI implementation, layout, interaction | Claude Code (Opus) |
| Diff / correctness review | Codex |
| Visual review (screenshots + named sources) | Codex |
| Pressure-test a plan (assume it is flawed) | a *different* harness than the one that wrote it |
| Stuck bug, two fixes already failed | a *different* harness than the parent |

**How to ask** (from whatever agent you are in):

- *Orchestrate this — outsource the slice to Codex.*
- *From Grok Bot: have Claude Code do this UI slice — named paths only.*
- *Ask Codex to review this diff.*
- *Get a visual review from Codex of the screenshots I just took.*
- *Ask Grok Build to try to refute this plan.*
- *Ask Codex from Claude Code* / *have Grok Build invoke Claude Code.*

**Worth a run:** second opinions, adversarial review of plans, visual confirmation, unstuck diagnosis, a bounded implement slice assigned to that harness.

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

That is the [skills.sh](https://skills.sh) installer: one command, copies the whole skill (`SKILL.md`, `references/`, `scripts/`, `assets/`, `evals/`) into the agents on this machine — Cursor Agent, Claude Code, Codex, and the rest the CLI detects. `-g` is user-level, so it is not tied to one repo. Grok Bot is a separate app; it only uses this skill if that Bot can run a CLI and can load the skill (or you point it at `SKILL.md`).

### Pin defaults (optional)

The CLIs do not load this file. The **skill** tells the parent to read it when you did not name a harness (utterance → this file → ask once). It lives **outside** the skill clone so updates cannot overwrite it.

```text
~/.config/harness-subagent/config.toml
```

Copy `assets/config.example.toml` there, or tell the parent “always use Codex for review.” Override path: `$HARNESS_SUBAGENT_CONFIG`. Schema: `references/user-config.md`.

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
cp -r references scripts assets evals ~/.claude/skills/harness-subagent/
```

Then ask in those words: orchestrate this, get a second opinion, pressure-test a plan or diff, or call Codex / Claude Code / Grok as a subagent.

## Requirements

At least one of `claude`, `codex`, `grok`, or `cursor-agent` on `PATH` and logged in. Optional extras: `gemini`, `opencode`, `droid` (not in `scripts/spawn.sh` yet) — see `references/more-clis.md`. Windows, WSL, Linux, and macOS.

On native Windows the parent must run `scripts/spawn.sh` through Git Bash (`%ProgramFiles%\Git\bin\bash.exe`) as a **file argument**. WSL `bash.exe` and a PowerShell-quoted `bash -lc` one-liner will not work.

## License

[MIT](LICENSE) — Gerhard Petermeir / [ptmrio](https://github.com/ptmrio). Issues welcome; PRs are not the default.
