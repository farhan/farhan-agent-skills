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
- `[tool.edx_lint].uv_constraints` must be a TOML **array** — `uv_constraints = []` for no repo-specific overrides, or `["package>=1.0"]` for pins. Never a string (e.g. `"uv"` is wrong — Python iterates it as `["u", "v"]` and edx-lint writes those as spurious package names). `[tool.uv].constraint-dependencies` is machine-managed (never edit directly)
- **Mypy: retain if already present.** If the repo had mypy configured before the migration (mypy in requirements, a `make mypy` target, or a `[tool.mypy]` section), keep it — add `mypy` to the `quality` dependency group, retain or add a `[tool.mypy]` config block, add a `mypy` tox env, keep a `make mypy` target, **and add `mypy` to the CI workflow matrix `toxenv` list**. Having mypy in `tox.ini`'s `envlist` is not sufficient — it must also appear in the CI matrix so CI actually executes it. Do not add mypy to repos that did not use it before.
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
- **Before rewriting, audit all existing targets.** List every target in the old Makefile and classify each as: (a) keep + adapt (tool still used, just invoked differently), (b) replace (tool deleted but ruff/uv provides equivalent coverage), or (c) drop (depends on a deleted tool with no equivalent AND was not running in CI). Never drop a target without documenting why. App-specific targets (e.g. Heroku deploy, server start) may be dropped if they are clearly infra-only, but err on the side of keeping.
- **Preserve original target ordering.** Keep targets in the same order as the original Makefile. Do not reorder targets — even to match a reference repo — as it inflates the diff with cosmetic noise that obscures real changes.
- **Document every removed target in the PR description.** Any target that cannot be kept (because it depends on a deleted tool with no equivalent) must be listed explicitly in the PR description with the reason (e.g. "`check-setup.py` removed — `setup.py` no longer exists"; "`pylint` removed — replaced by `ruff` via the `lint` target").
- `requirements` target: `uv sync --group dev` + `uv tool install tox --with tox-uv`
- `upgrade` target: `uv run --with edx-lint edx_lint write_uv_constraints pyproject.toml` then `uv lock --upgrade`
- Has `lint`, `format`, `test`, `docs` targets (delegates to tox or uv run ruff)
- `format` target uses `uv run ruff check --fix .` and `uv run ruff format .`
- Has a `mypy` target (`uv run tox -e mypy`) **if the repo used mypy before the migration**
- All other targets that existed before and do not depend on deleted tools must be preserved, with implementation adapted to the new tooling (e.g. `pytest` invocation → `tox -e test`, `pip install` → `uv sync`)

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
- **Branch protection check names are preserved.** Before restructuring CI jobs, check the repo's required status checks: `gh api repos/<org>/<repo>/branches/master/protection --jq '.required_status_checks.checks'`. If a check name like `Tests (ubuntu-latest, 3.12)` is required, the new CI must produce that exact string. GitHub generates check names as `<job.name> (<matrix-value>, <matrix-value>)` when a matrix is used. If renaming a job breaks a required check name, split it into a dedicated job with the old `name:` and the old matrix dimensions so the string is reproduced exactly (see Implementation rule 14).

### release.yml
**Only add `release.yml` if a PyPI publish workflow already existed on `main`/`master`.** Before doing anything, check:

```bash
git ls-tree main .github/workflows/   # or: master
```

Look for any workflow whose name contains `pypi`, `publish`, or `release`. If none exists, **skip this section entirely** — do not add `release.yml`, do not add `[tool.semantic_release]` to `pyproject.toml`, and document the omission in the PR description as:

> `release.yml` / `python-semantic-release` — master had no PyPI publish workflow.

If a publish workflow **did** exist, replace it with `release.yml` following these rules:
- `run_tests` (or `run_ci`) job calls the CI workflow as a reusable workflow
  - Must pass `secrets: inherit`
  - Must have `permissions: contents: read`
- `release` job: checkout + `git reset --hard ${{ github.sha }}` + PSR action
  - `permissions: contents: write` only (no `id-token`)
  - No `setup-uv` step — PSR does not need uv; `build_command` handles everything via pip
  - PSR action SHA-pinned
