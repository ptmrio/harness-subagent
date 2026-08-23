---
name: harness-subagent
description: >
  Use when the user asks to orchestrate, outsource, delegate, or hand off a
  slice to another coding-agent CLI as a one-shot subagent — Claude Code,
  Codex, Grok Build, Cursor Agent, Gemini CLI, OpenCode, or Droid — or to ask
  Claude, ask GPT, ask Codex, ask Grok, get a second opinion, or pressure-test
  a plan or diff from a different harness. Do not use to install those CLIs or
  to explain their flags.
license: MIT
compatibility: Requires another coding-agent CLI on PATH (claude, codex, grok, and/or cursor-agent). Windows, WSL, Linux, macOS. Git Bash on native Windows.
metadata:
  author: ptmrio
  version: "0.1.1"
---

# Harness Subagent

Dispatch **another coding-agent harness** as a one-shot subagent, then synthesize.

**Core principle: the harness is a subagent, not an oracle.** A model reviewing its own work reproduces its own blind spots. That worth is destroyed if you forward the answer without judging it.

Do **not** pick a harness because of a task stereotype (UI vs review vs visual). Routing order: **this utterance → user config → ask once.** Same protocol for every backend.

Default to **read-only Review**. Allow writes only when the user (or an approved plan) asks for Implement.

## Pick a backend

Never spawn the **parent’s own family** unless the user named it this turn (Grok parent → no `grok`; Claude Code parent → no `claude`; Codex parent → no `codex`). One harness per question unless the user asked for multiple opinions.

| User says | Binary (PATH) | Default model (latest series) | Default thinking | Flags |
|---|---|---|---|---|
| Claude, Opus, Fable, ask-claude | `claude` | `opus` (also `fable`, `sonnet`, `haiku`) | `xhigh` | [references/backend-claude.md](references/backend-claude.md) |
| GPT, Codex, Sol, Terra, Luna, ask-gpt | `codex` | `gpt-5.6-sol` | `xhigh` | [references/backend-codex.md](references/backend-codex.md) |
| Grok, ask-grok | `grok` | `grok-4.6` | `xhigh` | [references/backend-grok.md](references/backend-grok.md) |
| Unspecified | User config `defaults.review` / `defaults.implement` if set **and** not the parent family; else ask once. | Config `[models]` / `[effort]`, else table defaults | — | [references/user-config.md](references/user-config.md) |

If the user pins a model id, use it. Cursor Agent / Gemini / OpenCode / Droid: [references/more-clis.md](references/more-clis.md) (not in `scripts/spawn.sh` yet).

**List what this machine actually has:**

```bash
claude --help
codex debug models --bundled
grok models
cursor-agent --list-models
```

Windows PowerShell: `Get-Command claude,codex,grok`. Do **not** hardcode `~/.local/bin/…`. **`agent` on PATH is often Grok Build, not Cursor.** Cursor’s CLI is `cursor-agent`.

There is no `harness-spawn` skill. Stale `ask-claude` / `ask-gpt` / `ask-grok` stubs: this skill.

## User config

Optional. Survives skill updates. **Never** store prefs in the skill clone (`npx skills add` fans out into every agent dir).

- If `$HARNESS_SUBAGENT_CONFIG` is set: that file. Missing file → ask once (do not fall through).
- Else: `${XDG_CONFIG_HOME:-$HOME/.config}/harness-subagent/config.toml`

Schema, search, and “always use X” write path: [references/user-config.md](references/user-config.md). Do not create the file unless the user asked to pin.

## OS, temp, stdin

Parent agents often pipe stdin. Treat that as hostile.

| | Linux / macOS / WSL | Windows cmd | Windows PowerShell |
|---|---|---|---|
| Run dir | `${TMPDIR:-/tmp}/harness-subagent/<run-id>` | `%TEMP%\harness-subagent\<id>` | `Join-Path $env:TEMP "harness-subagent\<id>"` |
| Spawn | `bash <skill>/scripts/spawn.sh …` | Git Bash on the script path | Git Bash **file argv** (below) — never a double-quoted `-lc` recipe |

`cwd` / `-C` / `--cwd` must be a path **that CLI understands** (WSL `/mnt/d/…` vs Windows `D:\…`). Do not mix Windows `claude.exe` into WSL.

Visual screenshots in `$RUN`: Claude and Cursor Agent need `--add-dir "$RUN"`. Grok: copy shots into `<project-dir>`. Codex: `-i` (script `--image`).

### Windows PowerShell (gotchas — do not skip)

PowerShell expands `$(…)`, `cat`, and `$RUN` **before** bash sees them. A double-quoted `& bash -lc "claude … $(cat $RUN/brief.md) > $RUN/last.md"` will look for `D:\c\Users\…`, write `last.md` to `/`, or pass an empty/flattened prompt. `system32\bash.exe` is WSL — it cannot see `%TEMP%` as `/c/…`.

1. Pin Git Bash: `"$env:ProgramFiles\Git\bin\bash.exe"` (confirm `Test-Path`; do not use WSL bash).
2. Write `brief.md` with the Write tool (UTF-8). Do **not** `Out-File` / `>` from PowerShell 5.1 (UTF-16LE + NULs).
3. Run the skill script **as arguments**, background the Shell call (`block_until_ms: 0` in Cursor):

```powershell
& "$env:ProgramFiles\Git\bin\bash.exe" -- "<skill-dir>\scripts\spawn.sh" --backend claude --mode review --project "D:/Code/app" --run "C:/Users/<you>/AppData/Local/Temp/harness-subagent/<id>"
```

