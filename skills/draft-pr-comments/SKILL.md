---
name: draft-pr-comments
description: Draft PR review comments from review notes, a comment, or file content. Maps each point to exact file/line references in the PR diff, creates them as a pending GitHub review draft (inline and file-level), and puts unanchorable points as a numbered list with reasons in the review body. Everything goes into one pending review draft. Use when specified explicitly with "draft-pr-comments" or a direct reference to this skill.
version: 1.1.0
allowed-tools: Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh api:*), Bash(gh repo view:*), Bash(git log:*), Bash(git show:*), Read
---

# Draft PR Comments

> **About:** This skill takes review notes — pasted text, a file, or a prior comment — and turns them into a pending GitHub review draft. It maps each point to exact file/line references in the PR diff, posts inline and file-level comments via the GitHub API as a pending (not-yet-submitted) review, and puts unanchorable points as a numbered list with reasons in the review body. Everything lands in one pending review draft. All written content follows the `/content-guide` style rules.

Takes review notes (from a file, inline text, or prior comment) and maps them to specific locations in a PR diff.

**One output: a pending GitHub review draft** — everything goes into the review. Comments that can be anchored to a file and line are posted inline or file-level. Comments that cannot be anchored are included as a numbered list in the review body, each with a brief reason why it could not be placed inline. The review is not submitted until you choose to.

---

## Step 1: Gather Required Inputs

### PR URL / Number

If the user has not provided a PR URL or number, ask:

> "What is the PR URL or number? (e.g. https://github.com/owner/repo/pull/123 or just `123`)"

Wait for the answer before proceeding.

Derive owner/repo from the URL or:

```bash
gh repo view --json nameWithOwner --jq '.nameWithOwner'
```

### Review Content

If the user has not provided any review content (inline text, a file path, or a reference to a comment), ask:

> "What content should I turn into PR comments? You can paste the notes directly, give me a file path, or describe what you want commented."

Accepted forms:
- **Inline text** — pasted directly in the message
- **File path** — read it with the Read tool
- **GitHub comment/issue URL** — fetch with `gh api`

Do not proceed until review content is available.

---

## Step 2: Fetch PR Metadata and Diff

```bash
gh pr view <PR_NUMBER> --repo <OWNER/REPO> --json title,body,headRefName,baseRefName,headRefOid
gh pr diff <PR_NUMBER> --repo <OWNER/REPO>
```

Parse the diff to build a lookup map of `{ file_path → set_of_diff_line_numbers }` (right-side, 1-based). This anchors every review point to a real location in the diff.

---

## Step 3: Analyse Review Content and Classify Each Point

Read through the full review content. For each distinct point or concern, determine its reference type:

| Type | When to use |
|------|-------------|
| **Inline** | A specific line or small range is identifiable in the diff |
| **File-level** | The concern applies to a whole file; no single line stands out |
| **General** | No file or line can be determined (architecture, missing tests, etc.) |

Matching strategy (try in order):
1. Review note explicitly names a file and/or line → use it directly, confirm it's in the diff.
2. Review note names a symbol or pattern → grep the diff for it:
   ```bash
   gh pr diff <PR_NUMBER> --repo <OWNER/REPO> | grep -n "<pattern>"
   ```
3. Review note describes a cross-file concern → identify all relevant files → file-level per file.
4. Nothing matches → mark as **general**.

If a note maps to multiple locations, create a separate comment for each.

**Comment body guidelines** (follow `/content-guide` rules):
- One concern per comment — do not bundle multiple issues.
- Reference the specific symbol, variable, or pattern when relevant.
- Use GitHub Markdown (code spans, fenced blocks) as appropriate.
- No filler phrases ("Great job", "Just a minor nit", etc.).
- Use the least possible wording — keep sentences short and complete, no padding.
- Hyperlink any referenced tools, standards, docs, or external concepts inline.

---

## Step 4: Create the Pending GitHub Review Draft

Use a single API call to create a pending review with all inline and file-level comments attached. A pending review is not visible to others until you submit it — you control when to publish.

### 4a. Fetch the head commit SHA

```bash
HEAD_SHA=$(gh pr view <PR_NUMBER> --repo <OWNER/REPO> --json headRefOid --jq '.headRefOid')
```

### 4b. Build the review body for general comments

Before making the API call, collect all **general** points (those that could not be anchored to any file or line). Format them as a numbered list to use as the review `body`:

```
1. <Point summary> — could not be anchored: <brief reason, e.g. "no file changed in this diff relates to this concern", "architectural question with no single code location">
2. <Point summary> — could not be anchored: <reason>
```

If there are no general points, use an empty string for `body`.

### 4c. Create the pending review with all inline/file-level comments

```bash
gh api repos/<OWNER>/<REPO>/pulls/<PR_NUMBER>/reviews \
  --method POST \
  -f commit_id="$HEAD_SHA" \
  -f event="PENDING" \
  -f body="<numbered list of general comments, or empty string>" \
  -f "comments[][path]=<file>" \
  -F "comments[][line]=<line>" \
  -f "comments[][side]=RIGHT" \
  -f "comments[][body]=<comment body>"
```

Repeat the `comments[]` fields for each inline comment. For **file-level** comments, omit `line` and `side` and add `-f "comments[][subject_type]=file"`.

> **Note:** GitHub's reviews API batches all inline comments into one review object — this is the correct way to create multiple inline comments at once. Do not create individual `/pulls/comments` entries; they would appear as orphaned "single comments" outside a review.

### 4d. Verify the review was created

```bash
gh api repos/<OWNER>/<REPO>/pulls/<PR_NUMBER>/reviews --jq '[.[] | select(.state=="PENDING")] | last | {id, state, submitted_at}'
```

Print a confirmation: `Pending review created (ID: <id>) with <N> inline/file-level comments and <M> general comments in the review body.`

---

## Step 5: Final Summary

Print a summary of everything done:

```
Pending review draft created on <OWNER/REPO>#<PR_NUMBER>

Inline / file-level comments added to pending review:
  #  | Type        | Location                    | Preview
  ---|-------------|-----------------------------|-------------------------------------
  1  | inline      | src/foo/bar.py:42           | Consider using a set here for O(1)…
  2  | file-level  | src/foo/utils.py            | This module has no test coverage…

General comments (included in review body as numbered list):
  3  | general     | (no file/line match)        | The PR is missing a migration for…

Next step: go to the PR on GitHub, review your pending comments and review body, edit if needed, then submit the review.
```

---

## Notes

- **Do not submit the review** — only create it as pending. The user submits it themselves.
- Inline comments must target lines present in the diff (added `+` or context lines). If a referenced line is not in the diff, downgrade to file-level or general.
- GitHub's right-side line numbers in the diff are what the API expects for `line`. Parse them from `gh pr diff` output.
- If a pending review already exists on this PR (from a previous run of this skill), add comments to it rather than creating a new one by using `PATCH /repos/<OWNER>/<REPO>/pulls/<PR_NUMBER>/reviews/<review_id>`.
- Use `gh api` for all GitHub interactions — do not use web fetch.