- `publish_to_pypi` job: **match master's auth mechanism** — read master's old publish workflow first (`git show master:.github/workflows/pypi-publish.yml`). If it used `PYPI_UPLOAD_TOKEN`, use `password: ${{ secrets.PYPI_UPLOAD_TOKEN }}` and omit `id-token: write`. If it used OIDC (`id-token: write`), keep that and omit the password. `pypa/gh-action-pypi-publish` SHA-pinned
- All artifact upload/download actions use consistent major versions (check against the reference repo)
- All actions SHA-pinned

---

## No inventions

Do not introduce any file, setting, threshold, or configuration that is not:
- present in the original repo, or
- explicitly required by this skill or the parent story.

If something didn't exist before the migration, do not add it. Specifically:
- **`codecov.yml`** — always add a minimal `codecov.yml` (header comment + URL reference only) if one does not already exist. If the repo already has one, read it (`git show main:codecov.yml` or `git show master:codecov.yml`) and copy its existing settings verbatim. Do not add any threshold, target, or key that is not already in the main/master version — in particular, do not invent `coverage.status.patch.target` or any other numeric threshold.
- **`fail_under`** — already covered in the pyproject rule above: carry over only if it existed before; otherwise omit entirely.
- **Any other config value** — same principle. If you find yourself setting a value that has no counterpart in the original repo, stop and omit it.

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
- **PyPI publish mechanism alignment across repos** — do not push for org-wide OIDC adoption as part of this migration. But the new `release.yml` **must** match what master's old publish workflow used. OIDC vs token alignment between different repos is out of scope; matching master's own mechanism is not.

---

## Step 0 — Drop support for Python < 3.11

Before touching any other file, check whether the repo declares support for Python versions older than 3.11. If it does, remove that support first — the modern tooling targets Python 3.12.

**Detect old Python support:**

```bash
# Check requires-python / python_requires
grep -rE 'python_requires|requires-python' setup.cfg setup.py pyproject.toml 2>/dev/null

# Check tox envlist for old Python versions
grep -E '\bpy3[0-9]\b' tox.ini 2>/dev/null

# Check CI matrix
grep -rE '"3\.(8|9|10)"' .github/workflows/ 2>/dev/null
```

**If old versions are found, remove them before proceeding:**

- `requires-python` / `python_requires`: bump to `>=3.11` minimum (the main migration will bring it to `>=3.12`)
- Tox envlist: remove `py38`, `py39`, `py310` entries
- CI matrix: remove `"3.8"`, `"3.9"`, `"3.10"` from `python-version` lists
- Classifiers in `setup.cfg` or `pyproject.toml`: remove `Programming Language :: Python :: 3.8` etc.

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

**Also produce two inventory tables before touching any files:**

**Table A — Makefile targets (current state):**
List every `make` target, what tool it invokes, and whether that tool is being removed by this migration. This table is the baseline for the Makefile parity check (Test 16).

**Table B — CI steps (current state):**
List every step in the existing CI workflow and what it runs. This is the baseline for ensuring the new CI matrix covers everything (Implementation rule 13 / Test 16).

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
- [ ] Migrate constraints from `requirements/constraints.txt` (if it existed):
  1. Read the old file: `git show master:requirements/constraints.txt` (or `main`).
  2. Identify any **repo-specific** pins — lines that are not `-c …` includes and not comments. If only a `-c common_constraints.txt` include exists, there are no repo-specific overrides.
  3. Set `[tool.edx_lint].uv_constraints` to a TOML array of those pins (e.g. `["mypackage<2.0"]`); use `[]` if there are none.
  4. Run `uv run --with edx-lint edx_lint write_uv_constraints pyproject.toml` to populate `[tool.uv].constraint-dependencies` from edx-lint's common list plus any repo-specific overrides. This must be done during migration — do **not** leave `constraint-dependencies = []` when a `requirements/constraints.txt` existed.
  5. Then run `uv lock` (**not** `uv lock --upgrade`) to generate the lockfile at current versions. Using `--upgrade` would mix dependency version bumps into the migration diff.
