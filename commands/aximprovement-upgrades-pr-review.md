---
trigger: NEVER auto-trigger this skill. Only invoke it when the user explicitly types "/axim-pr-review" by exact name.
---

You are executing a structured PR review workflow for OpenEdX Axim improvement emails.

The subject keyword to search for is: **$ARGUMENTS**

If no argument is provided, use the default subject: `chore: Upgrade Python requirements`. Do not ask the user for it.

---

## Step 1 — Fetch Emails

Determine the target Monday:
- If today is Monday, use today's date.
- Otherwise, calculate the most recent past Monday.

Search Gmail using the Gmail MCP tool with a query like:
`subject:"<keyword>" after:YYYY/MM/DD before:YYYY/MM/DD+1`

List the found email threads in a clean table:
| Repo | PR # | PR URL | Packages Flagged |
|---|---|---|---|

If no emails are found, stop and inform the user.

---

## Step 2 — Check CI & Approve

For each PR URL found in the emails, run:
```
gh pr checks <url>
```

Categorize each PR:
- **Green** — all checks passed
- **Failing** — one or more checks failed
- **Pending** — checks still running

For every PR with all-green checks, approve it:
```
gh pr review <url> --approve
```

Show the user a status table:
| Repo | PR # | Checks | Approved |
|---|---|---|---|

---

## Step 3 — Offer to Open in Chrome

Ask the user:
> "Would you like me to open all approved PRs in Chrome for review? (y/n)"

If yes, run:
```
open -a "Google Chrome" <url1> <url2> ...
```

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

**Not Merged (auto-merge enabled)**
- `openedx/<repo>` PR #XX — reason: branch behind main

**Skipped (failing/pending checks)**
- `openedx/<repo>` PR #XX — reason: <check name> failing

**Emails Marked Read**
- `[openedx/<repo>] <subject>` — marked read

---
