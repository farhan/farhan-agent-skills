---
name: address-copilot-change-requests
description: Address GitHub Copilot change requests on a PR. Resolves well-recommended suggestions with code changes, replies to others with a short comment, then commits and prompts for push.
version: 1.0.0
allowed-tools: Bash(gh pr view:*), Bash(gh pr diff:*), Bash(gh api:*), Bash(gh repo view:*), Bash(git log:*), Bash(git diff:*), Bash(git checkout:*), Bash(git status:*), Bash(git fetch:*), Read, Edit, Write
---

# Address Copilot Change Requests

Workflow to triage GitHub Copilot review comments on a PR, address the good ones in code, reply to the rest, and commit.

## Step 1: Confirm Repo and Branch

Ask the user:
> "Which repository path should I work in, and which branch should I check out?"

Wait for the answer. Then:

```bash
cd <repo-path>
git fetch origin
git checkout <branch>
git pull origin <branch>
```

## Step 2: Get the PR Number

If the user has not provided a PR number or URL, ask:
> "What is the PR number or URL?"

Derive the owner/repo if not known:
```bash
gh repo view --json nameWithOwner --jq '.nameWithOwner'
```

## Step 3: Fetch All Copilot Review Threads

Use the GitHub GraphQL API to get all unresolved review threads. Filter for comments authored by `copilot` or `github-advanced-security` or any bot whose login contains `copilot`.

```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          line
          path
          comments(first: 10) {
            nodes {
              databaseId
              author { login }
              body
              path
              line
              originalLine
              diffHunk
              url
            }
          }
        }
      }
    }
  }
}' -f owner=OWNER -f repo=REPO -F pr=PR_NUMBER
```

Collect all threads where at least one comment is authored by a login that contains `copilot` (case-insensitive). Split into two buckets:

- **Active** — `isResolved: false` AND `isOutdated: false`
- **Outdated** — `isResolved: false` AND `isOutdated: true`

Resolved threads (`isResolved: true`) are always skipped entirely.

## Step 4: Triage Each Thread

### Active threads

For each active Copilot thread, read the comment body and the `diffHunk` to understand the context.

Classify each thread as one of:

| Class | Criteria |
|---|---|
| **ADDRESSABLE** | The suggestion is concrete, correct, and improves code quality, readability, or correctness. It can be implemented by editing the file. |
| **NOT-ADDRESSABLE** | The suggestion is vague, debatable, context-dependent, already handled elsewhere, or would require changes outside the scope of this PR. |

### Outdated threads

Do **not** skip outdated threads — always reply to them. Before replying, check whether the underlying issue flagged by Copilot still exists in the current code (grep / read the referenced file).

- **Issue still present** → reply acknowledging the thread is outdated but confirming the problem remains, naming the specific files/lines where it persists, and stating it will be addressed in a follow-up:
  > "Thread is outdated after the latest push, but the underlying issue still exists: `<prop/symbol>` is still referenced in `<file>` (line N). Will be cleaned up in a follow-up commit."

- **Issue no longer present** → reply confirming the concern has already been resolved by the latest changes:
  > "Thread is outdated — this was resolved in the latest push. `<brief explanation of what changed>`."

After posting the reply, **always resolve the thread** regardless of which case applies:

```bash
gh api graphql -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread { isResolved }
  }
}' -f threadId=THREAD_ID
```

### For ADDRESSABLE threads

1. Read the relevant file at `path`.
2. Apply the suggested change using the Edit tool.
3. Resolve the thread via GraphQL:

```bash
gh api graphql -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread { isResolved }
  }
}' -f threadId=THREAD_ID
```

### For NOT-ADDRESSABLE threads

Reply with a short, professional comment explaining why it is not being addressed:

```bash
gh api repos/OWNER/REPO/pulls/comments/COMMENT_DB_ID/replies \
  -f body="<short explanation — 1-2 sentences>"
```

Keep replies factual and brief. Examples:
- "This is intentional — the existing pattern is consistent with the rest of the module."
- "Out of scope for this PR; tracked separately."
- "The suggestion conflicts with the project's linting rules."

## Step 5: Summary Before Committing

Print a summary table:

```
Thread | File | Copilot Comment (truncated) | Action
-------|------|----------------------------|-------
1      | foo/bar.py:42 | "Use list comprehension..." | RESOLVED (code changed)
2      | foo/baz.py:10 | "Consider adding type hint..." | REPLIED (out of scope)
```

## Step 6: Commit the Changes

Invoke the `commit` skill to stage and commit all addressed changes.

### Commit message format

The commit message **must** follow this pattern:

```
<type>: address Copilot change requests for <short context>

<1-3 sentence body explaining what was actually fixed and why —
focus on the underlying problem, not "Copilot said so">
```

Rules:
- The first line must start with the appropriate conventional-commit type (`fix`, `refactor`, `test`, etc.) followed by **"address Copilot change requests for …"** so the intent is immediately clear.
- The short context after "for" should name the feature/area being changed (e.g. "waffle flag removal", "auth middleware refactor"), not a file name.
- The body should explain *what was wrong and why the fix is correct* — not just list the files changed.
- Keep the first line ≤ 70 characters.

**Examples:**

```
fix: address Copilot change requests for waffle flag removal

Restores config gates for video uploads and certificates that were
dropped when waffle flags were removed. Routes remain gated behind
config flags so unconditional links caused dead hrefs. Also guards
against null courseId in PageSettingButton.
```

```
test: address Copilot change requests for auth middleware tests

Removes stale tests that asserted legacy token-storage behavior no
longer present after the compliance-driven middleware rewrite.
```

## Step 7: Ask for Push

After the commit skill completes, ask the user:
> "Changes committed. Should I push to origin/<branch>?"

If they confirm, run:
```bash
git push origin <branch>
```

## Notes

- Only target threads from Copilot (login contains `copilot` case-insensitively). Skip threads from human reviewers.
- Do not resolve threads unless the corresponding code change has actually been made.
- Do not skip outdated threads — always reply to them after checking if the underlying issue still exists in the current code.
- Do not auto-push — always ask first, per the commit skill convention.
- If no Copilot threads are found, tell the user and stop.
- Use the correct reply endpoint: `POST /repos/OWNER/REPO/pulls/PR_NUMBER/comments/COMMENT_DB_ID/replies` (not `/pulls/comments/…/replies`).
