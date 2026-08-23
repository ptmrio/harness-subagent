---
name: harness-subagent
description: >
  Use when the user asks to dispatch another coding-agent CLI as a one-shot
  subagent — Claude Code, Codex, Grok Build, Cursor Agent, Gemini CLI, OpenCode,
  or Droid — or to ask Claude, ask GPT, ask Codex, ask Grok, get a second
  opinion, or pressure-test a plan/diff from a different harness.
license: MIT
compatibility: Requires another coding-agent CLI on PATH (claude, codex, grok, and/or cursor-agent). Windows, WSL, Linux, macOS.
metadata:
  author: ptmrio
  version: "0.1.0"
user-invocable: true
argument-hint: "[claude|codex|grok|cursor|gemini|opencode|droid] [review|implement|…]"
allowed-tools: Bash Read
---

# Harness Subagent

Dispatch **another coding-agent harness** as a one-shot subagent, then synthesize.

**Core principle: the harness is a subagent, not an oracle.** A model reviewing its own work reproduces its own blind spots. That worth is destroyed if you forward the answer without judging it.

Do **not** pick a harness because of a task stereotype (UI vs review vs visual). The user names the harness, or you ask once. Same protocol for every backend.

Default to **read-only Review**. Allow writes only when the user (or an approved plan) asks for Implement.

Extra CLIs (Cursor Agent, Gemini, OpenCode, Droid): Read `references/more-clis.md` before spawning.

## Pick a backend

| User says | Binary (PATH) | Default model (latest series) | Default thinking |
|---|---|---|---|
| Claude, Opus, Fable, ask-claude | `claude` | `--model opus` (alias = current Opus). Also `fable`, `sonnet`, `haiku` | `--effort xhigh` |
| GPT, Codex, Sol, Terra, Luna, ask-gpt | `codex` | `-m gpt-5.6-sol` | `-c model_reasoning_effort=xhigh` |
| Grok, ask-grok | `grok` | `-m grok-4.6` | `--effort xhigh` |
| Unspecified | Ask once. Do not default. | — | — |

If the user pins a model id, use it. Otherwise use the series default in the table.

**List what this machine actually has:**

```bash
claude --help          # --model aliases: opus, fable, sonnet, haiku (no catalog subcommand)
codex debug models --bundled
grok models
cursor-agent --list-models   # see references/more-clis.md
```

Windows PowerShell: `Get-Command claude,codex,grok`. Do **not** hardcode `~/.local/bin/…`.

**`agent` on PATH is often Grok Build, not Cursor.** Cursor’s CLI is `cursor-agent`.

## OS, temp, stdin

Parent agents often pipe stdin. Treat that as hostile.

| | Linux / macOS / WSL | Windows cmd | Windows PowerShell |
|---|---|---|---|
| Run dir | `${TMPDIR:-/tmp}/harness-subagent/<run-id>` | `%TEMP%\harness-subagent\<id>` | `Join-Path $env:TEMP "harness-subagent\<id>"` |
| Close stdin | `< /dev/null` | `< NUL` | wrap in `cmd /c "… < NUL"` or bash |
| Codex prompt file | `codex exec … - < brief.md` | same after `cd` to run dir | Git Bash / WSL, or `cmd /c` after `cd` (see Codex) |

The spawn blocks below are **bash** (Git Bash, WSL, macOS, Linux). Native PowerShell cannot do `< file` or `$(cat …)`. Prefer Git Bash or WSL on Windows.

`cwd` / `-C` / `--cwd` must be a path **that CLI understands** (WSL `/mnt/d/…` vs Windows `D:\…`). Do not mix Windows `claude.exe` into WSL or assume WSL `~/.local/bin` exists on native Windows.

Visual screenshots in `$RUN`: Claude and Cursor Agent need `--add-dir "$RUN"` (workspace-scoped Read otherwise misses `/tmp` / `%TEMP%`). Grok has no extra-dir flag — copy shots into `<project-dir>` (or name absolute paths you have verified it can Read). Codex uses `-i`.

## Shared protocol

1. Write `brief.md` under the temp run dir (never inside the repo).
2. Spawn in the **background** (minutes; a foreground timeout kills spend).
3. Capture report + stderr in that run dir.
4. Synthesize — never paste-only.

### Write the brief

Task description, not a data dump. **Do not paste diffs or file contents** — name paths and a **bounded** investigation. Exception: files unreachable from the working directory (screenshots under the temp run dir).

