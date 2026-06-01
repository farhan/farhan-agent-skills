---
trigger: NEVER auto-trigger this skill. Only invoke it when the user explicitly types "/axim-pr-review" by exact name.
---

You are executing a structured PR review workflow for OpenEdX Axim improvement emails.

The subject keyword to search for is: **$ARGUMENTS**

If no argument is provided, use the default subject: `chore: Upgrade Python requirements`. Do not ask the user for it.

---

## Step 1 — Fetch Emails

Determine the date range for the current week:
- If today is Monday, the range is **last Tuesday through today (inclusive)** — i.e. 6 days back to today.
- If today is not Monday, calculate the most recent past Monday and use **the Tuesday before that Monday through that Monday** as the range.

This ensures emails arriving any day of the week (Tue–Mon) are captured, not just those arriving on Monday.

Search Gmail using the Gmail MCP tool with a query like:
`subject:"<keyword>" after:YYYY/MM/DD before:YYYY/MM/DD+1`

where `after` is the Tuesday start date and `before` is the day after Monday (to make the range inclusive).

List the found email threads in a clean table:
| Repo | PR # | PR URL | Packages Flagged |
|---|---|---|---|

If no emails are found, stop and inform the user.

---

## Step 2 — Check CI, Auto-Fix Quality Failures & Approve

For each PR URL found in the emails, run:
```
gh pr checks <url>
```

Categorize each PR:
- **Green** — all checks passed, or the only failing check is `codecov/project`
- **Quality Fix Applied** — the only non-`codecov/project` failing check is a quality/mypy/lint check — auto-fix and push (see below)
- **Failing** — one or more checks failed (excluding `codecov/project` and quality checks that were auto-fixed)
- **Pending** — checks still running

> Note: `codecov/project` failures do not block merging — treat a PR as Green if it is the only failing check.

### Auto-fixing quality check failures (no user approval needed)

If a PR's only failing check is a quality check (e.g. `quality`, `mypy`, `pylint`, `lint`):

1. Fetch the failing job logs:
   ```
   gh run view <run_id> --job <job_id> --log --repo <owner>/<repo>
   ```
2. Clone or update the PR branch into the dedicated workspace at `/Users/farhan.khan/MyStuff/Development/Claude_Workspaces/axim-pr-fixes/`:
   ```
   WORKSPACE=/Users/farhan.khan/MyStuff/Development/Claude_Workspaces/axim-pr-fixes/<repo>

   if [ -d "$WORKSPACE" ]; then
     # Already cloned — fetch and switch to the PR branch
     cd "$WORKSPACE"
     git fetch origin <branch>
     git checkout <branch>
     git pull origin <branch>
   else
     # Fresh clone into the dedicated workspace
     mkdir -p /Users/farhan.khan/MyStuff/Development/Claude_Workspaces/axim-pr-fixes
     git clone --depth 1 --branch <branch> https://github.com/<owner>/<repo>.git "$WORKSPACE"
   fi
   ```
3. Create a virtual environment inside the cloned repo (if it doesn't already exist) and install dependencies:
   ```
   cd /Users/farhan.khan/MyStuff/Development/Claude_Workspaces/axim-pr-fixes/<repo>
   python3 -m venv .venv
   .venv/bin/pip install -r requirements/quality.txt
   .venv/bin/pip install -e .
   ```
4. Read the failing files identified in the logs and apply the minimal fix (e.g. use `cast()` from `typing`, add `# type: ignore[misc]`, annotate a variable type, fix a lint rule).
5. **Verify the fix locally before pushing** — run mypy and pylint on the changed files:
   ```
   .venv/bin/mypy --show-traceback 2>&1 | grep -E "error:|Found|Success"
   .venv/bin/pylint <changed_file1> <changed_file2> 2>&1; echo "exit: $?"
   ```
   Only proceed to push if mypy reports `Success` and pylint exits 0.
6. Commit and push directly to the PR branch — **no user confirmation required**:
   ```
   git commit -m "fix: resolve quality check failures from upgraded dependencies"
   git push origin <branch>
   ```
7. Mark the PR as **Quality Fix Applied** in the status table.

For every PR that is Green or had a Quality Fix Applied (including those where only `codecov/project` fails), approve it:
```
gh pr review <url> --approve
```

### Here's the full status table:

| Repo | PR # | Checks | Quality Fix | Approved |
|---|---|---|---|---|

---

## Step 3 — Offer to Open in Chrome

Ask the user:
> "Would you like me to open all PRs in Chrome for review? (y/n)"

If yes, run:
```
open -a "Google Chrome" <url1> <url2> ...
```

Open **all PRs** — both approved (green checks) and those with failing or pending checks.

Then say:
> "PRs are open in Chrome. Review them and come back when you're ready to merge."

**Stop here and wait for the user to respond.**

---

## Step 4 — Merge

When the user returns and is ready to merge, ask:
> "Ready to merge? I'll squash-merge all approved PRs with green checks. Proceed? (y/n)"

If yes, for each approved PR run:
```
gh pr merge <url> --squash --auto
```

After attempting all merges, verify each PR's state:
```
gh pr view <url> --json state,mergedAt
```

Build two lists:
- **Merged** — state is MERGED
- **Not merged** — still OPEN (note the reason: branch behind, required reviews, etc.)

---

## Step 5 — Mark Emails Read

For every PR that was successfully merged, find its corresponding email thread and mark it as read by removing the UNREAD label using the Gmail MCP tool.

---

## Step 6 — Summary

Present a final summary:

---
**PR Review Summary — <Date>**

**Merged ✓**
- `openedx/<repo>` PR #XX — merged at <time>

**Quality Fix Applied & Merged ✓**
- `openedx/<repo>` PR #XX — fixed: <description of fix> — merged at <time>

**Not Merged (auto-merge enabled)**
- `openedx/<repo>` PR #XX — reason: branch behind main

**Skipped (failing/pending checks)**
- `openedx/<repo>` PR #XX — reason: <check name> failing

**Emails Marked Read**
- `[openedx/<repo>] <subject>` — marked read

---
