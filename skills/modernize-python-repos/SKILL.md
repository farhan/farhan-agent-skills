---
name: modernize-python-repos
description: >
  Modernize an Open edX Python repo to use uv, pyproject.toml (PEP 621/735), and
  python-semantic-release. Use when asked to modernize a Python package, migrate from
  pip-compile/setup.cfg, or apply the openedx standard tooling migration.
allowed-tools: Read Glob Grep Bash Write Edit
---

# Modernize Python Repos

You are helping modernize an Open edX Python package to the standard modern tooling:
- `pyproject.toml` (PEP 621/735) replaces `setup.py`, `setup.cfg`, `requirements/*.txt`
- `uv` replaces `pip-compile` for dependency management
- `python-semantic-release` automates versioning and PyPI publishing

**Parent story:** [`openedx/public-engineering#506`](https://github.com/openedx/public-engineering/issues/506) — all requirements defined there are mandatory and must be implemented in full. Do not skip or defer any item from that issue unless the user explicitly says to ignore the parent story requirements.

**Reference implementation:** `openedx/xblocks-extra` — model after its:
- `pyproject.toml`
- `tox.ini`
- `Makefile`
- `.github/workflows/ci.yml`
- `.github/workflows/release.yml`

---

## What needs to be checked

Everything in this list must be verified and fixed if missing or wrong.

### pyproject.toml
- `[build-system]` uses `setuptools>=61.0` and `setuptools-scm>=8.0` (pin the `>=8.0`)
- `[project]` has all metadata: name, description, readme, requires-python, license (SPDX string), authors, classifiers, keywords, urls
- `classifiers` includes Django framework classifiers: `Framework :: Django`, `Framework :: Django :: 4.2`, `Framework :: Django :: 5.2`
- `dependencies` is a **static list** (not dynamic from a requirements file)
- `dynamic = ["version"]` only — not `["dependencies"]`
- `[tool.setuptools_scm]` has `version_scheme = "only-version"` and `local_scheme = "no-local-version"`
- `[tool.uv]` has `package = true`
- `[dependency-groups]` covers: `test-base`, `test`, `django42` (or similar legacy group), `quality`, `doc`, `ci`, `dev`
- `[tool.uv].conflicts` lists the mutually exclusive Django version groups
- `[tool.edx_lint].uv_constraints` present; `[tool.uv].constraint-dependencies` machine-managed (never edit directly)
- **Mypy: retain if already present.** If the repo had mypy configured before the migration (mypy in requirements, a `make mypy` target, or a `[tool.mypy]` section), keep it — add `mypy` to the `quality` dependency group, retain or add a `[tool.mypy]` config block, add a `mypy` tox env, and keep a `make mypy` target. Do not add mypy to repos that did not use it before.
- **Ruff replaces pylint/pycodestyle/pydocstyle/isort.** `[tool.ruff]` must have:
  - `line-length = 120`
  - `target-version = "py312"`
  - `[tool.ruff.lint]` select: `E`, `W`, `F`, `I`, `B`, `C4`, `UP`, `DJ`; ignore: `E501`
  - `[tool.ruff.lint.isort]` `known-third-party = ["django", "xblock"]`
  - `[tool.ruff.format]` `quote-style = "double"`, `indent-style = "space"`
- **Coverage config in pyproject** — not in a separate `.coveragerc`:
  - `[tool.coverage.run]` with `branch = true`, `source`, `omit` patterns
  - `[tool.coverage.report]` with `fail_under = <see rule below>`, `show_missing = true`, `exclude_lines`
  - `[tool.coverage.html]` with `directory = "htmlcov"`
  - **`fail_under` rule:** read the old `.coveragerc` and `setup.cfg` first. If a `fail_under` value exists, carry it over exactly. If no threshold was set before, omit `fail_under` entirely — do not invent one.
- `[tool.semantic_release]` has `build_command` using `python -m build` (never `uv build`)
- No hardcoded `__version__` in the package's `__init__.py` — version is derived from git tags via `setuptools-scm`; the `importlib.metadata` API should be used instead if the version is needed at runtime

### Files to delete
- `setup.py`
- `setup.cfg`
- `requirements/` directory
- `CHANGELOG.rst` (semantic-release uses GitHub Releases instead)
- `.coveragerc` (config moves into pyproject.toml)
- `pylintrc` and `pylintrc_tweaks` (replaced by ruff)

### tox.ini
- `requires = tox-uv>=1`
- All environments use `runner = uv-venv-lock-runner`
- All environments use `dependency_groups =` (not `deps =`)
- Has a `quality` (or `lint`) env that runs `ruff check .` and `ruff format --check .`
- Test envs named `py312-django{42,52}` or similar matrix form
- Has a `mypy` env **if the repo used mypy before the migration**

### Makefile
- `requirements` target: `uv sync --group dev` + `uv tool install tox --with tox-uv`
- `upgrade` target: `uv run --with edx-lint edx_lint write_uv_constraints pyproject.toml` then `uv lock --upgrade`
- Has `lint`, `format`, `test`, `docs` targets (delegates to tox or uv run ruff)
- `format` target uses `uv run ruff check --fix .` and `uv run ruff format .`
- Has a `mypy` target (`uv run tox -e mypy`) **if the repo used mypy before the migration**

### CI workflow (python-tests.yml or ci.yml)
- Has `workflow_call:` trigger so release.yml can reuse it
- Has `push: branches: [main]` trigger
- Has `pull_request:` trigger
- `strategy.fail-fast: false`
- Matrix job `name:` is `${{ matrix.toxenv }}` (not a hardcoded string)
- Uses **only** `astral-sh/setup-uv` — no separate `actions/setup-python` step
  - `astral-sh/setup-uv` must have `enable-cache: true` and `python-version: "${{ matrix.python-version }}"`
- All actions SHA-pinned with a version comment (e.g. `@de0fac2e… # v6.0.2`)
- `uv sync --group ci` then `uv run tox -e ${{ matrix.toxenv }}`

### release.yml
- `run_tests` (or `run_ci`) job calls the CI workflow as a reusable workflow
  - Must pass `secrets: inherit`
  - Must have `permissions: contents: read`
- `release` job: checkout + `git reset --hard ${{ github.sha }}` + PSR action
  - `permissions: contents: write` only (no `id-token`)
  - No `setup-uv` step — PSR does not need uv; `build_command` handles everything via pip
  - PSR action SHA-pinned
- `publish_to_pypi` job: OIDC (`id-token: write`), no password secret, `pypa/gh-action-pypi-publish` SHA-pinned
- All artifact upload/download actions use consistent major versions (check against the reference repo)
- All actions SHA-pinned

---

## What doesn't need to be checked

These items look like gaps when comparing two repos but are **not in scope** for this migration skill and should not be changed:

- **`django` upper bound in `[project].dependencies`** — e.g. `"django>=4.2"` without `<6.0` — downstream constraint management is out of scope
- **MANIFEST.in philosophy** — inclusion-based vs exclusion-based depends on the repo's file layout; do not normalize this
- **CI workflow file name** — `python-tests.yml` vs `ci.yml` is cosmetic; do not rename unless explicitly asked
- **Tox quality env name** — `quality` vs `lint` is acceptable either way; do not change a working name
- **`uv tool install tox --with tox-uv` in `requirements` target** — this is the standard pattern; do not remove it in favor of `uv run`
- **`src/` layout** — adopting `src/` layout is a recommended long-term direction (agreed in public-engineering#506 comments) but is a separate concern; do not restructure the package layout as part of this migration
- **`upload-artifact` / `download-artifact` major versions in `release.yml`** — aligning artifact action versions across repos is out of scope; do not flag or change these
- **PyPI publish mechanism (OIDC vs token)** — both are valid; do not flag a mismatch between repos or push for org-wide alignment as part of this migration

---

## Step 1 — Assess current state

Before doing any work, read the repo and produce a status checklist covering all three
sections below. Mark each item ✅ Done, ❌ Not done, or ⚠️ Partial, with a brief note.

Files to read:
- `pyproject.toml` (if exists)
- `setup.py` / `setup.cfg` (if exists)
- `tox.ini` (if exists)
- `Makefile` (if exists)
- `requirements/` directory listing (if exists)
- `.github/workflows/` — all workflow files

---

## Section 1 — Consolidate package metadata into pyproject.toml

Goal: single `pyproject.toml` using PEP 621, with static `dependencies`, and
`setuptools-scm` for version management. No `setup.py`, no `setup.cfg`.

Checklist:
- [ ] `[project]` table has all metadata (name, description, readme, requires-python,
      license, authors, classifiers, keywords, urls)
- [ ] `classifiers` includes `Framework :: Django`, `Framework :: Django :: 4.2`,
      `Framework :: Django :: 5.2`
- [ ] `dependencies` is a **static list** under `[project]` (not `dynamic` pointing to a
      requirements file)
- [ ] `[build-system]` uses `setuptools>=61.0` and `setuptools-scm>=8.0`
- [ ] `[tool.setuptools_scm]` is configured (`version_scheme = "only-version"`,
      `local_scheme = "no-local-version"`). Do NOT set `root` unless the Python package
      lives in a subdirectory.
- [ ] No hardcoded `__version__` in any `__init__.py` — remove it; version comes from git tags
- [ ] **Ruff configured** — `[tool.ruff]`, `[tool.ruff.lint]` (E, W, F, I, B, C4, UP, DJ;
      ignore E501), `[tool.ruff.lint.isort]` (known-third-party), `[tool.ruff.format]`
      (quote-style, indent-style)
- [ ] **Coverage config in pyproject** — `[tool.coverage.run/report/html]` present; `.coveragerc` deleted
      - `fail_under`: carry over from old `.coveragerc`/`setup.cfg` if set; omit entirely if no threshold existed before
- [ ] `setup.py` deleted
- [ ] `setup.cfg` deleted
- [ ] `CHANGELOG.rst` deleted
- [ ] `pylintrc` and `pylintrc_tweaks` deleted

---

## Section 2 — Switch dependency management from pip-compile to uv

Goal: PEP 735 `[dependency-groups]` in `pyproject.toml`, a committed `uv.lock`, tox
running via `tox-uv`, and CI using `uv run tox`.

Standard dependency groups: `test-base`, `test`, `quality`, `doc`, `ci`, `dev`.
Add version-matrix groups (e.g. `django42`, `django52`) only when needed.

Checklist:
- [ ] `[dependency-groups]` added to `pyproject.toml` with at minimum: `test`, `quality`,
      `doc`, `ci`, `dev`
- [ ] `[tool.edx_lint].uv_constraints` added for any repo-specific pin overrides, then
      `edx_lint write_uv_constraints` run to populate `[tool.uv].constraint-dependencies`
      (**never edit `[tool.uv].constraint-dependencies` directly**)
- [ ] `uv.lock` generated (`uv lock`) and committed
- [ ] `requirements/` directory deleted
- [ ] `tox.ini` updated (or created) to use `tox-uv>=1` with `uv-venv-lock-runner` and
      `dependency_groups` per environment; quality/lint env runs ruff
- [ ] `Makefile` targets updated:
      - `requirements` → `uv sync --group dev` + `uv tool install tox --with tox-uv`
      - `upgrade` → `edx_lint write_uv_constraints` then `uv lock --upgrade`
      - `lint` → `tox -e quality` (or `tox -e lint`)
      - `format` → `uv run ruff check --fix .` + `uv run ruff format .`
      - `test`, `docs` targets present
- [ ] CI updated:
      - `push: branches: [main]` + `pull_request:` + `workflow_call:` triggers
      - `fail-fast: false` in matrix strategy
      - Matrix job name is `${{ matrix.toxenv }}`
      - Only `astral-sh/setup-uv` (SHA-pinned) with `enable-cache: true` + `python-version`; no separate `setup-python` step
      - `uv sync --group ci` then `uv run tox`

---

## Section 3 — Add semantic-release

Goal: pushing a conventional commit to `main` automatically cuts a version, tags it,
and publishes to PyPI via OIDC trusted publisher.

Checklist:
- [ ] `[tool.semantic_release]` added to `pyproject.toml` with `build_command` that sets
      `SETUPTOOLS_SCM_PRETEND_VERSION=$NEW_VERSION` at build time using `python -m build`
      (do **not** use `uv build`; do **not** override `minor_tags`)
- [ ] `release.yml` workflow added:
      - `run_tests` job calls CI workflow with `secrets: inherit` + `permissions: contents: read`
      - `release` job: checkout + reset + PSR (SHA-pinned, `changelog: "false"`); `permissions: contents: write`; no `setup-uv` step
      - `publish_to_pypi` job: OIDC (`id-token: write`), `pypa/gh-action-pypi-publish` SHA-pinned; all artifact actions SHA-pinned at consistent versions
- [ ] `commitlint.yml` workflow added to enforce conventional commits on PRs
- [ ] Old `pypi-publish.yml` deleted if it exists (to prevent duplicate publishes)
- [ ] PyPI trusted publisher (OIDC) confirmed configured for the repo on pypi.org

---

## Implementation rules

1. **Always assess first.** Read the repo before writing any code.
2. **Work section by section.** Complete Section 1 before starting Section 2.
3. **Prefer editing over creating.** Update existing files; only create files that are
   truly new (e.g. `tox.ini` if it didn't exist, new workflow files).
4. **Do not copy the sample-plugin `root` setting** in `[tool.setuptools_scm]` unless the
   Python package lives in a subdirectory.
5. **Never edit `[tool.uv].constraint-dependencies` directly.** It is machine-managed by
   `edx_lint write_uv_constraints`.
6. **OIDC, not token auth**, for PyPI publishing. The `publish_to_pypi` job must use
   `id-token: write` and `pypa/gh-action-pypi-publish` without credentials.
7. **`uv sync` does not put tools on PATH.** Always use `uv run tox`, never bare `tox`.
8. **All GitHub Actions must be SHA-pinned** with a version comment. Floating tags (`@v6`,
   `@v10.5.3`) are not acceptable. This includes `setup-uv`.
9. **No separate `setup-python` step in CI.** Use `astral-sh/setup-uv` with
   `python-version` to handle Python installation; `setup-python` is redundant and
   inconsistent with the standard.
10. **Retain mypy if it was already in the repo.** Before starting, check if the repo had mypy configured (presence of `mypy` in requirements files, a `make mypy` target, or a tox mypy env). If so: add `mypy` to the `quality` dependency group, keep or add `[tool.mypy]` in `pyproject.toml`, add a `mypy` tox env, and add a `make mypy` target. Do not add mypy to repos that never used it.
12. **Check `requires-python` when bumping the Django/framework version matrix.** If the
    new version drops support for an older Python, bump `requires-python` accordingly and
    remove that Python version from the tox envlist and CI matrix.
11. **After completing all changes**, re-run the status checklist and confirm every item
    is ✅ Done. Flag any items that require out-of-band action (e.g. configuring PyPI
    trusted publisher).

---

## Testing the migration

Run these checks after completing all three sections. All must pass before reporting the migration as done.

### Test 1 — Make targets

Run every Makefile target that does not require network access or external credentials and verify each exits with code 0:

```bash
# Install dev dependencies first
make requirements

# Then run each target
make lint
make format
make test
make docs   # skip if no docs/ directory exists
```

If any target fails, fix the root cause before moving on. Do not skip or mark a target as out-of-scope if it was working before the migration — a regression is a bug.

### Test 2 — Package build and tarball contents

Build the distribution and verify the tarball contains everything it should:

```bash
# Build (prefer uv-based invocation; fall back to plain python -m build)
uv run python -m build
# or, if uv is not available:
#   pip install build && python -m build
```

Then inspect the generated `.tar.gz` under `dist/`:

```bash
# List what was produced
ls dist/

# Extract and inspect the tarball (replace <name>-<version> with the actual filename stem)
tar -tzf dist/<name>-<version>.tar.gz | sort
```

Check that the tarball includes **all** of the following (adjust paths to match the repo layout):

| Expected content | Why it must be present |
|---|---|
| `PKG-INFO` | PEP 566 metadata — generated from `pyproject.toml` |
| `pyproject.toml` | Build recipe — must be included by setuptools |
| `setup.cfg` (if any) | Should **not** be present — it was deleted |
| Source package directory (e.g. `<package>/`) | All `.py` files under the package root |
| `README.rst` or `README.md` | Linked via `readme =` in `[project]` |
| `LICENSE` | Required for PyPI |
| `MANIFEST.in` (if any) | Only if the repo uses inclusion-based manifests |
| Static assets (e.g. `*.html`, `*.css`, `*.js`, `*.png` under the package) | Any non-`.py` file referenced by `package_data` or `MANIFEST.in` |

Flag as a failure if:
- Deleted files (`setup.py`, `setup.cfg`, `CHANGELOG.rst`, `pylintrc`) appear in the tarball — they should not be included after deletion.
- The source package directory is missing or empty.
- Static assets that existed before the migration are absent — their absence will break installs.

### Test 3 — Lockfile consistency

Verify the committed `uv.lock` is in sync with the current `pyproject.toml`. This catches the case where someone edited `pyproject.toml` after running `uv lock`:

```bash
uv lock --check
```

Must exit 0. If it fails, run `uv lock` to regenerate and commit the updated lockfile.

### Test 4 — Dependency group resolution

Verify every declared dependency group resolves without conflicts:

```bash
uv sync --group dev
uv sync --group ci
uv sync --group quality
uv sync --group test
```

A conflict here (e.g. incompatible pins between a group and `[tool.uv].constraint-dependencies`) means the lockfile is broken for that environment. Fix by adjusting `[tool.edx_lint].uv_constraints` and re-running `edx_lint write_uv_constraints` + `uv lock`.

### Test 5 — Tox environment listing

Confirm tox can parse the updated `tox.ini` and resolve all declared environments without actually running them:

```bash
uv run tox --listenvs
```

If this fails (parse error, missing dependency group, unknown runner), the CI matrix will never run. Fix `tox.ini` before proceeding.

### Test 6 — Package importability

Install the package in editable mode and verify the top-level package can be imported cleanly (no missing dependencies, no import-time errors):

```bash
uv pip install -e .
uv run python -c "import <package_name>; print('OK')"
```

Replace `<package_name>` with the actual importable module name (the directory under the repo root that contains `__init__.py`). A clean import confirms that `[project].dependencies` lists everything the package needs at runtime.

### Test 7 — setuptools-scm version resolution

Confirm that `setuptools-scm` can derive a version from git (required for `python -m build` to succeed in CI):

```bash
uv run python -m setuptools_scm
```

This should print a version string (e.g. `1.2.3` or `1.2.3.dev4+gabcdef`). If it prints an error about no git tags or a dirty working tree, note it — the build will fail until a tag exists, which is expected for a brand-new repo. If it errors on a repo that already has tags, the `[tool.setuptools_scm]` config is wrong.

### Test 8 — Ruff lint and format

Run ruff directly (not via make or tox) to confirm the `[tool.ruff]` config in `pyproject.toml` is valid and the codebase passes:

```bash
uv run ruff check .
uv run ruff format --check .
```

Both must exit 0. A config error (e.g. unknown rule code, bad `target-version`) surfaces here as a startup error rather than a lint finding — fix the `[tool.ruff]` table if that happens.

### Test 9 — Wheel contents

`python -m build` produces both a `.tar.gz` and a `.whl`. Inspect the wheel too:

```bash
# List wheel contents (replace filename with actual)
unzip -l dist/<name>-<version>-py3-none-any.whl | sort
```

Check that:
- The package directory and all its `.py` files are present.
- Static assets (templates, JS, CSS, locale files) are included — wheels use `package_data` rules, not `MANIFEST.in`.
- `METADATA` (wheel equivalent of `PKG-INFO`) is present under `<name>-<version>.dist-info/`.
- No compiled `.pyc` files or test files appear in the wheel.

If static assets are missing from the wheel but present in the tarball, add them under `[tool.setuptools.package-data]` in `pyproject.toml`.

### Test 10 — No stale files on disk

Confirm that files which should have been deleted are actually gone:

```bash
for f in setup.py setup.cfg CHANGELOG.rst pylintrc pylintrc_tweaks .coveragerc; do
  [ -f "$f" ] && echo "STALE: $f still exists" || echo "OK: $f absent"
done
[ -d requirements ] && echo "STALE: requirements/ still exists" || echo "OK: requirements/ absent"
```

Any `STALE:` line is a failure — the file must be removed and the deletion committed.

### Test 11 — GitHub Actions workflow YAML validity

Validate the CI and release workflow files are syntactically correct YAML before pushing. Use `actionlint`, not `yamllint` — `yamllint`'s 80-char line limit flags every SHA-pinned action line as an error, producing noise that cannot be fixed without removing the SHA or the version comment. `actionlint` checks for real structural problems (unknown fields, bad expressions, missing secrets) without style rules:

```bash
brew install actionlint   # macOS
actionlint .github/workflows/ci.yml .github/workflows/release.yml
```

A syntax or structural error in a workflow file causes a silent failure on GitHub (the workflow simply never runs). Catching it locally saves a push-and-wait cycle.

### Test 12 — SHA pinning audit

Scan every workflow file for GitHub Actions references that are not SHA-pinned. Floating tags (`@v4`, `@v10.5.3`) are forbidden by the implementation rules:

```bash
# Print any action reference that is NOT a 40-char SHA
grep -rE 'uses:\s+\S+@' .github/workflows/ \
  | grep -v '@[0-9a-f]\{40\}' \
  | grep -v '^#'
```

Any output from this command means there is an un-pinned action. Replace the floating tag with its resolved SHA and add a version comment (e.g. `# v6.0.2`).

### Test 13 — Bundle diff against main

Compare the distribution tarball produced on the PR branch against one built from `main` (or `master`) to catch accidental file exclusions introduced by the migration.

**Step 1 — Build on main/master using a worktree:**

Do **not** use `git stash` + `git checkout` + `git stash pop` — this causes merge conflicts when the stash contains changes that conflict with the branch being checked out. Use a git worktree instead, which gives a clean isolated checkout with no risk to the current working tree:

```bash
# Create an isolated checkout of the base branch
git worktree add /tmp/bundle-worktree-main main   # or: master

# Confirm the key files are there
ls /tmp/bundle-worktree-main/
```

**Step 2 — Build from the worktree:**

The old `setup.py` often reads files like `requirements.txt` using a relative path. `python -m build` (with its default isolated build environment) can fail to find those files because the build frontend may change the working directory. Use `--no-isolation` to build directly in the project directory:

```bash
cd /tmp/bundle-worktree-main
python -m build --no-isolation --outdir /tmp/bundle-main
ls /tmp/bundle-main/
```

If `--no-isolation` fails due to missing build deps, install them first:

```bash
pip install setuptools wheel build
python -m build --no-isolation --outdir /tmp/bundle-main
```

**Step 3 — Build on the PR branch:**

```bash
REPO_DIR=$(git -C /tmp/bundle-worktree-main rev-parse --show-toplevel 2>/dev/null || echo ".")
# Build from the original repo directory (PR branch is already checked out there)
cd /path/to/repo   # or just stay in the repo root

uv run python -m build --outdir /tmp/bundle-pr
ls /tmp/bundle-pr/
```

**Step 4 — Compare tarball contents (strip version prefix first):**

Version strings differ between branches, so strip the `<name>-<version>/` prefix before diffing:

```bash
# Replace <pkg> with the actual package name (e.g. openedx_webhooks)
diff \
  <(tar -tzf /tmp/bundle-main/<pkg>-*.tar.gz | sed 's|[^/]*/||' | sort) \
  <(tar -tzf /tmp/bundle-pr/<pkg>-*.tar.gz   | sed 's|[^/]*/||' | sort)
```

Interpret the diff output:
- Lines starting with `<` — present in **main** but **missing from PR**. These are regressions.
- Lines starting with `>` — present in **PR** but not in main. These are expected additions (new tooling files).

**Step 5 — Compare wheel contents:**

```bash
diff \
  <(unzip -l /tmp/bundle-main/<pkg>-*-py3-none-any.whl | awk '{print $4}' | grep -v '^$\|^Name\|^----\|files$' | sort) \
  <(unzip -l /tmp/bundle-pr/<pkg>-*-py3-none-any.whl   | awk '{print $4}' | grep -v '^$\|^Name\|^----\|files$' | sort)
```

**Step 6 — Clean up the worktree:**

```bash
git worktree remove /tmp/bundle-worktree-main --force
```

**Flag as REGRESSION** if any of the following are missing from the PR bundle but present in main:

| Missing file type | Consequence |
|---|---|
| Any `.py` file under the source package directory | Broken installs — code simply won't be there |
| Static assets (`*.html`, `*.css`, `*.js`, `*.png`, `*.json`, `*.po`, `*.mo`) | UI or locale breakage at runtime |
| `LICENSE`, `README.*`, `pyproject.toml` | Missing PyPI metadata — may fail upload validation |
| `setup.cfg`, `setup.py` (deleted intentionally) | These should NOT appear in main's bundle either; if they do, note it but do not re-add them |

**Common false regressions (expected PR-only additions):**

| Added in PR | Reason |
|---|---|
| `pyproject.toml`, `tox.ini`, `uv.lock` | New tooling files — expected |
| `release.yml`, `commitlint.yml` | New workflow files — expected |
| `.github/workflows/` entries | New or updated CI files — expected |
| `openedx_webhooks.egg-info/scm_file_list.json`, `scm_version.json` | setuptools-scm artifacts — expected |

**Watch for the implicit namespace package trap (wheel only):**

Modern setuptools (via PEP 420) treats any directory without `__init__.py` as an implicit namespace package and may include it in the wheel. Common culprits: `docs/`, `scripts/`, `bin/`. If a non-source directory appears in the PR wheel but not the main wheel, fix it by adding it to the exclude list in `pyproject.toml`:

```toml
[tool.setuptools.packages.find]
exclude = ["tests*", "*.tests", "*.tests.*", "docs*"]
```

Also check the inverse: static assets (templates, JS, CSS) that were in the main wheel but missing from the PR wheel. This happens when `setup.py` used `include_package_data=True` or `package_data` and the new `pyproject.toml` doesn't replicate it. Fix with:

```toml
[tool.setuptools.package-data]
"mypackage" = ["templates/*", "static/**/*"]
```

### Test 14 — Logic change audit

Review the full PR diff and flag any changes that alter runtime behaviour, not just tooling or configuration. A pure migration should contain no logic changes — only file deletions, pyproject.toml additions, tox/Makefile/CI rewrites, and lockfile additions.

```bash
git diff main...HEAD -- '*.py'
```

Read every modified `.py` file in the diff. For each changed function, class, or module-level statement, classify the change as one of:

| Class | Description | Acceptable? |
|---|---|---|
| **Mechanical rename** | Import path changed because a file moved | Yes |
| **Dead code removal** | Unused import or variable deleted | Yes, flag it |
| **Logic change** | Conditional, loop, assignment, or return value changed | No — must be justified |
| **New behaviour** | New function, method, or branch added | No — must be justified |

Report each finding in this format:

```
FILE: <path>
TYPE: <Mechanical rename | Dead code removal | Logic change | New behaviour>
LINES: <line range in the PR diff>
SUMMARY: <one sentence description>
ACTION REQUIRED: <Yes / No>
```

Any finding marked `ACTION REQUIRED: Yes` must be resolved before the PR is considered migration-only. Resolution options:
1. Revert the change and open a separate PR for it.
2. Add a comment in the PR description explaining why the logic change is intentional and safe as part of this migration.

### Test 15 — No hardcoded `__version__` in package source

With `setuptools-scm` deriving the version from git tags, any hardcoded `__version__` string is permanently wrong after the first tag. Check that no such string exists:

```bash
grep -rn '__version__' --include='*.py' .
```

Any match in the package source (i.e. not in test or build tooling) is a failure. Remove the line. If the version is genuinely needed at runtime, replace it with:

```python
from importlib.metadata import version, PackageNotFoundError
try:
    __version__ = version("your-package-name")
except PackageNotFoundError:
    pass
```

A bare `__version__ = "0.1.0"` (or any static string) must not remain after the migration.
