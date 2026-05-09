# .claude/ — AI Navigation Index
# Read this first. Skip files not relevant to your current task.
# Last updated: 2026-05-08

---

## ACTIVE CONFIG FILES

| File | What it does | Read when |
|------|-------------|-----------|
| [settings.json](settings.json) | Hooks: PreToolUse (rtk rewrite), SessionStart (supervisor), Stop (supervisor). Permission mode: bypassPermissions. | Debugging hook failures or adding new hooks |
| [settings.local.json](settings.local.json) | Allowed Bash/PowerShell command whitelist (legacy from autonomous builder phase). | Debugging permission denied errors only |

---

## COMMANDS (slash commands — invoke with `/command-name`)

Installed from: `anthropics/claude-code` (official repo)

| Command | Invoke | What it does | Use for this project? |
|---------|--------|-------------|----------------------|
| [commands/commit-push-pr.md](commands/commit-push-pr.md) | `/commit-push-pr` | Stages all changes, commits, pushes branch, opens GitHub PR automatically | ✅ Yes — use when pushing feature branches |
| [commands/dedupe.md](commands/dedupe.md) | `/dedupe` | Launches parallel agents to find duplicate GitHub issues and comments on them | ⚪ General — only if managing GitHub issues |
| [commands/triage-issue.md](commands/triage-issue.md) | `/triage-issue` | Analyzes a GitHub issue and applies labels (bug/enhancement/needs-repro etc.) | ⚪ General — only if managing GitHub issues |

---

## GLOBAL HOOKS (installed by caveman — live at C:\Users\U I S\.claude\hooks\)

These run automatically every session. **Do not read these files unless debugging caveman.**

| Hook file | When it fires | Effect |
|-----------|--------------|--------|
| caveman-activate.js | SessionStart | Loads caveman terse-response rules |
| caveman-mode-tracker.js | On mode change | Updates statusline badge (CAVEMAN / CAVEMAN:ULTRA) |
| caveman-stats.js | Session end | Logs token savings to session stats |
| caveman-config.js | Config read | Caveman intensity settings |
| caveman-statusline.ps1 | Statusline refresh | Shows [CAVEMAN] badge in status bar |

Activate caveman: `/caveman` | `/caveman ultra` | `/caveman lite`
Compress memory files: `/caveman:compress`
Terse commits: `/caveman-commit`

---

## WHAT IS NOT HERE (skip looking for these)

- No CLAUDE.md in this folder — project instructions are in memory files at `C:\Users\U I S\.claude\projects\d--EMI-APP\memory\`
- No MCP servers configured at project level — MCP is global only
- No skill definitions here — caveman skills are global at `C:\Users\U I S\.claude\plugins\`
- `settings.local.json` whitelist is stale (from Phase 1 autonomous builder, no longer active)

---

## QUICK REFERENCE — EMI APP PROJECT STACK

For AI models starting a new session, the relevant codebases are:

| Folder | Stack | Purpose |
|--------|-------|---------|
| `backend/` | Node.js + Express + PostgreSQL | API server (deployed on Render) |
| `admin-panel/` | React 18 + TypeScript + Vite + Tailwind | Admin dashboard |
| `dealer-app-v2/` | Flutter | Dealer mobile app |
| `user-app/` | Flutter (disguised) | End-user device lock app |
| `database/migrations/` | SQL | Schema migrations (current: 112) |

Memory index (load for context): `C:\Users\U I S\.claude\projects\d--EMI-APP\memory\MEMORY.md`
