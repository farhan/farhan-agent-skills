---
name: commit-guide
description: The default guideline for committing code following Open edX conventions. ALWAYS invoke this skill BEFORE any `git commit` — whether the user asked for the commit or the agent is about to commit on its own (e.g. as a step inside another skill, workflow, or fix loop). Never run `git commit` without following this skill first. Two modes — write (default: create a compliant commit; runs on any commit, user- or agent-initiated) and verify (lint an existing/proposed commit message; explicit only via /commit-guide v).
---

This skill is the single source of truth for how commits are made in this workspace. **Any time code is being committed — by the user's request or by the agent's own decision (including as a step inside another skill) — follow the WRITE mode below. Do not run a bare `git commit`.**

## Modes

Pick the mode from how the skill was invoked:

| Invocation | Mode | Use when |
|---|---|---|
| `/commit-guide`, `/commit-guide w`, **any request to commit code**, or **the agent is about to run `git commit`** | **WRITE** (default) | Creating a commit. This is the default — if no mode is given, the user simply asks to "commit", or the agent decides to commit on its own, use WRITE. |
| `/commit-guide v` (or `/commit-guide verify`) | **VERIFY** | Explicitly linting a commit message against conventions. Read-only — never commits or amends. |

If invoked with no argument, **default to WRITE**.

---

## WRITE mode (default)

Commit all staged and unstaged changes in the current repository.

Follow these steps exactly:

1. **Always include the Claude co-author trailer** in every commit message — do not ask. Use the active model's trailer (e.g. `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`).

2. Run `git status` to see what files have changed.
3. Run `git diff HEAD` to review all changes (staged and unstaged).
4. Run `git log --oneline -5` to match the existing commit message style.
5. Stage only the relevant changed files (never use `git add -A` or `git add .` blindly — add specific files by name).
6. Choose the commit type from the Open edX standard below (per [OEP-0051](https://open-edx-proposals.readthedocs.io/en/latest/best-practices/oep-0051-bp-conventional-commits.html)). If the commit mixes types, use the highest-priority type per this order: `revert > feat > fix > perf > docs > test > build > refactor > style > chore > temp`.

   | Type | When to use |
   |---|---|
   | `build` | Build/release tooling: Makefile, tox.ini, CI/CD, GitHub Actions |
   | `chore` | Repetitive mechanical tasks: updating requirements, translations |
   | `docs` | Documentation-only changes: READMEs, ADRs, docstrings, comments, annotations. Docs that accompany other work belong in *that* commit, not a separate `docs` commit |
   | `feat` | New or changed feature, public API entry points or behavior |
   | `<type>!` | Breaking change — append `!` to **any** type, e.g. `feat!: remove the ability to author courses` |
   | `fix` | Bug fixes, behavioral corrections, security vulnerability mitigations |
   | `perf` | Performance improvements |
   | `refactor` | Code reorganization with no behavior change from consumer perspective |
   | `revert` | Undo a previous commit (include original commit message in body) |
   | `style` | Code style/formatting improvements |
   | `test` | Test-only changes: adding missing tests or correcting existing ones. Tests that accompany other work belong in *that* commit, not a separate `test` commit |
   | `temp` | Temporary/exploratory changes not meant to be permanent |

   **Separating commits:** Split changes so each commit is easy to review and understand. Some types combine well — a feature together with its tests and documentation. But `refactor`, `style`, `chore`, and `temp` changes should be their own commits, separate from more significant work. When staging, group files accordingly rather than lumping unrelated types together.

   **Breaking changes:** Append `!` after the type label whenever the change breaks backwards compatibility. This applies to any type, not just `feat`. Examples:
   - `feat!: remove the ability to author courses`
   - `fix!: drop support for the legacy enrollment API`
   - `refactor!: rename CourseKey to CourseLocator throughout public API`

7. Write a concise commit message that focuses on the *why*, not the *what*. The first line (`<type>: <short summary>`) MUST be 70 characters or fewer. Always end with the co-author trailer for the active model:
   ```
   git commit -m "$(cat <<'EOF'
   <type>: <short summary>

   <optional body if needed>

   Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
   EOF
   )"
   ```
8. After committing, run `git status` to confirm success.

After confirming success, output the summary section:

---
**Commit Summary**

- Total commits made: <N>
- Co-author included: Yes (always)
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