- Prefer named files/symbols over “explore the repo.”
- Diff: exact range, `git diff <A>..<B> -- <paths…>`.
- Visual/confirm: **forbid** `git log`, full-tree `git diff`, status dumps.
- Put parent evidence under **What was already tried**. Prefer “verify this” over “rediscover.”
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

Visual: parent provides image paths (any capture method). Copy images into the temp run dir. Codex: `-i` per image before `-o`. Claude / Cursor Agent: `--add-dir "$RUN"` plus named paths. Grok: copy shots into `<project-dir>` (no `--add-dir`). Parent still synthesizes.

### Report back — synthesis, never a paste

1. **What was asked** — one line.
2. **Harness verdict** — verbatim first `VERDICT` line (strip preamble).
3. **Where I agree and disagree** — grounded in this codebase.
4. **My recommendation.**

Cheap-check claims (`file:line` exists; tests actually fail). For Implement: files changed and gates claimed.

### Hang / progress hygiene

- Capture stderr to `stderr.log` (not `/dev/null`). Codex transcripts are large — normal, not a hang.
- **Do not kill** because stderr is noisy or mentions `git`. Kill only if the process is dead **and** the report file is empty/stale, or there is no growth and no process activity for a long stretch.
- If a Visual run starts unbounded git: kill, rewrite the brief with the forbid line, relaunch.

### Red flags

| Thought | Reality |
|---|---|
| "It found a bug, I'll just fix it" | Verify first. False positives are the main failure mode. |
| "I'll paste the response" | Synthesis is the deliverable. |
| "It disagrees, so I was wrong" | Decorrelated ≠ correct. |
| "I'll paste the diff to save it a step" | Named paths + bounded range. |
| "Harness must be read-only" | Review is; Implement may edit when the brief says so. |
| "This task wants Codex / Opus / Grok" | User picks the harness. No task map. |

### Not worth a run

Naming, style, formatting, or anything already answerable from context.

---

## Backend: Claude Code

Official headless: `claude -p` / `--print`. Do **not** default `--bare` (it skips subscription login; needs `ANTHROPIC_API_KEY`).

### Review

```bash
cd "<project-dir>" && claude -p --permission-mode plan \
  --tools "Bash,Read,Glob,Grep" \
  --output-format text --model opus --effort xhigh \
  --no-session-persistence --add-dir "$RUN" \
  "$(cat "$RUN/brief.md")" \
  < /dev/null > "$RUN/last.md" \
  2> "$RUN/stderr.log"
```

### Implement

```bash
cd "<project-dir>" && claude -p --permission-mode acceptEdits \
  --tools "Bash,Read,Edit,Write,Glob,Grep" \
  --output-format text --model opus --effort xhigh \
  --no-session-persistence --add-dir "$RUN" \
  "$(cat "$RUN/brief.md")" \
  < /dev/null > "$RUN/last.md" \
  2> "$RUN/stderr.log"
```

Windows: same flags under Git Bash/WSL; close stdin with `< NUL` in cmd. Keep the brief small enough for argv (`"$(cat brief)"` hits ARG_MAX).

| Part | Why |
|---|---|
| `-p` | Headless one-shot. Without it you get the TUI. |
| `--permission-mode plan` | Official: explore, no source edits. |
| `--permission-mode acceptEdits` | Unattended Implement; still not full bypass. |
| `--tools` | Explicit surface. Review omits Edit/Write. |
| `--model opus` | Current Opus series alias. `fable` / `sonnet` / `haiku` or a full id if the user pins. |
| `--effort xhigh` | `low` `medium` `high` `xhigh` `max`. |
| `--no-session-persistence` | One-shot; do not clutter resume history. |
| `--add-dir "$RUN"` | Lets Read see the brief/screenshots outside the project tree. |
| `< /dev/null` or `< NUL` | Parent shells pipe stdin; Claude may hang on a non-EOF pipe. |

Optional: `--append-system-prompt 'First line of your final report must be: VERDICT — …'`.
Images: name paths in the brief.

If `last.md` is `You've hit your session limit`, do **not** relaunch Claude immediately — switch backend or wait for the stated reset.

---

## Backend: Codex (GPT)

Official: `codex exec`. Prompt from file with `-`. Progress on stderr; final message on stdout. Pin `--sandbox`; user `config.toml` can change approval.

### Review / Visual

```bash
codex exec --ephemeral --sandbox read-only -m gpt-5.6-sol \
  -c model_reasoning_effort=xhigh --skip-git-repo-check \
  -C "<project-dir>" \
  -o "$RUN/last.md" \
  - < "$RUN/brief.md"
```

