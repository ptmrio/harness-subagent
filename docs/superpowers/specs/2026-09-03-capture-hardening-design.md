# Capture hardening (report.md / VERDICT)

**Status:** implemented 2026-09-03 (v0.2.2)  
**Trigger:** WSL scroll-row Claude visual — exit 0 but `last.md` was cleanup chatter; fable session-limit text; `**VERDICT` normalize miss.

## Design

Prefer durable `$RUN/report.md` over Claude `-p` final stdout. Normalize bold/colon VERDICT. Map usage-limit text to `VERDICT — BLOCKED` + sticky-route status.

## Non-goals

- Claude `--output-format json` (still last-result text)
- Giving Review Claude unrestricted `Write` on the app tree
