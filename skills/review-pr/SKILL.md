---
name: review-pr
description: This skill should be used when the user says "review PR", "review pull request", "start PR review", "I'm reviewing a PR", "let's review a PR", or starts a pull request review session. Gathers GitHub issue context, PR details, iterates through commits, and performs a thorough multi-dimensional code review.
version: 1.0.0
allowed-tools: Bash(gh issue view:*), Bash(gh issue list:*), Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh pr list:*), Bash(gh pr checks:*), Bash(gh api:*), Bash(git log:*), Bash(git diff:*), Bash(git show:*)
---

# PR Review Skill

A comprehensive pull request review workflow that combines GitHub issue context, full commit history analysis, and multi-dimensional code quality checks.

## Phase 1: Gather Context

### 1a. GitHub Issue (Story/Ticket context)

If the user has not provided a GitHub issue number or URL, ask:
> "What is the GitHub issue number or URL for this PR? (e.g. #123 or https://github.com/owner/repo/issues/123)"

Once provided, fetch the issue details:
```bash
gh issue view <issue-number> --repo <owner/repo>
```

Extract and note:
- Issue title and description (treat as the "story" / acceptance criteria)
- Labels, milestone, assignees
- Any linked PRs mentioned in the issue body
- Acceptance criteria or definition of done (look for checklists)

### 1b. PR Details

If the user has not provided a PR number or URL, ask:
> "What is the PR number or URL? (e.g. #456 or https://github.com/owner/repo/pull/456)"

Once provided, run the following to understand the PR fully:

```bash
# View PR metadata
gh pr view <pr-number> --repo <owner/repo>

# Get the base branch and head branch
gh pr view <pr-number> --repo <owner/repo> --json baseRefName,headRefName,commits,additions,deletions,changedFiles

# List all commits in the PR
gh pr view <pr-number> --repo <owner/repo> --json commits --jq '.commits[] | "\(.oid[0:8]) \(.messageHeadline)"'

# Get the full diff
gh pr diff <pr-number> --repo <owner/repo>
```

Note:
- Base branch (target branch the PR merges into)
- Head branch (the PR branch)
- Number of commits, files changed, additions/deletions
- Iterate through each commit and summarize its purpose

## Phase 2: Pre-Review Eligibility Check

Before proceeding with a full review, quickly verify:
- Is the PR still open (not closed or merged)?
- Is it a draft PR? (If so, note it but still review unless the user says otherwise)
- Is it an automated/bot PR (e.g. Dependabot, Renovate)? If so, apply a lighter review focused on dependency safety.

## Phase 3: Multi-Dimensional Code Review

Launch the following review dimensions in parallel (use Sonnet agents where possible):

### Dimension 1 — Story/Issue Alignment
Compare the PR changes against the GitHub issue requirements:
- Does the implementation satisfy the acceptance criteria from the issue?
- Are there any requirements from the issue that are NOT addressed in the PR?
- Are there any changes in the PR that go beyond the issue scope (scope creep)?
- Flag any "unwanted changes" — modifications unrelated to the issue

### Dimension 2 — Bug & Logic Review
Read the full diff carefully:
- Logic errors or off-by-one mistakes
- Incorrect conditionals or edge cases not handled
- Null/undefined/None dereferences
- Race conditions or concurrency issues
- Incorrect error handling or silent failures
- Wrong return values or missing returns

### Dimension 3 — Security Review
Check for OWASP Top 10 and common security issues:
- SQL injection, XSS, CSRF vulnerabilities
- Hardcoded secrets, tokens, or credentials
- Insecure use of eval, exec, or shell commands
- Missing authentication/authorization checks
- Sensitive data exposure in logs or responses
- Insecure deserialization

### Dimension 4 — Code Quality & Conventions
Check adherence to the project's CLAUDE.md and coding standards:
- Style, naming conventions, and formatting
- Dead code, commented-out code, debug statements left in
- Overly complex code that could be simplified
- Missing or incorrect tests for new functionality
- Documentation/comments accuracy

### Dimension 5 — Commit History Quality
Iterate through each commit in the PR:
- Are commit messages meaningful and descriptive?
- Does each commit represent a logical unit of work?
- Are there "WIP", "fixup", "temp" commits that should be squashed?
- Check `git show <commit-sha>` for any commits that seem out of place

### Dimension 6 — Unwanted/Accidental Changes
Look for changes that shouldn't be in this PR:
- Whitespace-only changes in unrelated files
- Unrelated refactoring mixed with feature changes
- Accidentally committed debug files, `.env` files, build artifacts
- Merge conflict markers left in code (`<<<<<<<`, `=======`, `>>>>>>>`)
- Version bumps or lockfile changes that are unintentional

## Phase 4: Scoring & Filtering

For each issue found across all dimensions, score confidence (0-100):
- **0**: False positive / pre-existing issue not introduced by this PR
- **25**: Possible issue but could be intentional
- **50**: Real issue but minor / nitpick
- **75**: Confirmed real issue that will impact functionality
- **100**: Definite bug / security issue / clearly wrong

Only surface issues with a score >= 60.

## Phase 5: Final Report

Present the review in this format:

---

### PR Review: <PR title> (#<number>)

**Issue:** #<issue-number> — <issue title>
**Base:** `<base-branch>` ← `<head-branch>`
**Commits reviewed:** <N> commits | **Files changed:** <N> | +<additions> -<deletions>

#### Story Alignment
<Did the PR fully address the issue? Any gaps or scope creep?>

#### Issues Found (<N> total)

**[SEVERITY]** Brief title of issue
- **Where:** `path/to/file.py:L42-L47` (link with full SHA if on GitHub)
- **Why:** Clear explanation of the problem
- **Suggestion:** How to fix it

_(Repeat for each issue, grouped by severity: CRITICAL > HIGH > MEDIUM)_

#### Unwanted Changes
<List any changes that appear unrelated to the issue or accidental>

#### Commit Quality
<Notes on commit hygiene — squash candidates, misleading messages, etc.>

#### Summary
<Overall assessment: Approve / Request Changes / Needs Discussion>

---

## Notes

- Use `gh` CLI for all GitHub interactions; do not use web fetch for PR/issue data
- Always use the full commit SHA when linking to specific lines in GitHub URLs
- Format GitHub links as: `https://github.com/<owner>/<repo>/blob/<full-sha>/<path>#L<start>-L<end>`
- If the repo owner/name is not known, derive it from `gh repo view --json nameWithOwner`
- Treat the GitHub issue as the source of truth for what the PR should do (equivalent to a Jira story)
- Flag scope creep clearly — changes not mentioned in the issue are potential risks
