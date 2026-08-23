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
Ever wanted **Grok Bot** in Cursor to keep working after its quota is gone — by handing the slice to Codex or Claude Code?

That's this skill. It dispatches another coding-agent harness — Claude Code, Codex (GPT), or Grok Build — as a **one-shot subagent**, then the parent synthesizes.

The other harness is not an oracle. A model reviewing its own work reproduces its own blind spots; a differently-trained harness does not. That worth is destroyed the moment you forward its answer without judging it.

This is a [Claude skill](https://code.claude.com/docs/en/skills) in the [Agent Skills](https://agentskills.io) format. The same protocol works from Cursor (including **Grok Bot**) and any other agent that can run a CLI in the background.

## Why this exists

I built it as a **collection for Grok Bot**.

**Grok Bot** in Cursor is the parent I actually live in. Even on **Cursor Ultra**, its usage limits are tight. When the quota is gone, the session is not — this skill lets Grok Bot **outsource** a bounded slice to another harness that still has budget: Claude Code, Codex, or Grok Build CLI. The Bot writes a brief, the other CLI runs one-shot, the Bot synthesizes. That is the difference between “Grok is rate-limited, stop” and “Grok is rate-limited, keep shipping.”

The second reason is the same protocol in the other direction: a decorrelated second opinion from a harness that did not write the code. Quota offload and second opinions are one mechanism.

## Why I use it this way

These are **my** defaults, not the protocol. The skill itself will not pick a harness from the job type — you name the CLI, or the parent asks once.

I find **Opus** (Claude Code) superior at **UI work** — layout, interaction, the thing on the screen. I find **GPT / Codex** superior at **reviewing**, especially **visual review**: screenshots plus the named CSS/JS, then a verdict on whether the defect is real.

So my default loop is: ship the UI with Opus, capture shots, dispatch Codex to confirm or refute, then the parent decides. Not the other way around, and never a paste-through of the subagent's report.

Going the other direction is the same idea. If you are already in Codex or Grok and the job is a UI slice, dispatch Claude Code / Opus to implement it.

## Recommended use

Author defaults (not the protocol):

| Job | I dispatch |
|---|---|
| Parent is Grok Bot and the quota is tight | Claude Code, Codex, or Grok Build CLI — bounded slice, then synthesize |
| UI implementation, layout, interaction | Claude Code (Opus) |
| Diff / correctness review | Codex |
| Visual review (screenshots + named sources) | Codex |
| Pressure-test a plan (assume it is flawed) | a *different* harness than the one that wrote it |
| Stuck bug, two fixes already failed | a *different* harness than the parent |

**How to ask** (from whatever agent you are in — including Grok Bot):

- *Outsource this to Codex — I'm near the Grok Bot limit.*
- *Ask Codex to review this diff.*
- *Get a visual review from Codex of the screenshots I just took.*
- *Have Claude Code implement this UI slice — named paths only.*
- *Ask Grok to try to refute this plan.*
- *Ask Codex from Claude Code* / *have Grok Build invoke Claude Code.*

**Worth a run:** second opinions, adversarial review of plans, visual confirmation, unstuck diagnosis, a bounded implement slice assigned to that harness.

**Not worth a run:** naming, style, formatting, or anything the parent can already answer from context.

The parent writes a **bounded brief** (named paths and a tight investigation — not a pasted dump), runs the other CLI in the background, then reports:

1. What was asked
2. The harness verdict (quoted)
3. Where it agrees and disagrees, with reasons
4. A recommendation

If you only paste the subagent's answer, you wasted the run.

## Install

Clone the **whole directory** (the skill reads `references/` for extra CLIs):

```bash
git clone https://github.com/ptmrio/harness-subagent.git ~/.claude/skills/harness-subagent
```

Windows PowerShell:

```powershell
git clone https://github.com/ptmrio/harness-subagent.git "$HOME\.claude\skills\harness-subagent"
```

That path is Claude Code’s personal skills dir. **Cursor also loads `~/.claude/skills/`**, so Grok Bot sees the same copy. Native Cursor path if you prefer: `~/.cursor/skills/harness-subagent`.

Already have a checkout? Copy the skill root, not just `SKILL.md`:

```bash
mkdir -p ~/.claude/skills/harness-subagent
cp SKILL.md ~/.claude/skills/harness-subagent/
cp -r references ~/.claude/skills/harness-subagent/
```

Then ask in those words: get a second opinion, pressure-test a plan or diff, or call Codex / Claude Code / Grok as a subagent.

## Requirements

At least one of `claude`, `codex`, or `grok` on `PATH` and logged in. Optional extras: `cursor-agent`, `gemini`, `opencode`, `droid` — see `references/more-clis.md`. Windows, WSL, Linux, and macOS; prefer Git Bash or WSL for the spawn recipes (native PowerShell cannot do `< file`).

## License

[MIT](LICENSE) — Gerhard Petermeir / [ptmrio](https://github.com/ptmrio). Issues welcome; PRs are not the default.
