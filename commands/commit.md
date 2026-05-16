---
trigger: ALWAYS use this skill (via the Skill tool) when the user asks to commit code. Never run git commit manually — always invoke this skill instead.
---

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
