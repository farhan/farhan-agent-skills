---
name: commit-guide
description: The default guideline for committing code following Open edX conventions. ALWAYS use this skill whenever the user asks to commit code, stage changes, or make a commit — never run `git commit` manually, always follow this instead. Two modes — write (default: create a compliant commit; runs on any commit request) and verify (lint an existing/proposed commit message; explicit only via /commit-guide v).
---

This skill is the single source of truth for how commits are made in this workspace. **Any time code is being committed, follow the WRITE mode below — do not run a bare `git commit`.**

## Modes

Pick the mode from how the skill was invoked:

| Invocation | Mode | Use when |
|---|---|---|
| `/commit-guide`, `/commit-guide w`, or **any request to commit code** | **WRITE** (default) | Creating a commit. This is the default — if no mode is given, or the user simply asks to "commit", use WRITE. |
| `/commit-guide v` (or `/commit-guide verify`) | **VERIFY** | Explicitly linting a commit message against conventions. Read-only — never commits or amends. |

If invoked with no argument, **default to WRITE**.

---

## WRITE mode (default)

Commit all staged and unstaged changes in the current repository.

Follow these steps exactly:

1. **Before doing anything else, ask the user:** "Add Claude as co-author? (y/n)"
   - Wait for the response before proceeding.
   - If **y**: include the co-author trailer in the commit message.
   - If **n**: omit it entirely.

2. Run `git status` to see what files have changed.
3. Run `git diff HEAD` to review all changes (staged and unstaged).
4. Run `git log --oneline -5` to match the existing commit message style.
5. Stage only the relevant changed files (never use `git add -A` or `git add .` blindly — add specific files by name).
6. Choose the commit type from the Open edX standard below. If the commit mixes types, use the highest-priority type per this order: `revert > feat > fix > perf > docs > test > build > refactor > style > chore > temp`.

   | Type | When to use |
   |---|---|
   | `build` | Build/release tooling: Makefile, tox.ini, CI/CD, GitHub Actions |
   | `chore` | Repetitive mechanical tasks: updating requirements, translations |
   | `docs` | Documentation only: READMEs, ADRs, docstrings, comments, annotations |
   | `feat` | New or changed feature, public API entry points or behavior |
   | `<type>!` | Breaking change — append `!` to **any** type, e.g. `feat!: remove the ability to author courses` |
   | `fix` | Bug fixes, behavioral corrections, security vulnerability mitigations |
   | `perf` | Performance improvements |
   | `refactor` | Code reorganization with no behavior change from consumer perspective |
   | `revert` | Undo a previous commit (include original commit message in body) |
   | `style` | Code style/formatting improvements |
   | `test` | Test-only changes: adding missing tests or correcting existing ones |
   | `temp` | Temporary/exploratory changes not meant to be permanent |

   **Breaking changes:** Append `!` after the type label whenever the change breaks backwards compatibility. This applies to any type, not just `feat`. Examples:
   - `feat!: remove the ability to author courses`
   - `fix!: drop support for the legacy enrollment API`
   - `refactor!: rename CourseKey to CourseLocator throughout public API`

7. Write a concise commit message that focuses on the *why*, not the *what*. The first line (`<type>: <short summary>`) MUST be 70 characters or fewer. Format (with co-author):
   ```
   git commit -m "$(cat <<'EOF'
   <type>: <short summary>

   <optional body if needed>

   Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
   EOF
   )"
   ```
   Format (without co-author):
   ```
   git commit -m "$(cat <<'EOF'
   <type>: <short summary>

   <optional body if needed>
   EOF
   )"
   ```
8. After committing, run `git status` to confirm success.

After confirming success, output the summary section:

---
**Commit Summary**

- Total commits made: <N>
- Co-author included: Yes / No
- Commit message(s):
  1. `<hash>` — <commit message>
  (add more lines if multiple commits were made)

---

9. After showing the summary, ask: "Push to remote? (y/n)"
   - If **y**: run `git push` and report the result.
   - If **n**: do nothing.

---

## VERIFY mode (explicit: `/commit-guide v`)

Lint a commit **message** against the Open edX conventions above. This mode is **read-only** — it never stages, commits, amends, or pushes.

1. **Determine the target message:**
   - If the user pasted a message, lint that.
   - Otherwise lint the latest commit: `git log -1 --pretty=format:'%B'`.

2. **Check each rule** and report a pass/fail checklist:

   | Check | Rule |
   |---|---|
   | Type present | Subject starts with a valid type from the table above (`feat`, `fix`, `docs`, …) |
   | Breaking marker | If the change breaks compatibility, the type ends with `!` (e.g. `feat!:`) |
   | Format | Subject is `<type>: <short summary>` (colon + single space) |
   | Subject length | First line is ≤ 70 characters |
   | Why-not-what | Body (if present) explains *why*, not a restatement of *what* changed |
   | Co-author trailer | If a co-author trailer exists, it matches `Co-Authored-By: <Name> <email>` format |

3. **Output:**
   - The checklist with ✅ / ❌ per row and a one-line reason for each ❌.
   - A **corrected version** of the message if any check failed.
   - Do **not** apply the fix. Tell the user they can re-run WRITE mode or amend it themselves.