4. List the run dir with Shell (`Get-ChildItem` / `ls`). Cursor **Glob is workspace-scoped** and will miss `%TEMP%`.
5. Two failed launches → stop. Answer from parent evidence. Mark the harness UNVERIFIED. Do not invent a third quoting recipe.

## Shared protocol

0. **Gate.** Name the one thing you cannot answer from this repo / this context. If you cannot name it, do not spawn. Naming, style, formatting, and “already tried” that already is the answer are not worth a run.
1. Write `brief.md` under the temp run dir (never inside the repo).
2. Spawn **`scripts/spawn.sh` in the background** (minutes; a foreground timeout kills spend). Do not copy or edit the script.
3. Wait until the **process exits**. Then read `$RUN/last.md`. Process still running + no `VERDICT` yet → not done. Process exited, `VERDICT` not on line 1 → completed but malformed; strip preamble and use the first `VERDICT` line. Do not relaunch a finished job because of a preamble.
4. Synthesize — never paste-only.

### Write the brief

Task description, not a data dump. **Do not paste diffs or file contents** — name paths and a **bounded** investigation. Exception: files unreachable from the working directory (screenshots under the temp run dir).

- Prefer named files/symbols over “explore the repo.”
- Diff: exact range, `git diff <A>..<B> -- <paths…>`.
- Visual/confirm: **forbid** `git log`, full-tree `git diff`, status dumps.
- Put parent evidence under **What was already tried**. Prefer “verify this” over “rediscover.” If you already ran `gh`/`curl` and Codex Review may lack network, put the output here and forbid re-running those commands.
- **Product override:** if the user locked a product decision, say so.

Five parts, in order:

1. **Objective** — one sentence naming the verdict / deliverable.
2. **Where to look** — paths, bounded commands, symbols; edit allowlist if Implement.
3. **What was already tried**
4. **What would change my mind** — settling evidence (Review) or acceptance gates (Implement).
5. **Return format** — paste the matching contract.

#### Review / Visual return contract

```
Return with VERDICT as the first line of the report (no preamble, no skill loading):
1. VERDICT — one line.
2. FINDINGS — ranked most serious first, each with file:line and a concrete failure case.
3. UNVERIFIED — what you could not check and what you would need to check it.
Be concrete and adversarial. If you think I am wrong, say so plainly.
Do not load using-superpowers, requesting-code-review, or other process skills — you are already the subagent.
Finish this report even if some checks failed; put gaps under UNVERIFIED.
```

Add for read-only Review: `Do not edit application files.`
Add for Visual: `Do not invent a browser stack. Reason from attached/named screenshots + code.`

#### Implement return contract

```
Return with VERDICT as the first line of the report (no preamble):
1. VERDICT — one line (done / blocked + why).
2. DONE — files touched and behaviour shipped.
3. GATES — exact commands run and pass/fail.
4. UNVERIFIED — what you could not prove.
Edit only paths named in the brief. Commit only if the brief says to. Never push.
Do not load using-superpowers as ceremony — execute the brief.
```

### Postures (harness-agnostic)

| Posture | Use for | Write? | Objective cue |
|---|---|---|---|
| **Adversarial** | plans, designs, hard-to-reverse calls | no | "Try to refute this plan. Assume it is flawed and find where." |
| **Critical** | a diff or change before merge | no | "Review this diff for correctness bugs. Rank by severity." |
| **Visual** | screenshot / live-UI defect confirm | no | "Confirm or refine these defects from screenshots + named sources." |
| **Unstuck** | a bug two fixes failed to kill | usually no | "Diagnose independently. Do not assume my diagnosis is right." |
| **Implement** | a bounded slice the user assigned to this harness | **yes** | "Ship the briefed deliverable. Edit only the named paths." |

Config `defaults.review` covers adversarial / critical / visual / unstuck. `defaults.implement` covers Implement. The skill still has no job→harness map.

### Report back — synthesis, never a paste

1. **What was asked** — one line.
2. **Harness verdict** — verbatim first `VERDICT` line (strip preamble).
3. **Where I agree and disagree** — grounded in this codebase.
4. **My recommendation.**

Cheap-check claims (`file:line` exists; tests actually fail). For Implement: files changed and gates claimed.

### Hang / progress hygiene

- Capture stderr to `$RUN/stderr.log` (the script does this). Codex transcripts are large — normal, not a hang.
- **Do not kill** because stderr is noisy or mentions `git`. Kill only if the process is dead **and** the report file is empty/stale, or there is no growth and no process activity for a long stretch.
- If a Visual run starts unbounded git: kill, rewrite the brief with the forbid line, relaunch **once**.

### Red flags

| Thought | Reality |
|---|---|
| "It found a bug, I'll just fix it" | Verify first. False positives are the main failure mode. |
| "I'll paste the response" | Synthesis is the deliverable. |
| "It disagrees, so I was wrong" | Decorrelated ≠ correct. |
| "I'll paste the diff to save it a step" | Named paths + bounded range. |
| "Harness must be read-only" | Review is; Implement may edit when the brief says so. |
| "This task wants Codex / Opus / Grok" | Utterance, then config, then ask. No task map. |
| "Three harnesses is more independent" | One, different family, unless asked for multiple. |
| "I'll nest the bash recipe in PowerShell -lc" | `scripts/spawn.sh` as file argv. |
| "Claude got an empty prompt — feed stdin from the parent" | Empty argv is quoting. Use the script (it already files stdin). |
| "I'll Glob the temp run dir" | Workspace-scoped. Shell `ls`. |
| "Config says Codex and I am Codex" | Skip same family; ask once if nothing else remains. |
| "Spawn failed — try another quoting trick" | Two failures then stop. |