- [ ] If `requirements/constraints.txt` did **not** exist: set `[tool.edx_lint].uv_constraints = []` and leave `[tool.uv].constraint-dependencies = []` — let the first automated upgrade workflow populate it after merge.
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
      - All targets from Table A (pre-migration audit) are present or have a documented replacement
      - `mypy` target present if the repo used mypy before
- [ ] CI updated:
      - `push: branches: [main]` + `pull_request:` + `workflow_call:` triggers
      - `fail-fast: false` in matrix strategy
      - Matrix job name is `${{ matrix.toxenv }}`
      - Only `astral-sh/setup-uv` (SHA-pinned) with `enable-cache: true` + `python-version`; no separate `setup-python` step
      - `uv sync --group ci` then `uv run tox`
      - Matrix `toxenv` list covers every check that was running in CI before (tests, lint, docs) — **plus `mypy` if the repo used mypy**. Being in `tox.ini`'s `envlist` is not enough; the env must appear in the CI matrix to actually run.
      - No tool that ran in the old CI is silently dropped
      - **Consolidate a separate `tests` job into `run_tests` when possible.** If the repo has a standalone `tests` job that only differs from `run_tests` by uploading coverage to Codecov, merge it: add `py312-test` to the `toxenv` matrix in `run_tests` and gate the Codecov upload with `if: matrix.toxenv == 'py312-test'`. Do not preserve a separate job just for Codecov. Exception: if branch protection requires the old check name (see rule 14 / Test 17), a dedicated job must be kept to preserve that name.

---

## Section 3 — Add semantic-release

**Gate: only proceed with this section if a PyPI publish workflow existed on `main`/`master`.** Run `git ls-tree main .github/workflows/` and look for any workflow file whose name contains `pypi`, `publish`, or `release`, or open each workflow and check for PyPI publishing steps. If no such workflow exists, skip this entire section and add a note to the PR description explaining why (see implementation rule 19).

Goal: pushing a conventional commit to `main` automatically cuts a version, tags it,
and publishes to PyPI via OIDC trusted publisher.

Checklist:
- [ ] `[tool.semantic_release]` added to `pyproject.toml` with `build_command` that sets
      `SETUPTOOLS_SCM_PRETEND_VERSION=$NEW_VERSION` at build time using `python -m build`
      (do **not** use `uv build`; do **not** override `minor_tags`)
- [ ] `release.yml` workflow added:
      - `run_tests` job calls CI workflow with `secrets: inherit` + `permissions: contents: read`
      - `release` job: checkout + reset + PSR (SHA-pinned, `changelog: "false"`); `permissions: contents: write`; no `setup-uv` step
      - `publish_to_pypi` job: **match master's auth mechanism** (see implementation rule 6); `pypa/gh-action-pypi-publish` SHA-pinned; all artifact actions SHA-pinned at consistent versions
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
6. **Match master's PyPI auth mechanism.** Before writing `publish_to_pypi`, read master's old publish workflow (`git show master:.github/workflows/pypi-publish.yml` or equivalent) and check whether it used `secrets.PYPI_UPLOAD_TOKEN` (token auth) or `id-token: write` (OIDC trusted publisher). Use the same mechanism in the new `release.yml`. Token → `password: ${{ secrets.PYPI_UPLOAD_TOKEN }}`, no `id-token: write`. OIDC → `id-token: write`, no password input. Do not switch mechanisms — OIDC requires a trusted publisher pre-configured on the PyPI project page, and if that is not set up the publish silently fails after semantic-release has already tagged and bumped the version.
7. **`uv sync` does not put tools on PATH.** Always use `uv run tox`, never bare `tox`.
8. **All GitHub Actions must be SHA-pinned** with a version comment. Floating tags (`@v6`,
   `@v10.5.3`) are not acceptable. This includes `setup-uv`.
9. **No separate `setup-python` step in CI.** Use `astral-sh/setup-uv` with
   `python-version` to handle Python installation; `setup-python` is redundant and
   inconsistent with the standard.
