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
- **Ruff replaces pylint/pycodestyle/pydocstyle/isort.** `[tool.ruff]` must have:
  - `line-length = 120`
  - `target-version = "py312"`
  - `[tool.ruff.lint]` select: `E`, `W`, `F`, `I`, `B`, `C4`, `UP`, `DJ`; ignore: `E501`
  - `[tool.ruff.lint.isort]` `known-third-party = ["django", "xblock"]`
  - `[tool.ruff.format]` `quote-style = "double"`, `indent-style = "space"`
- **Coverage config in pyproject** — not in a separate `.coveragerc`:
  - `[tool.coverage.run]` with `branch = true`, `source`, `omit` patterns
  - `[tool.coverage.report]` with `fail_under = 70`, `show_missing = true`, `exclude_lines`
  - `[tool.coverage.html]` with `directory = "htmlcov"`
- `[tool.semantic_release]` has `build_command` using `python -m build` (never `uv build`)

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

### Makefile
- `requirements` target: `uv sync --group dev` + `uv tool install tox --with tox-uv`
- `upgrade` target: `uv run --with edx-lint edx_lint write_uv_constraints pyproject.toml` then `uv lock --upgrade`
- Has `lint`, `format`, `test`, `docs` targets (delegates to tox or uv run ruff)
- `format` target uses `uv run ruff check --fix .` and `uv run ruff format .`

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
- [ ] **Ruff configured** — `[tool.ruff]`, `[tool.ruff.lint]` (E, W, F, I, B, C4, UP, DJ;
      ignore E501), `[tool.ruff.lint.isort]` (known-third-party), `[tool.ruff.format]`
      (quote-style, indent-style)
- [ ] **Coverage config in pyproject** — `[tool.coverage.run/report/html]` present;
      `.coveragerc` deleted
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
10. **Check `requires-python` when bumping the Django/framework version matrix.** If the
    new version drops support for an older Python, bump `requires-python` accordingly and
    remove that Python version from the tox envlist and CI matrix.
11. **After completing all changes**, re-run the status checklist and confirm every item
    is ✅ Done. Flag any items that require out-of-band action (e.g. configuring PyPI
    trusted publisher).
