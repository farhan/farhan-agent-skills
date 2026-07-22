---
name: move-pr-to-review
description: Move one or more GitHub PRs into code review — assign yourself, add them to the "Aximprovements Team" project, set project Status to "In review", and flip any draft PR to ready-for-review. Use when asked to "move PR(s) to review/code review", "put PRs up for review", or given a list of PR URLs to assign and add to the Aximprovements board.
version: 1.0.0
argument-hint: [pr-url-or-number ...]
allowed-tools: Bash(gh api:*), Bash(gh pr view:*), Bash(gh pr edit:*), Bash(gh pr ready:*), Bash(gh project list:*), Bash(gh project field-list:*), Bash(gh project item-add:*), Bash(gh project item-edit:*)
---

# Move PR to Review

Takes a list of PRs and, for each one:

1. Assigns you (the authenticated GitHub user) as assignee.
2. Adds the PR to the **Aximprovements Team** org project (openedx, project #55).
3. Sets the project **Status** field to **👀 In review** (the code-review column).
4. Converts the PR from **draft** to **ready for review** if it is a draft.

> **Note on "Code review":** The Aximprovements Team board has no column literally named "Code review". Its review stage is **👀 In review** — use that. If the user insists on a differently-named column, re-list the Status options (Step 2) and pick the match.

---

## Step 1: Gather inputs

Collect the list of PRs the user gave (URLs or `repo#number`). If none were provided, ask:
> "Which PR(s) should I move to review? Paste the URLs or numbers."

Resolve the authenticated username once — this is the assignee:

```bash
gh api user --jq .login
```

For each PR, capture its current state (owner/repo, number, draft flag, existing assignees). Query PRs **one at a time** — a shell loop that re-parses `owner repo number` into positional args is error-prone; just run one command per PR:

```bash
gh pr view <number> --repo <owner>/<repo> --json number,title,isDraft,assignees,url
```

Note which PRs are already assigned to you (skip re-assigning) and which are drafts (need Step 4).

## Step 2: Locate the project and its Status field (once)

Find the Aximprovements Team project number and node id:

```bash
gh project list --owner openedx --format json --limit 100 \
  | jq -r '.projects[] | select(.title|test("Axim";"i")) | "\(.number)\t\(.id)\t\(.title)"'
```

Expected: project **#55**, id `PVT_kwDOAmUX2M4AUNn1`, title "Aximprovements Team". (IDs are stable but always re-fetch rather than hardcoding, in case the project is recreated.)

Get the **Status** field id and its option ids:

```bash
gh project field-list 55 --owner openedx --format json \
  | jq -r '.fields[] | select(.name=="Status") | {id, name, options}'
```

Record:
- Status field id (e.g. `PVTSSF_lADOAmUX2M4AUNn1zgM6cSw`)
- The **"👀 In review"** option id (e.g. `2901b076`)

## Step 3: Assign, add to project, set status

**Assign yourself** to each PR that isn't already assigned to you:

```bash
gh pr edit <number> --repo <owner>/<repo> --add-assignee <your-login>
```

**Add each PR to the project** — capture the returned item id (needed for the next command):

```bash
gh project item-add 55 --owner openedx --url <pr-url> --format json | jq -r '.id'
```

**Set Status to "In review"** for each returned item id:

```bash
gh project item-edit \
  --project-id PVT_kwDOAmUX2M4AUNn1 \
  --id <item-id> \
  --field-id <status-field-id> \
  --single-select-option-id <in-review-option-id> \
  --format json | jq -r '.id + " -> In review"'
```

You can iterate the item ids in a shell `for` loop since they're plain tokens with no re-parsing.

## Step 4: Flip drafts to ready

For any PR that was `isDraft: true` in Step 1:

```bash
gh pr ready <number> --repo <owner>/<repo>
```

Skip this for PRs that were already open (not draft).

## Step 5: Report

Print a summary table: PR link | assignee (added / already set) | added to project | status | draft→ready (yes / not needed). Call out anything skipped and why (e.g. "already assigned", "was not a draft").