10. **Retain mypy if it was already in the repo.** Before starting, check if the repo had mypy configured (presence of `mypy` in requirements files, a `make mypy` target, or a tox mypy env). If so: add `mypy` to the `quality` dependency group, keep or add `[tool.mypy]` in `pyproject.toml`, add a `mypy` tox env, add a `make mypy` target, **and add `mypy` to the CI matrix `toxenv` list**. Mypy has no ruff equivalent — it cannot be dropped. Do not add mypy to repos that never used it.
11. **Never remove a tool without a direct replacement.** Ruff replaces pylint/pycodestyle/pydocstyle/isort. Nothing replaces mypy, bandit, or other specialized tools — if those were present, they must remain. Before removing any linter or checker from the repo, verify that ruff provides equivalent coverage for every rule that tool was enforcing.
12. **Preserve all Makefile targets that don't depend on deleted tools.** Before rewriting the Makefile, list every target and determine what each does. Targets that invoke deleted tools (pip-compile, setup.py, pylint) may be replaced or removed if ruff/uv covers them. All other targets — including repo-specific ones (e.g. `fulltest`, `testschema`) — must be adapted to use the new tooling and kept. App-specific deployment targets (Heroku, Docker, etc.) may be dropped only if they are clearly infra-only and unrelated to Python tooling. Keep targets in their original order — do not reorder them. List every dropped target in the PR description with the reason.
13. **CI must maintain parity with master/main.** Every test, lint, or tool that ran in CI before the migration must run in CI after. Check the old workflow file carefully. Enumerate what ran (e.g., `make test`, `make lint`, `mypy`), then confirm each has a corresponding tox env in the new CI matrix. Gaps are regressions.
14. **Preserve required branch protection check names.** Before restructuring the CI workflow, run `gh api repos/<org>/<repo>/branches/master/protection --jq '.required_status_checks.checks'` to see what check names the branch protection rule requires. GitHub derives check names from `<job.name> (<matrix-value1>, <matrix-value2>)` — renaming a job or changing its matrix breaks the required check silently (it shows as "not run" rather than failing). If the new CI uses `name: ${{ matrix.toxenv }}` but the old required check was `Tests (ubuntu-latest, 3.12)`, split the test job out as a dedicated job: `name: Tests`, `runs-on: ${{ matrix.os }}`, `matrix: os: [ubuntu-latest], python-version: ["3.12"]` — this reproduces the exact required string. Admin access to update branch protection is not always available on Open edX repos; prefer preserving the check name.
15. **Check `requires-python` when bumping the Django/framework version matrix.** If the
    new version drops support for an older Python, bump `requires-python` accordingly and
    remove that Python version from the tox envlist and CI matrix.
16. **After completing all changes**, re-run the status checklist and confirm every item
    is ✅ Done. Flag any items that require out-of-band action (e.g. configuring PyPI
    trusted publisher).
18. **Consolidate a standalone `tests` job into `run_tests` when its only extra step is Codecov upload.** Add `py312-test` to the `toxenv` matrix and gate the upload with `if: matrix.toxenv == 'py312-test'`. Multi-OS expansion via a separate `os` matrix is not a requirement unless explicitly asked for. Skip this consolidation only when branch protection requires the old check name (e.g. `Tests (ubuntu-latest, 3.12)`) — in that case, keep the dedicated job to preserve the name.
20. **Never delete `upgrade-python-requirements.yml` — update it.** This workflow is an automated bot that opens dependency-bump PRs on a schedule. `make upgrade` is what a developer runs manually; it is not a replacement for the workflow. The reusable workflow at `openedx/.github` calls `make upgrade` internally, so it automatically runs `uv lock --upgrade` on uv-based repos without any changes to its invocation. Keep the workflow and update only what is needed for parity with master/main:
    - Change `default: 'main'` → `default: 'master'` (or vice versa) to match the repo's actual default branch name
    - Change `branch || 'main'` → `branch || 'master'` (or vice versa) to match
    - **Do NOT add or change `team_reviewers`, `email_address`, `user_reviewers`, or `send_success_notification`.** Keep those fields exactly as they appear on master/main — if they are commented out on master, leave them commented out. Do not fill them in or uncomment them.

