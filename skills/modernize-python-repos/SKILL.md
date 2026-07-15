---
name: modernize-python-repos
description: >
  Modernize an Open edX Python repo to use uv, pyproject.toml (PEP 621/735), a src/ layout,
  and python-semantic-release. Five modes: Implement (create the migration PR from scratch),
  Re-implement (update an existing migration PR with new commits), Test/Verify (run the
  full test suite against a PR and report every result), PR description (generate a
  formatted PR body for a completed migration), and Separate-ruff (split ruff out of an
  existing modernization PR into its own stacked follow-up PR). Use when asked to modernize
  a Python package, migrate from pip-compile/setup.cfg, update a modernization PR, verify a
  modernization PR, generate/write the PR description, or separate/split ruff out into its
  own PR.
allowed-tools: Read Glob Grep Bash Write Edit
---

# Modernize Python Repos

You are helping modernize an Open edX Python package to the standard modern tooling:
- `pyproject.toml` (PEP 621/735) replaces `setup.py`, `setup.cfg`, `requirements/*.txt`
- `uv` replaces `pip-compile` for dependency management
- a `src/` package layout replaces the top-level package directory
- `python-semantic-release` automates versioning and PyPI publishing (PyPI repos only)

**Parent story:** [`openedx/public-engineering#506`](https://github.com/openedx/public-engineering/issues/506) — all requirements defined there are mandatory and must be implemented in full. Do not skip or defer any item from that issue unless the user explicitly says to ignore the parent story requirements.

**Reference implementations:** `openedx/xblocks-extra` and `openedx/xblock-core` — model after their:
- `pyproject.toml` (including the `src/` layout and coverage config)
- `tox.ini`
- `Makefile`
- `.github/workflows/ci.yml`
- `.github/workflows/release.yml`

---

## Cycle decisions (public-engineering#506 meeting)

These decisions were finalized in the [#506 meeting](https://github.com/openedx/public-engineering/issues/506#issuecomment-4981671896) and define the scope of this cycle. They override any older framing:

- **Ruff is OUT of scope this cycle.** It causes large auto-format diffs and review overhead, and pylint cannot be fully dropped until stricter type checking is in place. **Do not add ruff.** Retain the repo's existing lint tooling (pylint/isort/pycodestyle/pydocstyle) exactly as it is on master/main — only adapt *how* it is invoked (via uv/tox-uv). Ruff adoption is its own separate epic; splitting ruff out of a PR that already bundles it is [Mode 5](#mode-5--separate-ruff).
- **Any repo with a `setup.py` is in scope** — regardless of whether it publishes to PyPI. Whether a repo *should* publish to PyPI is a separate evaluation; it does not gate modernization.
- **`src/` layout is IN scope this cycle** (precedent: `xblocks-extra`, `xblock-core`). Move the package under `src/` by default. Skip the move only if the user explicitly says to leave the layout unchanged for a given repo.
- **PyPI publishing uses OIDC trusted publishing**, and the release workflow is named `release.yml` consistently across repos. The trusted publisher must be configured on PyPI before a repo can publish — that is an out-of-band prerequisite (handled by the Axim team) and a **merge blocker**, not a review blocker.
- **`tox.ini` is added where missing**, for consistency across the org.
- **Semantic versioning** follows the 0.x-vs-1.0+ rules (see the [zero-version guard](#releaseyml--semantic-release-gated) and Test 24): the same `pyproject.toml` config handles both via `allow_zero_version` + `major_on_zero`.

---

## Modes

Pick the mode from the user's request. If the request doesn't clearly indicate one, ask before starting.

| Mode | When | What you do |
|---|---|---|
| **1. Implement** | Repo has no migration PR yet; user asks to modernize it | Create the migration from scratch: [Mode 1 workflow](#mode-1--implement), driven by the [Target state](#target-state) and verified with the [Test suite](#test-suite--tests-125) |
| **2. Re-implement** | A migration PR already exists and needs changes (review feedback, failed checks, skill updates) | Update the existing PR with **new commits only**: [Mode 2 workflow](#mode-2--re-implement) |
| **3. Test/Verify** | User asks to test or verify a migration PR | Run all 25 tests and report every result in one table — no fixes: [Mode 3 workflow](#mode-3--testverify) |
| **4. PR description** | User asks to generate or write the PR description | Collect migration facts from the diff and produce a formatted PR body: [Mode 4 workflow](#mode-4--pr-description) |
| **5. Separate-ruff** | A modernization PR already bundles the pylint→ruff swap and ruff must be deferred to its own PR | Leave the original PR untouched (it becomes the future ruff PR); open one new PR — `farhan/modernize-python-repo` (non-ruff, off master) — then footnote the original PR pointing at it: [Mode 5 workflow](#mode-5--separate-ruff) |

All modes share the same two references below: **Target state** (what the migrated repo must look like) and the **Test suite** (how to verify it). Never restate or re-derive these per mode — they are the single source of truth.

**Versioning path shorthand** used throughout: *PyPI repo* = a PyPI publish workflow exists on master/main (release gate passes); *no-PyPI repo* = no such workflow (release gate fails). Determine this once at the start and apply consistently to all versioning-related rules and tests.

---

## Target state

Everything in this section must be true of the migrated repo. In Implement/Re-implement modes, make it true; in Test/Verify mode, the Test suite checks it.

### No ruff (this cycle)

Ruff is **not** added in this cycle (see [Cycle decisions](#cycle-decisions-public-engineering506-meeting)). The migrated repo must:
- contain **no** `[tool.ruff]` / `[tool.ruff.*]` sections in `pyproject.toml`
- **not** list `ruff` in any dependency group
- **not** delete `pylintrc` / `pylintrc_tweaks`
- retain pylint/isort/pycodestyle/pydocstyle in the `quality` dependency group and in the lint tox env, exactly as master/main used them — only the invocation changes (via uv/tox-uv)
- leave `*.py` files unformatted by ruff — no quote-style, import-order, or whitespace churn

Test 1 is a hard gate on this: if ruff is present, the test suite halts.

### pyproject.toml

- **Versioning — fork based on the release gate** (same gate as [release.yml](#releaseyml--semantic-release-gated)):
  - **No PyPI publish workflow on master/main (common case):** use a **static** `version = "<x.y.z>"` in `[project]`. Read the version from master: `git show master:<pkg>/__init__.py | grep __version__` or from `setup.cfg`'s `version =` field. `[build-system]` requires only `setuptools>=61.0` — do **not** add `setuptools-scm`. Do **not** add a `[tool.setuptools_scm]` block or `dynamic = ["version"]`.
  - **PyPI publish workflow exists:** `[build-system]` uses `setuptools>=61.0` and `setuptools-scm>=8.0`; `dynamic = ["version"]` only (not `["dependencies"]`); `[tool.setuptools_scm]` has `version_scheme = "only-version"` and `local_scheme = "no-local-version"`. Do **not** set `root` unless the Python package lives in a subdirectory.
- `[project]` has all metadata: name, description, readme, requires-python, license (SPDX string), authors, classifiers, keywords, urls
- `classifiers` includes Django framework classifiers: `Framework :: Django`, `Framework :: Django :: 4.2`, `Framework :: Django :: 5.2`
- `dependencies` is a **static list** (not dynamic from a requirements file)
- `[tool.uv]` has `package = true`
- `[dependency-groups]` covers: `test-base`, `test`, `quality`, `doc`, `ci`, `dev` — plus version-matrix groups (e.g. `django42`, `django52`) only when needed. The `quality` group keeps the repo's existing linters (pylint/isort/pycodestyle/pydocstyle, plus mypy if present) — it does **not** gain ruff.
- `[tool.uv].conflicts` lists the mutually exclusive Django version groups
- **Package discovery — `src/` layout:** `[tool.setuptools.packages.find]` has `where = ["src"]` and keeps the repo's `exclude` patterns (see [Package layout](#package-layout--src)).
- **Constraints** — migrated from `requirements/constraints.txt` if it existed on master/main:
  1. Read the old file: `git show master:requirements/constraints.txt` (or `main`).
  2. Identify any **repo-specific** pins — lines that are not `-c …` includes and not comments. If only a `-c common_constraints.txt` include exists, there are no repo-specific overrides.
  3. Set `[tool.edx_lint].uv_constraints` to a TOML **array** of those pins (e.g. `["mypackage<2.0"]`); `[]` if there are none. Never a string (e.g. `"uv"` is wrong — Python iterates it as `["u", "v"]` and edx-lint writes those as spurious package names).
  4. Run `uv run --with edx-lint edx_lint write_uv_constraints pyproject.toml` to populate `[tool.uv].constraint-dependencies`. This must be done during migration — do **not** leave `constraint-dependencies = []` when a `constraints.txt` existed. Never edit `constraint-dependencies` by hand — it is machine-managed by that command.
  5. Run `uv lock` (**not** `uv lock --upgrade`) to generate the lockfile at current versions — `--upgrade` would mix dependency version bumps into the migration diff.

  If `constraints.txt` did **not** exist: set `uv_constraints = []` and leave `constraint-dependencies = []` — the first automated upgrade workflow populates it after merge.
- **Mypy: retain if already present.** If the repo had mypy configured before the migration (mypy in requirements, a `make mypy` target, a tox mypy env, or a `[tool.mypy]` section), keep it: `mypy` in the `quality` dependency group, a `[tool.mypy]` config block, a `mypy` tox env, a `make mypy` target (`uv run tox -e mypy`), **and `mypy` in the CI workflow matrix `toxenv` list**. Being in `tox.ini`'s `envlist` is not sufficient — it must appear in the CI matrix so CI actually executes it. Do not add mypy to repos that never used it.
- **Lint tooling retained (no ruff).** Keep whatever linters the repo ran on master (pylint, isort, pycodestyle, pydocstyle, etc.) in the `quality` group, in the lint tox env, in the Makefile, and in CI. Do not remove or replace them; only adapt the invocation to uv/tox-uv. `pylintrc` and `pylintrc_tweaks` stay.
- **Coverage config in pyproject** — not in a separate `.coveragerc`:
  - `[tool.coverage.run]` with `branch = true`, `source`/`source_pkgs`, `omit` patterns — configured so coverage measures the package under `src/` (model after the reference repo; use `source_pkgs = ["<pkg>"]` or a `[tool.coverage.paths]` mapping as needed)
  - `[tool.coverage.report]` with `show_missing = true`, `exclude_lines`
  - `[tool.coverage.html]` with `directory = "htmlcov"`
  - **`fail_under` rule:** read the old `.coveragerc` and `setup.cfg` first. If a `fail_under` value exists, carry it over exactly. If no threshold was set before, omit `fail_under` entirely — do not invent one.
- `[tool.semantic_release]` — **only if the release gate passes** (see [release.yml](#releaseyml--semantic-release-gated)): `build_command` sets `SETUPTOOLS_SCM_PRETEND_VERSION=$NEW_VERSION` and uses `python -m build` (never `uv build`); do not override `minor_tags`. **Zero-version guard:** check the latest git release tag — if the repo is on `0.x.y` (or has no release tags yet), also set `allow_zero_version = true` and `major_on_zero = false` to prevent semantic-release from bumping `0.x.y → 1.0.0` on the first `feat:` commit:
  ```bash
  git tag --sort=version:refname | grep -E '^v?[0-9]+\.[0-9]+' | tail -1
  ```
  If the output is `v0.x.y` (or empty — no release tags yet), add both settings. If the output is `v1.x.y` or higher, omit them.
- **`docs/` exclusion:** check whether main/master was already packaging `docs/` (base branch's `pyproject.toml` packages config, `MANIFEST.in`, `setup.cfg`). If it was, preserve that; if not (the common case), ensure `docs/` is excluded — add `"docs*"` to `exclude` under `[tool.setuptools.packages.find]` if needed. Never introduce `docs/` packaging where it didn't exist.
- **`__version__` in `__init__.py`:** Do not define `__version__` in any `__init__.py` regardless of the versioning path. The version is owned by `pyproject.toml` in both cases. For PyPI repos, if `__version__` is genuinely needed at runtime use the `importlib.metadata` pattern shown in Test 15. For no-PyPI repos, simply omit it — there is no reason to re-expose the static version through `__init__.py`.

### Package layout — src/

The importable package moves under a `src/` directory (in scope this cycle; precedent: `xblocks-extra`, `xblock-core`). **Default: perform the move.** Skip only if the user explicitly says to leave the layout unchanged for this repo.

- Move the package with history preserved: `git mv <pkg> src/<pkg>` (repeat for multiple top-level packages).
- Do **not** move `tests/` if master ran them from the repo root — match the reference repo's choice. Only move a `tests/` dir if it lived inside the package.
- `[tool.setuptools.packages.find]` → `where = ["src"]`, keep the existing `exclude` patterns.
- Coverage config points at the package so it is measured under `src/` (see the coverage bullet above).
- Update any hardcoded references to the old top-level package path in `tox.ini`, `Makefile`, `MANIFEST.in`, docs `conf.py`, and CI.
- If the repo already uses a `src/` layout, this is a no-op — confirm and move on.

### Files to delete

- `setup.py`
- `setup.cfg`
- `requirements/` directory
- `CHANGELOG.rst` — **only if the release gate passes** (PyPI publish workflow exists and semantic-release is being added). For no-PyPI repos, **keep `CHANGELOG.rst`** — there is no automated release-notes alternative and deleting it removes the only release history record.
- `.coveragerc` (config moves into pyproject.toml)

**Do NOT delete** `pylintrc` or `pylintrc_tweaks` — ruff is out of scope, so pylint stays. (These are only removed by [Mode 5](#mode-5--separate-ruff) when ruff is adopted in its own PR.)

### tox.ini

- Add `tox.ini` if the repo doesn't have one (some repos inherited from other orgs lack it — standardize).
- `requires = tox-uv>=1`
- All environments use `runner = uv-venv-lock-runner`
- All environments use `dependency_groups =` (not `deps =`)
- Has a `quality` (or `lint`) env that runs the repo's **existing** linters (pylint/isort/pycodestyle/pydocstyle as on master) — not ruff.
- Test envs named `py312-django{42,52}` or similar matrix form
- Has a `mypy` env **if the repo used mypy before the migration**

### Makefile

- **Audit before rewriting.** List every target in the old Makefile (Table A in Step 1) and classify each as: (a) keep + adapt (tool still used, just invoked differently), (b) drop (depends on a deleted tool — i.e. pip-compile/setup.py — with no equivalent AND was not running in CI). Never drop a target without documenting why. App-specific deployment targets (Heroku, Docker, server start) may be dropped only if clearly infra-only and unrelated to Python tooling — err on the side of keeping. **Lint/quality targets are kept as-is (pylint), only adapted to uv/tox — not replaced by ruff.**
- **Preserve original target ordering.** Do not reorder targets — even to match a reference repo — as it inflates the diff with cosmetic noise that obscures real changes.
- **Document every removed target in the PR description** with the reason (e.g. "`check-setup.py` removed — `setup.py` no longer exists").
- `requirements` target: `uv sync --group dev` + `uv tool install tox --with tox-uv`
- `upgrade` target: `uv run --with edx-lint edx_lint write_uv_constraints pyproject.toml` then `uv lock --upgrade`
- `lint`/`quality` target: `tox -e quality` (or `tox -e lint`) — running the existing pylint-based checks
- `test` and `docs` targets present (delegate to tox or uv run)
- `mypy` target (`uv run tox -e mypy`) **if the repo used mypy before the migration**
- All other pre-existing targets that don't depend on deleted tools must be preserved, with implementation adapted to the new tooling (e.g. `pytest` invocation → `tox -e test`, `pip install` → `uv sync`) — including repo-specific ones (e.g. `fulltest`, `testschema`)

### CI workflow (python-tests.yml or ci.yml)

- Triggers: `workflow_call:` (so release.yml can reuse it) + `push: branches: [main]` + `pull_request:`
- `strategy.fail-fast: false`
- Matrix job `name:` is `${{ matrix.toxenv }}` (not a hardcoded string)
- Uses **only** `astral-sh/setup-uv` — no separate `actions/setup-python` step (setup-uv's `python-version` handles Python installation; setup-python is redundant)
  - `astral-sh/setup-uv` must have `enable-cache: true` and `python-version: "${{ matrix.python-version }}"`
- All actions SHA-pinned with a version comment (e.g. `@de0fac2e… # v6.0.2`) — floating tags (`@v6`, `@v10.5.3`) are not acceptable, including for `setup-uv`
- `uv sync --group ci` then `uv run tox -e ${{ matrix.toxenv }}`
- **CI parity with master/main.** Every test, lint, or tool that ran in the old CI (Table B in Step 1) must have a corresponding tox env in the new CI matrix — including the pylint/quality checks, `mypy` if the repo used it, and `docs` if a docs build ran. Gaps are regressions.
- **Consolidate a standalone `tests` job into `run_tests`** when its only extra step is Codecov upload: add `py312-test` to the `toxenv` matrix and gate the upload with `if: matrix.toxenv == 'py312-test'`. Do not preserve a separate job just for Codecov. Multi-OS expansion via a separate `os` matrix is not a requirement unless explicitly asked for. Exception: branch protection (next bullet).
- **Branch protection check names are preserved.** Before restructuring CI jobs, check the required status checks: `gh api repos/<org>/<repo>/branches/master/protection --jq '.required_status_checks.checks'`. GitHub generates check names as `<job.name> (<matrix-val1>, <matrix-val2>)` when a matrix is used — renaming a job or changing its matrix breaks the required check silently (it shows as "not run", permanently blocking the PR). If a check like `Tests (ubuntu-latest, 3.12)` is required, split the test env into a dedicated job with the old `name:` and old matrix dimensions so the exact string is reproduced (see Test 17 for the YAML). Admin access to update branch protection is not always available on Open edX repos; prefer preserving the check name.

### release.yml + semantic-release (gated)

**Gate: only add `release.yml`, `commitlint.yml`, and `[tool.semantic_release]` if a PyPI publish workflow existed on `main`/`master`.** Check first:

```bash
git ls-tree main .github/workflows/   # or: master
```

Look for any workflow whose name contains `pypi`, `publish`, or `release`, or a `pypa/gh-action-pypi-publish` step inside. If none exists, **skip this entire section** — add neither `release.yml` nor `[tool.semantic_release]` — and document the omission in the PR description as:

> `release.yml` / `python-semantic-release` — master had no PyPI publish workflow.

If a publish workflow **did** exist, replace it with `release.yml` (named exactly `release.yml`, consistently across repos):
- `run_tests` (or `run_ci`) job calls the CI workflow as a reusable workflow, with `secrets: inherit` and `permissions: contents: read`
- `release` job: checkout + `git reset --hard ${{ github.sha }}` + PSR action (SHA-pinned, `changelog: "false"`); `permissions: contents: write` only (no `id-token` on this job); no `setup-uv` step — PSR does not need uv, `build_command` handles everything via pip
- `publish_to_pypi` job: **OIDC trusted publishing.** Use `permissions: id-token: write` and `pypa/gh-action-pypi-publish` with **no** `password:` input and **no** `PYPI_UPLOAD_TOKEN`. This is the org-wide decision for this cycle (#506), applied even if master used token auth.
  - **Out-of-band prerequisite / merge blocker:** OIDC requires a trusted publisher pre-configured on the PyPI project page (PyPI project → *Publishing* → *Add a new publisher*, pointing at `openedx/<repo>`, workflow `release.yml`, no environment). The Axim team (Feanil) enables these. Until it is confirmed, the PR **must not be merged** — the first publish would silently fail after semantic-release has already tagged and bumped the version. Flag this in the PR description `## Code reviewer notes` and confirm with the maintainer before merge.
  - After the switch, the old `PYPI_UPLOAD_TOKEN` secret can be removed from the repo (out-of-band, note it — do not attempt it from the migration).
  - `pypa/gh-action-pypi-publish` SHA-pinned.
- All artifact upload/download actions SHA-pinned at consistent major versions (check against the reference repo)
- `commitlint.yml` workflow added to enforce conventional commits on PRs — **this is a behavioral change for all contributors to this repo** (every future PR must use a conventional commit subject line: `feat:`, `fix:`, `chore:`, etc.). Flag this impact explicitly in the PR description `## Code reviewer notes` section and mention it to the repo maintainer before opening the PR for review.
- Old `pypi-publish.yml` deleted (to prevent duplicate publishes)

### Other workflows

- **Never delete `upgrade-python-requirements.yml` — update it.** It is an automated bot that opens dependency-bump PRs on a schedule; `make upgrade` is the manual counterpart, not a replacement. The reusable workflow at `openedx/.github` calls `make upgrade` internally, so it automatically runs `uv lock --upgrade` on uv-based repos with no invocation changes. Update only for parity with master/main:
  - `default: 'main'` ↔ `default: 'master'` to match the repo's actual default branch
  - `branch || 'main'` ↔ `branch || 'master'` to match
  - **Do NOT add or change `team_reviewers`, `email_address`, `user_reviewers`, or `send_success_notification`.** Keep those fields exactly as on master/main — if commented out there, leave them commented out.
- **Never delete cross-repo or release-automation workflows unless they directly depend on deleted functionality.** Workflows triggered on tag push (e.g. bumping the package version in a downstream repo) read the tag from `$GITHUB_REF`, not from `__init__.py` — they are unaffected by this migration and must be kept. Only delete a workflow if it explicitly reads/writes the hardcoded `__version__`, invokes pip-compile, or references a deleted file (e.g. `requirements/base.in`). When in doubt, keep it. Document every deleted workflow in the PR description with the precise reason.

### codecov.yml and no inventions

Do not introduce any file, setting, threshold, or configuration that is not present in the original repo or explicitly required by this skill or the parent story. Specifically:
- **`codecov.yml`** — always add a minimal `codecov.yml` (header comment + URL reference only) if one does not already exist. If the repo already has one, read it (`git show main:codecov.yml` or `master:`) and copy its settings verbatim. Do not add any threshold, target, or key that is not already in the main/master version — in particular, do not invent `coverage.status.patch.target` or any other numeric threshold.
- **`fail_under`** — covered by the pyproject rule above: carry over only if it existed before; otherwise omit entirely.
- **Any other config value** — same principle. If you find yourself setting a value with no counterpart in the original repo, stop and omit it.

### Out of scope

These items look like gaps when comparing two repos but are **not in scope** and should not be changed:

- **Ruff adoption** — deferred to its own epic this cycle (see [Cycle decisions](#cycle-decisions-public-engineering506-meeting)). Do not add ruff. If a PR already bundles ruff, use [Mode 5](#mode-5--separate-ruff) to split it out.
- **`django` upper bound in `[project].dependencies`** — e.g. `"django>=4.2"` without `<6.0` — downstream constraint management is out of scope
- **MANIFEST.in philosophy** — inclusion-based vs exclusion-based depends on the repo's file layout; do not normalize this (but do fix package paths that changed due to the `src/` move)
- **CI workflow file name** — `python-tests.yml` vs `ci.yml` is cosmetic; do not rename unless explicitly asked
- **Tox quality env name** — `quality` vs `lint` is acceptable either way; do not change a working name
- **`uv tool install tox --with tox-uv` in `requirements` target** — this is the standard pattern; do not remove it in favor of `uv run`
- **`upload-artifact` / `download-artifact` major versions in `release.yml`** — aligning artifact action versions across repos is out of scope; do not flag or change these

---

## Process rules

Apply in Implement and Re-implement modes:

1. **Always assess first.** Read the repo before writing any code.
2. **Work section by section.** Complete each workflow step before starting the next.
3. **Prefer editing over creating.** Update existing files; only create files that are truly new (e.g. `tox.ini` if it didn't exist, new workflow files).
4. **`uv sync` does not put tools on PATH.** Always use `uv run tox`, never bare `tox`.
5. **Do not add or remove tools beyond the migration's scope.** `uv` replaces `pip-compile`; that is the only tooling swap this cycle. **Ruff is not added.** Linters (pylint/isort/pycodestyle/pydocstyle), mypy, bandit, and any other specialized tool present on master must remain, with the invocation adapted to uv/tox.
6. **Check `requires-python` when bumping the Django/framework version matrix.** If the new version drops support for an older Python, bump `requires-python` accordingly and remove that Python version from the tox envlist and CI matrix.
7. **Test failures are fixed, not skipped.** In Implement and Re-implement modes, a failing test from the Test suite means fixing the root cause before reporting done. In Test/Verify mode, failures are only reported — never fixed. Test 1 (ruff gate) is special: if it fails, **halt** and follow its instructions rather than continuing.

---

## Mode 1 — Implement

Create the migration PR from scratch. Work through these steps in order; the [Target state](#target-state) defines what each file must look like.

### Step 0 — Drop support for Python < 3.12

Dropping old Python versions is **in scope for this migration** — not a separate PR or prerequisite. The target is `requires-python = ">=3.12"` (set in Step 2 during pyproject.toml consolidation); this step removes the legacy version entries from tox, CI, and classifiers.

```bash
# Check requires-python / python_requires
grep -rE 'python_requires|requires-python' setup.cfg setup.py pyproject.toml 2>/dev/null

# Check tox envlist for old Python versions
grep -E '\bpy3[0-9]\b' tox.ini 2>/dev/null

# Check CI matrix
grep -rE '"3\.(8|9|10|11)"' .github/workflows/ 2>/dev/null
```

If old versions are found, remove them first:
- `requires-python` / `python_requires`: leave as-is for now — Step 2 will set `>=3.12` in `pyproject.toml`
- Tox envlist: remove `py38`, `py39`, `py310`, `py311` entries; target is `py312`
- CI matrix: remove `"3.8"`, `"3.9"`, `"3.10"`, `"3.11"` from `python-version` lists
- Classifiers: remove `Programming Language :: Python :: 3.8` / `3.9` / `3.10` / `3.11` entries

### Step 1 — Assess current state

Read the repo and produce a status checklist covering the whole Target state. Mark each item ✅ Done, ❌ Not done, or ⚠️ Partial, with a brief note.

Files to read:
- `pyproject.toml` (if exists)
- `setup.py` / `setup.cfg` (if exists)
- `tox.ini` (if exists)
- `Makefile` (if exists)
- `requirements/` directory listing (if exists)
- `.github/workflows/` — all workflow files

**Also produce two inventory tables before touching any files:**

**Table A — Makefile targets (current state):** every `make` target, what tool it invokes, and whether that tool is being removed by this migration (only pip-compile/setup.py targets are). Baseline for the Makefile audit and Test 16.

**Table B — CI steps (current state):** every step in the existing CI workflow and what it runs. Baseline for CI parity and Test 16.

### Step 2 — Consolidate package metadata into pyproject.toml

Goal: single `pyproject.toml` per the [pyproject.toml target state](#pyprojecttoml) (metadata, static dependencies, versioning, coverage, lint tooling retained), remove any `__version__` from `__init__.py`, and delete the [files to delete](#files-to-delete) (`setup.py`, `setup.cfg`, `CHANGELOG.rst` per gate, `.coveragerc`). Keep `pylintrc`/`pylintrc_tweaks`. Apply the versioning fork: static `version =` in `[project]` when no PyPI publish workflow exists; `setuptools-scm` + `dynamic = ["version"]` when one does.

### Step 2b — Adopt the src/ layout

Move the package under `src/` per [Package layout](#package-layout--src), unless the user explicitly asked to leave the layout unchanged. Use `git mv <pkg> src/<pkg>`, set `where = ["src"]` in `[tool.setuptools.packages.find]`, fix coverage config, and update any hardcoded paths in tox/Makefile/MANIFEST/docs/CI.

### Step 3 — Switch dependency management from pip-compile to uv

Goal: PEP 735 `[dependency-groups]`, migrated constraints, a committed `uv.lock`, tox via `tox-uv`, and CI using `uv run tox` — per the target-state sections for [pyproject.toml](#pyprojecttoml) (dependency groups + constraints procedure), [tox.ini](#toxini), [Makefile](#makefile), and [CI workflow](#ci-workflow-python-testsyml-or-ciyml). Delete the `requirements/` directory once migrated. Keep the existing linters in the `quality` group.

### Step 4 — Add semantic-release

Run the gate check in the [release.yml target state](#releaseyml--semantic-release-gated). If it passes, add `[tool.semantic_release]`, `release.yml` (OIDC trusted publishing), and `commitlint.yml`, and delete the old publish workflow, per that section — and flag the OIDC trusted-publisher config as an out-of-band merge blocker. If it fails, skip and note the omission for the PR description.

### Step 5 — Verify

Re-run the Step 1 status checklist and confirm every item is ✅ Done. Flag any items that require out-of-band action (e.g. configuring the PyPI trusted publisher). Then run the full [Test suite](#test-suite--tests-125) — all tests must pass (fixing root causes as needed) before reporting the migration as done. Report the results as one table per the [reporting format](#reporting-format).

### Step 6 — PR description

Write it per the [PR description format](#pr-description-format) section.

### Step 7 — Fix CI checks

After the PR is created and commits are pushed, wait 3 minutes for CI checks to initialize, then invoke the `/fix-checks` skill to make any failing checks green.

---

## Mode 2 — Re-implement

Update an existing migration PR. History is append-only: all changes land as **new commits** — never amend, rebase, squash, or force-push the branch. This holds for every mode: even [Mode 5](#mode-5--separate-ruff) leaves the original branch untouched and does its split on two brand-new branches.

### Step 1 — Identify the PR

If the user did not specify which PR to update, **ask for it** (URL or number) before doing anything else. Then check it out and gather context:

```bash
gh pr checkout <number>
gh pr view <number> --json title,body,comments,reviews,statusCheckRollup
```

Read the PR description, all review comments, and CI check results.

### Step 2 — Determine what needs to change

Sources of required changes, in priority order:
1. Explicit instructions from the user
2. Reviewer comments / requested changes on the PR
3. Failing CI checks
4. Drift from the current [Target state](#target-state) (e.g. the skill was updated since the PR was made) — run the relevant tests from the [Test suite](#test-suite--tests-125) to find gaps

List the planned changes before making them.

### Step 3 — Apply updates as new commits

- Make the changes and commit them on top of the existing branch, using conventional commit messages (commitlint may be enforced on the repo).
- **Reversions:** if something previously committed on the PR must be undone, revert it in a **new commit** — `git revert <sha>` when the commit reverts cleanly, otherwise a manual reversal commit. Never rewrite the branch history to remove it.
- Group logically distinct changes into separate commits so reviewers can follow what changed since their last review.

### Step 4 — Re-verify

Run the tests from the [Test suite](#test-suite--tests-125) that cover the areas you touched — or the full suite if the changes were broad. Fix any failures (per Process rule 7) before finishing. Report results as one table per the [reporting format](#reporting-format).

### Step 5 — Update the PR description

Keep the description accurate: update the removed-targets list, gate notes, and any other affected sections per the [PR description format](#pr-description-format) rules. Push the new commits and post a brief PR comment summarizing what changed and why, if review feedback was addressed.

### Step 6 — Fix CI checks

After new commits are pushed, wait 3 minutes for CI checks to initialize, then invoke the `/fix-checks` skill to make any failing checks green.

---

## Mode 3 — Test/Verify

Verify an existing migration PR against the full Test suite. **Report only — do not fix, commit, or modify anything.** Fixes belong to Re-implement mode.

### Step 1 — Identify the PR

If a PR (or branch) isn't specified and the working tree isn't already on the migration branch, ask which PR to verify. Check it out with `gh pr checkout <number>`.

### Step 2 — Run every test

Run **all** tests from the [Test suite](#test-suite--tests-131), in order, Test 1 through Test 31.

**Test 1 is a hard gate.** If ruff is present, Test 1 fails: **stop running the remaining tests**, report only Test 1's failure, and follow its instructions (ask the user to drop the ruff implementation or split it via [Mode 5](#mode-5--separate-ruff), then re-run). Do not report the other tests as passed or failed when Test 1 halts — record them as `⏭️ Skipped (halted at Test 1 — ruff present)`.

Otherwise, do not stop at the first failure and do not skip a test without recording why (e.g. `make docs` with no `docs/` directory, Test 20 when the release gate excluded release.yml, Test 8 or Test 22 based on the versioning path, Test 23 when no PR has been opened yet, Test 24 when the release gate excluded release.yml, Test 25 when the user opted out of the src/ move, Tests 27/31/32 when the release gate excluded release.yml). Record the outcome of every single test.

### Step 3 — Report

Follow the [reporting format](#reporting-format) exactly. Every test appears, pass or fail, in one table.

### Reporting format

Used whenever test results are reported (all modes). Rules:

- **One table, all tests.** Every test appears as a row, identified as `Test#XX`. Do **not** split passing and failing results into separate tables, and do **not** omit any test — passes, failures, and skips are all listed.
- Result values: `✅ Pass`, `❌ Fail`, `⏭️ Skipped (<reason>)`, `🛑 Halt` (Test 1 only), `ℹ️ Info` (Test 14 only). A skip without a reason is not allowed.
- After the table, add a detail section **per failed test** (what failed, the evidence/output, what would fix it), Test 14's informational notes, Test 22's versioning path note (skip reason or pass evidence), and Test 23's PR description check (skippable if no PR has been opened yet).

Template:

```
## Test results

| Test | Name | Result | Notes |
|---|---|---|---|
| Test#01 | Ruff absence gate | ✅ Pass | no ruff present |
| Test#02 | Make targets | ✅ Pass | all targets exit 0 |
| Test#03 | Package build and tarball contents | ✅ Pass | |
| Test#04 | Lockfile consistency | ❌ Fail | uv lock --check exits 1 |
| ... | ... | ... | ... |
| Test#22 | Static versioning parity | ⏭️ Skipped (PyPI publish workflow exists — setuptools-scm used) | |
| Test#23 | PR description completeness | ⏭️ Skipped (no PR opened yet) | |
| Test#25 | src/ layout | ✅ Pass | package under src/<pkg> |

## Failure details

### Test#04 — Lockfile consistency
<evidence + what would fix it>
```

If Test 1 halts, the table lists Test#01 as `🛑 Halt` and every other row as `⏭️ Skipped (halted at Test 1 — ruff present)`, followed by the halt instructions.

---

## Mode 4 — PR description

Generate the PR body for a completed or in-progress modernization. Use standalone ("write the PR description") or as the final step after Mode 1/2.

### Step 1 — Identify what changed

Collect the migration facts from the diff. Run every command — the outputs feed the content accuracy rules in Step 2:

```bash
# What files changed
git diff master...HEAD --stat

# Versioning path — determines which Versioning paragraph to write
grep -E 'setuptools-scm|^version\s*=|dynamic' pyproject.toml

# src/ layout — detect whether the package was moved
[ -d src ] && echo "src/ layout: PRESENT" || echo "src/ layout: ABSENT"

# Python support — detect if requires-python actually changed
echo "=== Old Python requirement ==="
git show master:setup.cfg 2>/dev/null | grep 'python_requires' || \
  git show master:pyproject.toml 2>/dev/null | grep 'requires-python' || echo "(not found)"
echo "=== New Python requirement ==="
grep 'requires-python' pyproject.toml

# release.yml — determines whether semantic-release was added or must be listed as "Not included"
[ -f .github/workflows/release.yml ] && echo "release.yml: PRESENT" || echo "release.yml: ABSENT"

# Deleted files — list only what actually existed on master AND is gone now
echo "=== File deletion status ==="
for f in setup.py setup.cfg CHANGELOG.rst .coveragerc; do
  if git show master:"$f" &>/dev/null 2>&1; then
    [ -f "$f" ] && echo "KEPT: $f" || echo "DELETED: $f"
  else
    echo "NOT ON MASTER: $f (do not list as deleted)"
  fi
done
if git ls-tree master requirements &>/dev/null 2>&1; then
  [ -d requirements ] && echo "KEPT: requirements/" || echo "DELETED: requirements/"
else
  echo "NOT ON MASTER: requirements/ (do not list as deleted)"
fi

# Sanity: pylintrc must NOT be deleted this cycle (ruff is out of scope)
for f in pylintrc pylintrc_tweaks; do
  if git show master:"$f" &>/dev/null 2>&1; then
    [ -f "$f" ] && echo "OK KEPT: $f" || echo "WARNING: $f deleted — ruff must be out of scope; restore it"
  fi
done

# Removed Makefile targets — targets present on master but absent from new Makefile
echo "=== Targets removed (in master, gone in PR) ==="
comm -23 \
  <(git show master:Makefile 2>/dev/null | grep -E '^[a-zA-Z_-]+:' | sed 's/:.*//' | sort) \
  <(grep -E '^[a-zA-Z_-]+:' Makefile 2>/dev/null | sed 's/:.*//' | sort)

echo "=== Targets kept (must NOT appear in removed table) ==="
comm -12 \
  <(git show master:Makefile 2>/dev/null | grep -E '^[a-zA-Z_-]+:' | sed 's/:.*//' | sort) \
  <(grep -E '^[a-zA-Z_-]+:' Makefile 2>/dev/null | sed 's/:.*//' | sort)

# Any non-obvious changes (constraints, codecov, branch protection, etc.)
git diff master...HEAD -- .github/workflows/
```

### Step 2 — Write the PR description

Use the template in [PR description format](#pr-description-format). Apply these content accuracy rules — each maps a Step 1 fact to what goes in the description:

- **Summary headline:** include `+ python-semantic-release` only if `release.yml: PRESENT` in Step 1.
- **`[- Move package into a src/ layout]` bullet:** include only if `src/ layout: PRESENT`.
- **`[- Add python-semantic-release + release.yml (OIDC publishing)]` bullet:** include only if `release.yml: PRESENT`.
- **`[- Add commitlint.yml ...]` bullet:** include only if `release.yml: PRESENT`. Always pair with a `## Code reviewer notes` bullet warning that conventional commit format is now enforced on all future PRs.
- **`CHANGELOG.rst` in deleted files line:** include only if `release.yml: PRESENT` (release gate passed). Omit from the deleted files list for no-PyPI repos — it was kept.
- **`[- Drop Python X.Y support]` bullet:** include only if `requires-python` changed vs master.
- **Deleted files line:** list only entries marked `DELETED:` in Step 1 — not `KEPT:` and not `NOT ON MASTER:`. Never list `pylintrc`/`pylintrc_tweaks` (they are kept this cycle).
- **Removed Makefile targets table:** populate from the `=== Targets removed ===` list only. Any target in `=== Targets kept ===` must not appear in this table, even if its implementation was rewritten.
- **`## Not included` section:** present if and only if `release.yml: ABSENT`. Omit entirely if `release.yml: PRESENT`.
- **`## Python X.Y dropped` section:** present if and only if `requires-python` changed vs master. Omit otherwise.
- **Versioning section:** write the `[Static]` paragraph if no `setuptools-scm` in `pyproject.toml`; write the `[Dynamic]` paragraph if `setuptools-scm` is present. Write exactly one, never both.
- **OIDC note:** if `release.yml: PRESENT`, add a `## Code reviewer notes` bullet flagging the PyPI trusted-publisher (OIDC) config as an out-of-band merge blocker.

---

## Mode 5 — Separate-ruff

Create one new clean PR from an existing modernization PR that bundles ruff, leaving the original PR untouched. Use when a modernization PR already bundles the pylint→ruff swap and ruff must be deferred to its own epic — per the [public-engineering#506 meeting decision](https://github.com/openedx/public-engineering/issues/506#issuecomment-4981671896): *"Ruff is out of scope for this cycle … Any ruff-related changes already in current PRs should be reverted or moved out. Ruff adoption will be its own separate epic."*

**End state:**
- The **original PR is never modified** — its branch, commits, and diff stay exactly as they are. It remains open and will serve as the future ruff adoption PR when that epic begins; only its description gets a footer note pointing at the new non-ruff PR.
- A new PR on branch **`farhan/modernize-python-repo`**, **cut from the latest `master`/`main`**, contains every modernization change **except** ruff; its lint tooling stays exactly as master/main (pylint/isort/pycodestyle/pydocstyle untouched).

**This mode never rewrites history and never force-pushes.** The original branch is read-only here; the new branch is cut fresh from master. This keeps the append-only rule in [Mode 2](#mode-2--re-implement) intact.

### What counts as "ruff" (the split boundary)

Everything in the left column stays in the **original PR** (which becomes the future ruff PR). Everything else goes into the **new non-ruff `farhan/modernize-python-repo` PR**.

| Ruff-owned (stays in original PR, future ruff epic) | Non-ruff PR (as master had it) |
|---|---|
| `[tool.ruff]`, `[tool.ruff.lint]`, `[tool.ruff.lint.isort]`, `[tool.ruff.format]` in `pyproject.toml` | pyproject metadata, `dependencies`, `[dependency-groups]`, versioning, `[tool.coverage.*]`, `[tool.uv]`, `src/` layout |
| `ruff` added to the `quality` dependency group | `pylint`/`isort`/`pycodestyle`/`pydocstyle` kept in the quality group exactly as master |
| Deletion of `pylintrc`, `pylintrc_tweaks` | `pylintrc`, `pylintrc_tweaks` retained (as master had them) |
| tox `quality`/`lint` env invoking `ruff check` / `ruff format` | tox lint/quality env keeps master's pylint/isort/pycodestyle invocation |
| Makefile `lint` switched to ruff, and any net-new `format` target running ruff | Makefile lint/quality/style targets keep master's pylint-based commands; `requirements`/`upgrade`/`test`/`docs` stay |
| CI matrix `quality`/`lint` toxenv that runs ruff | CI keeps master's lint step |
| `# pylint: disable=unused-import` → `# noqa: F401` translations | pylint suppression directives kept as-is (still pylint era) |
| Every ruff auto-format hunk in `*.py` (quote style, import sort, whitespace, line wrapping) | `*.py` files kept at master's formatting; genuine non-format modernization edits (e.g. `__version__` handling, src/ move) stay |

Rule of thumb: **anything master already had goes to the non-ruff PR unchanged; anything that exists only to serve ruff stays in the original PR.** uv, tox-uv, SHA-pinning, semantic-release, commitlint, the Python-version drop, and the src/ layout are **not** ruff — they belong in the non-ruff PR.

### Step 1 — Identify the original PR and capture state

Ask for the PR if the user did not specify one. Then (read-only against the original branch):

```bash
gh pr view <number> --json number,title,headRefName,baseRefName,body,url
gh pr checkout <number>
BASE=$(gh pr view <number> --json baseRefName --jq '.baseRefName')     # master or main
ORIG_BRANCH=$(gh pr view <number> --json headRefName --jq '.headRefName')
git fetch origin "$BASE"
ORIG=$(git rev-parse HEAD)          # original PR head — read-only reference
MERGE_BASE=$(git merge-base "origin/$BASE" HEAD)
echo "orig-branch=$ORIG_BRANCH base=$BASE orig=$ORIG merge-base=$MERGE_BASE"
```

Confirm the PR actually contains ruff (`grep -q 'tool\.ruff' pyproject.toml`). If it does not, stop — there is nothing to split.

Note the branch name this mode creates (fixed):

```bash
NONRUFF_BRANCH=farhan/modernize-python-repo   # cut from origin/$BASE, holds everything except ruff
```

### Step 2 — Build the non-ruff branch

Build the new branch from the latest base. The original branch (`$ORIG_BRANCH`) is **never checked out for writing, reset, or pushed** in this mode.

**Non-ruff branch (`farhan/modernize-python-repo`), cut from the latest base:**

```bash
git checkout -B "$NONRUFF_BRANCH" "origin/$BASE"   # fresh branch off latest master/main
git read-tree -u --reset "$ORIG"                   # worktree == full original PR (ruff included) as a starting point
```

Now transform the working tree so ruff is gone and lint tooling matches master, using the split table above:

```bash
# Restore ruff-owned files that master owned differently
git checkout "origin/$BASE" -- pylintrc pylintrc_tweaks 2>/dev/null || true
# For every *.py that differs from master ONLY by ruff formatting, restore master's copy;
# for a *.py with a genuine non-format edit, hand-edit to drop only the format hunks and keep the edit.
git diff "origin/$BASE" -- '*.py'
# Edit pyproject.toml: remove [tool.ruff*]; restore master's quality group (pylint/isort/…); drop `ruff`.
# Edit tox.ini / Makefile / CI: restore master's lint/quality/style commands.
```

Confirm the non-ruff branch reproduces master's lint behavior (pylint, not ruff), then commit:

```bash
uv run tox -e quality   # or the repo's lint target — must behave as on master (pylint)
git add -A
git commit -m "<original PR's subject — with any ruff mention removed from the body>"
NONRUFF_HEAD=$(git rev-parse HEAD)
```

### Step 3 — Show the branch for review

```bash
echo "=== Non-ruff branch ($NONRUFF_BRANCH, base $BASE) ==="; git show "$NONRUFF_HEAD" --stat
echo "=== What stays in original PR (ruff-only delta) ==="; git diff "$NONRUFF_HEAD" "$ORIG" --stat
```

Summarize for the user: what landed in the non-ruff branch, what stays in the original PR (the ruff changes), and confirm pylint config is retained as on master. Note explicitly that the original branch/PR has not been touched.

### Step 4 — Verification checkpoint (blocking)

Ask the user exactly: **"Verified (y/n)?"** and stop.

Do **not** push or open a PR until the user answers `y`. On `n`, collect what's wrong and rebuild the branch (return to Step 2). (Nothing has been pushed and the original branch is untouched, so a rebuild is always safe.)

### Step 5 — Push the new branch and open the PR

Only after the user answers `y`:

```bash
git push -u origin "$NONRUFF_BRANCH"

# Non-ruff PR — based on master/main
gh pr create --base "$BASE" --head "$NONRUFF_BRANCH" \
  --title "<original PR's title — without ruff>" \
  --body-file /tmp/nonruff_pr_body.md
```

The original PR keeps its own base and diff — untouched. It will serve as the ruff adoption PR in a future epic.

### Step 6 — Write descriptions and cross-link

**Non-ruff PR description** — use the standard [PR description format](#pr-description-format), with ruff removed: no "replace pylint/isort with ruff" bullet, no `pylintrc`/`pylintrc_tweaks` deletion, and a note that pylint is retained exactly as on master. Near the top, add: `Split out of <original-PR-link>; ruff retained there for adoption in a future epic (per public-engineering#506).`

**Update the original PR — description footer only, no code changes.** Append (do not remove existing content) a note at the **end** of the original PR body via `gh pr edit <original-number> --body-file /tmp/orig_pr_body.md`:

```
---

The non-ruff modernization work has been extracted into a focused PR per the decision in the main story ([public-engineering#506](https://github.com/openedx/public-engineering/issues/506#issuecomment-4981671896)):

- Modernization (no ruff): <non-ruff-PR-link>

This PR retains the ruff adoption and can be rebased onto `farhan/modernize-python-repo` once that lands, to serve as the ruff epic PR.
```

Leave the original PR **open**; do not close, force-push, or otherwise modify its branch.

**Cross-linking:** the original PR footer links to the non-ruff PR; the non-ruff PR links back to the original. Optionally post a short comment on the original PR pointing at the new non-ruff PR.

### Step 7 — Fix CI checks

After the new PR is created and commits are pushed, wait 3 minutes for CI checks to initialize, then invoke the `/fix-checks` skill to make any failing checks green.

---

## PR description format

This is the authoritative template used by Mode 1 Step 6, Mode 2 Step 5, and Mode 4.

````
> [!IMPORTANT]
> PR implemented with the assistance of [Claude Code](https://claude.com/claude-code), human-reviewed and improved before pushing to code review.

## Summary

Modernize `<repo-name>` to uv + pyproject.toml (PEP 621/735) + src/ layout[+ python-semantic-release].

Part of https://github.com/openedx/public-engineering/issues/506.

- Replace `setup.py`/`setup.cfg` with `pyproject.toml` (PEP 621 static metadata)
- Switch from pip-compile to `uv` with PEP 735 dependency groups; commit `uv.lock`
- Move the package into a `src/` layout   ← include only if the src/ move was done
- Retain pylint/isort/pycodestyle as on master (ruff deferred to its own epic per #506); coverage config moved into `pyproject.toml`
- Update `tox.ini` to use `tox-uv` with `uv-venv-lock-runner`
- Update CI to use `astral-sh/setup-uv`; SHA-pin all actions; add `workflow_call` trigger
[- Add `python-semantic-release` + `release.yml` (OIDC trusted publishing)]   ← include only if release gate passed
[- Add `commitlint.yml` to enforce conventional commit format on all future PRs to this repo]   ← include only if release gate passed
[- Drop Python X.Y support; set `requires-python = ">=3.12"`]   ← include only if Python version changed

## Removed

**Deleted files:** `setup.py`, `setup.cfg`, `requirements/`, `.coveragerc`[, `CHANGELOG.rst` ← only if release gate passed]

**Removed Makefile targets:**

| Target | Reason |
|---|---|
| `<target>` | <one-line reason> |

<!-- CONDITIONAL SECTIONS — include only what applies, in this order: -->

## Python X.Y dropped   [← only when requires-python was bumped]
Python X.Y reached end-of-life on <date> and Open edX <release> dropped it platform-wide. Removed from the tox envlist, CI matrix, and classifiers.

## Not included   [← only when release gate failed]
`release.yml` / `python-semantic-release` — master had no PyPI publish workflow.

<!-- END CONDITIONAL SECTIONS -->

## Versioning
[Static] `version = "<x.y.z>"` declared directly in `pyproject.toml` — master had no PyPI publish workflow, so `setuptools-scm` is not used and the version is bumped manually on each release tag.

OR

[Dynamic] `setuptools-scm` with `dynamic = ["version"]` — master had a PyPI publish workflow; `python-semantic-release` controls the version string at release time via git tags.

## Testing Notes
This PR has not been manually tested against the repo's own features. Testing relied on CI checks and local agent tooling (`make requirements`, `make lint`, `make test`, `python -m build`). Repo-owner is encouraged to run the repo's feature tests before merging.

## Code reviewer notes:
- <non-obvious decisions worth flagging, e.g. an unusual constraint pin, a retained workflow, a branch-protection check name that must match>
- [OIDC trusted publisher must be configured on PyPI before merge — first publish fails silently otherwise (out-of-band, Axim team)]   ← only if release gate passed
- <what to scrutinise — e.g. dependency group separation, static version accuracy, the src/ move, a deleted workflow's impact>

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)
````

**Filling-in rules:**
- Every bullet is one sentence. No multi-sentence paragraphs.
- Omit any conditional section whose condition is false — don't write empty headings.
- The "Removed Makefile targets" table must list every target dropped from master's Makefile, with a specific reason (not "no longer needed"). Targets kept but rewritten are not listed here.
- `## Code reviewer notes:` is always present. Combine all non-obvious decisions and reviewer action items into this single section — do not split them across multiple headings. Each bullet must be unique; never repeat a fact already stated in another section.
- The `> [!IMPORTANT]` callout is always present.
- The 🤖 footer is always present, separated by `---`.
- **No repeated content:** every claim must appear in exactly one section. Before writing any bullet, verify it is not already conveyed elsewhere in the description.
- **Accuracy over completeness:** every claim in the description must be true of this specific PR. Never write a conditional item (bracketed or conditional section) unless its condition was confirmed true in Mode 4 Step 1. When in doubt, omit rather than guess.
- **Never mention ruff** as part of this migration — it is out of scope. If ruff was split out via Mode 5, the non-ruff PR description links the ruff follow-up PR instead.

---

## Test suite — Tests 1–31

All tests must be run before a migration is reported as done (Implement/Re-implement) or as part of a verification report (Test/Verify). Failure handling per mode is Process rule 7: fix in Implement/Re-implement, report-only in Test/Verify. **Test 1 is a hard gate — if it fails, halt.**

### Test 1 — Ruff absence gate (HALT on failure)

Ruff is out of scope this cycle (see [Cycle decisions](#cycle-decisions-public-engineering506-meeting)). Before running any other test, confirm the PR did **not** introduce ruff.

```bash
echo "=== ruff config in pyproject.toml ==="
grep -nE '\[tool\.ruff' pyproject.toml || echo "(none)"
echo "=== ruff as a dependency ==="
grep -rnE '(^|[^a-z])ruff([^a-z]|$)' pyproject.toml uv.lock tox.ini Makefile .github/workflows/ 2>/dev/null \
  | grep -iE 'ruff' | grep -vE 'ruffle|scruff' || echo "(none)"
echo "=== pylintrc still present (must exist if it was on master) ==="
git show master:pylintrc &>/dev/null 2>&1 && { [ -f pylintrc ] && echo "OK: pylintrc kept" || echo "FAIL: pylintrc deleted"; } || echo "(no pylintrc on master)"
```

**Pass:** No `[tool.ruff]` sections; `ruff` appears nowhere in pyproject/lock/tox/Makefile/CI; `pylintrc`/`pylintrc_tweaks` are still present if master had them.

**Fail → HALT:** If ruff is present in any form, **stop the test suite immediately.** Do not run Tests 2–25. Report only this failure and instruct:

> Ruff was found in this PR, but ruff is out of scope for this cycle (public-engineering#506). Drop the ruff implementation from this PR — either revert the ruff changes here, or split them into their own stacked PR with **Mode 5 (Separate-ruff)** — then re-run the test suite.

In Test/Verify mode, mark every other test `⏭️ Skipped (halted at Test 1 — ruff present)`. In Implement/Re-implement mode, remove ruff before continuing.

### Test 2 — Make targets

Run every Makefile target that does not require network access or external credentials and verify each exits with code 0:

```bash
# Install dev dependencies first
make requirements

# Then run each target
make lint      # runs the retained pylint-based checks via tox
make test
make docs      # skip if no docs/ directory exists
```

A target that was working before the migration and fails now is a regression, not an out-of-scope item.

### Test 3 — Package build and tarball contents

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

Check that the tarball includes **all** of the following (adjust paths to match the repo layout — with a src/ layout the package lives under `src/<package>/`):

| Expected content | Why it must be present |
|---|---|
| `PKG-INFO` | PEP 566 metadata — generated from `pyproject.toml` |
| `pyproject.toml` | Build recipe — must be included by setuptools |
| `setup.cfg` (if any) | Should **not** be present — it was deleted |
| Source package directory (e.g. `src/<package>/`) | All `.py` files under the package root |
| `README.rst` or `README.md` | Linked via `readme =` in `[project]` |
| `LICENSE` | Required for PyPI |
| `MANIFEST.in` (if any) | Only if the repo uses inclusion-based manifests |
| Static assets (e.g. `*.html`, `*.css`, `*.js`, `*.png` under the package) | Any non-`.py` file referenced by `package_data` or `MANIFEST.in` |

Flag as a failure if:
- Deleted files (`setup.py`, `setup.cfg`, `CHANGELOG.rst`) appear in the tarball — they should not be included after deletion.
- The source package directory is missing or empty.
- Static assets that existed before the migration are absent — their absence will break installs.

### Test 4 — Lockfile consistency

Verify the committed `uv.lock` is in sync with the current `pyproject.toml`. This catches the case where someone edited `pyproject.toml` after running `uv lock`:

```bash
uv lock --check
```

Must exit 0. If it fails, run `uv lock` to regenerate and commit the updated lockfile.

### Test 5 — Dependency group resolution

Verify every declared dependency group resolves without conflicts:

```bash
uv sync --group dev
uv sync --group ci
uv sync --group quality
uv sync --group test
```

A conflict here (e.g. incompatible pins between a group and `[tool.uv].constraint-dependencies`) means the lockfile is broken for that environment. Fix by adjusting `[tool.edx_lint].uv_constraints` and re-running `edx_lint write_uv_constraints` + `uv lock`.

### Test 6 — Tox environment listing

Confirm tox can parse the updated `tox.ini` and resolve all declared environments without actually running them:

```bash
uv run tox --listenvs
```

If this fails (parse error, missing dependency group, unknown runner), the CI matrix will never run. Fix `tox.ini` before proceeding.

### Test 7 — Package importability

Install the package in editable mode and verify the top-level package can be imported cleanly (no missing dependencies, no import-time errors):

```bash
uv pip install -e .
uv run python -c "import <package_name>; print('OK')"
```

Replace `<package_name>` with the actual importable module name (the directory under `src/` that contains `__init__.py`). A clean import confirms both that `[project].dependencies` lists everything the package needs at runtime **and** that the `src/` layout is wired up correctly in `[tool.setuptools.packages.find]`.

### Test 8 — setuptools-scm version resolution

**Skip this test if no PyPI publish workflow exists on master/main** — setuptools-scm is not used in that case (version is a static field in `pyproject.toml`). Record as `⏭️ Skipped (no PyPI publish workflow — static version used)`.

Confirm that `setuptools-scm` can derive a version from git (required for `python -m build` to succeed in CI):

```bash
uv run python -m setuptools_scm
```

This should print a version string (e.g. `1.2.3` or `1.2.3.dev4+gabcdef`). If it prints an error about no git tags or a dirty working tree, note it — the build will fail until a tag exists, which is expected for a brand-new repo. If it errors on a repo that already has tags, the `[tool.setuptools_scm]` config is wrong.

### Test 9 — Wheel contents

`python -m build` produces both a `.tar.gz` and a `.whl`. Inspect the wheel too:

```bash
# List wheel contents (replace filename with actual)
unzip -l dist/<name>-<version>-py3-none-any.whl | sort
```

Check that:
- The package directory and all its `.py` files are present — note the wheel strips the `src/` prefix, so the package appears as `<package>/` (not `src/<package>/`).
- Static assets (templates, JS, CSS, locale files) are included — wheels use `package_data` rules, not `MANIFEST.in`.
- `METADATA` (wheel equivalent of `PKG-INFO`) is present under `<name>-<version>.dist-info/`.
- No compiled `.pyc` files or test files appear in the wheel.

If static assets are missing from the wheel but present in the tarball, add them under `[tool.setuptools.package-data]` in `pyproject.toml`.

### Test 10 — No stale files on disk

Confirm that files which should have been deleted are actually gone (and that files which must be kept are still present):

```bash
for f in setup.py setup.cfg CHANGELOG.rst .coveragerc; do
  [ -f "$f" ] && echo "STALE: $f still exists" || echo "OK: $f absent"
done
[ -d requirements ] && echo "STALE: requirements/ still exists" || echo "OK: requirements/ absent"

# pylintrc / pylintrc_tweaks must be KEPT this cycle (ruff out of scope)
for f in pylintrc pylintrc_tweaks; do
  if git show master:"$f" &>/dev/null 2>&1; then
    [ -f "$f" ] && echo "OK: $f kept" || echo "REGRESSION: $f was deleted — ruff is out of scope, restore it"
  fi
done
```

Any `STALE:` line or `REGRESSION:` line is a failure. Note: `CHANGELOG.rst` counts as `STALE` only on PyPI repos (release gate passed); for no-PyPI repos it must be kept, so a present `CHANGELOG.rst` there is correct.

### Test 11 — GitHub Actions workflow YAML validity

Validate the CI and release workflow files are syntactically correct YAML before pushing. Use `actionlint`, not `yamllint` — `yamllint`'s 80-char line limit flags every SHA-pinned action line as an error, producing noise that cannot be fixed without removing the SHA or the version comment. `actionlint` checks for real structural problems (unknown fields, bad expressions, missing secrets) without style rules:

```bash
brew install actionlint   # macOS
actionlint .github/workflows/ci.yml .github/workflows/release.yml
```

A syntax or structural error in a workflow file causes a silent failure on GitHub (the workflow simply never runs). Catching it locally saves a push-and-wait cycle.

### Test 12 — SHA pinning audit

Scan every workflow file for GitHub Actions references that are not SHA-pinned:

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
# Build from the original repo directory (PR branch is already checked out there)
cd /path/to/repo   # or just stay in the repo root

uv run python -m build --outdir /tmp/bundle-pr
ls /tmp/bundle-pr/
```

**Step 4 — Compare tarball contents (strip version prefix AND the src/ prefix first):**

Version strings differ between branches, and the `src/` move relocates the package from `<pkg>/` (main) to `src/<pkg>/` (PR). Strip both the `<name>-<version>/` prefix and any leading `src/` so the move does not show as a false regression:

```bash
# Replace <pkg> with the actual package name (e.g. openedx_webhooks)
diff \
  <(tar -tzf /tmp/bundle-main/<pkg>-*.tar.gz | sed 's|[^/]*/||' | sed 's|^src/||' | sort) \
  <(tar -tzf /tmp/bundle-pr/<pkg>-*.tar.gz   | sed 's|[^/]*/||' | sed 's|^src/||' | sort)
```

Interpret the diff output:
- Lines starting with `<` — present in **main** but **missing from PR**. These are regressions.
- Lines starting with `>` — present in **PR** but not in main. These are expected additions (new tooling files).

**Step 5 — Compare wheel contents:**

The wheel strips `src/` on both branches, so no extra normalization is needed there:

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
| `<pkg>.egg-info/scm_file_list.json`, `scm_version.json` | setuptools-scm artifacts — expected |

**Watch for the implicit namespace package trap (wheel only):**

Modern setuptools (via PEP 420) treats any directory without `__init__.py` as an implicit namespace package and may include it in the wheel. Common culprits: `docs/`, `scripts/`, `bin/`. If a non-source directory appears in the PR wheel but not the main wheel, fix it by adding it to the exclude list in `pyproject.toml`:

```toml
[tool.setuptools.packages.find]
where = ["src"]
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
| **Mechanical rename** | Import path changed because a file moved (including the `src/` move) | Expected |
| **Dead code removal** | Unused import or variable deleted | Note only |
| **Logic change** | Conditional, loop, assignment, or return value changed | Note only |
| **New behaviour** | New function, method, or branch added | Note only |

There should be **no** ruff-formatting changes this cycle (ruff is out of scope). If you see mass reformatting (quote-style flips, import reordering, whitespace churn) across many files, that is a sign ruff crept in — cross-check against Test 1. Report any genuine logic or behaviour changes as a brief note for awareness — but do not mark them `ACTION REQUIRED` and do not recommend a separate PR.

### Test 15 — No `__version__` in package source

The version is now owned by `pyproject.toml` under both versioning paths. There is no reason to declare `__version__` in `__init__.py`. Check that none exists:

```bash
grep -rn '__version__' --include='*.py' .
```

Any match in the package source (not in tests or build tooling) is a failure. Remove it.

**Exception — PyPI repos only:** if `__version__` is genuinely consumed at runtime by third-party code or by the package's own public API, replace the static string with the `importlib.metadata` pattern instead of deleting it:

```python
from importlib.metadata import version, PackageNotFoundError
try:
    __version__ = version("your-package-name")
except PackageNotFoundError:
    __version__ = "0.0.0"
```

The `except` block **must** assign a fallback — never use bare `pass`. Without a fallback, `from package import __version__` raises `AttributeError` on any checkout that has not been `pip install -e .`'d.

For no-PyPI repos, the `importlib.metadata` pattern is also acceptable when there is a genuine runtime need — but the simpler and preferred outcome is no `__version__` in `__init__.py` at all.

### Test 16 — Makefile target and CI parity

Compare the inventory tables produced in Mode 1 Step 1 (Tables A and B) against the post-migration state. In Test/Verify mode, reconstruct the tables from the base branch first (`git show master:Makefile`, `git show master:.github/workflows/<ci>.yml`).

**Makefile parity:**

```bash
# List all targets in the new Makefile
grep -E '^[a-zA-Z_-]+:' Makefile | sed 's/:.*//'
```

For each target from Table A (pre-migration):
- If it invoked a deleted tool (pip-compile, setup.py) → confirm an equivalent target exists using uv
- If it invoked a retained tool (pytest, pylint, isort, pycodestyle, mypy, sphinx) → confirm the target still exists with updated invocation (the lint/quality target keeps its pylint-based checks)
- If it was infra-only (Heroku deploy, Docker build) → note the deliberate removal in the PR description

Any target from Table A that is missing from the new Makefile without a documented reason is a regression. Every removed target must appear in the PR description with the reason.

**CI parity:**

For each step from Table B (pre-migration CI), confirm there is a corresponding entry in the new CI matrix `toxenv` list:

```bash
# Show the toxenv matrix in the CI workflow
grep -A5 'toxenv:' .github/workflows/ci.yml  # or python-tests.yml
```

A tool that ran in the old CI must run in the new CI. Common gaps to check:
- The pylint/quality checks — must be in the `toxenv` list (as a `quality`/`lint` env)
- `mypy` — must be in `toxenv` list if repo had mypy
- `docs` build — must be a tox env in the matrix, not just referenced locally
- Any additional linter or checker that ran as a separate step

Flag any CI step from Table B that has no corresponding new matrix entry.

### Test 17 — Branch protection check name coverage

Confirm the new CI produces every check name that branch protection requires:

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

Verify that every package declared in master's `requirements/*.in` files is still present somewhere in `[project].dependencies` or `[dependency-groups]` in `pyproject.toml`. This catches silent drops during the migration. **Because ruff is out of scope, the linters (pylint/isort/pycodestyle/pydocstyle) are NOT removed — only pip-tools is.**

Run from the repo root (requires Python 3.11+ for `tomllib`):

```bash
python3 << 'PYEOF'
import re, subprocess, tomllib

# The ONLY tool legitimately removed by this migration (replaced by uv).
# Ruff is out of scope, so pylint/isort/pycodestyle/pydocstyle are NOT removed.
REPLACED_BY_MIGRATION = {
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
- If it is `pip-tools` (or `pip-compile`) → expected, it is replaced by uv; add it to `REPLACED_BY_MIGRATION` if the script did not already
- If it is a linter (pylint/isort/pycodestyle/pydocstyle) → **this is a failure this cycle** — ruff is out of scope, so it must remain; add it back to the `quality` group and re-run `uv lock`
- If it is a genuine runtime or test dependency → add it to the appropriate `[dependency-groups]` in `pyproject.toml` and re-run `uv lock`

**`ADDED:` lines are expected** for `tox`, `tox-uv` (new tooling). `ruff` must **not** appear here — if it does, Test 1 should have already halted.

### Test 19 — Constraints migration

If `requirements/constraints.txt` existed on master/main, verify it was properly migrated to `pyproject.toml` (per the constraints procedure in the Target state).

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

### Test 20 — PyPI publish uses OIDC trusted publishing

Skip (with reason) if the release gate excluded `release.yml`. Otherwise verify that `release.yml`'s `publish_to_pypi` job uses **OIDC trusted publishing** — the org-wide mechanism for this cycle (#506), applied even if master used token auth.

**Step 1 — Inspect the new `release.yml`:**

```bash
echo "=== id-token permission (must be present) ==="
grep -n "id-token" .github/workflows/release.yml || echo "(none — FAIL)"
echo "=== password / PYPI_UPLOAD_TOKEN (must be absent) ==="
grep -nE "password:|PYPI_UPLOAD_TOKEN" .github/workflows/release.yml || echo "(none — OK)"
echo "=== workflow filename ==="
[ -f .github/workflows/release.yml ] && echo "OK: named release.yml" || echo "FAIL: release workflow is not named release.yml"
```

**Step 2 — Confirm the out-of-band prerequisite is flagged:**

OIDC requires a trusted publisher pre-configured on the PyPI project page (handled by the Axim team). The PR description must flag this as a merge blocker.

```bash
gh pr view <number> --json body --jq '.body' | grep -iE "trusted publisher|OIDC" || echo "MISSING: OIDC trusted-publisher merge-blocker note in PR description"
```

**Pass:** `id-token: write` present in `publish_to_pypi`; **no** `password:` input and **no** `PYPI_UPLOAD_TOKEN`; the workflow is named `release.yml`; the PR description flags the trusted-publisher config as an out-of-band merge blocker.

**Fail:** Token auth is used (`password:`/`PYPI_UPLOAD_TOKEN` present) or `id-token: write` is missing; the workflow is misnamed; or the merge-blocker note is absent. Switch to OIDC and add the note. Remember the PR must not merge until the trusted publisher is confirmed configured (first publish fails silently otherwise).

### Test 21 — Configuration thresholds must maintain parity with master

Verify no configuration thresholds, limits, or settings were introduced that don't exist in master/main (see "codecov.yml and no inventions" in the Target state — migration is tooling, not policy).

**Step 1 — Check master's configuration files:**

```bash
# Check old .coveragerc for fail_under
git show master:.coveragerc 2>/dev/null | grep -i "fail_under" || echo "(none)"

# Check old setup.cfg for any thresholds
git show master:setup.cfg 2>/dev/null | grep -E "fail_under|threshold|limit" || echo "(none)"
```

**Step 2 — Compare against new pyproject.toml:**

```bash
# Check new pyproject.toml for fail_under in coverage config
grep "fail_under" pyproject.toml || echo "(none)"

# Check for any new threshold settings
grep -E "fail_under|min_percent|threshold|limit" pyproject.toml | grep -v "# " || echo "(none)"
```

**Pass:** All configuration thresholds in pyproject.toml match what was in master's old config files (.coveragerc, setup.cfg, etc.). No new limits added (e.g. a `fail_under = 70` that has no counterpart in master is a failure).

**Fail:** New thresholds/limits introduced (e.g., `fail_under`, `min_coverage`, etc.) that don't exist in master.

**Recovery:** Remove any new configuration settings. Keep only what existed in master. If a threshold was present before, carry it over exactly as it was.

### Test 22 — Static versioning parity (no-PyPI repos)

**Skip this test if a PyPI publish workflow exists on master/main** — setuptools-scm is in use on that path and Test 8 covers it. Record as `⏭️ Skipped (PyPI publish workflow exists — setuptools-scm used)`.

Verify the static versioning approach is applied correctly for repos with no PyPI publish workflow.

**Step 1 — Confirm no setuptools-scm in build system:**

```bash
python3 -c "
import tomllib
with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)
requires = data.get('build-system', {}).get('requires', [])
scm = [r for r in requires if 'setuptools-scm' in r]
print('FAIL: setuptools-scm in build-system.requires:', scm if scm else 'OK: no setuptools-scm in build-system')
scm_section = data.get('tool', {}).get('setuptools_scm')
print('FAIL: [tool.setuptools_scm] section present' if scm_section else 'OK: no [tool.setuptools_scm]')
"
```

**Step 2 — Confirm static version in `[project]`:**

```bash
python3 -c "
import tomllib
with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)
project = data.get('project', {})
dynamic = project.get('dynamic', [])
version = project.get('version')
if 'version' in dynamic:
    print('FAIL: version is in dynamic — should be a static field for no-PyPI repos')
elif not version:
    print('FAIL: no version field in [project]')
else:
    print(f'OK: static version = {version!r}')
"
```

**Step 3 — Verify static version matches master:**

```bash
# Try __init__.py first (under src/ for the new layout, or top-level on master)
PKG=$(python3 -c "import tomllib; d=tomllib.load(open('pyproject.toml','rb')); print(d['project']['name'].replace('-','_'))" 2>/dev/null)
MASTER_VER=$(git show master:${PKG}/__init__.py 2>/dev/null | grep -oE "__version__\s*=\s*['\"][^'\"]+['\"]" | grep -oE "['\"][^'\"]+['\"]" | tr -d "'\"")
if [ -z "$MASTER_VER" ]; then
    MASTER_VER=$(git show master:src/${PKG}/__init__.py 2>/dev/null | grep -oE "__version__\s*=\s*['\"][^'\"]+['\"]" | grep -oE "['\"][^'\"]+['\"]" | tr -d "'\"")
fi

# Fall back to setup.cfg
if [ -z "$MASTER_VER" ]; then
    MASTER_VER=$(git show master:setup.cfg 2>/dev/null | grep -oP "(?<=^version = )\S+")
fi

echo "Master version: ${MASTER_VER:-not found}"

python3 -c "
import tomllib, sys
with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)
pr_ver = data.get('project', {}).get('version', 'missing')
master_ver = '${MASTER_VER}'
print(f'PR version: {pr_ver}')
if master_ver and master_ver not in ('', 'not found'):
    if pr_ver == master_ver:
        print('OK: PR version matches master')
    else:
        print(f'FAIL: PR version ({pr_ver}) does not match master ({master_ver})')
else:
    print('INFO: could not read master version — verify manually that the static version is reasonable')
"
```

**Pass:** No `setuptools-scm` in `[build-system].requires`; no `[tool.setuptools_scm]` section; `[project].version` is a static string (not in `dynamic`); the static version matches what master carried in `__init__.py` or `setup.cfg`.

**Fail:** `setuptools-scm` present in build system; `dynamic = ["version"]` is set; or `[project].version` is absent.

### Test 23 — PR description completeness

Verify the PR body contains every required section in the correct order and with real content. Run this after Mode 1 Step 6 or Mode 4, or as part of a full Mode 3 verification.

**Step 1 — Read the PR body:**

```bash
# If a PR number is known:
gh pr view <number> --json body --jq '.body' > /tmp/pr_body.txt

# Or, if describing a local branch before opening the PR, paste the draft body into /tmp/pr_body.txt manually.
```

**Step 2 — Run the section checks:**

```python
import re, sys

body = open('/tmp/pr_body.txt').read()

REQUIRED = [
    (r'>\s*\[!IMPORTANT\]',                                    '[!IMPORTANT] callout block'),
    (r'>\s*PR implemented with the assistance of \[Claude Code\]', 'Claude assistance line inside callout'),
    (r'## Summary',                                            '## Summary heading'),
    (r'public-engineering/issues/506',                         'parent story link (public-engineering#506)'),
    (r'## Removed',                                            '## Removed heading'),
    (r'\|\s*`[^`]+`\s*\|',                                    'Makefile targets table row'),
    (r'## Versioning',                                         '## Versioning heading'),
    (r'(static|setuptools-scm|dynamic)',                       'versioning path explanation (static / setuptools-scm / dynamic)'),
    (r'## Testing Notes',                                      '## Testing Notes heading'),
    (r'(not been manually tested|not.*manual)',                 'manual testing disclaimer in Testing Notes'),
    (r'## Code reviewer notes:',                               '## Code reviewer notes: heading'),
    (r'🤖 Generated with \[Claude Code\]',                    '🤖 footer'),
]

failures = []
for pattern, label in REQUIRED:
    if not re.search(pattern, body, re.IGNORECASE):
        failures.append(f'MISSING: {label}')

# Order check: key headings must appear in the defined sequence
ORDER = ['## Summary', '## Removed', '## Versioning', '## Testing Notes',
         '## Code reviewer notes:', '🤖 Generated']
positions = [(body.find(h), h) for h in ORDER if body.find(h) != -1]
for i in range(len(positions) - 1):
    if positions[i][0] > positions[i+1][0]:
        failures.append(f'ORDER: "{positions[i][1]}" appears after "{positions[i+1][1]}"')

# Empty-section check: each heading must have at least one non-blank line after it
for heading in ['## Summary', '## Removed', '## Versioning', '## Testing Notes',
                '## Code reviewer notes:']:
    m = re.search(re.escape(heading) + r'\s*\n((?:\s*\n)*)', body)
    if m and not body[m.end():m.end()+5].strip():
        failures.append(f'EMPTY: {heading} has no content under it')

# Ruff must NOT be mentioned as part of this migration
if re.search(r'\bruff\b', body, re.IGNORECASE) and not re.search(r'split|follow-up|deferred|separate', body, re.IGNORECASE):
    failures.append('INCORRECT: PR body mentions ruff — ruff is out of scope this cycle')

if failures:
    print('\n'.join(failures))
    sys.exit(1)
else:
    print('OK: all required sections present, ordered correctly, and non-empty')
```

**Step 3 — Conditional section checks:**

```bash
# If no PyPI publish workflow exists on master, "Not included" or equivalent must appear:
gh api repos/<org>/<repo>/contents/.github/workflows \
  | python3 -c "import json,sys; wf=[f['name'] for f in json.load(sys.stdin) if any(k in f['name'] for k in ['pypi','publish','release'])]; print('has publish workflow' if wf else 'no publish workflow')"

# If no publish workflow, check that the PR body explains the omission:
grep -i "no PyPI publish\|release gate\|not included\|excluded" /tmp/pr_body.txt \
  || echo "MISSING: explanation of why release.yml was omitted"

# If Python support was dropped, check for a section or mention:
DROPPED=$(git diff master...HEAD -- pyproject.toml \
  | grep '+requires-python' | grep -oP '3\.\d+' | head -1)
[ -n "$DROPPED" ] && {
  grep -i "python $DROPPED\|py$DROPPED\|3\.$DROPPED" /tmp/pr_body.txt \
    || echo "MISSING: mention of Python $DROPPED being dropped"
}

# If the src/ move was done, the description should mention it:
[ -d src ] && { grep -iE "src/ layout|src layout|into a \`src" /tmp/pr_body.txt \
  || echo "MISSING: mention of the src/ layout move"; }
```

**Step 4 — Content accuracy checks (cross-reference body against actual implementation):**

```bash
# 4a. release.yml presence vs description claims
echo "=== 4a: release.yml ==="
HAS_RELEASE_YML=$([ -f .github/workflows/release.yml ] && echo "yes" || echo "no")
if [ "$HAS_RELEASE_YML" = "yes" ]; then
  grep -iE "add.*python-semantic-release|add.*release\.yml|python-semantic-release.*release\.yml" /tmp/pr_body.txt \
    || echo "INCORRECT: release.yml exists in branch but Summary does not mention it was added"
  grep -i "## Not included" /tmp/pr_body.txt \
    && echo "INCORRECT: '## Not included' section present but release.yml exists in branch"
else
  grep -i "## Not included" /tmp/pr_body.txt \
    || echo "INCORRECT: '## Not included' section missing — release.yml was not added"
  grep -iE "add.*python-semantic-release|add.*release\.yml" /tmp/pr_body.txt \
    && echo "INCORRECT: Summary claims release.yml was added but it does not exist in branch"
fi

# 4b. Versioning section matches pyproject.toml
echo "=== 4b: Versioning ==="
HAS_SCM=$(grep -c 'setuptools-scm' pyproject.toml 2>/dev/null || echo 0)
if [ "$HAS_SCM" -gt 0 ]; then
  grep -iE "\[Dynamic\]|setuptools-scm" /tmp/pr_body.txt \
    || echo "INCORRECT: Versioning section should say '[Dynamic]'/'setuptools-scm' — setuptools-scm is in pyproject.toml"
  grep -iE "^\[Static\]|\[Static\]" /tmp/pr_body.txt \
    && echo "INCORRECT: Versioning section says '[Static]' but setuptools-scm is present in pyproject.toml"
else
  grep -iE "\[Static\]" /tmp/pr_body.txt \
    || echo "INCORRECT: Versioning section should say '[Static]' — pyproject.toml uses a static version string"
  grep -iE "\[Dynamic\]|setuptools-scm" /tmp/pr_body.txt \
    && echo "INCORRECT: Versioning section says '[Dynamic]'/setuptools-scm but pyproject.toml uses static versioning"
fi

# 4c. Deleted files list accuracy (pylintrc must NOT be listed — kept this cycle)
echo "=== 4c: Deleted files ==="
for f in setup.py setup.cfg .coveragerc requirements; do
  WAS_ON_MASTER="no"
  git show master:"$f" &>/dev/null 2>&1 && WAS_ON_MASTER="yes"
  git ls-tree master "$f" &>/dev/null 2>&1 && WAS_ON_MASTER="yes"
  IS_GONE=$([ ! -e "$f" ] && echo "yes" || echo "no")

  if [ "$WAS_ON_MASTER" = "yes" ] && [ "$IS_GONE" = "yes" ]; then
    grep -F "\`$f\`" /tmp/pr_body.txt \
      || echo "MISSING from deleted files: '$f' was deleted but not listed in PR body"
  elif [ "$WAS_ON_MASTER" = "no" ]; then
    grep -F "\`$f\`" /tmp/pr_body.txt \
      && echo "INCORRECT: '$f' listed as deleted but it did not exist on master"
  fi
done
for f in pylintrc pylintrc_tweaks; do
  grep -F "\`$f\`" /tmp/pr_body.txt \
    && echo "INCORRECT: '$f' listed as deleted — ruff is out of scope, pylintrc must be kept this cycle"
done
# CHANGELOG.rst: only expected deleted when release gate passed
CHANGELOG_ON_MASTER="no"
git show master:CHANGELOG.rst &>/dev/null 2>&1 && CHANGELOG_ON_MASTER="yes"
CHANGELOG_GONE=$([ ! -f CHANGELOG.rst ] && echo "yes" || echo "no")
if [ "$CHANGELOG_ON_MASTER" = "yes" ] && [ "$HAS_RELEASE_YML" = "yes" ] && [ "$CHANGELOG_GONE" = "yes" ]; then
  grep -F "\`CHANGELOG.rst\`" /tmp/pr_body.txt \
    || echo "MISSING from deleted files: 'CHANGELOG.rst' was deleted (release gate passed) but not listed in PR body"
elif [ "$CHANGELOG_ON_MASTER" = "yes" ] && [ "$HAS_RELEASE_YML" = "no" ] && [ "$CHANGELOG_GONE" = "yes" ]; then
  echo "INCORRECT: 'CHANGELOG.rst' was deleted but release gate did not pass — it should have been kept for no-PyPI repos"
fi

# 4d. Makefile targets table — kept targets must not appear in the removed table
echo "=== 4d: Makefile targets table ==="
OLD_TARGETS=$(git show master:Makefile 2>/dev/null | grep -E '^[a-zA-Z_-]+:' | sed 's/:.*//' | sort)
NEW_TARGETS=$(grep -E '^[a-zA-Z_-]+:' Makefile 2>/dev/null | sed 's/:.*//' | sort)
KEPT_TARGETS=$(comm -12 <(echo "$OLD_TARGETS") <(echo "$NEW_TARGETS"))
TABLE_SECTION=$(awk '/\*\*Removed Makefile targets\*\*/,/^##/' /tmp/pr_body.txt | head -40)
for t in $KEPT_TARGETS; do
  echo "$TABLE_SECTION" | grep -F "\`$t\`" \
    && echo "INCORRECT: target '$t' listed in removed table but it still exists in the new Makefile"
done
REMOVED_TARGETS=$(comm -23 <(echo "$OLD_TARGETS") <(echo "$NEW_TARGETS"))
for t in $REMOVED_TARGETS; do
  echo "$TABLE_SECTION" | grep -F "\`$t\`" \
    || echo "MISSING from removed table: target '$t' was dropped but not listed"
done
```

**Pass:** Python script in Step 2 exits 0; all Step 3 conditional checks produce no `MISSING:` lines; all Step 4 content accuracy checks produce no `INCORRECT:` or `MISSING:` lines.

**Fail:**
- A required section is absent — add it per the [PR description format](#pr-description-format).
- A section is out of order — reorder to match the template sequence.
- A section heading is present but empty — fill it with content.
- A conditional section is missing when its condition is true (no publish workflow / Python dropped / src move).
- Content accuracy mismatch (Step 4): description claims something that is not true of the actual PR — correct the specific claim.

### Test 24 — Zero-version guard in semantic-release config

**Skip this test if the release gate excluded `release.yml`** — `[tool.semantic_release]` is not present for no-PyPI repos. Record as `⏭️ Skipped (no PyPI publish workflow — semantic-release not added)`.

Verify that `[tool.semantic_release]` correctly includes or excludes `allow_zero_version` and `major_on_zero` based on the repo's current release version (per the #506 versioning rules: 0.x repos bump minor/patch, 1.0+ repos bump major/minor/patch).

**Step 1 — Determine the current version from git tags:**

```bash
LATEST_TAG=$(git tag --sort=version:refname | grep -E '^v?[0-9]+\.[0-9]+' | tail -1)
echo "Latest tag: ${LATEST_TAG:-(none)}"
MAJOR=$(echo "$LATEST_TAG" | grep -oE '[0-9]+' | head -1)
echo "Major version: ${MAJOR:-(none — treat as 0)}"
```

If `MAJOR` is empty (no release tags), treat it as `0` — the repo has never cut a stable release.

**Step 2 — Read the semantic-release config:**

```bash
python3 -c "
import tomllib
with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)
sr = data.get('tool', {}).get('semantic_release', {})
allow_zero = sr.get('allow_zero_version')
major_on_zero = sr.get('major_on_zero')
print(f'allow_zero_version = {allow_zero!r}')
print(f'major_on_zero = {major_on_zero!r}')
"
```

**Step 3 — Evaluate:**

| Condition | Expected | Fail if |
|---|---|---|
| Latest tag is `v0.x.y` or no release tags | `allow_zero_version = true` **and** `major_on_zero = false` both present | Either setting absent |
| Latest tag is `v1.x.y` or higher | Neither setting present | Either setting present |

**Pass:** Settings match the table above for this repo's current version.

**Fail:** Either setting is absent on a 0.x repo; or either setting is present on a 1.x+ repo.

**Recovery for 0.x repo:** Add to `[tool.semantic_release]` in `pyproject.toml`:

```toml
[tool.semantic_release]
allow_zero_version = true
major_on_zero = false
build_command = "..."  # keep the existing build_command value
```

### Test 25 — src/ layout

**Skip this test if the user explicitly opted out of the src/ move for this repo.** Record as `⏭️ Skipped (src/ move opted out by user)`.

Verify the importable package was moved under `src/` and that packaging points at it.

**Step 1 — Confirm the package lives under `src/`:**

```bash
PKG=$(python3 -c "import tomllib; d=tomllib.load(open('pyproject.toml','rb')); print(d['project']['name'].replace('-','_'))" 2>/dev/null)
[ -d "src/$PKG" ] && echo "OK: src/$PKG present" || echo "FAIL: src/$PKG missing"
# The old top-level package dir must be gone (it was moved, not copied)
if [ -d "$PKG" ] && [ "$PKG" != "src" ]; then echo "FAIL: top-level $PKG/ still exists — package was not moved, it was duplicated"; else echo "OK: no stray top-level $PKG/"; fi
```

**Step 2 — Confirm pyproject points at src:**

```bash
python3 -c "
import tomllib
with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)
find = data.get('tool', {}).get('setuptools', {}).get('packages', {}).get('find', {})
where = find.get('where')
print(f'where = {where!r}')
print('OK' if where == ['src'] else 'FAIL: [tool.setuptools.packages.find].where should be [\"src\"]')
"
```

**Step 3 — Confirm the move preserved history and import works:**

```bash
# History preserved (git mv, not delete+add):
git log --oneline --follow -1 -- "src/$PKG/__init__.py" >/dev/null 2>&1 && echo "OK: history follows through the move" || echo "INFO: could not confirm follow history"
# Import (covered by Test 7 too):
uv run python -c "import $PKG; print('import OK')"
```

**Pass:** `src/<pkg>/` exists; no stray top-level `<pkg>/`; `where = ["src"]`; the package imports cleanly; coverage config measures the package under src.

**Fail:** Package not moved (still top-level), duplicated (exists in both places), `where` not set to `["src"]`, or import fails.

### Test 26 — Tooling parity with master/main

Ensure no linting, type-checking, or test tools were added or removed compared to master/main. The migration preserves the repo's existing tooling ecosystem exactly—only how tools are invoked changes (from pip-compile to uv, from bare tox to uv run tox). Master had specific tools like pylint, mypy, isort, pycodestyle, pydocstyle, pytest, coverage, and sphinx for good reasons. Removing them silently breaks the repo's quality gates; adding new ones introduces surprise dependencies. Parity ensures the migration is purely about tooling and workflow, not policy.

```bash
python3 << 'PYEOF'
import tomllib
import subprocess

# Get tools from master
master_result = subprocess.run(['git', 'show', 'master:pyproject.toml'], 
                               capture_output=True, text=True)
master_tools = set()
if master_result.returncode == 0:
    try:
        master_data = tomllib.loads(master_result.stdout)
        for group in master_data.get('dependency-groups', {}).values():
            for dep in (group if isinstance(group, list) else []):
                name = dep.split('[')[0].split(';')[0].split('>=')[0].split('>')[0].split('<')[0].split('==')[0].split('!=')[0].split('~')[0].strip().lower()
                if any(t in name for t in ['pylint', 'mypy', 'isort', 'pycodestyle', 'pydocstyle', 'pytest', 'coverage', 'sphinx', 'flake8']):
                    master_tools.add(name.split('-')[0])
    except:
        pass

# Get tools from current branch
with open('pyproject.toml', 'rb') as f:
    current_data = tomllib.load(f)
current_tools = set()
for group in current_data.get('dependency-groups', {}).values():
    for dep in (group if isinstance(group, list) else []):
        name = dep.split('[')[0].split(';')[0].split('>=')[0].split('>')[0].split('<')[0].split('==')[0].split('!=')[0].split('~')[0].strip().lower()
        if any(t in name for t in ['pylint', 'mypy', 'isort', 'pycodestyle', 'pydocstyle', 'pytest', 'coverage', 'sphinx', 'flake8']):
            current_tools.add(name.split('-')[0])

removed = master_tools - current_tools
added = current_tools - master_tools

if removed:
    print(f"FAIL: tools removed from master: {removed}")
elif added:
    print(f"WARN: new tools added: {added} (only ruff should be new, and ruff is gated)")
else:
    print("OK: tooling parity maintained with master")
PYEOF
```

**Pass:** All tools present on master/main are still present. No quality or test tools were silently dropped.

**Fail:** Any tool that existed on master (pylint, mypy, isort, etc.) is missing.

### Test 27 — Versioning strategy (consolidated)

Verify the versioning approach matches the release gate decision and is correctly configured throughout the pyproject.toml, build system, and setuptools_scm settings. This test covers the complete versioning picture: PyPI-publishing repos must use setuptools-scm with dynamic version, no-PyPI repos must use static version, and repos on 0.x branches require zero-version guard settings.

```bash
python3 << 'PYEOF'
import tomllib
import subprocess

# Determine release gate (whether a PyPI publish workflow exists on master)
check = subprocess.run(['git', 'ls-tree', 'master', '.github/workflows/'], 
                       capture_output=True, text=True)
has_publish_wf = 'release' in check.stdout or 'publish' in check.stdout or 'pypi' in check.stdout
gate = "pypi" if has_publish_wf else "no-pypi"

with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)

project = data.get('project', {})
dynamic = project.get('dynamic', [])
version = project.get('version')
build_requires = data.get('build-system', {}).get('requires', [])
scm = data.get('tool', {}).get('setuptools_scm', {})

# Validate versioning matches the gate
if gate == "pypi":
    has_scm = any('setuptools-scm' in req for req in build_requires)
    if not has_scm:
        print("FAIL: PyPI repo missing setuptools-scm in build-system.requires")
    elif 'version' not in dynamic:
        print("FAIL: PyPI repo must have dynamic = ['version']")
    else:
        # Check zero-version guard for 0.x repos
        tag_result = subprocess.run(['git', 'tag', '--sort=version:refname'], 
                                    capture_output=True, text=True)
        tags = [t for t in tag_result.stdout.strip().split('\n') if t and t[0].isdigit()]
        if tags:
            latest_tag = tags[-1].lstrip('v')
            if latest_tag[0] == '0':
                allow_zero = scm.get('allow_zero_version')
                major_on_zero = scm.get('major_on_zero')
                if allow_zero is not True or major_on_zero is not False:
                    print("FAIL: 0.x PyPI repo missing zero-version guard (allow_zero_version=true, major_on_zero=false)")
                else:
                    print("OK: PyPI repo (0.x) versioned via setuptools-scm with zero-version guard")
            else:
                print("OK: PyPI repo (1.x+) versioned via setuptools-scm")
        else:
            print("OK: PyPI repo configured for setuptools-scm (no tags yet)")
else:
    if not version:
        print("FAIL: no-PyPI repo missing static version in [project]")
    elif 'version' in dynamic:
        print("FAIL: no-PyPI repo should not have dynamic version")
    else:
        print(f"OK: no-PyPI repo has static version = {version!r}")
PYEOF
```

**Pass:** PyPI repos use setuptools-scm with `dynamic = ["version"]` and include zero-version guard (allow_zero_version=true, major_on_zero=false) if on 0.x. No-PyPI repos use static `version` field (not dynamic).

**Fail:** Versioning config does not match the release gate, or zero-version guard is missing on 0.x PyPI repos.

### Test 28 — uv run tox in CI (not bare tox)

Verify all CI workflows invoke `uv run tox`, not bare `tox` command. Bare `tox` fails at runtime because tox is not on PATH without the `uv run` wrapper.

```bash
for workflow in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ ! -f "$workflow" ] && continue
  if grep -E '^\s*-\s+run:\s+tox\s' "$workflow" > /dev/null; then
    echo "FAIL: bare tox in $(basename $workflow) — use 'uv run tox'"
  fi
done
echo "OK: all tox invocations use uv run"
```

**Pass:** All tox invocations in CI workflows use `uv run tox`.

**Fail:** Any bare `tox` command found.

### Test 29 — Python < 3.12 dropped

Verify old Python versions (3.8, 3.9, 3.10, 3.11) were removed from tox envlist, CI matrix, and classifiers. The standardization to Python 3.12+ happens in Step 0 and must be reflected across all configuration.

```bash
grep -E 'py3(8|9|10|11)' tox.ini && echo "FAIL: old Python in tox" || echo "OK: tox uses 3.12+"
grep -rE '"3\.(8|9|10|11)"' .github/workflows/ && echo "FAIL: old Python in CI" || echo "OK: CI uses 3.12+"
grep -E 'Programming Language :: Python :: 3\.(8|9|10|11)' pyproject.toml && echo "FAIL: old classifier" || echo "OK: classifiers use 3.12+"
```

**Pass:** No references to Python 3.8, 3.9, 3.10, or 3.11 remain in tox, CI, or classifiers.

**Fail:** Old Python versions found.

### Test 30 — Static dependencies declared

Verify `[project].dependencies` is a static list, not dynamic from a requirements file. This ensures package metadata is completely self-contained in pyproject.toml and not split across multiple sources.

```bash
python3 << 'PYEOF'
import tomllib
with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)
if 'dependencies' in data.get('project', {}).get('dynamic', []):
    print("FAIL: dependencies marked dynamic — must be static list")
elif not isinstance(data.get('project', {}).get('dependencies'), list):
    print("FAIL: [project].dependencies must be a list")
else:
    print("OK: dependencies is static")
PYEOF
```

**Pass:** `[project].dependencies` is a static list (not in `dynamic`).

**Fail:** dependencies is dynamic, missing, or not a list.

### Test 31 — Quality dependency group retains original linters

Verify the `quality` dependency group includes the repo's original linters (pylint, isort, pycodestyle, pydocstyle) and does not include ruff. This ensures lint behavior is preserved across the migration and confirms ruff remains out of scope per the cycle decisions.

```bash
python3 << 'PYEOF'
import tomllib
with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)
quality = data.get('dependency-groups', {}).get('quality', [])
if not quality:
    print("FAIL: quality group missing")
else:
    has_ruff = any('ruff' in d.lower() for d in quality)
    has_linters = any(l in '|'.join(quality).lower() for l in ['pylint', 'isort', 'pycodestyle', 'pydocstyle'])
    if has_ruff:
        print("FAIL: ruff in quality group (out of scope this cycle)")
    elif has_linters:
        print("OK: quality group has original linters")
    else:
        print("WARN: no standard linters detected — verify manually")
PYEOF
```

**Pass:** quality group exists and includes original linters (pylint, isort, pycodestyle, pydocstyle); does not include ruff.

**Fail:** ruff present in quality group; or no linters when master had them.

---

## PR description

See [PR description format](#pr-description-format) — the authoritative template used by Mode 1 Step 6, Mode 2 Step 5, and Mode 4.