Visual: add one `-i "$RUN/<shot>"` per image **before** `-o`.

### Implement

```bash
codex exec --ephemeral --sandbox workspace-write -m gpt-5.6-sol \
  -c model_reasoning_effort=xhigh --skip-git-repo-check \
  -C "<project-dir>" \
  -o "$RUN/last.md" \
  - < "$RUN/brief.md"
```

Do **not** use `--full-auto` (deprecated) or `--dangerously-bypass-approvals-and-sandbox` for ordinary Implement.

Windows cmd: `cd` to the run dir first so `brief.md` / `last.md` are relative and unquoted. Do **not** nest `"` around `-C` inside `cmd /c "…"` — that terminates the string. Paths with spaces: use Git Bash.

```bat
cd /d %TEMP%\harness-subagent\<id>
cmd /c "codex exec --ephemeral --sandbox read-only -m gpt-5.6-sol -c model_reasoning_effort=xhigh --skip-git-repo-check -C C:\path\to\project -o last.md - < brief.md"
```

| Part | Why |
|---|---|
| `--sandbox read-only` | Review — writes refused. |
| `--sandbox workspace-write` | Implement — edit inside `-C` only. |
| `-m gpt-5.6-sol` | Current bundled default series. List: `codex debug models --bundled`. |
| `-c model_reasoning_effort=xhigh` | `minimal` `low` `medium` `high` `xhigh`. |
| `--skip-git-repo-check` | Always in this protocol (temp dirs, odd checkouts). |
| `--ephemeral` | No session files. |
| `-o` | Last message to file (also printed on stdout). |
| `- < brief.md` | Official prompt-from-file. Do **not** also pass an argv prompt (duplicate + stdin races). |

`--ignore-user-config` when you must not inherit a drifted `~/.codex/config.toml`. Auth still uses `CODEX_HOME`.

### Codex `review` subcommand

Ranked `P1`–`P3` on a diff, no custom rubric:

```bash
codex exec -C "<project-dir>" --sandbox read-only -m gpt-5.6-sol \
  -c model_reasoning_effort=xhigh --ephemeral \
  review --uncommitted
```

Shared flags go **before** `review`. Scope: `--uncommitted`, `--base <branch>`, `--commit <sha>`. A scope flag and a custom prompt are mutually exclusive — for instructed review, use plain `codex exec` and a bounded diff in the brief.

---

## Backend: Grok Build

Official headless: `-p` / `--prompt-file`. **Does not** treat piped stdin as the prompt. Still close stdin so a parent pipe cannot hang the process.

### Review

```bash
grok --permission-mode plan -m grok-4.6 --effort xhigh \
  --cwd "<project-dir>" \
  --prompt-file "$RUN/brief.md" \
  --output-format plain \
  < /dev/null > "$RUN/last.md" \
  2> "$RUN/stderr.log"
```

### Implement

```bash
grok --permission-mode acceptEdits -m grok-4.6 --effort xhigh \
  --cwd "<project-dir>" \
  --prompt-file "$RUN/brief.md" \
  --output-format plain \
  < /dev/null > "$RUN/last.md" \
  2> "$RUN/stderr.log"
```

Strict CI allowlist (official enterprise pattern) instead of `plan`:

```bash
grok --permission-mode dontAsk --allow Read --allow Grep --allow Glob \
  --deny 'Bash(rm -rf *)' \
  --prompt-file "$RUN/brief.md" --output-format plain < /dev/null
```

| Part | Why |
|---|---|
| `--prompt-file` | Official file prompt; implies headless. |
| `--permission-mode plan` | No source edits. |
| `--permission-mode acceptEdits` | Unattended edits. |
| `dontAsk` + `--allow` | Headless deny-by-default; `auto` is a classifier and can block. |
| `-m grok-4.6` | CLI default. List: `grok models`. |
| `--effort xhigh` | `none` `minimal` `low` `medium` `high` `xhigh` `max`. |
| `--output-format plain` | Final text. |
| `< /dev/null` | Hang insurance. |

Grok often narrates before the verdict and loads process skills — the brief’s “first line = VERDICT” and “do not load process skills” lines are **required**.

Do **not** use `--always-approve` / `bypassPermissions` for routine work. Auth: `grok login` or `XAI_API_KEY`.

---

If a local skills dir still has `ask-claude` / `ask-gpt` / `ask-grok` stubs, follow **this** skill with the matching backend instead.