21. **Never delete cross-repo or release-automation workflows unless they directly depend on deleted functionality.** Workflows triggered on tag push (e.g. a workflow that bumps the package version in a downstream repo) read the tag from `$GITHUB_REF`, not from `__init__.py`. They are unaffected by the tooling migration and must be kept. Only delete a workflow if it explicitly reads or writes the hardcoded `__version__` string in `__init__.py`, invokes pip-compile, or references a file that was deleted (e.g. `requirements/base.in`). When in doubt, keep it. Document every deleted workflow in the PR description with the precise reason.

19. **Only add `release.yml` and `[tool.semantic_release]` if a PyPI publish workflow existed on `main`/`master`.** Before touching anything in Section 3, run `git ls-tree main .github/workflows/` and inspect each workflow for PyPI publishing steps (`pypi`, `publish`, `release` in the filename or a `pypa/gh-action-pypi-publish` step inside). If no such workflow exists, skip Section 3 entirely — add neither `release.yml` nor `[tool.semantic_release]` — and include this line in the PR description: "`release.yml` / `python-semantic-release` — master had no PyPI publish workflow."
17. **`docs/` exclusion from PyPI package.** Before including `docs/` in the distribution,
    check whether the main/master branch was already packaging it. Inspect the base branch's
    `pyproject.toml` (`[tool.setuptools.packages.find]` exclude/include, `package-data`),
    `MANIFEST.in`, and `setup.cfg` to determine if `docs/` was explicitly included. If it
    was, preserve that behavior in the migrated config. If it was not (the common case), ensure
    `docs/` is excluded — add `"docs*"` to the `exclude` list under
    `[tool.setuptools.packages.find]` if needed. Never introduce `docs/` packaging where it
    didn't exist on main/master.

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

### Test 14 — Logic change audit (informational only)

Review the full PR diff for changes that alter runtime behaviour. This test is **informational only** — logic changes embedded in a migration PR are the author's decision and are out of scope for this skill to approve or reject. Do not flag them as failures and do not suggest splitting the PR.

```bash
git diff main...HEAD -- '*.py'
```

Read every modified `.py` file in the diff. For each changed function, class, or module-level statement, classify the change as one of:

| Class | Description | Note |
|---|---|---|
| **Mechanical rename** | Import path changed because a file moved | Expected |
| **Ruff formatting** | Quote style, indentation, import order normalised by ruff | Expected — skip |
| **Dead code removal** | Unused import or variable deleted | Note only |
| **Logic change** | Conditional, loop, assignment, or return value changed | Note only |
| **New behaviour** | New function, method, or branch added | Note only |

Report **ruff-formatting-only** changes as a group (no per-file detail needed). Report any genuine logic or behaviour changes as a brief note for awareness — but do not mark them `ACTION REQUIRED` and do not recommend a separate PR.

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
    __version__ = "0.0.0"
```

The `except` block **must** assign a fallback — never use bare `pass`. Without a fallback, `from package import __version__` raises `AttributeError` on any checkout that has not been `pip install -e .`'d.

A bare `__version__ = "0.1.0"` (or any static string) must not remain after the migration.

### Test 16 — Makefile target and CI parity

Compare the inventory tables you produced in Step 1 against the post-migration state.

**Makefile parity:**

```bash
# List all targets in the new Makefile
grep -E '^[a-zA-Z_-]+:' Makefile | sed 's/:.*//'
```

For each target from Table A (pre-migration):
- If it invoked a deleted tool (pip-compile, pylint, setup.py) → confirm an equivalent target exists using ruff/uv
- If it invoked a retained tool (pytest, mypy, sphinx) → confirm the target still exists with updated invocation
- If it was infra-only (Heroku deploy, Docker build) → note the deliberate removal in the PR description

Any target from Table A that is missing from the new Makefile without a documented reason is a regression. Every removed target must appear in the PR description with the reason.

**CI parity:**

For each step from Table B (pre-migration CI), confirm there is a corresponding entry in the new CI matrix `toxenv` list:

```bash
# Show the toxenv matrix in the CI workflow
grep -A5 'toxenv:' .github/workflows/ci.yml  # or python-tests.yml
```

A tool that ran in the old CI must run in the new CI. Common gaps to check:
- `mypy` — must be in `toxenv` list if repo had mypy
- `docs` build — must be a tox env in the matrix, not just referenced locally
- Any additional linter or checker that ran as a separate step

Flag any CI step from Table B that has no corresponding new matrix entry.

### Test 17 — Branch protection check name coverage

Before pushing, confirm the new CI produces every check name that branch protection requires:

```bash
# List required status checks on the base branch
gh api repos/<org>/<repo>/branches/master/protection \
  --jq '.required_status_checks.checks[].context'
