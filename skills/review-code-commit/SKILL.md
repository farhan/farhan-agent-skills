---
name: review-code-commit
description: Review uncommitted git changes for bugs, typos, correctness issues, and security concerns before committing
argument-hint: [directory]
---

Perform working on the current working directory or the directory shared in the prompt

Run `git restore --staged .`

Run `git diff HEAD` 

then do the code review for the files changes which user is going to commit.

Areas to focus:
- Bugs or logic errors
- Typos in strings, comments, or identifiers
- Correctness issues (wrong flags, invalid config values, broken syntax)
- Security or best-practice concerns

Report findings grouped by file. For each issue include the line number/context and a brief explanation of the problem. If no issues are found, say so clearly.

At the end
Run `git add .`