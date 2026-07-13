---
name: review-pr
description: This skill should be used when the user says "review PR", "review pull request", "start PR review", "I'm reviewing a PR", "let's review a PR", or starts a pull request review session. Gathers GitHub issue context, PR details, iterates through commits, and performs a thorough multi-dimensional code review.
version: 1.1.0
allowed-tools: Bash(gh issue view:*), Bash(gh issue list:*), Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh pr list:*), Bash(gh pr checks:*), Bash(gh api:*), Bash(git log:*), Bash(git diff:*), Bash(git show:*)
---

# PR Review Skill

**Base skill:** Invoke the built-in `/review` skill first to perform the core PR review.

```
Skill({ skill: "review" })
```

Then apply the additional checks below as supplementary dimensions on top of the base review.

---

## Additional Notes

### GitHub Issue Context (Story/Ticket)

Before starting the review, gather the GitHub issue context if available:

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

### Commit History Details

List all commits in the PR and iterate through each:
```bash
gh pr view <pr-number> --repo <owner/repo> --json commits --jq '.commits[] | "\(.oid[0:8]) \(.messageHeadline)"'
```

For each commit:
- Is the commit message meaningful and descriptive?
- Does the commit represent a logical unit of work?
- Are there "WIP", "fixup", "temp" commits that should be squashed?
- Use `git show <commit-sha>` for any commits that seem out of place

### Extra Review Dimensions

Run these in addition to the base `/review` findings:

#### Story/Issue Alignment
Compare the PR changes against the GitHub issue requirements:
- Does the implementation satisfy the acceptance criteria from the issue?
- Are there requirements from the issue NOT addressed in the PR?
- Are there changes in the PR that go beyond the issue scope (scope creep)?
- Flag any "unwanted changes" — modifications unrelated to the issue

#### Unwanted/Accidental Changes
Look for changes that shouldn't be in this PR:
- Whitespace-only changes in unrelated files
- Unrelated refactoring mixed with feature changes
- Accidentally committed debug files, `.env` files, build artifacts
- Merge conflict markers left in code (`<<<<<<<`, `=======`, `>>>>>>>`)
- Version bumps or lockfile changes that are unintentional

### Scope Rule (strictly enforced)

Every finding MUST be rooted in a line that appears in the PR diff (`+` or `-` lines). Do NOT flag issues in surrounding context lines, unchanged files, or pre-existing code the PR didn't touch — even if you spot a general improvement opportunity. The review is of what changed, not of the codebase at large.

**Never recommend improvements to code the PR didn't change.** If you notice a pre-existing issue in surrounding context, silently ignore it.

### Additional Report Sections

Append these sections to the base `/review` report:

#### Story Alignment
<Did the PR fully address the issue? Any gaps or scope creep?>

#### Unwanted Changes
<List any changes that appear unrelated to the issue or accidental>

#### Commit Quality
<Notes on commit hygiene — squash candidates, misleading messages, etc.>

### Test Cases for Common Pattern Violations

#### Linter Migration: Django AppConfig Signal Imports

When reviewing PRs that migrate Django projects from pylint to ruff (or similar linter upgrades):

**❌ Common Issue:** Signal imports inside `AppConfig.ready()` are removed because they appear unused to static analysis:

```python
# WRONG: import was simply deleted
class ForumConfig(AppConfig):
    def ready(self) -> None:
        """Import Signals."""
        # import forum.signals removed — handlers won't register!
```

**✅ Correct Fix:** Preserve the import with ruff suppression instead of pylint:

```python
class ForumConfig(AppConfig):
    def ready(self) -> None:
        """Import Signals."""
        import forum.signals  # noqa: F401
```

**Why this matters:**
- Django's `@receiver` decorators on signal handlers only register when the module is imported
- Removing the import silently breaks signal-dependent functionality (search indexing, cache invalidation, etc.)
- The import MUST stay in `ready()` to preserve the lazy-loading pattern — don't move it to module level
- Replace pylint directives with `# noqa: F401` (ruff syntax)

**Review checklist for linter migrations:**
- [ ] Django AppConfig signal imports are preserved (not deleted)
- [ ] Imports stay inside `ready()` method (don't move to module level)
- [ ] Pylint directives converted to ruff `# noqa` syntax
- [ ] No unrelated logic changes mixed with linter updates

### Notes

- Use `gh` CLI for all GitHub interactions; do not use web fetch for PR/issue data
- Always use the full commit SHA when linking to specific lines in GitHub URLs
- Format GitHub links as: `https://github.com/<owner>/<repo>/blob/<full-sha>/<path>#L<start>-L<end>`
- If the repo owner/name is not known, derive it from `gh repo view --json nameWithOwner`
- Treat the GitHub issue as the source of truth for what the PR should do (equivalent to a Jira story)
- Flag scope creep clearly — changes not mentioned in the issue are potential risks