```

For each required check name, verify the new CI will produce it. GitHub constructs check names as:
- **No matrix:** `<job.name>`
- **With matrix:** `<job.name> (<matrix-val1>, <matrix-val2>)`

Common failure pattern: old CI had `name: Tests` + `matrix: os: [ubuntu-latest], python-version: ["3.12"]` → check name `Tests (ubuntu-latest, 3.12)`. New CI collapses it into `name: ${{ matrix.toxenv }}` → check name `py312-test`. The required check is never produced, the PR is permanently blocked, and admin access is needed to update branch protection.

**Fix (no admin access needed):** Split the test env into a dedicated job that reproduces the original name+matrix:

```yaml
  tests:
    name: Tests
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest]
        python-version: ["3.12"]
    steps:
      # same steps as run_tests job, but hardcode the tox env:
      - run: uv run tox -e py312-test
```

This generates `Tests (ubuntu-latest, 3.12)` and satisfies the branch protection rule without any repo admin involvement.

### Test 18 — Dependency package parity

Verify that every package declared in master's `requirements/*.in` files is still present somewhere in `[project].dependencies` or `[dependency-groups]` in `pyproject.toml`. This catches silent drops during the migration.

Run from the repo root (requires Python 3.11+ for `tomllib`):

```bash
python3 << 'PYEOF'
import re, subprocess, tomllib

# Tools legitimately removed by this migration (replaced by ruff or uv)
REPLACED_BY_MIGRATION = {
    'pylint', 'pylint-pytest', 'pylint-django',
    'isort', 'pycodestyle', 'pydocstyle', 'flake8',
    'pip-tools',
}

def normalize(name):
    name = re.sub(r'\[.*?\]', '', name).strip()
    return name.lower().replace('_', '-').replace('.', '-')

def parse_in_file(content):
    pkgs = set()
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('-r') or line.startswith('-c') or line.startswith('-e'):
            continue
        if 'github.com' in line or line.startswith('git+'):
            m = re.search(r'egg=([^&\s]+)', line)
            if m:
                pkgs.add(normalize(m.group(1))); continue
            m = re.search(r'/([^/@]+?)(?:\.git)?(?:@[^\s]*)?(?:\s|$|#)', line)
            if m:
                pkgs.add(normalize(m.group(1))); continue
        name = re.split(r'[><=!~\s;@\[]', line)[0]
        if name:
            pkgs.add(normalize(name))
    return pkgs

in_files = ['base.in', 'test.in', 'dev.in', 'doc.in']
master_pkgs = set()
for f in in_files:
    r = subprocess.run(['git', 'show', f'master:requirements/{f}'], capture_output=True, text=True)
    if r.returncode == 0:
        master_pkgs |= parse_in_file(r.stdout)

with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)

pr_pkgs = set()
for dep in data.get('project', {}).get('dependencies', []):
    pr_pkgs.add(normalize(dep.split('@')[0]))
for group_deps in data.get('dependency-groups', {}).values():
    for dep in group_deps:
        if isinstance(dep, str):
            pr_pkgs.add(normalize(dep.split('@')[0]))

missing = master_pkgs - pr_pkgs - REPLACED_BY_MIGRATION
added   = pr_pkgs - master_pkgs

print("MISSING from PR (in master .in files but not in pyproject.toml):")
for p in sorted(missing): print(f"  MISSING: {p}")
if not missing: print("  (none — all packages accounted for)")

print("\nADDED in PR (not in any master .in file):")
for p in sorted(added): print(f"  ADDED: {p}")
if not added: print("  (none)")

print(f"\nMaster total: {len(master_pkgs)} | PR total: {len(pr_pkgs)}")
if missing:
    raise SystemExit(f"\nFAIL: {len(missing)} package(s) missing from pyproject.toml")
PYEOF
```

**Pass:** No `MISSING:` lines printed, exit code 0.

**Fail:** Any `MISSING:` line means a package from the old requirements was dropped. For each missing package:
- If it was replaced by ruff (e.g. another pylint plugin) → add it to `REPLACED_BY_MIGRATION` in the script and confirm ruff covers it
- If it is a genuine runtime or test dependency → add it to the appropriate `[dependency-groups]` in `pyproject.toml` and re-run `uv lock`

**`ADDED:` lines are expected** — `ruff`, `tox`, `tox-uv` are new tooling from this migration and will always appear here. Any other unexpected addition should be investigated before merging.

### Test 19 — Constraints migration

If `requirements/constraints.txt` existed on master/main, verify it was properly migrated to `pyproject.toml`.

**Step 1 — Read the old constraints file:**

```bash
git show master:requirements/constraints.txt 2>/dev/null || git show main:requirements/constraints.txt 2>/dev/null || echo "No constraints.txt on base branch"
```

Note any repo-specific pins — lines that are not `-c …` includes and not comments.

**Step 2 — Verify `[tool.edx_lint].uv_constraints` captures repo-specific pins:**

```bash
python3 -c "
import tomllib
with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)
uv_constraints = data.get('tool', {}).get('edx_lint', {}).get('uv_constraints', 'MISSING')
if uv_constraints == 'MISSING':
    print('FAIL: [tool.edx_lint].uv_constraints not found in pyproject.toml')
elif not isinstance(uv_constraints, list):
    print(f'FAIL: uv_constraints must be a TOML array, got: {type(uv_constraints).__name__}')
else:
    print(f'OK: uv_constraints = {uv_constraints}')
"
```

**Step 3 — Verify `[tool.uv].constraint-dependencies` was populated:**

```bash
python3 -c "
import tomllib
with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)
constraint_deps = data.get('tool', {}).get('uv', {}).get('constraint-dependencies', 'MISSING')
if constraint_deps == 'MISSING':
    print('FAIL: [tool.uv].constraint-dependencies not found — run edx_lint write_uv_constraints')
elif not constraint_deps:
    print('FAIL: constraint-dependencies is empty — edx_lint write_uv_constraints was not run during migration')
else:
    print(f'OK: constraint-dependencies = {constraint_deps}')
"
```

This must be non-empty if `requirements/constraints.txt` existed on master — even a file that only contained a `-c common_constraints.txt` include expands to a non-empty list of common constraints.

**Step 4 — Verify repo-specific pins are present in `constraint-dependencies`:**

For each repo-specific pin noted in Step 1 (those beyond the common `-c` include), confirm it appears in `[tool.uv].constraint-dependencies`:

```bash
grep -F "<repo-specific-pin>" pyproject.toml   # replace with the actual pin
```

**Step 5 — Verify the lockfile respects the constraints:**

```bash
uv lock --check
```

Then spot-check a constrained package in `uv.lock` (e.g. for `Django<6.0`):

```bash
grep -A2 'name = "django"' uv.lock
```

The resolved version must satisfy the constraint.

**Pass:** `[tool.edx_lint].uv_constraints` is a TOML array; `[tool.uv].constraint-dependencies` is non-empty (contains at least the edx-lint common constraints); all repo-specific pins from the old `constraints.txt` appear in `constraint-dependencies`; `uv lock --check` exits 0.

**Fail:** Either section is missing; `constraint-dependencies` is empty when it should be populated; a repo-specific pin from the old `constraints.txt` is absent; or `uv lock --check` fails.

### Test 20 — PyPI publish auth mechanism matches master

Verify that `release.yml`'s `publish_to_pypi` job uses the same authentication mechanism as master's old publish workflow.

**Step 1 — Read master's publish workflow:**

```bash
git show master:.github/workflows/pypi-publish.yml 2>/dev/null \
  || git show main:.github/workflows/pypi-publish.yml 2>/dev/null \
  || git show master:.github/workflows/release.yml 2>/dev/null \
  || echo "No publish workflow found on master"
```

**Step 2 — Identify which auth mechanism master used:**

- `user: __token__` + `password: ${{ secrets.PYPI_UPLOAD_TOKEN }}` → **token auth**
- `id-token: write` permission with no `password:` input → **OIDC**

**Step 3 — Confirm the new `release.yml` matches:**

```bash
# Check which mechanism the new publish_to_pypi job uses
echo "=== id-token permission ==="
grep "id-token" .github/workflows/release.yml || echo "(none)"
echo "=== password / PYPI_UPLOAD_TOKEN ==="
grep -E "password:|PYPI_UPLOAD_TOKEN" .github/workflows/release.yml || echo "(none)"
```

**Pass:** The new `release.yml` uses the same mechanism as master. Token → `password: ${{ secrets.PYPI_UPLOAD_TOKEN }}` present, no `id-token: write`. OIDC → `id-token: write` present, no `password:` input.

**Fail:** The mechanism changed. A switch from token → OIDC requires a trusted publisher pre-configured on the PyPI project page before merging (verify with the repo maintainer). A switch from OIDC → token requires the `PYPI_UPLOAD_TOKEN` secret to exist in the repo. Either mismatch must be resolved before merging — revert to master's mechanism unless the maintainer explicitly confirms the new one is ready.

---

### Test 21 — Django AppConfig signal imports preserved

**Only for Django apps** (check `[project.entry-points."lms.djangoapp"]` in pyproject.toml).

Django apps use `AppConfig.ready()` to register signal handlers. When migrating from pylint to ruff, these imports appear "unused" to static analysis but are **critical** — without them, signal handlers won't register.

**Step 1 — Find AppConfig classes:**

```bash
grep -r "class.*AppConfig" --include="*.py" | grep "apps.py"
```

**Step 2 — Check each AppConfig for signal imports inside `ready()`:**

```bash
grep -A 5 "def ready" <file> | grep "import.*signals"
```

**Pattern to validate:**

```python
# ✅ CORRECT: Import inside ready() with ruff suppression
class ForumConfig(AppConfig):
    def ready(self) -> None:
        """Import Signals."""
        import forum.signals  # noqa: F401
```

**Pass:** Signal imports are present inside `ready()` with `# noqa: F401` (not `# pylint: disable=...`).

**Fail:** 
- Signal import was removed entirely → handlers won't register, search indexing/cache invalidation breaks silently
- Import moved to module level → breaks lazy-loading pattern used before
- Pylint directive not replaced → ruff will flag as unused

**Recovery:** Restore the import inside `ready()` with `# noqa: F401` to preserve the original pattern and ensure handlers are registered.

---

## PR description

Write short 1-liner bullets — no paragraphs. Each line states what changed and why in one sentence.

**Always include** a reference to the parent story:

> Part of https://github.com/openedx/public-engineering/issues/499

**Template:**

```
Modernize <repo-name> to uv + pyproject.toml (PEP 621/735) + python-semantic-release.

Part of https://github.com/openedx/public-engineering/issues/499.

Changes:
- Drop Python <3.11 support; set requires-python = ">=3.12"
- Replace setup.cfg/setup.py with pyproject.toml (PEP 621 static metadata)
- Replace pip-compile with uv + PEP 735 dependency groups; commit uv.lock
- Replace pylint/isort/pycodestyle with ruff (check + format)
- Move coverage config from .coveragerc into pyproject.toml
- Update tox.ini to use tox-uv with uv-venv-lock-runner
- Update CI to use astral-sh/setup-uv; SHA-pin all actions; add workflow_call trigger
- Add python-semantic-release + release.yml  [omit if no PyPI publish workflow existed]

Removed Makefile targets:
- `<target>` — <one-line reason>
```
