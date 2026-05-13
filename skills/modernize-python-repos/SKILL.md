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

**Reference implementation:** `openedx/sample-plugin` — model after:
- `backend/pyproject.toml`
- `backend/tox.ini`
- `backend/Makefile`
- `.github/workflows/backend-ci.yml`
- `.github/workflows/release.yml`

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
- [ ] `dependencies` is a **static list** under `[project]` (not `dynamic` pointing to a
      requirements file)
- [ ] `[build-system]` uses `setuptools>=61.0` and `setuptools-scm>=8.0`
- [ ] `[tool.setuptools_scm]` is configured (`version_scheme`, `local_scheme`). Do NOT
      set `root` unless the Python package lives in a subdirectory (sample-plugin does
      this, but most repos should not).
- [ ] `setup.py` deleted
- [ ] `setup.cfg` deleted

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
      `dependency_groups` per environment
- [ ] `Makefile` targets updated:
      - `requirements` → `uv sync`
      - `upgrade` → `uv lock --upgrade`
      - `compile-requirements` → remove or replace with `uv lock`
- [ ] CI updated:
      - Install uv: `astral-sh/setup-uv`
      - Install deps: `uv sync --group ci`
      - Run tests: `uv run tox`

---

## Section 3 — Add semantic-release

Goal: pushing a conventional commit to `main` automatically cuts a version, tags it,
and publishes to PyPI via OIDC trusted publisher.

Checklist:
- [ ] `[tool.semantic_release]` added to `pyproject.toml` with `build_command` that sets
      `SETUPTOOLS_SCM_PRETEND_VERSION=$NEW_VERSION` at build time
      (do **not** override `minor_tags` unless there is a specific documented reason)
- [ ] `release.yml` workflow added: runs CI, then `python-semantic-release/python-semantic-release@v10`,
      then publishes to PyPI using **OIDC** (`id-token: write` permission, no token secret)
- [ ] `commitlint.yml` workflow added to enforce conventional commits on PRs
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
8. **After completing all changes**, re-run the status checklist and confirm every item
   is ✅ Done. Flag any items that require out-of-band action (e.g. configuring PyPI
   trusted publisher).
