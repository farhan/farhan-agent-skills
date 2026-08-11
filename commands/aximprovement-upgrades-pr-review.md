---
trigger: NEVER auto-trigger this skill. Only invoke it when the user explicitly types "/axim-pr-review" by exact name.
---

You are executing a structured PR review workflow for OpenEdX Axim improvement emails.

The subject keyword to search for is: **$ARGUMENTS**

If no argument is provided, use the default subject: `chore: Upgrade Python requirements`. Do not ask the user for it.

---

## Step 1 — Fetch Emails

Determine the date range for the current week:
- If today is **Monday**, the range is **last Tuesday through today (inclusive)** — i.e. 6 days back to today. This captures the full Tue–Mon cycle.
- If today is **not Monday**, use **the most recent Tuesday through today (inclusive)**. "Most recent Tuesday" means: go back from today until you hit a Tuesday (if today is Tuesday, that's today itself).

Examples:
- Monday July 28 → last Tuesday = July 22 → range: July 22–July 28
- Sunday July 27 → most recent Tuesday = July 22 → range: July 22–July 27
- Friday July 25 → most recent Tuesday = July 22 → range: July 22–July 25
- Tuesday July 22 → today is Tuesday → range: July 22–July 22

Search Gmail using the Gmail MCP tool with a query like:
`subject:"<keyword>" after:YYYY/MM/DD before:YYYY/MM/DD+1`

where `after` is the Tuesday start date and `before` is the day after today (to make the range inclusive).

List the found email threads in a clean table. **Always start with a serial-number column (`S.No`) as the first column, and include a `Major Upgrades` column** listing any packages flagged for manual review / major version bumps (the bot marks these `[MAJOR]`; write `—` if none):
| S.No | Repo | PR # | PR URL | Packages Flagged | Major Upgrades |
|---|---|---|---|---|---|

If no emails are found, stop and inform the user.

---

## Step 2 — Check CI & Approve Green PRs

For each PR URL found in the emails, run **in parallel**:
```
gh pr checks <url>
```

Categorize each PR:
- **Green** — all checks passed, or the only failing check is `codecov/project`
- **Failing** — one or more checks failed (excluding `codecov/project`)
- **Pending** — checks still running

> Note: `codecov/project` failures do not block merging — treat a PR as Green if it is the only failing check.

For every **Green** PR, immediately approve it (no user confirmation needed):
```
gh pr review <url> --approve
```

### Status table:

**Always start with a serial-number column (`S.No`) as the first column, and include a `Major Upgrades` column** (same `[MAJOR]` packages as Step 1; `—` if none):

| S.No | Repo | PR # | Checks | Approved | Major Upgrades |
|---|---|---|---|---|---|

---

## Step 3 — Handle Failing PRs

### 3a — Re-run first for known-flaky repos

For the following repos, **always try re-running the failing job before spawning a fix agent**:
- `openedx/xblocks-core` — JS tests are known to be flaky; a re-run usually fixes them.

To re-run a failing job:
```
gh run rerun <run_id> --job <job_id> --repo <owner>/<repo>
```

After re-running, note in the status table that a re-run was triggered and move on — do **not** spawn a fix agent yet. If the re-run also fails, then treat it as a genuine failure and spawn a fix agent.

### 3b — Spawn Parallel Fix Agents for All Other Failing PRs

For every other PR categorised as **Failing** (and for re-run failures from 3a), immediately spawn a background Agent — **no user approval needed, no questions asked**. Launch all agents in a single message so they run in parallel.

Each agent receives this prompt (fill in the specifics per PR):

---
```
You are fixing CI failures on an OpenEdX upgrade PR. Diagnose, fix, verify locally, commit, and push — no user confirmation needed at any step.

PR: <url>
Repo: <owner>/<repo>
Failing checks (with job URLs):
  - <check name>: <job url>
  ...

Workspace: /Users/farhan.khan/MyStuff/Development/Claude_Workspaces/axim-pr-fixes/

## Instructions

### 1. Get PR branch
  gh pr view <url> --json headRefName,headRepository

### 2. Clone or update workspace
  WORKSPACE=/Users/farhan.khan/MyStuff/Development/Claude_Workspaces/axim-pr-fixes/<repo>
  if [ -d "$WORKSPACE" ]; then
    cd "$WORKSPACE" && git fetch origin <branch> && git checkout <branch> && git pull origin <branch>
  else
    mkdir -p /Users/farhan.khan/MyStuff/Development/Claude_Workspaces/axim-pr-fixes
    git clone --depth 1 --branch <branch> https://github.com/<owner>/<repo>.git "$WORKSPACE"
  fi

### 3. Fetch failing CI logs for every failing job
  gh run view <run_id> --job <job_id> --log --repo <owner>/<repo> 2>&1 | tail -100

### 4. Set up environment and reproduce the failure
  Check tox.ini / .github/workflows/ for the exact test/quality commands.
  Create a venv if needed and install deps from requirements/test.txt or
  requirements/quality.txt or via uv sync --group test.

### 5. Fix the issue
  Apply the minimal targeted fix. Do NOT rewrite tests or add broad changes.

### 6. Verify locally — all failing checks must pass before pushing.

### 7. Commit and push (no confirmation needed)
  git add <changed files>
  git commit -m "fix: resolve CI failures from upgraded dependencies"
  git push origin <branch>

### 8. Report back
  Short summary: what was failing, what you changed, local tests pass, push succeeded.
```
---

After spawning all agents, continue immediately to Step 4 — do NOT wait for agents to finish.

---

## Step 4 — Upgrades Summary, then Ask to Open PRs in Chrome

**Before asking anything**, present a short prose **Upgrades Summary** right after the Step 2 status table, so the user can review the notable version bumps first. Summarize the major upgrades across all PRs: group each `[MAJOR]` (and `[DOWNGRADE]`) package by version change, list which repos it affects, and call out which bump is most likely to have runtime implications downstream. Example:

> **Upgrades Summary:** The major bumps this week are **setuptools 82 → 83** (in 8 repos), **lazy 1.6 → 2.0** (XBlock and xblock-sdk), and a **pandas 3.0.4 → 3.0.3 downgrade** in xapi-db-load — all passed CI, but the lazy 2.0 jump is the one most likely to have runtime implications downstream.

Then ask the user:
> "If you have read the upgrades summary, would you like me to open all PRs in Chrome for review? (y/n)"

**Stop here and wait for the user to respond.**

If yes, open **all PRs** (green + failing) in a **new** Chrome window:
```
open -na "Google Chrome" --args --new-window <url1> <url2> ...
```

Immediately after opening, ask:
> "Do you want me to merge all the PRs that have green checks and are approved?"

**Stop here and wait for the user to respond.**

---

## Step 5 — Merge

If the user says yes, for each approved PR with green checks run:
```
gh pr merge <url> --squash --auto
```

If a repo does not support squash merges, fall back to `--merge --auto`.

After attempting all merges, verify each PR's state:
```
gh pr view <url> --json state,mergedAt
```

Build two lists:
- **Merged** — state is MERGED
- **Not merged** — still OPEN (note the reason: branch behind, required reviews, etc.)

---

## Step 6 — Mark Emails Read

For every PR that was successfully merged, find its corresponding email thread and mark it as read by removing the UNREAD label using the Gmail MCP tool.

---

## Step 7 — Summary

Present a final summary:

---
**PR Review Summary — <Date>**

**Merged ✓**
- `openedx/<repo>` PR #XX — merged at <time>

**Fix Applied & Merged ✓**
- `openedx/<repo>` PR #XX — fixed: <description of fix> — merged at <time>

**Not Merged (auto-merge enabled)**
- `openedx/<repo>` PR #XX — reason: branch behind main

**Skipped (failing/pending checks)**
- `openedx/<repo>` PR #XX — reason: <check name> failing

**Emails Marked Read**
- `[openedx/<repo>] <subject>` — marked read

---
