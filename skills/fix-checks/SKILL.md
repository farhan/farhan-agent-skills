---
name: fix-checks
description: Run ONLY when the user explicitly says "fix-checks". Finds the PR (asks if not given), checks out the branch locally, sets up a test environment, reproduces failing CI checks, fixes them in a loop until all pass, cleans up the fix, and pushes a proper commit.
argument-hint: [pr-number-or-url]
allowed-tools: Bash(gh pr view:*), Bash(gh pr list:*), Bash(gh pr checks:*), Bash(gh pr diff:*), Bash(gh api:*), Bash(git checkout:*), Bash(git fetch:*), Bash(git pull:*), Bash(git log:*), Bash(git diff:*), Bash(git status:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(find:*), Bash(ls:*), Bash(python:*), Bash(python3:*), Bash(pip:*), Bash(pip3:*), Bash(uv:*), Bash(npm:*), Bash(yarn:*), Bash(pnpm:*), Bash(node:*), Bash(make:*), Bash(pytest:*), Bash(tox:*)
---

# Fix Checks Skill

Reproduces and fixes failing CI checks for a PR, then pushes a clean commit.

**IMPORTANT:** Only invoke this skill when the user explicitly types `fix-checks`. Never run it automatically.

---

## Phase 1: Identify the PR

If the user provided a PR number or URL as an argument, use it. Otherwise ask:
> "Which PR should I fix the checks for? Please provide a PR number or URL."

Once you have the PR, fetch its details:

```bash
gh pr view <pr-number-or-url> --json number,title,headRefName,baseRefName,url,state,headRepositoryOwner,headRepository
```

Extract:
- PR number and title
- Head branch name (`headRefName`)
- Repository owner and name (to derive `owner/repo`)
- PR URL

---

## Phase 2: Find and Check Out the Branch Locally

### 2a. Locate the local clone

Determine the repo slug (`owner/repo`) from the PR. Then find the local clone:

```bash
# Try the current working directory first
git -C . rev-parse --show-toplevel 2>/dev/null

# If that doesn't match, search common local paths
find ~/MyStuff ~/Development ~ -maxdepth 5 -name ".git" -type d 2>/dev/null | head -20
```

Match the local clone against the repo slug by checking the remote URL:

```bash
git -C <candidate-path> remote get-url origin
```

Use the first match as `<repo-root>`.

### 2b. Fetch and check out the branch

```bash
cd <repo-root>

# Fetch latest remote state
git fetch origin

# Check if already on the right branch
CURRENT=$(git rev-parse --abbrev-ref HEAD)
echo "Current branch: $CURRENT"
```

If already on the correct branch, confirm and skip the checkout. Otherwise:

```bash
git checkout <head-branch>
```

### 2c. Pull latest

```bash
git pull origin <head-branch>
```

Confirm the branch is up to date with the remote.

---

## Phase 3: Identify Failing Checks

Fetch the current CI check status from GitHub:

```bash
gh pr checks <pr-number> --repo <owner/repo>
```

List all failing checks by name. If no checks are failing, inform the user and stop:
> "All checks are currently passing for this PR. Nothing to fix."

Note the names and types of failing checks to guide the local reproduction strategy.

---

## Phase 4: Set Up the Test Environment

Inspect the repo to determine what kind of project it is.

### Python project detection

Look for any of: `pyproject.toml`, `setup.py`, `setup.cfg`, `tox.ini`, `requirements*.txt`, `Makefile` with pytest targets.

If Python:

```bash
cd <repo-root>

# Prefer uv if available
if command -v uv &>/dev/null; then
  uv venv .venv --python python3
  source .venv/bin/activate
  uv pip install -e ".[dev,test]" 2>/dev/null || uv pip install -r requirements/test.txt 2>/dev/null || uv pip install -e ".[testing]" 2>/dev/null
else
  python3 -m venv .venv
  source .venv/bin/activate
  pip install -e ".[dev,test]" 2>/dev/null || pip install -r requirements/test.txt 2>/dev/null || pip install -e ".[testing]" 2>/dev/null
fi
```

If a `Makefile` is present, also try:
```bash
make requirements 2>/dev/null || true
```

### Frontend project detection

Look for `package.json`, `yarn.lock`, `pnpm-lock.yaml`, `.nvmrc`.

If frontend:

```bash
cd <repo-root>

# Use the right package manager
if [ -f yarn.lock ]; then
  yarn install
elif [ -f pnpm-lock.yaml ]; then
  pnpm install
else
  npm install
fi
```

If `.nvmrc` is present:
```bash
nvm use 2>/dev/null || true
```

---

## Phase 5: Reproduce and Fix (Loop)

### 5a. Map failing check names to local commands

Based on the failing check names from Phase 3, determine the appropriate local command(s):

| Check name pattern | Local command |
|---|---|
| `pytest` / `test` / `unit` | `pytest` or `make test` |
| `lint` / `pylint` / `flake8` / `ruff` | `make lint` or `ruff check .` or `flake8` |
| `quality` / `pep8` / `pycodestyle` | `make quality` |
| `mypy` / `type` | `mypy .` or `make type-check` |
| `jest` / `vitest` / `mocha` | `npm test` or `yarn test` |
| `eslint` | `npm run lint` or `npx eslint .` |
| `tox` | `tox` |

Prefer `Makefile` targets if they exist (`make test`, `make quality`, `make lint`).

### 5b. Reproduce → Fix → Recheck loop

Run the loop until **all originally-failing checks pass locally**:

```
LOOP:
  1. Run the local command(s) for each failing check.
  2. Capture the full output (stdout + stderr).
  3. Analyze each failure:
     - Read the exact error messages, file paths, and line numbers.
     - Read the relevant source files.
     - Apply a targeted fix (edit only what is needed).
  4. Re-run the command.
  5. If it still fails, go back to step 3 with the new output.
  6. Once a check passes, move to the next failing check.
  7. Repeat until all checks pass.
```

Guiding principles during the loop:
- Fix the root cause, not the symptom (do not suppress errors with `noqa`, `# type: ignore`, or similar unless it is genuinely the correct approach).
- Prefer minimal, surgical edits — do not refactor or rewrite surrounding code.
- If a fix for check A breaks check B, address both in the same iteration before moving on.
- If you are stuck on a check after 3 iterations without progress, describe the blocker clearly and ask the user for guidance rather than continuing blindly.

---

## Phase 6: Post-Fix Review and Cleanup

Once all checks pass locally:

### 6a. Review all changed files

```bash
git diff HEAD
```

Go through every changed line and ask:
- Is this change strictly necessary to fix the failing checks?
- Is there any debug code, temporary print statements, or commented-out code left behind?
- Is there any duplicated logic or unnecessary complexity introduced?
- Did the fix accidentally touch unrelated lines (whitespace, imports, etc.)?

Remove anything that is not essential to the fix.

### 6b. Run the full check suite one final time

After cleanup, re-run **all** local checks (not just the previously failing ones) to confirm nothing regressed:

```bash
make test 2>/dev/null || pytest
make quality 2>/dev/null || true
make lint 2>/dev/null || true
```

If any check fails after cleanup, go back to the fix loop (Phase 5).

---

## Phase 7: Commit and Push

### 7a. Stage only the relevant files

```bash
git add <only the files changed to fix the checks>
```

Do not use `git add .` — be explicit about which files are being committed.

### 7b. Write a meaningful commit message

The commit message should follow this structure:
- **Subject line (≤72 chars):** `fix: <what was broken and what fixed it>`
- **Body (optional):** brief explanation of root cause and approach if non-obvious

Examples:
- `fix: resolve flake8 E501 line-length violations in utils.py`
- `fix: correct mypy type annotation for get_user return value`
- `fix: update jest snapshot after Button component refactor`

```bash
git commit -m "$(cat <<'EOF'
<subject line>

<optional body>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

### 7c. Push to the PR branch

```bash
git push origin <head-branch>
```

After pushing, move on to Phase 8 to monitor the CI results.

---

## Phase 8: Wait and Verify CI (Outer Loop)

After every push, enter a wait-and-verify cycle:

### 8a. Wait 5 minutes

Inform the user:
> "Pushed. Waiting 5 minutes for CI to run before checking results…"

```bash
sleep 300
```

### 8b. Check PR checks on GitHub

```bash
gh pr checks <pr-number> --repo <owner/repo>
```

### 8c. Evaluate results

**If all checks are green** — the work is done. Proceed to the Final Report.

**If any check is still failing:**
- Note which checks are still failing (they may differ from the original set).
- Pull the latest branch state (another commit may have landed in the meantime):
  ```bash
  git pull origin <head-branch>
  ```
- Re-enter the fix loop from **Phase 3** using the newly observed failing checks as the starting point.
- Work through Phases 3 → 4 → 5 → 6 → 7 again, then return to Phase 8 after pushing.

Repeat this outer loop — fix → push → wait 5 min → check — until all checks pass on GitHub.

> **Stuck guard:** If after 3 full outer-loop iterations checks are still failing and you are not making progress, stop and report the blocker to the user rather than continuing to loop.

---

## Final Report

After all checks go green on GitHub, provide a short summary:

```
### fix-checks complete

**PR:** #<number> — <title>
**Branch:** <head-branch>

**Checks fixed:**
- <check name>: <one-line description of what was wrong and how it was fixed>
- ...

**Commits pushed:** <N> fix commit(s)
**CI status:** All checks green on GitHub
**PR:** <pr-url>
```

---

## Notes

- Never use `--no-verify` when committing.
- Never force-push unless the user explicitly asks.
- If the virtual environment already exists (`.venv`), reuse it — do not recreate it.
- If the repo uses `tox`, prefer running `tox -e <env>` matching the failing check over a bare `pytest`.
- If credentials or secrets are needed to run a check and are not available, skip that check and inform the user.
