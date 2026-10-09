---
name: modernize-python-repos
description: >
  Modernize an Open edX Python repo to use uv, pyproject.toml (PEP 621/735), optional src/ layout
  (if publishing to PyPI), and python-semantic-release. Three modes: Implement/Re-implement (create or update
  the migration), PR creation (generate a formatted PR body for a completed migration), and
  Test/Verify (run the full test suite against a PR and report every result).
allowed-tools: Read Glob Grep Bash Write Edit
---

> **STRICT MODE — execute every step in order.**
> Before starting each step, state: `"Step <number>: <title> — starting"`.
> After completing each step, state: `"Step <number>: <title> — done"`.
> Do not skip, combine, reorder, or silently omit any step.
> If a step cannot be completed, stop and report the blocker before moving on.

# Modernize Python Repos

## Step 0 — Identify and confirm the target repo

Before selecting a mode or touching any file, identify and confirm the repository with the user.

**1. Find the repo.**

Check the default search directory first:

```bash
ls /Users/farhan.khan/MyStuff/Development/Axim/modernize-python-repos/
```

If a repo name was mentioned in the user's request, look for a matching directory there. If the current working directory is already inside a repo, note that too.

**2. Confirm with the user.**

Present what you found — full path, current branch, last commit — and ask the user to confirm this is the correct repo before proceeding:

```bash
# Run inside the identified repo directory
git -C <repo-path> status
git -C <repo-path> log --oneline -3
git -C <repo-path> remote get-url origin
```

Show a short summary like:

> Found **`/Users/farhan.khan/MyStuff/Development/Axim/modernize-python-repos/<repo-name>`**
> Branch: `<branch>` | Last commit: `<hash> <message>`
> Remote: `<url>`
>
> Is this the correct repo, and should I proceed?

**Do not proceed to mode selection or any file changes until the user confirms.**

If the repo cannot be found in the default directory, ask the user to provide the path.

---

## Modes

Pick the mode from the user's request. If the request doesn't clearly indicate one, ask before starting.

| Mode | When | What you do |
|---|---|---|
| **1. Implement/Re-implement** | Repo has no migration yet, or an existing migration PR needs changes | TBD |
| **2. PR creation** | User asks to generate or write the PR description | Collect migration facts from the diff and produce a formatted PR body |
| **3. Test/Verify** | User asks to test or verify a migration PR | Run all tests and report every result in one table — no fixes |

---

## Mode 1 — Implement/Re-implement

> **Guiding principles — read before touching any file:**
> - **Story-first:** implement only what is described in [public-engineering#506](https://github.com/openedx/public-engineering/issues/506). If a change is not in the story, it must be in exact parity with master.
> - **Least change + YAGNI:** minimum edits to achieve the story's goals. No extra refactors, no new abstractions, no speculative cleanup.
> - **Ruff is out of scope this cycle.** Keep pylint, isort, pycodestyle exactly as they are on master. Never introduce ruff, even if a reference repo uses it.
> - **Makefile targets are sacred.** Keep every target. Never rename one. Only drop targets directly replaced by the story (e.g. `compile-requirements`, pip-compile targets).
> - **Tooling flow:** Makefile defines commands → tox.ini invokes Makefile targets → CI invokes tox envs.

The story defines three phases. Work through them in order.

---

### Step 0 — Pre-flight: understand the repo

Run every command below before touching any file. Record the results — they drive every decision in Steps 1–5.

```bash
# 1. Current branch? Create a feature branch if not already on one.
git status && git log --oneline -5

# 2. Release gate: is this repo in the hardcoded non-PyPI list?
#    Non-PyPI repos (never published to PyPI):
#      credentials-themes, mockprock, edx-repo-health, openedx-webhooks-data-schema,
#      enterprise-catalog, enterprise-access, enterprise-subsidy, xapi-db-load,
#      codejail-service, openedx-user-groups, cc2olx, pr_watcher_notifier,
#      openedx-webhooks
#    All other repos → PyPI repo (release gate: yes)
git remote get-url origin 2>/dev/null

# 3. Package metadata
git show HEAD:setup.cfg 2>/dev/null || git show HEAD:setup.py 2>/dev/null

# 4. Requirements files
ls requirements/*.in 2>/dev/null

# 5. Constraints file
git show HEAD:requirements/constraints.txt 2>/dev/null | head -60

# 6. Makefile targets (record ALL — these must not be dropped or renamed)
grep -E '^[a-zA-Z_-]+:' Makefile 2>/dev/null

# 7. Stale file check
for f in .coveragerc CHANGELOG.rst; do [ -f "$f" ] && echo "EXISTS: $f" || echo "absent: $f"; done
# Note: CHANGELOG.rst is never created and never deleted. If it exists, Step 3.4 prepends a deprecation note; if absent, leave it absent.

# 8. Current version
git show HEAD:setup.cfg 2>/dev/null | grep 'version\s*='
git tag --sort=version:refname | tail -5

# 9. Python and Django versions on master
git show HEAD:setup.cfg 2>/dev/null | grep 'python_requires'
git show HEAD:tox.ini 2>/dev/null

# 10. Existing CI workflows
ls .github/workflows/
git show HEAD:.github/workflows/ci.yml 2>/dev/null || git show HEAD:.github/workflows/python-tests.yml 2>/dev/null | head -60

# 11. Layout
[ -d src ] && echo "src/ layout: PRESENT" || echo "src/ layout: ABSENT"

# 12. Hardcoded __version__
grep -rn '__version__' --include='*.py' . 2>/dev/null | grep -v '\.tox' | grep -v test

# 13. Quality linters on master
git show HEAD:Makefile 2>/dev/null | grep -E 'pylint|isort|pycodestyle|mypy'

# 14. Existing action SHAs in CI (record these — used in Step 2.6 to avoid downgrades)
git show HEAD:.github/workflows/ci.yml 2>/dev/null | grep 'uses:.*@' || \
  git show HEAD:.github/workflows/python-tests.yml 2>/dev/null | grep 'uses:.*@'

# 15. Master's MANIFEST.in (record ALL lines — used in Step 1.2 to migrate assets)
git show HEAD:MANIFEST.in 2>/dev/null

# 16. Git-tracked symlinks in the package tree (mode 120000 = symlink).
#     A translations/ symlink causes `python -m build --wheel` to fail with
#     "doesn't exist or not a regular file" — setuptools-scm's file finder
#     hands it to build_py regardless of package-data config.
#     Record any hits here; Step 1.1 will add exclude-package-data for them.
git ls-files --stage | awk '$1 == "120000" {print $4}' | grep -i 'translations' \
  || echo "no git-tracked translation symlinks found"
```

Before proceeding, summarize:

| Characteristic | Value |
|---|---|
| Release gate | PyPI / non-PyPI |
| Current version | e.g. `1.2.3` |
| Python tested | e.g. `3.12` |
| Django versions | e.g. `4.2`, `5.2` |
| Quality linters | e.g. pylint, isort, pycodestyle |
| `.coveragerc` | exists / absent |
| `CHANGELOG.rst` | exists / absent |
| `constraints.txt` | exists / absent |
| MANIFEST.in asset lines | e.g. `recursive-include pkg *.html *.js` |
| CI action SHAs | e.g. `actions/checkout@<SHA> # v7.0.1` |
| Translation symlinks | e.g. `src/pkg/translations` (mode 120000) — or none |

**Reference — cross-check pyproject.toml structure against the org reference repo:**
`openedx/sample-plugin` → `backend-plugin-sample/pyproject.toml` is the org-canonical example for `[build-system]`, `[tool.setuptools_scm]`, `[tool.semantic_release]`, and action SHA pinning style. Read it and match its structure for those sections.

**Also produce three inventory tables before touching any file:**

**Table A — Makefile targets (current state):** list every `make` target (from command #6 above), what tool it invokes, and whether that tool is being removed by this migration. Mark only pip-compile/setup.py targets as "removed"; everything else is "keep + adapt". This is the baseline for the Makefile audit and the removed-targets table in the PR description.

**Table B — CI steps (current state):** list every step in the existing CI workflow (from command #10 above) and what it runs. This is the baseline for CI parity — every tool that ran in the old CI must appear in the new CI matrix.

**Table C — `requirements/*.in` → dependency-group mapping:** discover the actual `.in` files (`git ls-tree master:requirements | grep '\.in$'` — do NOT assume canonical names; legacy repos use `sandbox.in`/`testing.in`/`tox.in`/`development.in`/`pip_tools.in`). For **every** `.in` file, record one row: the target group name, OR the deviation shape (canonical-rename / role-split / `-r`-only / documented-drop) with its reason. This table is the accountability gate — no `.in` file may be left unlisted — and it drives the group-mapping rules in Step 2.1. Every direct package in every `.in` must end up somewhere in `pyproject.toml` (a group or `[project].dependencies`) unless it is an explicit documented-drop.

---

### Step 0a — Drop support for Python < 3.12

Dropping old Python versions is **in scope for this migration** — not a separate PR. The target is `requires-python = ">=3.12"` (set in Step 1 when writing pyproject.toml); this step removes the legacy version entries from tox, CI, and classifiers before touching anything else.

```bash
# Check tox envlist for old Python versions
grep -E '\bpy3[0-9]\b' tox.ini 2>/dev/null

# Check CI matrix
grep -rE '"3\.(8|9|10|11)"' .github/workflows/ 2>/dev/null

# Check classifiers in setup.cfg or pyproject.toml
grep -E 'Python :: 3\.(8|9|10|11)' setup.cfg pyproject.toml 2>/dev/null
```

If old versions are found, remove them:
- **Tox envlist:** remove `py38`, `py39`, `py310`, `py311` — target is `py312`
- **CI matrix:** remove `"3.8"`, `"3.9"`, `"3.10"`, `"3.11"` from `python-version` lists
- **Classifiers:** remove `Programming Language :: Python :: 3.8/3.9/3.10/3.11` entries
- **`requires-python` / `python_requires`:** leave as-is for now — Step 1 will set `>=3.12` in `pyproject.toml`

---

### Step 1 — Phase 1: pyproject.toml

**Story tasks:**
- Migrate metadata from `setup.cfg`/`setup.py` into `[project]`
- Declare `dependencies` as a static list (not dynamic from a requirements file)
- Configure `setuptools-scm` for version discovery (PyPI repos only)
- Delete `setup.py` and `setup.cfg`

#### 1.1 — Create pyproject.toml

Read every field in `setup.cfg`/`setup.py` and migrate it. Do not invent fields that were not there.

**For PyPI repos** (release gate: yes):

Start with this exact template, then adapt every placeholder to match the repo (fill in name, description, license, readme filename, entry points, classifiers, Django versions, and dependencies from setup.cfg/setup.py and the .in files):

```toml
[build-system]
requires = ["setuptools", "setuptools-scm>8.1"]
build-backend = "setuptools.build_meta"

[project]
name = "<package-name>"          # from setup.cfg [metadata] name
description = "<short description>"  # from setup.cfg [metadata] description
readme = "README.rst"            # set to actual filename; keep here only when NOT in dynamic
requires-python = ">=3.12"
license = "AGPL-3.0-only"        # SPDX identifier — derive from master (see adaptation rules below)
license-files = ["LICENSE*"]
authors = [
    {name = "Open edX Project", email = "oscm@openedx.org"},
]
classifiers = [
    'Development Status :: 3 - Alpha',
    'Framework :: Django',
    'Framework :: Django :: 4.2',    # one entry per Django version tested; remove if not tested
    'Intended Audience :: Developers',
    'Natural Language :: English',
    'Programming Language :: Python :: 3',
    'Programming Language :: Python :: 3.12',
]
keywords = [
    "Python",
    "edx",
]

dynamic = ["readme", "version"]  # version via setuptools-scm; readme via [tool.setuptools.dynamic]
                                  # NOTE: remove "readme" from dynamic if set as static above

dependencies = [
    # copy from requirements/base.in — static list, no version constraints here
]

[project.entry-points."lms.djangoapp"]
# <app_label> = "<package>.apps:<AppConfig>"

[project.entry-points."cms.djangoapp"]
# <app_label> = "<package>.apps:<AppConfig>"

[project.urls]
Homepage = "https://github.com/openedx/<repo-name>"
Repository = "https://github.com/openedx/<repo-name>"

[dependency-groups]
test-base = [
    # packages from test.in minus Django — used when multiple Django versions are tested
]
test = [
    {include-group = "test-base"},
    "Django>=5.0,<6.0",          # highest Django version tested
]
django42 = [                     # add one group per legacy Django version tested
    {include-group = "test-base"},
    "Django>=4.2,<5.0",
]
quality = [
    {include-group = "test"},
    "edx-lint",
    "isort",
    "pycodestyle",
    "pydocstyle",                # include only if present in quality.in on master
]
doc = [
    {include-group = "test"},
    "doc8",
    "sphinx-book-theme",
    "twine",
    "build",
    "Sphinx",
]
ci = [
    "tox",
    "tox-uv",
]
dev = [
    {include-group = "quality"},
    {include-group = "ci"},
    "diff-cover",
    "edx-i18n-tools",            # include only if present in dev.in on master
]

[tool.setuptools]
include-package-data = true

[tool.setuptools.dynamic]
readme = {file = ["README.rst"], content-type = "text/x-rst"}
# If README is Markdown: {file = ["README.md"], content-type = "text/markdown"}
# Verify the actual README filename on disk

[tool.setuptools.packages.find]
where = ["src"]                  # omit this line for non-src/ layout

[tool.setuptools.package-data]
"*" = [
    # Add non-.py asset glob patterns migrated from master's MANIFEST.in
    # e.g. "*.html", "*.js", "*.css", "*.png"
    # e.g. "translations/**/*", "templates/**/*"
]

[tool.semantic_release]
# SETUPTOOLS_SCM_PRETEND_VERSION lets python-semantic-release drive the version
# at build time without needing a setup.py file.
build_command = "pip install build && SETUPTOOLS_SCM_PRETEND_VERSION=$NEW_VERSION python -m build"

# Zero-version guard — add ONLY if latest git tag starts with 0.x (e.g. v0.3.1)
# Omit entirely for 1.x+ repos
# allow_zero_version = true
# major_on_zero = false

# Do NOT add [tool.semantic_release.commit_parser_options]. Per
# public-engineering#506, other libraries use PSR's DEFAULT release tags
# (minor: feat; patch: fix, perf). The org-canonical backend-plugin-sample
# overrides these (minor adds "docs", patch adds "build") ONLY because it is a
# deliberate example-repo exception — #506 says not to copy that. Add an
# override here only if this specific repo has a documented reason to release
# on other commit types.

[tool.setuptools_scm]
version_scheme = 'only-version'
local_scheme = 'no-local-version'
fallback_version = "0.0.0.dev0"

[tool.uv]
# Each entry lists groups with mutually exclusive version requirements so uv can
# produce a single uv.lock with a separate resolution for each.
# Add a new pair here whenever you add a legacy-version group to [dependency-groups].
# Remove conflicts entirely if only one Django version is tested.
conflicts = [
    [{group = "test"}, {group = "django42"}],
]
constraint-dependencies = []

[tool.edx_lint]
# Repo-specific uv constraints merged with edx-lint's global constraints.
# Local entries override global ones for the same package.
# Run `make upgrade` to regenerate [tool.uv].constraint-dependencies.
uv_constraints = [
    # "some-package<=X.Y.Z",  # Date: YYYY-MM-DD — reason / link to issue
]
```

**Adaptation rules after writing the initial template:**
- Replace `<package-name>`, `<short description>`, and `<repo-name>` from `setup.cfg`/`setup.py`
- **Set `license` by mirroring master exactly** — master is the source of truth; never change the license intent. Read `setup.cfg`/`setup.py` and map to the correct SPDX identifier:

  | Master declares | SPDX identifier to use |
  |---|---|
  | `license = AGPL-3.0` or `license = AGPL` or classifier `AGPLv3` / `v3` (no "or later") | `"AGPL-3.0-only"` |
  | classifier `GNU Affero General Public License v3 or later (AGPLv3+)` or `license = AGPL-3.0-or-later` | `"AGPL-3.0-or-later"` |
  | `license = Apache-2.0` or classifier `Apache Software License` | `"Apache-2.0"` |
  | `license = MIT` | `"MIT"` |
  | `license = BSD` or classifier `BSD License` | `"BSD-3-Clause"` (verify which BSD variant) |
  | No `license=` field and no `License ::` classifier | Read the actual `LICENSE` file in the repo — its title/header line identifies the license (e.g. "Apache License, Version 2.0", "MIT License", "GNU AFFERO GENERAL PUBLIC LICENSE Version 3"). Map that to the correct SPDX identifier using the rows above. If the LICENSE file itself is absent or ambiguous, **ask the user explicitly** before writing any value, and add a `> [!CAUTION]` note in the PR description (see PR description format). |

  **Critical:** `AGPL-3.0` is a deprecated/invalid SPDX identifier — always use `AGPL-3.0-only` or `AGPL-3.0-or-later`. When metadata is missing, read the LICENSE file *header/title* to determine the license — do **not** rely on the "How to Apply These Terms to Your New Programs" appendix, which always contains "or later than version 3" as boilerplate template text and is **not** a grant this repo makes.
- `authors` must **always** be exactly `[{name = "Open edX Project", email = "oscm@openedx.org"}]` — do not copy whatever was in `setup.cfg` or `setup.py`; this is the org-standard value for all repos
- Verify the README filename on disk (`README.rst` vs `README.md`) and update `[tool.setuptools.dynamic]`; remove `readme` from `dynamic` if you set it as a static `readme =` field above
- Remove `[project.entry-points]` sections that have no entries on master
- Keep only the Django `Framework ::` classifiers that match the versions actually tested
- Populate `dependencies` from `requirements/base.in` (static list, no version pins)
- Adapt `[dependency-groups]` to mirror the actual `.in` files — remove groups whose `.in` doesn't exist, add packages from each `.in` file exactly; remove `django42`/`conflicts` if only one Django version is tested
- Add `[tool.setuptools.package-data]` entries from master's `MANIFEST.in` non-`.py` asset patterns
- Add zero-version guard to `[tool.semantic_release]` only if latest git tag starts with `0.`
- **Translation symlink guard (PyPI repos only):** If pre-flight command #16 found a git-tracked `translations/` symlink, add `[tool.setuptools.exclude-package-data]` right after `[tool.setuptools.package-data]`. Without it, `python -m build --wheel` fails at release time with "doesn't exist or not a regular file" — `setuptools-scm`'s file finder lists the symlink and `build_py` tries to copy it as a regular file, regardless of what `package-data` says. Moving assets to `conf/locale/**/*` in `package-data` does not fix it; the symlink must be explicitly excluded:
  ```toml
  [tool.setuptools.exclude-package-data]
  "*" = ["tests*", "*.tests*", "spec*", "*.spec*"]
  <package_name> = ["translations"]  # git-tracked symlink — build_py cannot copy symlinks
  ```
  Replace `<package_name>` with the package directory name (e.g. `drag_and_drop_v2`). This failure is invisible in CI because the standard matrix never runs `python -m build --wheel`; it surfaces only on the first `release.yml` run after merge.

**For non-PyPI repos** (release gate: no) — use a static version, no setuptools-scm:

```toml
[build-system]
requires = ["setuptools"]
build-backend = "setuptools.build_meta"

[project]
name = ""                        # from setup.cfg [metadata] name
version = ""                     # fetch from master: check setup.cfg [metadata] version=,
                                 # then setup.py (look for version= or __version__ import),
                                 # then package __init__.py (__version__ = "x.y.z")
                                 # bump manually at each release
description = ""
requires-python = ">=3.12"
license = "AGPL-3.0-only"       # SPDX identifier — derive from master (see adaptation rules below)
license-files = ["LICENSE*"]
authors = [
    {name = "Open edX Project", email = "oscm@openedx.org"},
]
classifiers = [
    "Development Status :: 3 - Alpha",
    "Intended Audience :: Developers",
    "Natural Language :: English",
    "Programming Language :: Python :: 3",
    "Programming Language :: Python :: 3.12",
]
keywords = [
    "Python",
    "edx",
]

readme = "README.rst"

dependencies = [
    # copy from requirements/base.in — static list
]

[project.urls]
Homepage = "https://github.com/openedx/<repo-name>"
Repository = "https://github.com/openedx/<repo-name>"

[tool.setuptools]
include-package-data = true

[tool.setuptools.packages.find]
exclude = ["tests*", "*.tests", "*.tests.*"]
# No src/ layout for non-PyPI repos

[tool.setuptools.package-data]
"*" = [
    # Add non-.py asset glob patterns migrated from master's MANIFEST.in
]

[tool.uv]
package = true
constraint-dependencies = []

[tool.edx_lint]
# Repo-specific uv constraints merged with edx-lint's global constraints.
# Local entries override global ones for the same package.
# Run `make upgrade` to regenerate [tool.uv].constraint-dependencies.
uv_constraints = [
    # "some-package<=X.Y.Z",  # Date: YYYY-MM-DD — reason / link to issue
]
```

**Coverage config** — migrate from `.coveragerc` only if it exists on master:

```toml
[tool.coverage.run]
branch = true
# For src/ layout repos use source = ["src"] — it tracks every .py file under
# src/ by path, so packages that are never imported (e.g. loncapa-style check
# scripts) still appear in the report.  source_pkgs resolves by import name and
# silently drops any package that pytest never imports, skewing the numbers.
# For flat layout (no src/ dir): use source = ["<package_import_name>"] instead.
source = ["src"]   # for src/ layout; replace with source = ["<pkg>"] for flat layout
omit = [
    "*/tests/*",
    "*/migrations/*",
]

[tool.coverage.report]
show_missing = true
# Only include fail_under if master's .coveragerc has it — do NOT invent a value
# fail_under = <value from .coveragerc>
```

**pytest config** — if master has `[tool:pytest]` in setup.cfg or `pytest.ini`, migrate it:

```toml
[tool.pytest.ini_options]
# Copy all settings from master verbatim — example:
# addopts = "--reuse-db"
# DJANGO_SETTINGS_MODULE = "test_settings"
```

**INI → TOML type coercion for multi-value pytest options:** In `tox.ini`/`pytest.ini` (INI format), multi-value options like `norecursedirs`, `filterwarnings`, and `markers` are space- or newline-separated strings. In `[tool.pytest.ini_options]` (TOML), they must be **arrays of strings** — copying the value verbatim produces a single-element array containing one space-joined string, which pytest cannot split and silently ignores.

```toml
# master tox.ini / pytest.ini (INI — space-separated):
# norecursedirs = .* docs requirements site-packages

# Correct migration to TOML array:
norecursedirs = [".*", "docs", "site-packages"]
```

Additionally, drop any directories that no longer exist after the migration (e.g. `requirements/` is deleted — remove it from `norecursedirs`). The same rule applies to any INI option that accepts multiple values: `filterwarnings`, `markers`, `testpaths`, etc.

**Critical — `addopts` with `--cov <dir>`:** If master's `addopts` contains `--cov <testdir>` (e.g. `--cov tests`), **drop the directory argument** and keep bare `--cov`:

```toml
# Master had: addopts = "--cov tests --cov-report term-missing"
# Correct migration:
addopts = "--cov --cov-report term-missing"
```

Why: `--cov <dir>` tells pytest-cov to measure that specific directory, overriding `[tool.coverage.run] source` in `pyproject.toml`. With bare `--cov`, pytest-cov defers to `source = ["src"]` and correctly measures the package instead of the test files. This was invisible on master because there was no `source` config — the conflict only surfaces after the migration adds it. Also delete `pytest.ini` after migrating — keeping it alongside `pyproject.toml` is redundant and confusing.

**Tooling config** — migrate from setup.cfg only if those sections exist on master:

```toml
[tool.isort]
# Copy all settings from master's [isort] section in setup.cfg verbatim.
# DO NOT change any style-affecting keys (multi_line_output, line_length, etc.)
# — changing them causes isort to reformat existing imports on next run.

[tool.mypy]
# Copy [mypy] and [mypy-*] sections from master's setup.cfg verbatim.
# Only include if mypy was already configured or used as a linter on master.
```

**Do NOT add:**
- `[tool.ruff]` or any ruff config — ruff is out of scope this cycle
- Any quality tooling config not already on master
- `fail_under` if master didn't have it
- `[tool.mypy]` if master had no mypy config or did not run mypy

#### 1.2 — Minimize MANIFEST.in

**Step 1 — Read and record master's MANIFEST.in before touching it:**

```bash
git show HEAD:MANIFEST.in
```

For every line in master's MANIFEST.in, classify it:

| Line type | Action |
|---|---|
| `include CHANGELOG.rst` | Drop — CHANGELOG.rst is deprecated and not packaged (kept in repo if it exists, else absent) |
| `include LICENSE.txt`, `include README.rst/md` | Drop — already declared via `license-files` and `readme` in pyproject.toml |
| `include requirements/*.in`, `include requirements/constraints.txt` | Drop — requirements/ is deleted |
| `recursive-include <pkg> *.html *.css *.js *.png ...` | **Migrate to `[tool.setuptools.package-data]`** — these are critical install-time assets |
| Any other `include` or `recursive-include` for package assets | **Migrate to `[tool.setuptools.package-data]`** |

**Step 2 — Migrate asset patterns to pyproject.toml `[tool.setuptools.package-data]`:**

Every `recursive-include <dir> *.ext` pattern from master's MANIFEST.in that covers non-Python files under the package directory must appear in `[tool.setuptools.package-data]`. Do not use generic globs like `conf/**/*` if master was more specific — mirror the exact extensions from master.

Example: if master had `recursive-include xapi_db_load *.html *.png *.js *.css`, then:

```toml
[tool.setuptools.package-data]
"*" = [
    "*.html",
    "*.png",
    "*.js",
    "*.css",
    # Add every extension from master's recursive-include lines
]
```

**Step 3 — Write the new minimized MANIFEST.in:**

```
# Exclude development, test, and documentation folders
prune .github
prune docs
prune tests

# Exclude root level configuration and build files
exclude Makefile
exclude conftest.py
exclude .gitignore
exclude tox.ini

# Exclude test/coverage artifacts (only if repo uses pytest-cov/coverage)
prune htmlcov
global-exclude .coverage
global-exclude coverage.xml
```

**Step 4 — Verify no assets are silently dropped** (also done in Step 5 final verification and Test 30):

```bash
uv run python -m build
# Then inspect that the tarball includes the same non-.py files as master's sdist
```

#### 1.3 — src/ layout

- **PyPI repo:** Move the package directory under `src/` (e.g. `src/<package_name>/`). This is the expected layout for PyPI packages. If the move is unusually complex, skip it and document in `## Important Notes` of the PR.
- **Non-PyPI repo:** Do NOT move to `src/` layout. Document in `## Important Notes` of the PR: "This repo does not publish to PyPI, so `src/` layout was not adopted."

#### 1.4 — Handle `__version__`

**Always keep `__version__` in the package `__init__.py` via `importlib.metadata` — as a norm, regardless of whether other code currently imports it.** This is the expected pattern across all Open edX repos.

Use this exact block for both PyPI and non-PyPI repos:

```python
from importlib.metadata import version

__version__ = version("<package-name>")
```

- **PyPI repo:** The hardcoded `__version__ = "x.y.z"` string is removed; the value is now derived from git tags via setuptools-scm at build time and from package metadata at runtime.
- **Non-PyPI repo:** The hardcoded string is replaced with the same importlib.metadata pattern. Also update any caller (e.g. `docs/conf.py`) to use `importlib.metadata.version("<package-name>")` instead of reading the source file with a regex.

---

### Step 2 — Phase 2: uv + dependency groups

**Story tasks:**
- Add `[dependency-groups]` to `pyproject.toml` covering test, quality, doc, ci, and dev
- Add `[tool.edx_lint].uv_constraints` for repo-specific pins; run `edx_lint write_uv_constraints` to populate `[tool.uv].constraint-dependencies`
- Generate `uv.lock` and commit it
- Delete the `requirements/` directory
- Update `tox.ini` to use `tox-uv>=1` and `uv-venv-lock-runner` with `dependency_groups`
- Update Makefile targets (`upgrade`, `compile-requirements`, `requirements`)
- Update CI to install uv via `astral-sh/setup-uv`, install deps via `uv sync --locked --group ci`, and run tests via `uv run tox` (**never** `uv run --locked` — see Test 250)

#### 2.1 — Add dependency groups to pyproject.toml

**Core rule: each dependency group must be an exact mirror of its corresponding `.in` file.**

For each `.in` file, read every non-comment, non-empty line:
- Direct package line (e.g. `pytest`) → add as a quoted package entry in the group
- `-r other.in` line → add as `{include-group = "other"}` (use the base filename without `.in`)
- `-c constraints.txt` → skip (handled via `[tool.edx_lint].uv_constraints`)
- `-e .` or git+ URL → add the egg name or the editable install as appropriate

Do **not** add packages that are not in the `.in` file, and do **not** drop packages that are.

```toml
[dependency-groups]
test = [
    # direct packages from test.in
    "coverage",
    "pytest",
    "pytest-cov",
    "pytest-django",
    # Django pinned to the highest version tested:
    "Django>=5.2,<6.0",
]

# If test.in has no Django pin and Django is added per-matrix (common pattern):
# Create a test-base group for the non-Django packages and one group per Django version:
# test-base = [<packages from test.in minus Django>]
# test       = [{include-group = "test-base"}, "Django>=5.2,<6.0"]
# django42   = [{include-group = "test-base"}, "Django>=4.2,<5.0"]
# Use this split ONLY when multiple Django versions are tested.

quality = [
    {include-group = "test"},
    # direct packages from quality.in — retain master's linters EXACTLY (NO ruff):
    "edx-lint",
    "isort",
    "pycodestyle",
    # add others only if they appear in quality.in
]

doc = [
    {include-group = "test"},
    # direct packages from doc.in:
    "build",
    "doc8",
    "Sphinx",
    "sphinx-book-theme",
]

ci = [
    # typically just tox + tox-uv; create this group if ci.in does not exist:
    "tox",
    "tox-uv",
]

dev = [
    {include-group = "quality"},  # only if dev.in has "-r quality.in"
    {include-group = "ci"},       # only if dev.in has "-r ci.in"
    {include-group = "doc"},      # only if dev.in has "-r doc.in"
    # direct packages from dev.in (those not already included via "-r"):
]
```

> **After writing the `doc` group**, cross-check it against what `tox -e docs` actually runs. If any Makefile target or tox command invokes a tool (e.g. `doc8`, `sphinx-apidoc`, `twine`) that is not in `doc.in` and not in the `doc` group, add it explicitly. Missing tools cause a silent "command not found" failure when `tox -e docs` runs.

**Group mapping rules:**
- `requirements/base.in` → `[project].dependencies` (runtime deps — never a dependency group)
- **Map every other `.in` file to a dependency group by default.** Prefer a group of the **same base name** (`test.in` → `test`, `ci.in` → `ci`, `dev.in` → `dev`). Deviate ONLY for one of the four strong reasons below, and record the reason in Table C:
  - **Canonical-rename** — a legacy name maps to the standard group name: `tox.in` → `ci`, `development.in` → `dev`, `testing.in` → `test`/`test-base`.
  - **Role-split** — one file must become several groups for the version matrix: `testing.in`'s `django` → `test`/`django42` (see Django rules below).
  - **`-r`-only** — the file has no direct packages (only `-r` includes); it collapses into the canonical aggregate (`dev`) rather than a redundant alias group.
  - **Documented drop** — the file's tool is deliberately removed (e.g. `pip_tools.in` → pip-compile is gone); no group, and the file appears under deleted `requirements/`.
- **Non-canonical name WITH direct packages AND a real consumer → create a same-named group.** If a bespoke `.in` (e.g. `sandbox.in`) holds direct packages and something installs them (a Dockerfile, an entrypoint, a separate sandbox venv), give it a same-named group and have the consumer install that group — do NOT scatter its packages into unrelated groups and then hardcode them at the consumer. This is the most-missed case: a `sandbox`-style group that must exist because a Dockerfile needs it.
- `-r other.in` in any `.in` file → `{include-group = "other"}` in the corresponding group
- If `ci.in` does not exist on master, create a `ci` group with `tox` and `tox-uv` as the only entries
- If only one Django version is tested, include `Django>=X.Y,<X+1.0` directly in `test` — no `test-base` split needed
- If multiple Django versions are tested, split into `test-base` (non-Django packages) + one group per Django version; `test` should be the highest-supported version

**Consuming a group outside the project venv** (Dockerfile, entrypoint, or any non-`.venv` virtualenv that used to `pip install -r requirements/X.txt`): install the matching group with
`uv pip install --python <path-to-venv>/bin/python --no-cache-dir --group <name>`
rather than re-listing packages by hand. This keeps the consumer in sync with `pyproject.toml`/`uv.lock` and is the general form of the `sandbox`/`ci`-group Dockerfile pattern.

**Declare uv conflicts** when multiple Django-version groups exist:

```toml
[tool.uv]
package = true
conflicts = [
    [{group = "test"}, {group = "django42"}],
]
```

#### 2.2 — Migrate constraints

Read `requirements/constraints.txt`. For each repo-specific pin (one with a comment explaining why it exists), add it to `[tool.edx_lint].uv_constraints`:

```toml
[tool.edx_lint]
uv_constraints = [
    # Date: YYYY-MM-DD
    # <Reason copied from constraints.txt comment>
    # <Link to issue if available>
    "some-package<=X.Y.Z",
]
```

If constraints.txt has no repo-specific pins (only global edx-lint constraints), use `uv_constraints = []`.

Then populate `[tool.uv].constraint-dependencies` automatically — never edit it by hand, and **never add any comment above the `constraint-dependencies` key**:

```bash
uv run --with edx-lint edx_lint write_uv_constraints pyproject.toml
```

The tool writes `constraint-dependencies` without a comment header. Any explanatory comment block placed above that key (e.g. `# machine-managed by edx-lint`, `# To regenerate, run:`) is a reviewer signal that the command was not actually run and the section was crafted manually instead.

#### 2.3 — Generate uv.lock

```bash
uv lock
```

**Use `uv lock`, not `uv lock --upgrade`.** Running `--upgrade` would silently bump all dependency versions as part of the migration diff, making the PR harder to review. The goal here is to lock at current versions; upgrades happen separately via the `upgrade` Makefile target after the PR merges.

Commit `uv.lock`. This file is the single source of truth for all locked dependencies.

#### 2.4 — Update tox.ini

Replace tox.ini using the **Makefile → tox → CI** tooling flow: tox provides the environment; the Makefile commands do the work.

```ini
[tox]
envlist = quality, docs, py312-django{42,52}
requires = tox-uv>=1

[testenv]
runner = uv-venv-lock-runner
setenv =
    PYTHONPATH = {toxinidir}
    # Copy any setenv / passenv from master's [testenv]
dependency_groups =
    django42: django42
    django52: test
allowlist_externals = make
commands =
    make test-with-coverage   # use whatever the test target is on master

[testenv:quality]
runner = uv-venv-lock-runner
dependency_groups = quality
allowlist_externals = make
commands =
    make quality

[testenv:docs]
runner = uv-venv-lock-runner
dependency_groups = doc
allowlist_externals = make
commands =
    make docs
```

**Adaptation rules:**
- Copy `setenv`, `passenv`, `changedir` from master's `[testenv]` verbatim
- If master tests only one Django version: use `dependency_groups = test` with a plain `[testenv]` (no matrix)
- If master has extra envs (e.g. `pii_check`, `translations`): add them, keeping same commands, using `runner = uv-venv-lock-runner` and the appropriate `dependency_groups`
- **Do NOT rename any environment** that master's tox.ini defines
- **Always add `[testenv:docs]`** — it is a required CI environment for all repos. Omit it only when the repo has no docs infrastructure whatsoever (no `docs/` directory, no `make docs` target, no Sphinx configuration) AND document the omission in `## Important Notes` of the PR with the specific reason.

#### 2.5 — Update Makefile

Only update the two targets the story changes. Everything else stays exactly as-is.

```makefile
requirements: ## install development environment requirements
	uv sync --locked --group dev

upgrade: ## update python dependencies
	uv run --with edx-lint edx_lint write_uv_constraints pyproject.toml
	uv lock --upgrade
```

**Every `uv sync` in the Makefile uses `--locked`** — same as CI. `make requirements` (and any other install target) then fails fast on a stale `uv.lock` instead of silently re-locking, so local envs always match what CI tests. When a developer edits dependencies in `pyproject.toml`, they run `uv lock` (or `make upgrade`) first.

**Never add `--locked` to the `upgrade` target.** Its whole job is to change the lockfile: `edx_lint write_uv_constraints` rewrites `[tool.uv].constraint-dependencies` in `pyproject.toml`, then `uv lock --upgrade` re-resolves. `uv lock --locked` asserts the lock is *unchanged* and would fail. Keep both `upgrade` lines exactly as shown.

**`--locked` goes on `uv sync` only — never on `uv run`** (Makefile or CI). The `uv sync --locked` step already fails on a stale `uv.lock`; repeating the flag on `uv run` adds nothing. Removed from all five modernize PRs on 2026-10-09 (e.g. edx-proctoring `780dcc06`).

**Do NOT add `uv tool install tox --with tox-uv` to the `requirements` target.** CI uses `uv sync --locked --group ci` + `uv run tox` (the locked, pinned tox from the `ci` dependency group). Installing a separate unpinned global tox via `uv tool install` is redundant and creates a version mismatch footgun — the global tox is outside `uv.lock` and can silently drift.

**Drop** only these targets (they are directly replaced by the story):
- `compile-requirements` — replaced by `uv lock`
- Any other pip-compile or `requirements/*.txt` generation targets

**Migrate ALL other targets that reference `requirements/*.txt`** — deleting `requirements/` breaks any target still calling `pip install -r requirements/*.txt`. Before touching any file, scan for them:

```bash
grep -n 'pip install.*requirements/' Makefile 2>/dev/null
```

For each hit, replace the `pip install -r` line using this mapping — **match the scope exactly, do not upgrade to a broader group**:

| Old command | Correct replacement |
|---|---|
| `pip install -r requirements/base.txt` | `uv sync --locked --no-default-groups` (runtime deps only — bare `uv sync` installs the `dev` group by default, ballooning the install from ~30 to ~90 packages) |
| `pip install -r requirements/test.txt` | `uv sync --locked --group test` |
| `pip install -r requirements/quality.txt` | `uv sync --locked --group quality` |
| `pip install -r requirements/doc.txt` | `uv sync --locked --group doc` |
| `pip install -r requirements/dev.txt` | `uv sync --locked --group dev` |

**Do NOT map a narrow-scope target (e.g. `base_requirements`) to `uv sync --locked --group dev`.** That installs all dev/test/quality packages where only runtime deps were intended.

**Keep and do not rename** everything else: `lint`, `test`, `test-with-coverage`, `docs`, and all other targets on master. Their implementations call the linters/pytest directly; tox manages the environment around them.

**No `uv run` prefix in Makefile targets (except `upgrade`)** — Feanil's rule (2026-09-28): Makefiles must not assume or force the uv environment. The developer controls their environment — locally by activating the venv or manually prefixing `uv run`, in CI by using `uv run tox` in the workflow step (not in the Makefile). Strip `uv run` from every target body except `upgrade`. Use bare tool names:

```makefile
test:
	pytest tests/           # not: uv run pytest tests/

quality:
	pylint src/             # not: uv run pylint src/
	isort --check-only src/ # not: uv run isort --check-only src/
```

Exception: `upgrade` keeps its `uv run --with edx-lint edx_lint write_uv_constraints pyproject.toml` line because the upgrade workflow requires it.

#### 2.6 — Update CI workflow

Create or update `.github/workflows/ci.yml`. The workflow **must be named `ci.yml`** (rename if currently named `python-tests.yml` or similar — update any `uses:` references in other workflows).

**Before writing the file, read master's existing CI workflow to extract its current action SHAs:**

```bash
# Read master's CI to capture existing SHA pins — NEVER go below these
git show HEAD:.github/workflows/ci.yml 2>/dev/null || git show HEAD:.github/workflows/python-tests.yml 2>/dev/null
```

Record every `uses: action@<SHA> # vX.Y.Z` line. For actions already on master, use the same SHA (or a newer one — never older). For new actions like `astral-sh/setup-uv`, fetch the latest SHA:

```bash
# Get latest SHA for astral-sh/setup-uv
gh api repos/astral-sh/setup-uv/git/ref/heads/main --jq '.object.sha'
# Get latest SHA for codecov-action (if needed)
gh api repos/codecov/codecov-action/git/ref/heads/main --jq '.object.sha'
```

```yaml
name: CI

on:
  pull_request:
  workflow_call:       # allows release.yml to call this as a reusable workflow

jobs:
  run_tests:
    name: ${{ matrix.toxenv }}
    runs-on: ubuntu-latest
    strategy:
      # Do NOT set fail-fast — it defaults to true. Adding it explicitly (whether
      # `true` or `false`) is an unnecessary deviation from master. Keep the
      # strategy block in parity with master's CI: if master omitted fail-fast,
      # omit it here too.
      matrix:
        python-version: ["3.12"]
        toxenv: [quality, docs, py]   # ← no Django: py; with Django: [quality, docs, django42, django52]
                                      # py, quality, and docs are required; omit docs only if the repo
                                      # has no docs infrastructure (no docs/ dir, no make docs, no Sphinx)
                                      # and document the omission in ## Important Notes of the PR

    steps:
      - name: Checkout repository
        uses: actions/checkout@<SHA_FROM_MASTER_OR_LATEST> # vX.Y.Z

      - name: Install uv
        uses: astral-sh/setup-uv@<LATEST_SHA> # vX.Y.Z
        with:
          enable-cache: true
          python-version: "${{ matrix.python-version }}"

      - name: Install CI dependencies
        run: uv sync --locked --group ci

      - name: Run tox
        run: uv run tox -e ${{ matrix.toxenv }}

      - name: Upload coverage to Codecov
        # Compound condition: toxenv name + python-version to pin the exact job.
        # No Django matrix → py. Django matrix → highest version, e.g. django52.
        if: matrix.toxenv == 'py' && matrix.python-version == '3.12'
        uses: codecov/codecov-action@<SHA_FROM_MASTER_OR_LATEST> # vX.Y.Z
        with:
          token: ${{ secrets.CODECOV_TOKEN }}
          flags: unittests
          fail_ci_if_error: true
```

**Parity rules:**
- **Do not add `fail-fast` to the matrix `strategy:` block.** `fail-fast` defaults to `true`, so setting it explicitly (`true` *or* `false`) is a needless deviation. Omit the key entirely and keep the `strategy:` block in parity with master — if master had no `fail-fast`, the modernized workflow must have none either.
- **Do not add `fetch-depth: 0` to the CI checkout step.** The reference CI workflows (`openedx/sample-plugin`, `openedx/xblocks-extra`) use the default shallow checkout even with the same `setuptools-scm` + `fallback_version` setup. A full-history checkout only slows CI — `setuptools-scm` falls back to `fallback_version` for the throwaway build artifact (nothing asserts a specific `__version__`), and the real release uses `SETUPTOOLS_SCM_PRETEND_VERSION`. Leave `actions/checkout` at its default depth in `ci.yml` **and `release.yml`**. The sample-plugin `release.yml` omits it too — `python-semantic-release` converts a shallow clone to a full one itself when it needs history. (Removed from edx-proctoring `935bb8ef` and edx-submissions `ebd0e5e` on 2026-10-09.)
- SHA-pin ALL actions — no mutable version tags (e.g. `@v4`)
- **Never downgrade a SHA** — for any action already on master, use its exact SHA or a newer one. Running with an older SHA than master is a regression.
- **Use `py` for the bare Python test env** (no Django suffix). The `python-version` matrix entry drives the interpreter. With Django matrix: use `django42`, `django52` etc.
- **Codecov `if:` condition** — use a compound condition that pins both the env name and the Python version: `if: matrix.toxenv == 'py' && matrix.python-version == '3.12'`. For Django matrix: `if: matrix.toxenv == 'django52' && matrix.python-version == '3.12'`.
- Keep any `env:` variables or step conditions from master's CI (e.g. `DJANGO_SETTINGS_MODULE`)
- If master's CI checked branch protection under specific job names, the new `name:` field on the matrix job must match exactly — check with repo owner before changing
- If master had no Codecov step, do not add one
- Do not add an `actions/setup-python` step — `astral-sh/setup-uv` handles Python installation via `python-version`
- **Never use `uv pip install` to override Django (or any package) version in CI.** `uv pip install "django~=X.Y.0"` bypasses the lockfile and is an anti-pattern for this modernization work. Django version selection must happen entirely through `uv sync --locked --group djangoXY` or `uv run tox -e djangoXY` — both of which pull the pinned version from `uv.lock`. If you see a step like `uv pip install "django~=${{ matrix.django-version }}.0"` on master, replace it with the correct `uv sync --locked --group ...` approach.
- **Preserve master's YAML list style — do not collapse a multi-line block list into a flow list.** If master writes a matrix list in block form (`os:\n  - ubuntu-latest`), keep it in block form; do not reformat it to flow form (`os: [ubuntu-latest]`). Block form keeps the diff clean — adding a new version (e.g. a new Python or OS entry) shows up as a single added line rather than editing an existing line, which is easier to read and to extend. This applies to every matrix list (`os`, `python-version`, `toxenv`, `django-version`, etc.). The template blocks in this skill use flow form only for brevity; match whatever style master already uses.
- **`codecov.yml` — do not create if absent.** Do not introduce a `codecov.yml` file if it does not already exist on master/main — an empty or header-only file adds noise with no value. If the repo already has one, read it (`git show master:codecov.yml`) and copy its settings verbatim; do not add any threshold, target, or key that is not already there (in particular, do not invent `coverage.status.patch.target` or any numeric threshold).
- **No `push:` trigger in `ci.yml` for PyPI repos.** When `release.yml` calls `ci.yml` via `workflow_call`, a separate `push: branches: [main]` trigger in `ci.yml` fires CI twice on every merge — both concurrent runs race to push to the coverage data branch, causing random failures. For PyPI repos, omit the `push:` trigger from `ci.yml` entirely; `release.yml` covers pushes to main. For **non-PyPI repos** (no `release.yml`), keep the `push:` trigger so coverage uploads still happen on merges.
- **`id: coverage_comment` on the coverage step.** If using `py-cov-action/python-coverage-comment-action`, the step must have `id: coverage_comment` — without it the coverage artifact is silently dropped and the PR comment is never posted. (Codecov-based repos are unaffected.)

---

### Step 3 — Phase 3: semantic-release

**Skip this entire step for non-PyPI repos.** Document in `## Important Notes` of the PR: "This repo has no PyPI publish workflow on master, so `python-semantic-release` and `release.yml` were not added."

**Story tasks (PyPI repos only):**
- Add `[tool.semantic_release]` config to `pyproject.toml`
- Add `release.yml` workflow that runs CI then publishes to PyPI via OIDC
- Add `commitlint.yml` workflow to enforce conventional commits on PRs

#### 3.1 — Add semantic-release config to pyproject.toml

```toml
[tool.semantic_release]
build_command = "pip install build && SETUPTOOLS_SCM_PRETEND_VERSION=$NEW_VERSION python -m build"

# Do NOT add changelog = false here — that belongs in release.yml as an action
# input (changelog: "false"). Putting it in pyproject.toml is an anti-pattern:
# it scatters release policy across two files and can silently drift out of sync.
#
# Do NOT add a [tool.semantic_release.changelog] section. We no longer manage a
# changelog file with PSR. Release notes live only on the GitHub Release page
# (PSR still creates the GitHub Release by default). See Step 3.4.

# Zero-version guard — add ONLY if latest git tag starts with 0.x (e.g. v0.3.1)
# Omit entirely for 1.x+ repos
allow_zero_version = true
major_on_zero = false

# Do NOT add [tool.semantic_release.commit_parser_options]. Per
# public-engineering#506, other libraries use PSR DEFAULT release tags
# (minor: feat; patch: fix, perf). backend-plugin-sample overrides these as a
# deliberate example-repo exception — #506 explicitly says not to copy it.
```

Check: `git tag --sort=version:refname | tail -1`. If it starts with `0.`, add the guard. If `1.` or higher, omit it.

#### 3.2 — Add release.yml

```yaml
name: Release

on:
  push:
    branches: [main]   # match master's default branch

jobs:
  run_ci:
    uses: ./.github/workflows/ci.yml

  release:
    needs: run_ci
    runs-on: ubuntu-latest
    if: github.ref_name == 'main'
    concurrency:
      group: ${{ github.workflow }}-release-${{ github.ref_name }}
      cancel-in-progress: false

    permissions:
      contents: write

    steps:
      - name: Checkout repository
        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          ref: ${{ github.ref_name }}

      - name: Force branch to workflow sha
        run: git reset --hard ${{ github.sha }}

      - name: Run Semantic Release
        id: release
        uses: python-semantic-release/python-semantic-release@9a026e9303981c866c3425723009becb2437c757 # v10.6.2
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          git_committer_name: "github-actions"
          git_committer_email: "actions@users.noreply.github.com"
          # Commit, tag, push and build, but don't create the GitHub release.
          # We create it ourselves in the next step so that the distributions
          # are attached before the release is published. See that step for why.
          vcs_release: "false"
          # Release notes live only on the GitHub Release page; no changelog file.
          changelog: "false"

      # The openedx org has immutable releases enabled, which freezes a release's
      # assets the moment it is published, so assets cannot be attached
      # afterwards. `gh release create` handles this by creating the release as a
      # draft, uploading the assets, and only then publishing it:
      # https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/immutable-releases
      - name: Create GitHub Release with Assets
        if: steps.release.outputs.released == 'true'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          # Reuse the release notes python-semantic-release generated for us.
          RELEASE_NOTES: ${{ steps.release.outputs.release_notes }}
          TAG: ${{ steps.release.outputs.tag }}
        run: |
          # Write the release notes to a file so arbitrary content (backticks,
          # $(...), quotes) passes through unexpanded.
          printf '%s' "$RELEASE_NOTES" > "$RUNNER_TEMP/release_notes.md"
          # Create the release as a draft, attach the dists, then publish.
          gh release create "$TAG" \
            --verify-tag \
            --title "$TAG" \
            --notes-file "$RUNNER_TEMP/release_notes.md" \
            dist/*

      - name: Upload distribution artifacts
        uses: actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a # v7.0.1
        if: steps.release.outputs.released == 'true'
        with:
          name: distribution-artifacts
          path: dist
          if-no-files-found: error

    outputs:
      released: ${{ steps.release.outputs.released || 'false' }}
      version: ${{ steps.release.outputs.version }}

  publish_to_pypi:
    runs-on: ubuntu-latest
    needs: release
    if: github.ref_name == 'main' && needs.release.outputs.released == 'true'

    permissions:
      contents: read
      id-token: write   # Required for OIDC trusted publishing

    steps:
      - name: Download build artifacts
        uses: actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c # v8.0.1
        with:
          name: distribution-artifacts
          path: dist

      - name: Publish to PyPI
        uses: pypa/gh-action-pypi-publish@dc37677b2e1c63e2034f94d8a5b11f265b73ba33 # v1.14.2
        # No user/password — OIDC trusted publisher (already configured on the repo's PyPI project).
```

The SHAs above are the current latest at the time of writing (`checkout` v7.0.1, `upload-artifact` v7.0.1, `download-artifact` v8.0.1, `python-semantic-release` v10.6.2, `gh-action-pypi-publish` v1.14.2). **Re-verify each against the latest release before use** — pin to a real **commit** SHA, not the annotated-tag object SHA:
```bash
for repo in actions/checkout actions/upload-artifact actions/download-artifact \
            python-semantic-release/python-semantic-release pypa/gh-action-pypi-publish; do
  tag=$(gh api repos/$repo/releases/latest --jq '.tag_name')
  # Resolve the tag to a commit SHA (dereferences annotated tags to the commit, not the tag object):
  sha=$(gh api repos/$repo/commits/$tag --jq '.sha')
  # Verify it resolves (returns the SHA, not a 422):
  gh api repos/$repo/commits/$sha --jq '.sha' >/dev/null && printf '%-50s %-9s %s\n' "$repo" "$tag" "$sha"
done
```

**SHA pinning rules for release.yml:**
- **Every action is SHA-pinned to a verified commit SHA** with the version in a trailing comment (e.g. `# v10.6.2`) — matching the `openedx/sample-plugin` reference standard. Pin the **commit** SHA, not the annotated-tag object SHA (they differ; the `commits/<tag>` lookup above returns the correct one).
- `pypa/gh-action-pypi-publish` — SHA-pinning is **non-negotiable**: a floating `@release/v1` branch on this action once caused a real production incident.
- `python-semantic-release/python-semantic-release` — **SHA-pin it** (with `# vX.Y.Z` comment), the same as `sample-plugin`. Even though it only runs on push to the default branch, pin it for consistency with the standard and to keep every `uses:` in the file verifiable.
- The GitHub Release is created by a `gh release create` shell step (not `python-semantic-release/publish-action`), so there is no action SHA to pin for it. This is required by the openedx org's **immutable releases** — assets must be attached to a draft before it is published. Keep `vcs_release: "false"` on the PSR step so it does not publish the release itself.
- `actions/checkout`, `actions/upload-artifact`, `actions/download-artifact` — SHA-pin as usual.

If master had a legacy `pypi-publish.yml` or similar workflow: `git rm .github/workflows/pypi-publish.yml`.

**Never delete cross-repo or release-automation workflows unless they directly depend on deleted functionality.** Workflows triggered on tag push or that call external services read from `$GITHUB_REF` or API calls — they are unaffected by this migration. Only delete a workflow if it explicitly reads/writes the hardcoded `__version__`, invokes pip-compile, or references a deleted file (e.g. `requirements/base.in`). When in doubt, keep it. Document every deleted workflow in the PR description with the precise reason.

**`upgrade-python-requirements.yml` — always keep this workflow.** Even though it previously used pip-compile under the hood, the shared `openedx/.github` workflow it calls installs uv and then runs plain `make upgrade`, which on the modernized branch is the uv path (`uv run --with edx-lint edx_lint write_uv_constraints pyproject.toml && uv lock --upgrade`). The `ADD_PATHS="requirements"` it sets only feeds the `peter-evans/create-pull-request` step, which is gated `if: env.is_fork == 'true'`; non-fork repos go through `pull_request_creator`, which commits whatever `make upgrade` changed with no path filter — and `edx-repo-tools` already reads `uv.lock`. Keeping this workflow is what **restores** weekly automated dependency upgrades (via `uv.lock` diffs) rather than just preserving them. If the workflow was failing before the migration on `make upgrade` (e.g. `pip-tools` against current pip), confirm it now passes on the modernized branch before considering removal.

#### 3.3 — Add commitlint.yml

```yaml
# Run commitlint on the commit messages in a pull request.

name: Lint Commit Messages

on:
  - pull_request

jobs:
  commitlint:
    uses: openedx/.github/.github/workflows/commitlint.yml@master
```

#### 3.3b — Update PR template

With `python-semantic-release` in place, version bumping, changelog entries and tagging are automated from commit message types — any manual checklist item for them is now meaningless and misleading. Replace them with a Conventional Commits reminder so contributors know which commit type triggers which release tier.

**Locate the template.** It may live at `.github/PULL_REQUEST_TEMPLATE.md`, `.github/pull_request_template.md`, or `docs/pull_request_template.md` (e.g. edx-proctoring). Check all three on master. If none exists, do not create one — only update an existing template.

**Use exactly this item** — the link must point to Open edX's own guidance (OEP-0051), **not** `conventionalcommits.org`. Feanil changed this himself in [openedx/forum#293](https://github.com/openedx/forum/pull/293) (commit `bd327c55`): *"one change to the checklist URL to point to our specific guidance on conventional commits."*

```markdown
- [ ] Commit messages (and PR title, if squash merging) use the correct
      [Conventional Commits](https://docs.openedx.org/projects/openedx-proposals/en/latest/best-practices/oep-0051-bp-conventional-commits.html#specification) type — they determine the
      release: `fix:` → patch, `feat:` → minor, `!` / `BREAKING CHANGE:` → major
```

**Rules:**
- **Remove** every manual release item: "Version bumped", "Updated the version number in `__init__.py`/`package.json`", "Changelog record added", "Described your changes in `CHANGELOG.rst`", and post-merge "Create a tag matching the new version number".
- **Place the item in the pre-merge checklist** (where "Version bumped" used to be). Never under a **Post-Merge** heading — PSR releases on merge, so a wrong commit type is already published by the time a post-merge item is checked. If removing the tag item leaves the Post-Merge section empty, delete the whole section.
- **Use the wording verbatim** — do not write variants like "If this should trigger a release, ensure the commit uses a conventional commit prefix…". The item covers every commit type (correctness, not just release triggers) and must mention the PR title for squash merges.
- Leave every other checklist item and heading untouched.

First seen in [openedx/edx-proctoring#1340](https://github.com/openedx/edx-proctoring/pull/1340) (commit `6eb6eb19`), where the item had been placed under Post-Merge with no OEP-0051 link.

---

#### 3.4 — Deprecate CHANGELOG.rst (do NOT wire it to semantic-release)

We no longer manage a changelog file with python-semantic-release. Release notes live **only** on the GitHub Release page (PSR still creates the GitHub Release). Do not add a `[tool.semantic_release.changelog]` config or any insertion marker.

- **If `CHANGELOG.rst` exists on master:** keep the file, but prepend a deprecation note at the very top (above all existing content — do not delete the old release notes below it):

  ```rst
  .. DEPRECATED: This changelog is no longer maintained. Release notes are
     published only on the GitHub Releases page:
     https://github.com/<org>/<repo>/releases
  ```

  Replace `<org>/<repo>` with the actual repo slug.

- **If `CHANGELOG.rst` does NOT exist on master:** do nothing. Do not create it. The repo ships without a changelog file.

---

### Step 4 — Delete stale files

**Before deleting, check for root-level `.py` files that linters target:**

```bash
# Master's Makefile may pass "*.py" to pylint/isort/pycodestyle.
# setup.py is about to be deleted. Check if any OTHER root-level .py files exist:
ls *.py 2>/dev/null | grep -v '^setup\.py$'
```

- If other root-level `.py` files exist: keep `*.py` in linter commands as-is.
- If `setup.py` was the only root-level `.py` file (nothing else returned): remove `*.py` from linter commands in the Makefile, AND document this in the "Updated Makefile targets" table in the PR description with reason: "`setup.py` was the only root-level `.py` file; the glob is removed since it would expand to nothing."
- **Never silently drop the glob** — if you remove it, it must appear in the PR description.

```bash
# Always delete:
git rm setup.py 2>/dev/null || true
git rm setup.cfg 2>/dev/null || true
git rm -r requirements/ 2>/dev/null || true

# Delete only if it existed on master:
git rm .coveragerc 2>/dev/null || true

# Delete if it existed on master — config migrated to [tool.pytest.ini_options] in pyproject.toml:
git rm pytest.ini 2>/dev/null || true

# NEVER delete CHANGELOG.rst — if it exists, Step 3.4 prepends a deprecation note (it is not wired to PSR).

# NEVER delete — ruff is out of scope:
# pylintrc, pylintrc_tweaks — leave exactly as on master
```

Verify:
```bash
for f in setup.py setup.cfg .coveragerc pytest.ini; do
  [ -f "$f" ] && echo "STALE: $f still exists" || echo "OK: $f absent"
done
[ -d requirements ] && echo "STALE: requirements/ still exists" || echo "OK: requirements/ absent"

for f in pylintrc pylintrc_tweaks; do
  git show HEAD:"$f" &>/dev/null 2>&1 && {
    [ -f "$f" ] && echo "OK: $f kept" || echo "REGRESSION: $f was deleted — restore it"
  }
done
```

---

### Step 5 — Final verification

Run these commands and fix anything that fails before opening the PR.

```bash
# Install dev environment
make requirements

# Run linting (master's pylint/isort/pycodestyle via tox → make)
make lint

# Run tests (all Django version combinations)
make test

# Check lockfile is consistent
uv lock --check

# Verify tox env listing works
uv run tox --listenvs

# Build the package (PyPI repos only)
uv run python -m build && ls dist/
```

A failure here is a regression introduced by the migration — fix it before opening the PR.

---

### Step 5a — Automated pre-PR validation (MUST pass before creating the PR)

Run every check below. Fix any `FAIL:` line before proceeding to Step 6. These checks catch the most common agent mistakes.

```bash
echo "======= PRE-PR VALIDATION ======="

# --- Check 1: fail-fast must NOT be set in CI, and strategy must stay in parity with master ---
echo "--- Check 1: fail-fast omitted + parity with master ---"
python3 << 'PYEOF'
import re, subprocess

WF = '.github/workflows/ci.yml'
try:
    pr = open(WF).read()
except FileNotFoundError:
    print("SKIP: no ci.yml found")
    raise SystemExit(0)

# fail-fast defaults to true; it must not appear at all (neither true nor false).
if re.search(r'^\s*fail-fast\s*:', pr, re.MULTILINE):
    print("FAIL: ci.yml sets fail-fast explicitly — remove it (it defaults to true; adding it deviates from master)")
else:
    print("OK: fail-fast is not set (defaults to true)")

# Parity: whatever master had for fail-fast, the PR must match (master omitted → PR omits).
base = next((b for b in ('main','master')
             if subprocess.run(['git','show-ref','--verify','--quiet',f'refs/heads/{b}'],
                               capture_output=True).returncode == 0), None)
if base:
    for wf in ('ci.yml','python-tests.yml'):
        r = subprocess.run(['git','show',f'{base}:.github/workflows/{wf}'],
                           capture_output=True, text=True)
        if r.returncode == 0:
            master_has = bool(re.search(r'^\s*fail-fast\s*:', r.stdout, re.MULTILINE))
            pr_has     = bool(re.search(r'^\s*fail-fast\s*:', pr, re.MULTILINE))
            if master_has != pr_has:
                print(f"FAIL: fail-fast parity broken vs {base}:{wf} — master {'set' if master_has else 'omitted'} it, PR {'sets' if pr_has else 'omits'} it")
            else:
                print(f"OK: fail-fast parity with {base}:{wf} preserved")
            break
    else:
        print(f"SKIP: no CI workflow on {base} to compare against")
else:
    print("SKIP: no local main/master branch for parity comparison")
PYEOF

# --- Check 2: toxenv must not use bare py3XX version-specific names ---
echo "--- Check 2: toxenv py vs py3XX ---"
python3 << 'PYEOF'
import re, glob
failures = []
for wf_path in glob.glob('.github/workflows/*.yml'):
    try:
        content = open(wf_path).read()
    except FileNotFoundError:
        continue
    for m in re.finditer(r'\bpy3\d{1,2}\b(?![-\w])', content):
        surrounding = content[max(0, m.start()-300):m.end()+50]
        if 'toxenv' in surrounding or 'matrix' in surrounding:
            failures.append(f"{wf_path}: bare toxenv entry '{m.group(0)}' — use 'py' instead (Feanil's rule)")
            break
if failures:
    for f in failures: print(f"FAIL: {f}")
else:
    print("OK: no bare py3XX toxenv entries")
PYEOF

# --- Check 3: Codecov if: condition matches toxenv name in matrix ---
echo "--- Check 3: Codecov condition ---"
python3 << 'PYEOF'
import re
try:
    content = open('.github/workflows/ci.yml').read()
except FileNotFoundError:
    print("SKIP: no ci.yml found")
    raise SystemExit(0)

# Find toxenv matrix entries
toxenv_match = re.search(r'toxenv:\s*\[([^\]]+)\]', content)
if not toxenv_match:
    print("SKIP: no toxenv matrix found")
    raise SystemExit(0)

toxenv_values = [t.strip().strip('"').strip("'") for t in toxenv_match.group(1).split(',')]

# Find Codecov condition — must be compound: matrix.toxenv == 'X' && matrix.python-version == 'Y'
codecov_match = re.search(r"if:\s*matrix\.toxenv\s*==\s*['\"]([^'\"]+)['\"]", content)
if codecov_match:
    condition_toxenv = codecov_match.group(1)
    has_pyver = bool(re.search(r"matrix\.python-version\s*==", content))
    if condition_toxenv not in toxenv_values:
        print(f"FAIL: Codecov condition references '{condition_toxenv}' but matrix has {toxenv_values}")
    elif not has_pyver:
        print(f"FAIL: Codecov condition is missing matrix.python-version check — use compound: matrix.toxenv == '{condition_toxenv}' && matrix.python-version == '3.12'")
    else:
        print(f"OK: Codecov condition '{condition_toxenv}' with python-version check matches matrix entry")
else:
    print("OK: no Codecov step (or no matrix.toxenv condition found)")
PYEOF

# --- Check 4: No action SHA downgrades vs master ---
echo "--- Check 4: SHA downgrades ---"
python3 << 'PYEOF'
import re, subprocess

def extract_sha_versions(content):
    actions = {}
    for line in content.splitlines():
        m = re.search(r'uses:\s+([^@\s]+)@([0-9a-f]{40})\s+#\s*(v[\d.]+)', line)
        if m:
            actions[m.group(1)] = m.group(3)
    return actions

def ver_tuple(v):
    try: return tuple(int(x) for x in v.lstrip('v').split('.'))
    except: return (0,)

base = next((b for b in ('main','master') if subprocess.run(['git','show-ref','--verify','--quiet',f'refs/heads/{b}'],capture_output=True).returncode==0), None)
if not base:
    print("SKIP: no local main/master branch")
    raise SystemExit(0)

master_vers = {}
for wf in ['ci.yml','python-tests.yml','release.yml']:
    r = subprocess.run(['git','show',f'{base}:.github/workflows/{wf}'],capture_output=True,text=True)
    if r.returncode == 0:
        for a,v in extract_sha_versions(r.stdout).items():
            if a not in master_vers or ver_tuple(v) > ver_tuple(master_vers[a]):
                master_vers[a] = v

pr_vers = {}
import glob
for wf in glob.glob('.github/workflows/*.yml'):
    try: content = open(wf).read()
    except: continue
    for a,v in extract_sha_versions(content).items():
        if a not in pr_vers or ver_tuple(v) > ver_tuple(pr_vers[a]):
            pr_vers[a] = v

failures = [(a, master_vers[a], pr_vers[a]) for a in pr_vers if a in master_vers and ver_tuple(pr_vers[a]) < ver_tuple(master_vers[a])]
if failures:
    for a,mv,pv in failures: print(f"FAIL: {a} downgraded from {mv} (master) to {pv} (PR)")
else:
    print("OK: no action SHA downgrades vs master")
PYEOF

# --- Check 5: MANIFEST.in asset patterns migrated to package-data ---
echo "--- Check 5: MANIFEST.in asset migration ---"
python3 << 'PYEOF'
import re, subprocess, tomllib

r = subprocess.run(['git','show','HEAD:MANIFEST.in'],capture_output=True,text=True)
if r.returncode != 0:
    print("SKIP: no MANIFEST.in on master")
    raise SystemExit(0)

# Find recursive-include or include lines with non-.py extensions
asset_patterns = []
for line in r.stdout.splitlines():
    line = line.strip()
    if line.startswith('recursive-include') or (line.startswith('include') and not line.startswith('include CHANGELOG') and not line.startswith('include LICENSE') and not line.startswith('include README') and not line.startswith('include requirements')):
        exts = re.findall(r'\*\.\w+', line)
        non_py = [e for e in exts if e != '*.py']
        if non_py:
            asset_patterns.append((line, non_py))

if not asset_patterns:
    print("OK: no non-Python asset patterns in master MANIFEST.in")
    raise SystemExit(0)

try:
    with open('pyproject.toml','rb') as f:
        data = tomllib.load(f)
    pkg_data = data.get('tool',{}).get('setuptools',{}).get('package-data',{})
    pkg_data_str = str(pkg_data)
except Exception as e:
    print(f"FAIL: could not read pyproject.toml — {e}")
    raise SystemExit(1)

failures = []
for line, exts in asset_patterns:
    for ext in exts:
        bare = ext.lstrip('*').lstrip('.')  # e.g. "html"
        if bare not in pkg_data_str:
            failures.append(f"Master MANIFEST.in has '{line}' → extension '{ext}' not found in [tool.setuptools.package-data]")

if failures:
    for f in failures: print(f"FAIL: {f}")
else:
    print(f"OK: all MANIFEST.in asset patterns ({[p[0] for p in asset_patterns]}) present in package-data")
PYEOF

# --- Check 6: stale files absent, pylintrc present ---
echo "--- Check 6: stale files ---"
for f in setup.py setup.cfg .coveragerc pytest.ini; do
  [ -f "$f" ] && echo "FAIL: $f still exists — config should be migrated to pyproject.toml" || echo "OK: $f absent"
done
[ -d requirements ] && echo "FAIL: requirements/ still exists" || echo "OK: requirements/ absent"
for f in pylintrc pylintrc_tweaks; do
  git show HEAD:"$f" &>/dev/null 2>&1 && {
    [ -f "$f" ] && echo "OK: $f kept" || echo "FAIL: $f deleted — ruff is out of scope, restore it"
  }
done

# --- Check 7: lockfile in sync ---
echo "--- Check 7: uv.lock ---"
uv lock --check && echo "OK: uv.lock in sync" || echo "FAIL: uv.lock out of sync — run uv lock"

# --- Check 8: no ruff introduced ---
echo "--- Check 8: ruff absence ---"
if grep -rnE '(^|[^a-z])ruff([^a-z]|$)' pyproject.toml uv.lock tox.ini Makefile .github/workflows/ 2>/dev/null | grep -iE 'ruff' | grep -vE 'ruffle|scruff' | grep -q .; then
  echo "FAIL: ruff found — ruff is out of scope this cycle"
else
  echo "OK: ruff absent"
fi

# --- Check 9: setup.py/setup.cfg migration parity ---
echo "--- Check 9: setup.py/setup.cfg migration parity ---"
python3 << 'PYEOF'
import re, subprocess, tomllib, configparser

FAIL = "FAIL"; WARN = "WARN"; INFO = "info"
findings = []
def add(sev, msg): findings.append((sev, msg))

BASE = None
for b in ("main", "master"):
    r = subprocess.run(["git", "show-ref", "--verify", "--quiet", f"refs/heads/{b}"], capture_output=True)
    if r.returncode == 0:
        BASE = b; break
if not BASE:
    for remote in ("upstream", "origin"):
        for b in ("main", "master"):
            r = subprocess.run(["git", "ls-remote", "--exit-code", "--heads", remote, b], capture_output=True)
            if r.returncode == 0:
                BASE = f"{remote}/{b}"; break
        if BASE: break
if not BASE:
    print("SKIP: no main/master branch found"); raise SystemExit(0)

def git_show(path):
    r = subprocess.run(["git", "show", f"{BASE}:{path}"], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None

def extract_setup_py_field(content, field):
    if not content: return None
    m = re.search(rf'{field}\s*=\s*\[([^\]]+)\]', content, re.DOTALL)
    if m: return re.findall(r'["\']([^"\']+)["\']', m.group(1)) or None
    m = re.search(rf'{field}\s*=\s*["\']([^"\']+)["\']', content)
    return m.group(1) if m else None

try:
    with open("pyproject.toml", "rb") as f: toml = tomllib.load(f)
except Exception as e:
    print(f"FAIL: cannot read pyproject.toml — {e}"); raise SystemExit(1)

project = toml.get("project", {}); tool = toml.get("tool", {})
setup_cfg = git_show("setup.cfg"); setup_py = git_show("setup.py"); coveragerc = git_show(".coveragerc")
cfg = configparser.ConfigParser()
if setup_cfg: cfg.read_string(setup_cfg)

def cfg_meta(key):
    for section in ("metadata", "options"):
        if cfg.has_section(section) and cfg.has_option(section, key):
            return cfg.get(section, key).strip()
    return extract_setup_py_field(setup_py, key)

master_name = cfg_meta("name"); pr_name = project.get("name", "")
if master_name and pr_name and master_name.replace("_","-").lower() != pr_name.replace("_","-").lower():
    add(FAIL, f"[project].name mismatch: master={master_name!r} PR={pr_name!r}")
elif not pr_name: add(FAIL, "[project].name missing")

if cfg_meta("description") and not project.get("description"):
    add(FAIL, f"[project].description missing")

master_py = cfg_meta("python_requires")
if master_py and not project.get("requires-python"):
    add(FAIL, f"[project].requires-python missing (master had: {master_py!r})")

master_license = cfg_meta("license")
if master_license and not project.get("license"):
    add(WARN, f"[project].license missing (master had: {master_license!r})")

master_cls_raw = cfg_meta("classifiers")
if master_cls_raw:
    master_cls = [c.strip() for c in master_cls_raw.splitlines() if c.strip() and not c.startswith("#")]
else:
    master_cls = extract_setup_py_field(setup_py, "classifiers") or []
pr_cls = project.get("classifiers", [])
if master_cls and not pr_cls:
    add(WARN, f"No classifiers in [project] (master had {len(master_cls)} classifiers)")
elif pr_cls:
    master_license_cls = [c for c in master_cls if "License ::" in c]
    if master_license_cls and not any("License ::" in c for c in pr_cls):
        add(INFO, f"License classifier dropped — master had: {master_license_cls[0]!r}")
    for d in sorted({c for c in master_cls if "Python :: 3." not in c and "License ::" not in c} - set(pr_cls)):
        add(INFO, f"Classifier dropped: {d!r}")

master_eps = {}
for section in ("options.entry_points", "entry_points"):
    if cfg.has_section(section):
        for k, v in cfg.items(section): master_eps[k] = v.strip()
if setup_py and not master_eps:
    m = re.search(r'entry_points\s*=\s*\{([^}]+)\}', setup_py, re.DOTALL)
    if m:
        for km in re.finditer(r'["\']([^"\']+)["\']\s*:\s*\[([^\]]+)\]', m.group(1), re.DOTALL):
            master_eps[km.group(1)] = km.group(2)
if "console_scripts" in master_eps and not project.get("scripts"):
    add(FAIL, "[project.scripts] missing — master had console_scripts")
for ep_key in master_eps:
    if ep_key != "console_scripts" and ep_key not in str(project.get("entry-points", {})):
        add(WARN, f"Entry point group {ep_key!r} from master not in [project.entry-points]")

if project.get("dependencies") is None:
    add(FAIL, "[project].dependencies missing")

if cfg.has_section("isort") and "isort" not in tool:
    add(WARN, "[isort] in master's setup.cfg not migrated to [tool.isort]")

has_mypy = cfg.has_section("mypy") or any(s.startswith("mypy-") for s in cfg.sections())
if has_mypy and "mypy" not in tool:
    add(WARN, "[mypy] in master's setup.cfg not migrated to [tool.mypy]")

has_pytest = cfg.has_section("tool:pytest") or cfg.has_section("pytest")
if not has_pytest:
    tox_ini = git_show("tox.ini")
    if tox_ini:
        tox_cfg = configparser.ConfigParser(); tox_cfg.read_string(tox_ini)
        has_pytest = tox_cfg.has_section("pytest")
if has_pytest and "pytest" not in tool:
    add(WARN, "[tool:pytest] config on master not migrated to [tool.pytest.ini_options]")

has_cov = bool(coveragerc) or cfg.has_section("coverage:run") or cfg.has_section("coverage:report")
if has_cov and "coverage" not in tool:
    add(WARN, "Coverage config on master not migrated to [tool.coverage]")

master_ipd = cfg.get("options", "include_package_data", fallback=None)
if not master_ipd and setup_py and re.search(r'include_package_data\s*=\s*True', setup_py):
    master_ipd = "True"
if master_ipd and master_ipd.lower() in ("true","1","yes") and not tool.get("setuptools",{}).get("include-package-data"):
    add(INFO, "[tool.setuptools] include-package-data = true not set (master had include_package_data=True)")

EXPECTED_AUTHORS = [{"name": "Open edX Project", "email": "oscm@openedx.org"}]
pr_authors = project.get("authors", [])
if pr_authors != EXPECTED_AUTHORS:
    add(FAIL, f"[project].authors must be exactly {EXPECTED_AUTHORS!r} — got {pr_authors!r}")

fails = [f for f in findings if f[0] == FAIL]
warns = [f for f in findings if f[0] == WARN]
infos = [f for f in findings if f[0] == INFO]
for sev, msg in findings:
    label = {"FAIL": "FAIL", "WARN": "WARN", "info": "info"}[sev]
    print(f"  [{label}]  {msg}")
print(f"setup.py/setup.cfg parity: {len(fails)} FAIL, {len(warns)} WARN, {len(infos)} info")
if fails: raise SystemExit(1)
PYEOF

# --- Check 10: codecov.yml not introduced when master didn't have one ---
echo "--- Check 10: codecov.yml ---"
python3 << 'PYEOF'
import subprocess, os

# Does master have codecov.yml?
base = next((b for b in ('main','master') if subprocess.run(['git','show-ref','--verify','--quiet',f'refs/heads/{b}'],capture_output=True).returncode==0), None)
if not base:
    print("SKIP: no local main/master branch")
    raise SystemExit(0)

master_has = subprocess.run(['git','show',f'{base}:codecov.yml'],capture_output=True).returncode == 0
pr_has = os.path.isfile('codecov.yml')

if pr_has and not master_has:
    print("FAIL: codecov.yml introduced but master had none — delete it (do not invent thresholds)")
    raise SystemExit(1)

if pr_has and master_has:
    # Both have it — check for invented keys not present on master
    master_content = subprocess.run(['git','show',f'{base}:codecov.yml'],capture_output=True,text=True).stdout
    pr_content = open('codecov.yml').read()
    invented = []
    for key in ('target:', 'threshold:', 'fail_under:'):
        if key in pr_content and key not in master_content:
            invented.append(key)
    if invented:
        print(f"FAIL: codecov.yml has key(s) not in master: {invented} — copy master verbatim, do not add thresholds")
        raise SystemExit(1)
    print("OK: codecov.yml copied from master (no invented keys)")
else:
    print("OK: codecov.yml status matches master")
PYEOF

# --- Check 11: tox.ini env section order matches master ---
echo "--- Check 11: tox.ini env order ---"
python3 << 'PYEOF'
import re, subprocess

base = next((b for b in ('main','master') if subprocess.run(['git','show-ref','--verify','--quiet',f'refs/heads/{b}'],capture_output=True).returncode==0), None)
if not base:
    print("SKIP: no local main/master branch")
    raise SystemExit(0)

def get_tox_sections(content):
    sections = []
    for line in content.splitlines():
        m = re.match(r'^\[testenv(?::([^\]]+))?\]', line.strip())
        if m:
            sections.append(m.group(1) or '(default)')
    return sections

r = subprocess.run(['git','show',f'{base}:tox.ini'], capture_output=True, text=True)
if r.returncode != 0:
    print("SKIP: no tox.ini on master")
    raise SystemExit(0)

master_sections = get_tox_sections(r.stdout)
try:
    pr_sections = get_tox_sections(open('tox.ini').read())
except FileNotFoundError:
    print("FAIL: tox.ini not found")
    raise SystemExit(1)

pr_set = set(pr_sections)
master_set = set(master_sections)
master_common = [s for s in master_sections if s in pr_set]
pr_common = [s for s in pr_sections if s in master_set]

if master_common != pr_common:
    print(f"FAIL: tox.ini section order differs from master")
    print(f"  Master order (common sections): {master_common}")
    print(f"  PR order (common sections):     {pr_common}")
else:
    print(f"OK: tox.ini env section order matches master ({pr_common})")
PYEOF

# --- Check 12: no new tox environments beyond py/docs/quality (lint) ---
echo "--- Check 12: no new tox environments ---"
python3 << 'PYEOF'
import re, subprocess

base = next((b for b in ('main','master') if subprocess.run(['git','show-ref','--verify','--quiet',f'refs/heads/{b}'],capture_output=True).returncode==0), None)
if not base:
    print("SKIP: no local main/master branch")
    raise SystemExit(0)

def get_named_envs(content):
    envs = set()
    for line in content.splitlines():
        m = re.match(r'^\[testenv:([^\]]+)\]', line.strip())
        if m:
            envs.add(m.group(1))
    return envs

r = subprocess.run(['git','show',f'{base}:tox.ini'], capture_output=True, text=True)
master_envs = get_named_envs(r.stdout) if r.returncode == 0 else set()

try:
    pr_envs = get_named_envs(open('tox.ini').read())
except FileNotFoundError:
    print("FAIL: tox.ini not found")
    raise SystemExit(1)

ALLOWED_NEW = {'lint', 'quality', 'docs'}
new_envs = pr_envs - master_envs
disallowed_new = new_envs - ALLOWED_NEW

if disallowed_new:
    print(f"FAIL: new tox environments introduced beyond py/docs/quality: {sorted(disallowed_new)}")
    print(f"  Only [testenv] (py), [testenv:docs], and [testenv:lint]/[testenv:quality] may be introduced")
    raise SystemExit(1)
elif new_envs:
    print(f"OK: only permitted new environments introduced: {sorted(new_envs)}")
else:
    print(f"OK: no new tox environments introduced")
PYEOF

# --- Check 13: Makefile target order matches master ---
echo "--- Check 13: Makefile target order ---"
python3 << 'PYEOF'
import re, subprocess

base = next((b for b in ('main','master') if subprocess.run(['git','show-ref','--verify','--quiet',f'refs/heads/{b}'],capture_output=True).returncode==0), None)
if not base:
    print("SKIP: no local main/master branch")
    raise SystemExit(0)

def get_targets(content):
    targets = []
    for line in content.splitlines():
        if line.startswith('\t') or line.startswith(' '):
            continue
        m = re.match(r'^([a-zA-Z_][a-zA-Z0-9_.-]*):', line)
        if m:
            targets.append(m.group(1))
    return targets

r = subprocess.run(['git','show',f'{base}:Makefile'], capture_output=True, text=True)
if r.returncode != 0:
    print("SKIP: no Makefile on master")
    raise SystemExit(0)
master_targets = get_targets(r.stdout)

try:
    pr_targets = get_targets(open('Makefile').read())
except FileNotFoundError:
    print("FAIL: Makefile not found")
    raise SystemExit(1)

pr_set = set(pr_targets)
master_set = set(master_targets)
master_common = [t for t in master_targets if t in pr_set]
pr_common = [t for t in pr_targets if t in master_set]

if master_common != pr_common:
    print(f"FAIL: Makefile target order differs from master")
    print(f"  Master order (common targets): {master_common}")
    print(f"  PR order (common targets):     {pr_common}")
    raise SystemExit(1)
else:
    print(f"OK: Makefile target order matches master")
PYEOF

# --- Check 14: Makefile changes are in scope (no new/removed targets outside allowed) ---
echo "--- Check 14: Makefile changes in scope ---"
python3 << 'PYEOF'
import re, subprocess

base = next((b for b in ('main','master') if subprocess.run(['git','show-ref','--verify','--quiet',f'refs/heads/{b}'],capture_output=True).returncode==0), None)
if not base:
    print("SKIP: no local main/master branch")
    raise SystemExit(0)

def get_targets(content):
    targets = []
    for line in content.splitlines():
        if line.startswith('\t') or line.startswith(' '):
            continue
        m = re.match(r'^([a-zA-Z_][a-zA-Z0-9_.-]*):', line)
        if m:
            targets.append(m.group(1))
    return targets

r = subprocess.run(['git','show',f'{base}:Makefile'], capture_output=True, text=True)
if r.returncode != 0:
    print("SKIP: no Makefile on master")
    raise SystemExit(0)
master_targets = get_targets(r.stdout)
master_set = set(master_targets)

try:
    pr_targets = get_targets(open('Makefile').read())
except FileNotFoundError:
    print("FAIL: Makefile not found")
    raise SystemExit(1)
pr_set = set(pr_targets)

# Allowed removals: compile-requirements and any pip-compile-style targets
pip_compile_re = re.compile(r'pip.?compile|compile.?req', re.IGNORECASE)
allowed_removed = {'compile-requirements'} | {t for t in master_targets if pip_compile_re.search(t)}

failures = []

new_targets = pr_set - master_set
if new_targets:
    failures.append(f"New Makefile targets introduced (not in master): {sorted(new_targets)}")

removed_targets = master_set - pr_set
disallowed_removed = removed_targets - allowed_removed
if disallowed_removed:
    failures.append(f"Makefile targets removed outside PR scope: {sorted(disallowed_removed)}")

if failures:
    for f in failures:
        print(f"FAIL: {f}")
    raise SystemExit(1)
else:
    if removed_targets:
        print(f"OK: only in-scope targets removed ({sorted(removed_targets)}); no new targets added")
    else:
        print(f"OK: no Makefile targets added or removed outside scope")
PYEOF

# --- Check 15: no source-tracing comments in [dependency-groups] ---
echo "--- Check 15: no source-tracing comments in [dependency-groups] ---"
python3 << 'PYEOF'
import re

try:
    content = open('pyproject.toml').read()
except FileNotFoundError:
    print("SKIP: no pyproject.toml found")
    raise SystemExit(0)

dep_groups_match = re.search(r'^\[dependency-groups\]', content, re.MULTILINE)
if not dep_groups_match:
    print("SKIP: no [dependency-groups] section found")
    raise SystemExit(0)

next_section = re.search(r'^\[', content[dep_groups_match.end():], re.MULTILINE)
dep_groups_content = content[dep_groups_match.start(): dep_groups_match.end() + (next_section.start() if next_section else len(content))]

BAD_PATTERNS = [
    (r'#.*\bFrom requirements/', 'source-tracing comment referencing old requirements file'),
    (r'#.*requirements/.*\.in', 'source-tracing comment referencing old .in file'),
    (r'#.*Each group mirrors', 'boilerplate migration comment'),
    (r'#.*-r \S+\.in.*include-group', 'migration mechanics comment explaining .in syntax'),
    (r'#.*Direct packages.*listed verbatim', 'obvious statement comment'),
]

failures = []
for line in dep_groups_content.splitlines():
    stripped = line.strip()
    if not stripped.startswith('#'):
        continue
    for pattern, description in BAD_PATTERNS:
        if re.search(pattern, stripped, re.IGNORECASE):
            failures.append(f"  {description}: {stripped!r}")
            break

if failures:
    print("FAIL: source-tracing/unimportant comments found in [dependency-groups]:")
    for f in failures: print(f)
    print("  Remove these — group names and include-group entries already document the structure.")
    raise SystemExit(1)
else:
    print("OK: no source-tracing comments in [dependency-groups]")
PYEOF

# --- Check 18: no uv tool install tox in Makefile requirements target ---
echo "--- Check 18: no uv tool install tox in Makefile ---"
python3 << 'PYEOF'
import re

try:
    content = open('Makefile').read()
except FileNotFoundError:
    print("SKIP: no Makefile found")
    raise SystemExit(0)

if re.search(r'uv\s+tool\s+install\s+tox', content):
    print("FAIL: 'uv tool install tox' found in Makefile — this installs an unpinned global tox outside uv.lock. "
          "Remove it; CI uses 'uv sync --locked --group ci' + 'uv run tox' (the locked tox from the ci dependency group).")
else:
    print("OK: no 'uv tool install tox' in Makefile")
PYEOF

# --- Check 21: no uv pip install in CI workflows ---
echo "--- Check 21: no uv pip install in CI workflows ---"
if grep -rqE 'uv pip install' .github/workflows/ 2>/dev/null; then
  echo "FAIL: 'uv pip install' found in CI workflow(s) — this is an anti-pattern:"
  grep -rnE 'uv pip install' .github/workflows/
  echo "  Use 'uv sync --locked --group <name>' or 'uv run tox -e <env>' instead — both pull from uv.lock."
else
  echo "OK: no uv pip install in CI workflows"
fi

# --- Check 20: no stray pip install -r requirements/ in Makefile ---
echo "--- Check 20: no stray pip install -r requirements/ in Makefile ---"
if grep -qE 'pip install.*requirements/' Makefile 2>/dev/null; then
  echo "FAIL: Makefile still references requirements/ files via pip install:"
  grep -nE 'pip install.*requirements/' Makefile
  echo "  requirements/ is deleted — migrate each target to 'uv sync --locked [--group <name>]' using the correct scope"
else
  echo "OK: no pip install -r requirements/ references in Makefile"
fi

# --- Check 19: constraint-dependencies is non-empty ---
echo "--- Check 19: constraint-dependencies populated ---"
python3 -c "
import tomllib
with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)
deps = data.get('tool', {}).get('uv', {}).get('constraint-dependencies', None)
if deps is None:
    print('FAIL: [tool.uv].constraint-dependencies missing — run edx_lint write_uv_constraints')
elif not deps:
    print('FAIL: constraint-dependencies is empty — edx_lint write_uv_constraints was not run')
else:
    print(f'OK: constraint-dependencies has {len(deps)} entries')
"

# --- Check 16: required tox environments present (py, quality, docs) ---
echo "--- Check 16: required tox environments ---"
python3 << 'PYEOF'
import re

try:
    content = open('tox.ini').read()
except FileNotFoundError:
    print("FAIL: tox.ini not found")
    raise SystemExit(1)

# [testenv] (no suffix) is the py/default test env
has_py = bool(re.search(r'^\[testenv\]', content, re.MULTILINE))
# quality or lint are both acceptable
has_quality = bool(re.search(r'^\[testenv:(quality|lint)\]', content, re.MULTILINE))
# docs env
has_docs = bool(re.search(r'^\[testenv:docs\]', content, re.MULTILINE))

failures = []
if not has_py:
    failures.append("Missing [testenv] (py env) — all repos must have a default test environment")
if not has_quality:
    failures.append("Missing [testenv:quality] (or [testenv:lint]) — all repos must have a quality/lint environment")
if not has_docs:
    failures.append(
        "Missing [testenv:docs] — add it, or if the repo has no docs infrastructure at all "
        "(no docs/ dir, no make docs target, no Sphinx config), document the omission "
        "in ## Important Notes of the PR before proceeding"
    )

if failures:
    for f in failures:
        print(f"FAIL: {f}")
    raise SystemExit(1)
else:
    print(f"OK: required tox environments present (py={has_py}, quality/lint={has_quality}, docs={has_docs})")
PYEOF

# --- Check 19: no manual GITHUB_PATH venv manipulation in CI workflows ---
echo "--- Check 19: no manual venv GITHUB_PATH echo ---"
python3 << 'PYEOF'
import re, glob

failures = []
for wf_path in glob.glob('.github/workflows/*.yml') + glob.glob('.github/workflows/*.yaml'):
    try:
        content = open(wf_path).read()
    except FileNotFoundError:
        continue
    for i, line in enumerate(content.splitlines(), 1):
        if re.search(r'echo\s+.*\.venv[/\\]bin.*GITHUB_PATH', line):
            failures.append(f"{wf_path}:{i}: manual venv PATH echo — use 'uv run <tool>' instead: {line.strip()!r}")

if failures:
    for f in failures:
        print(f"FAIL: {f}")
    print("  Remove these echoes. When using astral-sh/setup-uv, prefix tool invocations with "
          "'uv run' — uv manages venv activation automatically. Manually adding .venv/bin to "
          "GITHUB_PATH is a workaround that indicates tools are still called as bare commands.")
else:
    print("OK: no manual .venv/bin GITHUB_PATH echoes in CI workflows")
PYEOF

# --- Check 22: no unnecessary fetch-depth: 0 in CI checkout ---
echo "--- Check 22: no unnecessary fetch-depth: 0 in CI checkout ---"
python3 << 'PYEOF'
import re, glob, os

# CI test workflow and release.yml — sample-plugin omits fetch-depth in both; PSR unshallows itself.
CI_WORKFLOWS = [p for p in glob.glob('.github/workflows/*.yml') + glob.glob('.github/workflows/*.yaml')
                if re.search(r'(ci|python-tests|release)\.ya?ml$', os.path.basename(p))]

failures = []
for wf in CI_WORKFLOWS:
    try:
        content = open(wf).read()
    except FileNotFoundError:
        continue
    for i, line in enumerate(content.splitlines(), 1):
        if re.search(r'^\s*fetch-depth\s*:\s*0\s*(#.*)?$', line):
            failures.append(f"{wf}:{i}: sets 'fetch-depth: 0' — unnecessary full-history checkout")

if not CI_WORKFLOWS:
    print("SKIP: no ci.yml / python-tests.yml found")
elif failures:
    for f in failures:
        print(f"FAIL: {f}")
    print("  Remove 'fetch-depth: 0' from the CI checkout — reference repos (sample-plugin, xblocks-extra) "
          "omit it with the same setuptools-scm + fallback_version setup; it only slows CI. release.yml is exempt.")
else:
    print("OK: CI checkout uses default shallow depth (no unnecessary fetch-depth: 0)")
PYEOF

# --- Check 25: no dead [tool.coverage.run] in pyproject.toml for non-Python-test repos ---
echo "--- Check 25: no dead [tool.coverage.run] block ---"
python3 << 'PYEOF'
import glob, os, tomllib

# A repo that has no Python test files and no coverage invocation in Makefile/tox
# does not run Python coverage. Porting .coveragerc → [tool.coverage.run] in
# pyproject.toml is dead config and must be dropped instead.
# Signal: .shellspec present (shellspec+kcov repo) OR no test_*.py files anywhere.

try:
    with open('pyproject.toml', 'rb') as f:
        data = tomllib.load(f)
except FileNotFoundError:
    print("SKIP: no pyproject.toml found")
    raise SystemExit(0)

has_coverage_block = 'coverage' in data.get('tool', {})
if not has_coverage_block:
    print("OK: no [tool.coverage.run] block in pyproject.toml")
    raise SystemExit(0)

# Check signals that Python coverage is not used
has_shellspec = os.path.exists('.shellspec')
python_test_files = glob.glob('tests/test_*.py') + glob.glob('**/test_*.py', recursive=True)
python_test_files = [f for f in python_test_files if '.tox' not in f and '.venv' not in f]

makefile_uses_coverage = False
try:
    makefile = open('Makefile').read()
    makefile_uses_coverage = 'coverage' in makefile and 'pytest' in makefile
except FileNotFoundError:
    pass

if has_shellspec and not python_test_files:
    print("FAIL: [tool.coverage.run] found in pyproject.toml but this repo uses shellspec+kcov "
          "(not Python coverage) — .shellspec exists and there are no test_*.py files. "
          "Drop the [tool.coverage.run] block instead of porting it from .coveragerc.")
elif not python_test_files and not makefile_uses_coverage:
    print("FAIL: [tool.coverage.run] found in pyproject.toml but no Python test files exist "
          "and Makefile does not invoke coverage. This block is dead config — drop it.")
else:
    print("OK: [tool.coverage.run] present and Python test infrastructure exists")
PYEOF

# --- Check 24: Makefile test/lint targets do not use uv run --group inside tox ---
echo "--- Check 24: Makefile test/lint targets don't re-sync env via uv run --group ---"
python3 << 'PYEOF'
import re

# When tox calls a Makefile target (e.g. make test), `uv run --group <name>` inside
# that target re-syncs the environment to the named group — overriding the dependency
# group tox already installed. This means both django42 and django52 envs end up
# running the same Django version (whichever the group pins), so 4.2 is never tested.
# Makefile targets invoked by tox must use plain `python`/`pytest`/tool invocations;
# tox owns the venv at that point.

try:
    content = open('Makefile').read()
except FileNotFoundError:
    print("SKIP: no Makefile found")
    raise SystemExit(0)

# Targets tox typically calls — anything with `make <target>` in tox.ini
TOX_CALLED_TARGETS = {'test', 'lint', 'quality', 'test-with-coverage', 'coverage'}

failures = []
current_target = None
for line in content.splitlines():
    m = re.match(r'^([a-zA-Z_-]+)\s*:', line)
    if m:
        current_target = m.group(1)
    if current_target in TOX_CALLED_TARGETS:
        if re.search(r'uv\s+run\s+--group\b', line):
            failures.append(f"  make {current_target}: {line.strip()}")

if failures:
    print("FAIL: Makefile target(s) called by tox use 'uv run --group', which re-syncs the")
    print("  environment and overrides the dependency group tox installed (e.g. django42 ends")
    print("  up running the version pinned in 'test', not 4.2). Use plain tool invocations")
    print("  instead — tox manages the venv, the Makefile just runs commands inside it:")
    print("    test:  uv run python -Wd -m pytest tests/")
    print("    lint:  uv run flake8 src tests")
    for f in failures:
        print(f)
else:
    print("OK: tox-called Makefile targets do not re-sync the environment via uv run --group")
PYEOF

# --- Check 23: every master requirement is covered (filename-agnostic) ---
echo "--- Check 23: requirements coverage ---"
python3 << 'PYEOF'
import re, subprocess, tomllib

def normalize(name):
    name = re.sub(r'\[.*?\]', '', name).strip()
    return name.lower().replace('_', '-').replace('.', '-')

def parse_in_file(content):
    pkgs = set()
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith(('#', '-r', '-c', '-e')):
            continue
        if 'github.com' in line or line.startswith('git+'):
            m = re.search(r'egg=([^&\s]+)', line)
            if m:
                pkgs.add(normalize(m.group(1))); continue
        name = re.split(r'[><=!~\s;@\[]', line)[0]
        if name:
            pkgs.add(normalize(name))
    return pkgs

base = next((b for b in ('main','master')
             if subprocess.run(['git','show-ref','--verify','--quiet',f'refs/heads/{b}'],
                               capture_output=True).returncode == 0), None)
if not base:
    print("SKIP: no local main/master branch"); raise SystemExit(0)

# Discover the repo's ACTUAL .in files — do NOT assume canonical names. This is the
# gap the hardcoded Test 160 list left open: legacy repos (sandbox.in/testing.in/
# tox.in) would otherwise be validated against nonexistent files and pass vacuously.
ls = subprocess.run(['git', 'ls-tree', '--name-only', f'{base}:requirements'],
                    capture_output=True, text=True)
in_files = [f for f in ls.stdout.split() if f.endswith('.in')]
if not in_files:
    print("SKIP: no requirements/*.in files on base — nothing to compare"); raise SystemExit(0)

master_pkgs = set()
for f in in_files:
    r = subprocess.run(['git', 'show', f'{base}:requirements/{f}'], capture_output=True, text=True)
    if r.returncode == 0:
        master_pkgs |= parse_in_file(r.stdout)

# Tools legitimately removed by the migration (replaced by uv's own machinery).
REPLACED = {'pip-tools'}

def bare(dep):
    # Strip version specifiers/extras so "Django>=5.2,<6.0" matches master's bare "django".
    return normalize(re.split(r'[><=!~\s;@\[]', dep)[0])

with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)
pr_pkgs = {bare(d) for d in data.get('project', {}).get('dependencies', [])}
for grp in data.get('dependency-groups', {}).values():
    for d in grp:
        if isinstance(d, str):
            pr_pkgs.add(bare(d))

# Packages still resolvable transitively via uv.lock are covered even if the explicit
# declaration moved — losing the declaration is a WARN, not a FAIL.
try:
    with open('uv.lock', 'rb') as f:
        LOCKED = {normalize(p.get('name','')) for p in tomllib.load(f).get('package', [])}
except (FileNotFoundError, tomllib.TOMLDecodeError):
    LOCKED = set()

missing = master_pkgs - pr_pkgs - REPLACED
gone       = sorted(p for p in missing if p not in LOCKED)
transitive = sorted(p for p in missing if p in LOCKED)

print(f"  Discovered {base} .in files: {sorted(in_files)}")
for p in transitive:
    print(f"WARN: {p} — in a {base} .in file, not declared in pyproject.toml but present in uv.lock (re-declare or confirm intentional)")
if gone:
    for p in gone:
        print(f"FAIL: {p} — in a {base} .in file but absent from pyproject.toml AND uv.lock")
    raise SystemExit(1)
else:
    print(f"OK: all {len(master_pkgs)} master requirement(s) covered by pyproject.toml / uv.lock")
PYEOF

# --- Check 26: no uv run in Makefile targets (except upgrade); CI calls make via uv run ---
echo "--- Check 26: Makefile uv run absence + CI uv run make parity ---"
python3 << 'PYEOF'
import re, glob

failures = []

# Part A: no uv run in Makefile targets (except upgrade)
try:
    content = open('Makefile').read()
    current_target = None
    for line in content.splitlines():
        m = re.match(r'^([a-zA-Z_][a-zA-Z0-9_.-]*)\s*:', line)
        if m and not line.startswith('\t'):
            current_target = m.group(1)
            continue
        if line.startswith('\t') and current_target != 'upgrade':
            if re.search(r'\buv\s+run\b', line):
                failures.append(f"  [Makefile] make {current_target}: {line.strip()!r}")
    if not any('[Makefile]' in f for f in failures):
        print("Part A OK: no 'uv run' in Makefile targets (upgrade exempt)")
except FileNotFoundError:
    print("Part A SKIP: no Makefile found")

# Part B: CI steps that call make directly must use uv run make
for wf_path in glob.glob('.github/workflows/*.yml') + glob.glob('.github/workflows/*.yaml'):
    try:
        content = open(wf_path).read()
    except FileNotFoundError:
        continue
    lines = content.splitlines()
    for i, line in enumerate(lines):
        m = re.match(r'^\s*run:\s*(make\b.*)', line)
        if m:
            failures.append(
                f"  [CI] {wf_path}:{i+1}: bare 'make' — use 'uv run make ...': {m.group(1).strip()!r}"
            )
        if re.match(r'^\s*run:\s*\|', line):
            for j in range(i+1, min(i+20, len(lines))):
                sub = lines[j]
                if re.match(r'^\s{8,}make\b', sub) and not re.search(r'uv\s+run\s+make\b', sub):
                    failures.append(
                        f"  [CI] {wf_path}:{j+1}: bare 'make' in multi-line run — use 'uv run make ...': {sub.strip()!r}"
                    )
                elif sub.strip() and not sub.startswith(' ' * 8):
                    break

makefile_fails = [f for f in failures if '[Makefile]' in f]
ci_fails = [f for f in failures if '[CI]' in f]

if makefile_fails:
    print("Part A FAIL: 'uv run' found in Makefile targets outside 'upgrade'.")
    print("  Strip 'uv run' and use bare tool names. 'upgrade' is the only exception.")
    for f in makefile_fails: print(f)
if ci_fails:
    print("Part B FAIL: CI step calls bare 'make' without 'uv run'.")
    print("  Change 'run: make <target>' to 'run: uv run make <target>'.")
    for f in ci_fails: print(f)
if not failures:
    print("Part A+B OK: Makefile clean; CI make calls use uv run make (or route through uv run tox)")
else:
    raise SystemExit(1)
PYEOF

# --- Check 27: README references deleted files or tooling ---
echo "--- Check 27: README stale installation instructions ---"
python3 << 'PYEOF'
import re, glob, subprocess

# Stale patterns: things that were deleted by the modernization
STALE_PATTERNS = [
    (r'python\s+setup\.py\s+install', "refers to deleted setup.py — replace with `pip install <package-name>`"),
    (r'python\s+setup\.py\b',         "refers to deleted setup.py — update installation instructions"),
    (r'pip\s+install\s+-r\s+requirements/', "refers to deleted requirements/ directory — update with uv or pip install instructions"),
    (r'pip-compile\b',                 "refers to pip-compile (replaced by uv) — update tooling notes"),
    (r'\brequirements/\w+\.txt\b',     "refers to deleted requirements/*.txt files — update accordingly"),
    (r'\bsetup\.cfg\b',                "refers to deleted setup.cfg — update any config references"),
]

readme_files = []
for pattern in ['README.rst', 'README.md', 'README.txt', 'readme.rst', 'readme.md']:
    readme_files += glob.glob(pattern)
for pattern in ['docs/*.rst', 'docs/**/*.rst']:
    readme_files += glob.glob(pattern, recursive=True)

if not readme_files:
    print("SKIP: no README or docs/*.rst files found")
    raise SystemExit(0)

failures = []
seen_files = set()
for path in readme_files:
    real = path.lower()
    if real in seen_files:
        continue
    seen_files.add(real)
    try:
        lines = open(path).readlines()
    except OSError:
        continue
    for i, line in enumerate(lines, 1):
        matched = set()
        for regex, reason in STALE_PATTERNS:
            if re.search(regex, line, re.IGNORECASE):
                if i not in matched:
                    failures.append(f"  {path}:{i}: {line.rstrip()!r} — {reason}")
                    matched.add(i)
                    break

if failures:
    print("FAIL: README/docs contain stale references to deleted files or tools:")
    for f in failures:
        print(f)
else:
    print(f"OK: no stale installation/tooling references found in {readme_files}")
PYEOF

echo "======= END PRE-PR VALIDATION ======="
```

**All `FAIL:` lines must be resolved before creating the PR.** Do not proceed to Step 6 until the validation output contains only `OK:` and `SKIP:` lines.

---

### Checklist before opening the PR

- [ ] `tox.ini` has `py` (default `[testenv]`), `quality` (or `lint`), and `docs` environments — if `docs` is absent, the reason is documented in `## Important Notes` of the PR
- [ ] All metadata migrated from setup.cfg/setup.py to pyproject.toml
- [ ] `dependencies` is a static list in `[project]`
- [ ] MANIFEST.in asset patterns migrated to `[tool.setuptools.package-data]`
- [ ] Dependency groups created with exact parity to master's .in files
- [ ] `[tool.edx_lint].uv_constraints` set; `edx_lint write_uv_constraints` run; `[tool.uv].constraint-dependencies` populated
- [ ] `uv.lock` committed
- [ ] `requirements/` deleted
- [ ] `tox.ini` uses `tox-uv>=1`, `uv-venv-lock-runner`, tox envs call `make` targets
- [ ] Makefile `upgrade` → `edx_lint write_uv_constraints` + `uv lock --upgrade` — **no `--locked`** in this target
- [ ] Every Makefile `uv sync` uses `--locked` (Test 450)
- [ ] Makefile `requirements` → `uv sync --locked --group dev` only — **no `uv tool install tox`** (that installs an unpinned global tox outside uv.lock)
- [ ] Makefile `test`/`lint` targets invoked by tox use plain `python`/tool invocations — **no `uv run --group`** (that re-syncs the venv and overrides the Django/package version tox installed)
- [ ] Makefile targets do **not** use `uv run <tool>` prefix (e.g. `pytest`, not `uv run pytest`) — exception: `upgrade` keeps its `uv run --with edx-lint` line
- [ ] No Makefile targets dropped (except pip-compile targets) and none renamed; `*.py` glob change documented if removed
- [ ] CI uses `astral-sh/setup-uv`, `uv sync --locked --group ci`, `uv run tox` (no `--locked` on `uv run`), named `ci.yml`
- [ ] CI does **not** set `fail-fast` (it defaults to `true`); `strategy:` block in parity with master
- [ ] No checkout sets `fetch-depth: 0` — neither `ci.yml` nor `release.yml` (reference repos omit it; PSR unshallows on its own)
- [ ] CI toxenv matrix uses `py` (not `py312`) for the bare Python test env; Codecov `if:` uses compound condition (`matrix.toxenv == 'py' && matrix.python-version == '3.12'`)
- [ ] Codecov `if:` condition references the exact toxenv name used in the matrix
- [ ] All actions SHA-pinned; no SHA is older than what master used
- [ ] **pylint/isort/pycodestyle retained in quality group — no ruff introduced**
- [ ] `pylintrc`/`pylintrc_tweaks` still exist on disk
- [ ] `make lint` exits 0
- [ ] `make test` exits 0
- [ ] `uv lock --check` exits 0
- [ ] **Step 5a pre-PR validation: zero `FAIL:` lines** (includes Check 9: setup.py/setup.cfg migration parity, Check 11: tox env order, Check 12: no new tox envs, Check 13: Makefile target order, Check 14: Makefile changes in scope, Check 23: requirements coverage — every master `requirements/*.in` package survives in pyproject.toml/uv.lock, filename-agnostic, Check 24: tox-called Makefile targets do not use `uv run --group`, Check 25: no dead `[tool.coverage.run]` block in non-Python-test repos, Check 26: no `uv run` in Makefile targets outside `upgrade`)
- [ ] Coverage thresholds match master (no invented `fail_under`)
- [ ] No source-tracing comments in `[dependency-groups]` (no `# From requirements/ci.in` style lines)
- [ ] PR template (if one exists — `.github/` or `docs/`) has the exact Conventional Commits item from Step 3.3b, linking OEP-0051 `#specification` (not conventionalcommits.org), in the pre-merge checklist; no version-bump/changelog/tag items and no Post-Merge release item remain
- [ ] `__version__` in package `__init__.py` uses `importlib.metadata.version("<pkg>")` — never remove `__version__` entirely
- [ ] **PyPI repos:** `release.yml` + `commitlint.yml` added; `[tool.semantic_release]` in pyproject.toml with NO `[tool.semantic_release.changelog]` section and NO `changelog = false` (anti-pattern — belongs in release.yml action input only); `changelog: "false"` present as action input in release.yml; `CHANGELOG.rst` not wired to PSR (deprecation note prepended if it exists, otherwise left absent); zero-version guard only if 0.x
- [ ] **Non-PyPI repos:** static `version = "x.y.z"` in `[project]`; no `setuptools-scm`; `## Important Notes` documents why `src/` layout and `release.yml` were not added
- [ ] `src/` layout decision documented in `## Important Notes` if not adopted

---

### Step 6 — Write the PR description

Write the PR description now, before pushing, using the [PR description format](#pr-description-format) in Mode 2. Run the Mode 2 Step 1 fact-collection commands first — they take 30 seconds and prevent inaccurate claims in the description.

---

### Step 7 — Fix CI checks

After the PR is created and commits are pushed, wait 3 minutes for CI checks to initialize, then invoke the `/fix-checks` skill to make any failing checks green.

---

## Mode 2 — PR creation

Generate the PR body for a completed or in-progress modernization.

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

# uv tool install tox — must be absent from requirements target
echo "=== uv tool install tox (must be absent) ==="
grep -n 'uv tool install tox' Makefile 2>/dev/null \
  && echo "WARNING: 'uv tool install tox' found — remove it; tox belongs in the ci dependency group, not as a global tool install" \
  || echo "OK: absent"

# Any non-obvious changes (constraints, codecov, branch protection, etc.)
git diff master...HEAD -- .github/workflows/
```

### Step 2 — Write the PR description

Use the template in [PR description format](#pr-description-format). Apply these content accuracy rules — each maps a Step 1 fact to what goes in the description:

- **PyPI link:** include the PyPI package URL in the first Summary bullet only if the repo publishes to PyPI (release gate passes).
- **`[- Move package into a src/ layout]` bullet:** include only if `src/ layout: PRESENT` (i.e., the layout move happened).
- **Coverage config bullet:** include only if a `.coveragerc` existed on master (i.e., was migrated into `pyproject.toml`).
- **CI update bullet:** include only if CI was actually modified in this PR.
- **`[- Add python-semantic-release + release.yml (OIDC publishing)]` bullet:** include only if `release.yml: PRESENT`.
- **`[- Add commitlint.yml ...]` bullet:** include only if added in the PR. Always add an `## Important Notes` bullet warning that conventional commit format is now enforced on all future PRs to this repo.
- **`[- Drop Python X.Y support]` bullet:** include only if `requires-python` changed vs master.
- **Deleted files line:** list only entries marked `DELETED:` in Step 1 — not `KEPT:` and not `NOT ON MASTER:`. Include `.coveragerc` only if it existed on master. Never list `CHANGELOG.rst` as deleted — it is never removed (if it exists, a deprecation note is prepended; if absent, it stays absent). Never list `pylintrc`/`pylintrc_tweaks` (they are kept this cycle).
- **Removed Makefile targets table:** populate from the `=== Targets removed ===` list only. Any target in `=== Targets kept ===` must not appear here, even if its implementation was rewritten. Include a specific reason per row.
- **Updated Makefile targets table:** include only if targets were updated (not removed). Omit the section entirely if no targets changed. For the `requirements` target, the entry must describe `uv sync --locked --group dev` — if the `=== uv tool install tox ===` check in Step 1 flagged a hit, do NOT document it as correct in the table; flag it as a bug to fix before the PR is merged.
- **`## Python X.Y dropped` section:** present if and only if `requires-python` changed vs master. Omit otherwise.
- **Versioning section:** write the `[Static]` paragraph if no `setuptools-scm` in `pyproject.toml`; write the `[Dynamic]` paragraph if `setuptools-scm` is present. Write exactly one, never both.
- **`## Important Notes` section:** include when there is something critical to flag. Use for: omitted items (`release.yml` not added because no PyPI workflow existed; `src/` layout not adopted because repo doesn't publish to PyPI), unusual constraint pins, branch-protection check names reviewers must verify, or any other non-obvious decision. (PyPI trusted publisher / OIDC is already configured on all repos — do not flag it as a merge blocker.)

---

## PR description format

This is the authoritative template used by Mode 2.

````
> [!IMPORTANT]
> PR implemented with the assistance of [Claude Code](https://claude.com/claude-code). Refined and validated before being submitted for code review.

Modernize `<repo-name>`
Part of https://github.com/openedx/public-engineering/issues/506

## Summary

- Mention if the repo has pypi publishable, add pypi online link here
[- Move the package into a `src/` layout]   ← include only if the src/ move was done (repo publishes to PyPI)
- Replace `setup.py`/`setup.cfg` with `pyproject.toml` (PEP 621 static metadata)
- Switch from pip-compile to `uv` with PEP 735 dependency groups; commit `uv.lock`
- Retain pylint/isort/pycodestyle as on master. 
- coverage config moved into `pyproject.toml` ← include only if the coverage config existed in the master
- Update CI to use `astral-sh/setup-uv`; SHA-pin all actions; ← include only if it happened in the PR
[- Add `python-semantic-release` + `release.yml` (OIDC trusted publishing)]   ← include only if release gate passed
[- Add `commitlint.yml` to enforce conventional commit format on all future PRs to this repo]   ← include only if added in the PR
[- Drop Python X.Y support; set `requires-python = ">=3.12"`]   ← include only if Python version dropped

## Removed/Updated

**Deleted files:** `setup.py`, `setup.cfg`, `requirements/`[, `.coveragerc` ← only if existed on master]

**Removed Makefile targets:**

| Target | Reason |
|---|---|
| `<target>` | <one-line reason> |

**Updated Makefile targets:** ← include if some targets were updated

| Target | Change |
|---|---|
| `<target>` | <one-line description of what changed> |

<!-- CONDITIONAL SECTIONS — include only what applies, in this order: -->

## Python X.Y dropped   [← only when requires-python was bumped]
Python X.Y reached end-of-life on <date> and Open edX <release> dropped it platform-wide. Removed from the tox envlist, CI matrix, and classifiers.

## Versioning
[Static] `version = "<x.y.z>"` declared directly in `pyproject.toml` — master had no PyPI publish workflow, so `setuptools-scm` is not used and the version is bumped manually on each release tag.

OR

[Dynamic] `setuptools-scm` with `dynamic = ["version"]` — master had a PyPI publish workflow; `python-semantic-release` controls the version string at release time via git tags.

## Important Notes
Add this section only if there is something critical to flag (e.g. a branch-protection check name that must match, a retained workflow that reviewers should scrutinise). Omit entirely if nothing warrants it.

<!-- LICENSE AMBIGUITY — include only when license was not derivable from setup.cfg/setup.py metadata -->
> [!CAUTION]
> The original `setup.cfg`/`setup.py` had no `license=` field or `License ::` classifier. The `license` field in `pyproject.toml` was set to `"<SPDX-identifier>"` based on the `LICENSE` file header. **Please verify this is correct** — if the intended license differs, update `[project].license` before merging.

## Testing Notes
This PR has not been manually tested against the repo's own features. Testing relied on CI checks and local agent tooling (`make requirements`, `make lint`, `make test`, `python -m build`). Repo-owner is encouraged to run the repo's feature tests before merging.

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)
````

**Filling-in rules:**
- Every bullet is one sentence. No multi-sentence paragraphs.
- Omit any conditional section whose condition is false — don't write empty headings.
- The `> [!IMPORTANT]` callout is always present.
- The 🤖 footer is always present, separated by `---`.
- The "Removed Makefile targets" table must list every target dropped from master's Makefile, with a specific reason per row (not "no longer needed"). Targets kept but rewritten are not listed here — use the "Updated Makefile targets" table instead.
- Omit the "Updated Makefile targets" table entirely if no targets changed.
- `## Important Notes` is conditional — include it only when there is something genuinely critical. Do not add it just to have a section. When included, each bullet must be unique and not repeat facts already stated elsewhere. **License ambiguity** is one such critical case: if the license was derived from the `LICENSE` file because `setup.cfg`/`setup.py` had no license metadata, add the `> [!CAUTION]` block shown in the template inside this section.
- **No repeated content:** every claim must appear in exactly one section. Before writing any bullet, verify it is not already conveyed elsewhere in the description.
- **Accuracy over completeness:** every claim in the description must be true of this specific PR. Never write a conditional item (bracketed or conditional section) unless its condition was confirmed true in Mode 2 Step 1. When in doubt, omit rather than guess.
- **Never mention ruff** as part of this migration — it is out of scope.

---

## Mode 3 — Test/Verify

Verify an existing migration PR against the full Test suite. **Report only — do not fix, commit, or modify anything.** Fixes belong to Mode 1.

### Step 1 — Identify the PR

If a PR (or branch) isn't specified and the working tree isn't already on the migration branch, ask which PR to verify. Check it out with `gh pr checkout <number>`.

### Step 2 — Run every test

Run **all** tests from the [Test suite](#test-suite--tests-10455), in order, Test 10 through Test 455.

**Test 10 is a hard gate.** If ruff is present, Test 10 fails: **stop running the remaining tests**, report only Test 10's failure, and follow its instructions (ask the user to revert the ruff changes, then re-run). Do not report the other tests as passed or failed when Test 10 halts — record them as `⏭️ Skipped (halted at Test 10 — ruff present)`.

Otherwise, do not stop at the first failure and do not skip a test without recording why (e.g. `make docs` with no `docs/` directory, Test 80 when the repo is in the hardcoded non-PyPI list, Test 110 always (gated — only runs on explicit user request), Test 180 when the repo is in the hardcoded non-PyPI list, Test 210 always (gated — only runs on explicit user request), Test 220 when the user opted out of the src/ move, Test 230 when master did not use mypy, Test 31 when the repo is in the hardcoded non-PyPI list, Test 355 when master had no Makefile, Test 360 when master had no isort config in any config file, Test 400 when master had no `upgrade-python-requirements.yml`, Test 405 when repo uses flat layout, Test 410 when `.readthedocs.yaml` is absent, Test 415 when master had no `requirements/base.txt`). Record the outcome of every single test.

### Step 3 — Report

Follow the [reporting format](#reporting-format) exactly. Every test appears, pass or fail, in one table.

### Reporting format

Used whenever test results are reported. Rules:

- **One table, all tests.** Every test appears as a row, identified as `Test#XX`. Do **not** split passing and failing results into separate tables, and do **not** omit any test — passes, failures, and skips are all listed.
- Result values: `✅ Pass`, `❌ Fail`, `⏭️ Skipped (<reason>)`, `🛑 Halt` (Test 10 only), `ℹ️ Info` (Test 140 only). A skip without a reason is not allowed.
- After the table, add a detail section **per failed test** (what failed, the evidence/output, what would fix it), and Test 120's informational notes. Tests 110 and 210 are gated and appear in the table only as `⏭️ Skipped` unless the user explicitly asked for them.

Template:

```
## Test results

| Test | Name | Result | Notes |
|---|---|---|---|
| Test#10 | Ruff absence gate | ✅ Pass | no ruff present |
| Test#20 | Make targets | ✅ Pass | all targets exit 0 |
| Test#30 | Package build and distribution contents | ✅ Pass | |
| Test#31 | Translation symlink exclusion | ✅ Pass | — OR — ⏭️ Skipped (non-PyPI repo) |
| Test#40 | Lockfile consistency | ❌ Fail | uv lock --check exits 1 |
| ... | ... | ... | ... |
| Test#110 | SHA pinning audit | ⏭️ Skipped (gated — run explicitly to check SHA pinning) | |
| Test#155 | setup.py/setup.cfg migration parity | ✅ Pass | all metadata, entry points, and tool configs migrated |
| Test#210 | PR description completeness | ⏭️ Skipped (gated — run explicitly to check PR description) | |
| Test#220 | src/ layout | ✅ Pass | (PyPI repo) package under src/<pkg> — OR — (non-PyPI repo) flat layout retained, documented in PR |
| Test#230 | Mypy not introduced (or retained if present) | ✅ Pass | — OR — ⏭️ Skipped (master did not use mypy — confirmed mypy not introduced) |
| Test#290 | No action version downgrades | ✅ Pass | all PR-modified workflows use versions ≥ main |
| Test#300 | CI toxenv uses `py` not `py312` | ✅ Pass | no bare version-specific toxenv entries |
| Test#305 | CI `fail-fast` not set + strategy parity with master | ✅ Pass | fail-fast omitted (defaults true); strategy matches master |
| Test#310 | No empty codecov.yml introduced | ✅ Pass | |
| Test#320 | Tox env names unchanged | ✅ Pass | all master tox env names preserved |
| Test#330 | tox commands invoke make targets | ✅ Pass | |
| Test#340 | Dependency groups use include-group | ✅ Pass | all -r references use include-group |
| Test#350 | Makefile targets run tools directly | ✅ Pass | |
| Test#355 | No `uv run` in Makefile targets (except upgrade) | ✅ Pass | |
| Test#360 | isort style unchanged | ✅ Pass | — OR — ⏭️ Skipped (no isort config on master) |
| Test#370 | No source-tracing comments in dependency-groups | ✅ Pass | |
| Test#380 | Required tox environments present | ✅ Pass | py, quality, docs all present |
| Test#390 | No manual venv GITHUB_PATH echo in CI | ✅ Pass | |
| Test#395 | No unnecessary fetch-depth: 0 in CI checkout | ✅ Pass | CI uses default shallow checkout |
| Test#400 | `upgrade-python-requirements.yml` not deleted | ✅ Pass | workflow present in PR branch |
| Test#405 | Coverage `source` config correct for layout | ✅ Pass | — OR — ⏭️ Skipped (flat layout) |
| Test#407 | pytest multi-value options are TOML arrays, not space-joined strings | ✅ Pass | — OR — ⏭️ Skipped (no [tool.pytest.ini_options]) |
| Test#410 | `.readthedocs.yaml` uses uv install method | ✅ Pass | — OR — ⏭️ Skipped (no .readthedocs.yaml) |
| Test#415 | `uv sync` scope matches original pip-sync scope | ✅ Pass | — OR — ⏭️ Skipped (no requirements/base.txt on master) |
| Test#420 | Lock file is current | ✅ Pass | — OR — ⚠️ Warn (major bumps, no upgrade workflow) |
| Test#425 | README stale installation instructions | ✅ Pass | no stale setup.py/requirements/ references |
| Test#430 | No invented `[project.optional-dependencies]` | ✅ Pass | — OR — ⏭️ Skipped (master had extras_require) |
| Test#435 | No package duplication across extras and dependency groups | ✅ Pass | — OR — ⏭️ Skipped (no optional-dependencies block) |
| Test#440 | Extras count parity with original `extras_require` | ✅ Pass | — OR — ⏭️ Skipped (master had no extras_require) |
| Test#445 | No double-run: `ci.yml` no `push:` when `release.yml` uses `workflow_call` | ✅ Pass | — OR — ⏭️ Skipped (no ci.yml) |
| Test#450 | `uv sync` in CI workflows and Makefile (except `upgrade`) uses `--locked` | ✅ Pass | — OR — ⏭️ Skipped (no .github/workflows/ or Makefile) |
| Test#455 | `extract_translations` Makefile target does not use `uv` | ✅ Pass | — OR — ⏭️ Skipped (no extract_translations target) |

## Failure details

### Test#40 — Lockfile consistency
<evidence + what would fix it>
```

If Test 10 halts, the table lists Test#10 as `🛑 Halt` and every other row as `⏭️ Skipped (halted at Test 10 — ruff present)`, followed by the halt instructions.

---

## Test suite — Tests 10–455

All tests must be run as part of a verification report (Test/Verify mode). **Test 10 is a hard gate — if it fails, halt.**

**Test groups** (tests are numbered in order of execution, not by group):

| Group | Tests | What they check |
|---|---|---|
| Entry gate (run first) | 10 | Ruff absent everywhere |
| Python version | 260 | Python < 3.12 removed from tox, CI, classifiers |
| Package structure and files | 90, 130, 220, 310 | Stale files deleted; `__version__` uses importlib.metadata (no hardcoded string); src/ layout correct; no empty codecov.yml introduced |
| Package build | 30, 70, 80 | Build output complete; package imports; setuptools-scm runtime (PyPI) |
| Dependency management | 40, 50, 160, 170, 270, 340 | Lockfile in sync; groups resolve; all packages migrated; constraints; static deps; `-r` refs use include-group |
| Migration parity | 155 | Every field from master's setup.py/setup.cfg (metadata, entry points, tool configs) present in pyproject.toml |
| Versioning | 240, 245, 246 | Versioning strategy: setuptools-scm (PyPI) or static version (no-PyPI), including 0.x guard; PSR `tag_format` matches existing release tags (245, offline) and a matching baseline tag exists for the latest PyPI release (246, ground-truth) — else manual baseline tag required |
| Quality tooling | 230, 280, 360, 370 | Mypy retained (if used); quality group has original linters; isort style unchanged; no source-tracing comments in dependency groups |
| Tox configuration | 60, 320, 330, 380 | tox.ini parses; all envs resolve; no env renamed; commands invoke make targets; required envs present |
| Makefile | 20, 140, 350, 355, 455 | Targets exit 0; no target dropped without reason; targets run tools directly (not via tox); no `uv run` prefix in target bodies (except `upgrade`); `extract_translations` does not use uv |
| GitHub Actions and CI | 100, 150, 180, 250, 290, 300, 305, 390, 395 | YAML valid; branch protection preserved; CI-first + immutable-safe `gh release create` (`vcs_release: "false"`, no `publish-action`) + OIDC in release.yml; `uv run tox`; no action version downgrades vs main; toxenv uses `py` not `py312`; `fail-fast` not set + strategy parity with master; no manual venv PATH echo; no `fetch-depth: 0` in CI or release checkout |
| Code review audit | 120, 190 | Logic changes noted; no invented thresholds |
| PR documentation (gated) | 210 | PR body complete and accurate (explicit request only) |
| SHA pinning audit (gated) | 110 | Actions SHA-pinned in PR-modified workflows (explicit request only) |
| Documentation | 425 | README/docs contain no stale references to deleted files (setup.py, requirements/) |

### Test 10 — Ruff absence gate (HALT on failure)

Ruff is out of scope this cycle. Before running any other test, confirm the PR did **not** introduce ruff.

```bash
echo "=== ruff config in pyproject.toml ==="
grep -nE '\[tool\.ruff' pyproject.toml || echo "(none)"
echo "=== ruff as a dependency ==="
grep -rnE '(^|[^a-z])ruff([^a-z]|$)' pyproject.toml uv.lock tox.ini Makefile .github/workflows/ 2>/dev/null \
  | grep -iE 'ruff' | grep -vE 'ruffle|scruff' || echo "(none)"
```

**Pass:** No `[tool.ruff]` sections; `ruff` appears nowhere in pyproject/lock/tox/Makefile/CI. (`pylintrc`/`pylintrc_tweaks` presence is verified by Test 90.)

**Fail → HALT:** If ruff is present in any form, **stop the test suite immediately.** Do not run Tests 20–290. Report only this failure and instruct:

> Ruff was found in this PR, but ruff is out of scope for this cycle (public-engineering#506). Revert the ruff changes from this PR, then re-run the test suite.

Mark every other test `⏭️ Skipped (halted at Test 10 — ruff present)`.

### Test 20 — Make targets

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

### Test 30 — Package build and distribution contents

Build the package **once** on the PR branch and **once** on master/main, then inspect and compare both tarballs and wheels in a single pass — no repeated builds.

**Step 0 — Pre-build symlink check (PyPI repos only; skip for non-PyPI):**

Run this before attempting any build. A git-tracked `translations/` symlink causes `python -m build --wheel` to fail silently until the first `release.yml` run — the standard CI matrix never exercises this path.

```bash
python3 << 'PYEOF'
import subprocess, tomllib

result = subprocess.run(
    ['git', 'ls-files', '--stage'],
    capture_output=True, text=True
)
symlinks = [
    line.split('\t', 1)[1]
    for line in result.stdout.splitlines()
    if line.startswith('120000') and 'translation' in line.lower()
]
if not symlinks:
    print("OK: no git-tracked translation symlinks found")
else:
    print(f"Found translation symlinks: {symlinks}")
    try:
        with open('pyproject.toml', 'rb') as f:
            data = tomllib.load(f)
    except FileNotFoundError:
        print("FAIL: pyproject.toml not found"); raise SystemExit(1)

    excl = data.get('tool', {}).get('setuptools', {}).get('exclude-package-data', {})
    missing = []
    for path in symlinks:
        # e.g. src/drag_and_drop_v2/translations → pkg = drag_and_drop_v2
        parts = path.strip('/').split('/')
        try:
            trans_idx = parts.index('translations')
        except ValueError:
            continue
        pkg = parts[trans_idx - 1] if trans_idx > 0 else None
        if pkg and ('translations' not in excl.get(pkg, []) and
                    'translations' not in excl.get('*', [])):
            missing.append(pkg)
    if missing:
        print(f"FAIL: git-tracked translation symlink found for {missing} but "
              f"[tool.setuptools.exclude-package-data] does not exclude 'translations' for "
              f"{'it' if len(missing)==1 else 'them'}. "
              f"Add:\n  [tool.setuptools.exclude-package-data]\n"
              + '\n'.join(f'  {p} = ["translations"]' for p in missing)
              + "\nWithout this, `python -m build --wheel` fails in release.yml.")
        raise SystemExit(1)
    else:
        print(f"OK: translation symlinks present but correctly excluded via exclude-package-data")
PYEOF
```

**Step 1 — Build the PR branch (single authoritative build):**

Build from a clean state. Tool-generated outputs (`htmlcov/`, `.coverage`, `coverage.xml`, `.pytest_cache/`, `.mypy_cache/`, `.ruff_cache/`, `.tox/`, stale `*.egg-info/`) may be left in the working tree by a prior `make test`/`make quality` run. `setuptools` includes matching paths in the sdist unless `MANIFEST.in` prunes them, so a dirty tree yields a non-reproducible tarball diff. Removing only tool-generated outputs (never source) makes the build reproducible:

```bash
rm -rf htmlcov/ .coverage coverage.xml .pytest_cache/ .mypy_cache/ .ruff_cache/ .tox/ dist/ build/ *.egg-info/
uv run python -m build
ls dist/
```

> This cleanup makes the build reproducible; it does **not** by itself prove `MANIFEST.in` is correct. Whether the repo would still ship those artifacts in a real release (maintainers typically build from their working tree right after running tests) is verified deterministically in **Step 3b**, independent of build-time tree state.

**Step 2 — Build main/master in an isolated worktree:**

Do **not** use `git stash` + `git checkout` — use a worktree to avoid conflicts with uncommitted changes:

```bash
git worktree add /tmp/bundle-worktree-main main   # or: master
cd /tmp/bundle-worktree-main

# --no-isolation keeps the old setup.py readable (it often reads requirements with relative paths)
python -m build --no-isolation --outdir /tmp/bundle-main
# If build deps are missing:
#   pip install setuptools wheel build
#   python -m build --no-isolation --outdir /tmp/bundle-main

cd -   # return to repo root
ls /tmp/bundle-main/
```

**Step 3 — Inspect PR tarball (absolute checks):**

```bash
tar -tzf dist/<name>-<version>.tar.gz | sort
```

Check that the tarball includes **all** of the following (adjust paths to match the repo layout — with a src/ layout the package lives under `src/<package>/`):

| Expected content | Why it must be present |
|---|---|
| `PKG-INFO` | PEP 566 metadata — generated from `pyproject.toml` |
| `pyproject.toml` | Build recipe — must be included by setuptools |
| Source package directory (e.g. `src/<package>/`) | All `.py` files under the package root |
| `README.rst` or `README.md` | Linked via `readme =` in `[project]` |
| `LICENSE` | Required for PyPI |
| `MANIFEST.in` (if any) | Only if the repo uses inclusion-based manifests |
| Static assets (e.g. `*.html`, `*.css`, `*.js`, `*.png` under the package) | Any non-`.py` file referenced by `package_data` or `MANIFEST.in` |

Flag as a failure if:
- `setup.py` appears in the tarball — it should be deleted as part of the migration and must not be packaged.
- `CHANGELOG.rst` (if present) is deprecated and must not be packaged.
- `uv.lock` appears in the tarball — **must never be packaged**. It is a dev/CI lockfile for project maintainers; pip and uv never read it during an sdist install (they resolve from `Requires-Dist` in `pyproject.toml`). Its presence in an sdist only bloats the tarball and confuses consumers. Fix: add `exclude uv.lock` to `MANIFEST.in`.
- The source package directory is missing or empty.
- Static assets that existed before the migration are absent — their absence will break installs.

**Note — `setup.cfg` in the tarball is expected and not a failure.** Setuptools auto-generates a minimal `setup.cfg` (containing only `[egg_info]` metadata) during the build process even when the repo's own `setup.cfg` has been deleted. This auto-generated file is a normal setuptools artifact, not the stale pre-migration config.

**Step 3b — `MANIFEST.in` prunes test/build artifacts (deterministic — independent of build-time tree state):**

Step 1's cleanup guarantees a reproducible *diff*, but a real release is often built from a working tree that still holds `htmlcov/` etc. right after a test run. Whether those would ship is a property of `MANIFEST.in`, not of the tree at build time — so check it statically. This only matters when an sdist is actually consumed (a PyPI repo): the wheel never carries these artifacts (they sit outside the package dir, and wheels use `package-data` not `MANIFEST.in`), and a non-PyPI repo's sdist is never installed. So for non-PyPI repos the check is **skipped entirely** — a missing prune rule there has zero effect and a standing WARN would only be noise.

```bash
python3 << 'PYEOF'
import re, subprocess, tomllib

# Repos that do NOT publish to PyPI — a leaked artifact in an unconsumed sdist is harmless (WARN, not FAIL).
NON_PYPI = {
    'credentials-themes', 'mockprock', 'edx-repo-health', 'openedx-webhooks-data-schema',
    'enterprise-catalog', 'enterprise-access', 'enterprise-subsidy', 'xapi-db-load',
    'codejail-service', 'openedx-user-groups', 'cc2olx', 'pr_watcher_notifier',
    'openedx-webhooks',
}

try:
    with open('pyproject.toml', 'rb') as f:
        data = tomllib.load(f)
except FileNotFoundError:
    print("SKIP: no pyproject.toml"); raise SystemExit(0)

repo = data.get('project', {}).get('name', '')
repo_slug = subprocess.run(['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True).stdout.strip().split('/')[-1]
is_non_pypi = repo in NON_PYPI or repo_slug in NON_PYPI

# Non-PyPI repos never publish an sdist, so MANIFEST.in prune rules have zero effect —
# skip outright rather than emit a standing WARN on every such migration.
if is_non_pypi:
    print("SKIP: non-PyPI repo — sdist is never consumed, MANIFEST.in prune rules have no effect")
    raise SystemExit(0)

# Does this repo generate coverage/cache artifacts? (coverage configured, or a test dep pulls it in)
has_coverage = 'coverage' in str(data.get('tool', {}).get('coverage', '')) or \
    any('coverage' in d or 'pytest-cov' in d
        for grp in data.get('dependency-groups', {}).values() for d in grp if isinstance(d, str)) or \
    ('tool' in data and 'coverage' in data['tool'])

try:
    manifest = open('MANIFEST.in').read()
except FileNotFoundError:
    manifest = ''

# Artifacts worth pruning and the MANIFEST.in directive that covers each.
EXPECTED = {
    'htmlcov':      r'prune\s+htmlcov',
    'coverage.xml': r'(exclude|global-exclude)\s+coverage\.xml',
    '.coverage':    r'(exclude|global-exclude)\s+\.coverage',
}
missing = [name for name, pat in EXPECTED.items() if not re.search(pat, manifest)]

# uv.lock must never be in the sdist — it is a dev/CI lockfile that pip/uv
# never reads during sdist installation. Check unconditionally for all PyPI repos.
import os
if os.path.exists('uv.lock') and not re.search(r'(exclude|global-exclude)\s+uv\.lock', manifest):
    print("FAIL: uv.lock is git-tracked but MANIFEST.in does not exclude it — add 'exclude uv.lock'")
    print("  uv.lock is a dev/CI lockfile; pip never reads it during sdist install and it only bloats the tarball.")
    raise SystemExit(1)
else:
    print("OK: uv.lock excluded from sdist (or not present)")

if not has_coverage:
    print("SKIP: repo does not generate coverage artifacts — no prune rules needed")
elif not missing:
    print("OK: MANIFEST.in prunes all test/coverage artifacts")
else:
    print(f"FAIL: MANIFEST.in missing prune rules for {missing} — a working-tree release build will ship these into the sdist")
    raise SystemExit(1)
PYEOF
```

**Step 4 — Inspect PR wheel (absolute checks):**

```bash
unzip -l dist/<name>-<version>-py3-none-any.whl | sort
```

Check that:
- The package directory and all its `.py` files are present — the wheel strips the `src/` prefix, so the package appears as `<package>/` (not `src/<package>/`).
- Static assets (templates, JS, CSS, locale files) are included — wheels use `package_data` rules, not `MANIFEST.in`.
- `METADATA` (wheel equivalent of `PKG-INFO`) is present under `<name>-<version>.dist-info/`.
- No compiled `.pyc` files or test files appear in the wheel.

If static assets are missing from the wheel but present in the tarball, add them under `[tool.setuptools.package-data]` in `pyproject.toml`.

**Step 5 — Compare tarball against main (regression diff):**

Version strings differ between branches and the `src/` move relocates the package. Strip both the `<name>-<version>/` prefix and any leading `src/` to avoid false regressions:

```bash
diff \
  <(tar -tzf /tmp/bundle-main/<pkg>-*.tar.gz | sed 's|[^/]*/||' | sed 's|^src/||' | sort) \
  <(tar -tzf dist/<pkg>-*.tar.gz             | sed 's|[^/]*/||' | sed 's|^src/||' | sort)
```

Lines starting with `<` are present in **main** but **missing from PR** — these are regressions. Lines starting with `>` are present in **PR** but not in main — expected additions (new tooling files).

**Step 6 — Compare wheel against main (regression diff):**

```bash
diff \
  <(unzip -l /tmp/bundle-main/<pkg>-*-py3-none-any.whl | awk '{print $4}' | grep -v '^$\|^Name\|^----\|files$' | sort) \
  <(unzip -l dist/<pkg>-*-py3-none-any.whl             | awk '{print $4}' | grep -v '^$\|^Name\|^----\|files$' | sort)
```

**Step 7 — Clean up:**

```bash
git worktree remove /tmp/bundle-worktree-main --force
```

**Pass:** PR tarball contains all required files; `setup.py` not in tarball (`setup.cfg` is auto-generated by setuptools and is expected — not a failure); PR wheel contains the full package with static assets, `METADATA` present, no `.pyc` files; no regressions vs main in either tarball or wheel; Step 3b reports OK or SKIP (SKIP for any non-PyPI repo, or a repo with no coverage artifacts).

**Fail:** `setup.py` reappears in the tarball; source package directory missing or empty; static assets absent from tarball or wheel; any file present in main missing from PR (regression); Step 3b FAILs (a PyPI repo whose `MANIFEST.in` omits prune rules for generated artifacts); Step 0 FAIL (translation symlink present without matching `exclude-package-data`).

### Test 31 — Translation symlink exclusion (fast gate, no build required)

**Skip this test for non-PyPI repos.** Record as `⏭️ Skipped (non-PyPI repo — no wheel published)`.

This is a standalone static check that runs before any build. It catches the same issue as Test 30 Step 0 without requiring `python -m build` to be invoked — useful when the build fails for unrelated reasons and you need to triage.

```bash
python3 << 'PYEOF'
import subprocess, tomllib, sys

# Find git-tracked symlinks (mode 120000) that contain 'translations'
result = subprocess.run(['git', 'ls-files', '--stage'], capture_output=True, text=True)
symlinks = [
    line.split('\t', 1)[1].strip()
    for line in result.stdout.splitlines()
    if line.startswith('120000') and 'translation' in line.lower()
]

if not symlinks:
    print("OK: no git-tracked translation symlinks — exclude-package-data not needed")
    sys.exit(0)

print(f"Found git-tracked translation symlinks: {symlinks}")

try:
    with open('pyproject.toml', 'rb') as f:
        data = tomllib.load(f)
except FileNotFoundError:
    print("FAIL: pyproject.toml not found"); sys.exit(1)

excl = data.get('tool', {}).get('setuptools', {}).get('exclude-package-data', {})
failures = []
for path in symlinks:
    parts = path.split('/')
    try:
        trans_idx = parts.index('translations')
    except ValueError:
        continue
    pkg = parts[trans_idx - 1] if trans_idx > 0 else None
    if pkg and ('translations' not in excl.get(pkg, []) and
                'translations' not in excl.get('*', [])):
        failures.append(
            f"  Package '{pkg}': symlink at '{path}' not excluded.\n"
            f"  Add to pyproject.toml:\n"
            f"    [tool.setuptools.exclude-package-data]\n"
            f"    {pkg} = [\"translations\"]"
        )

if failures:
    print("FAIL: git-tracked translation symlinks exist without matching exclude-package-data.")
    print("Root cause: setuptools-scm's file finder lists the symlink and build_py tries to")
    print("copy it as a regular file — `python -m build --wheel` fails in release.yml with")
    print("  error: can't copy '<pkg>/translations': doesn't exist or not a regular file")
    print("Moving assets to conf/locale/**/* in package-data does NOT fix this; exclude-package-data does.")
    for f in failures:
        print(f)
    sys.exit(1)
else:
    print(f"OK: translation symlinks present and correctly excluded in exclude-package-data")
PYEOF
```

**Pass:** No git-tracked translation symlinks found (test trivially passes); OR symlinks found and `[tool.setuptools.exclude-package-data]` has a `translations` entry for the affected package(s).

**Fail:** A git-tracked `translations/` symlink exists under a package directory but `[tool.setuptools.exclude-package-data]` does not exclude it. This will cause `python -m build --wheel` to fail the first time `release.yml` runs on main after merge — it is invisible in CI because the standard matrix never runs the wheel build.

### Test 40 — Lockfile consistency

```bash
uv lock --check
```

Must exit 0. If it fails, run `uv lock` to regenerate and commit the updated lockfile.

### Test 50 — Dependency group resolution

```bash
uv sync --locked --group dev
uv sync --locked --group ci
uv sync --locked --group quality
uv sync --locked --group test
```

A conflict means the lockfile is broken for that environment.

### Test 60 — Tox environment listing

```bash
uv run tox --listenvs
```

If this fails (parse error, missing dependency group, unknown runner), the CI matrix will never run.

### Test 70 — Package importability

```bash
uv pip install -e .
uv run python -c "import <package_name>; print('OK')"
```

Replace `<package_name>` with the actual importable module name.

### Test 80 — setuptools-scm version resolution

**Skip this test if the repo is in the hardcoded non-PyPI list** (credentials-themes, mockprock, edx-repo-health, openedx-webhooks-data-schema, enterprise-catalog, enterprise-access, enterprise-subsidy, xapi-db-load, codejail-service, openedx-user-groups, cc2olx, pr_watcher_notifier). Record as `⏭️ Skipped (non-PyPI repo — static version used)`.

```bash
uv run python -m setuptools_scm
```

This should print a version string.

### Test 130 — `__version__` uses `importlib.metadata` pattern and is in a shipped file

```bash
grep -rn '__version__' --include='*.py' . | grep -v '\.tox' | grep -v '/test'
```

**Pass criteria — all three must hold:**
1. No hardcoded `__version__ = "x.y.z"` string remains in package source.
2. `importlib.metadata.version("<package-name>")` is used in the package `__init__.py` (with or without a `try/except PackageNotFoundError` wrapper — both are acceptable):

```python
from importlib.metadata import version

__version__ = version("<package-name>")
```

3. The file containing `__version__` is inside a package or module that actually ships in the wheel.
   A root-level `__init__.py` is never included by `packages.find where = ["src"]`. A file under
   `src/<pkg>/` only ships if `<pkg>` is discoverable by the packaging config. Cross-reference
   the file's location against `pyproject.toml` to confirm it will be included:

```bash
python3 << 'PYEOF'
import os, re, subprocess, tomllib

# Find files containing importlib-based __version__
result = subprocess.run(
    ["grep", "-rln", "__version__", "--include=*.py", "."],
    capture_output=True, text=True
)
candidates = [
    l.lstrip("./") for l in result.stdout.splitlines()
    if ".tox" not in l and "/test" not in l
]
version_files = []
for f in candidates:
    try:
        if "importlib" in open(f).read():
            version_files.append(f)
    except Exception:
        pass

if not version_files:
    print("SKIP: no importlib-based __version__ found — acceptable if repo has no canonical top-level package")
    raise SystemExit(0)

try:
    with open("pyproject.toml", "rb") as fh:
        data = tomllib.load(fh)
except Exception as e:
    print(f"FAIL: could not read pyproject.toml — {e}")
    raise SystemExit(1)

setuptools = data.get("tool", {}).get("setuptools", {})
py_modules = setuptools.get("py-modules", [])
find_cfg = setuptools.get("packages", {}).get("find", {})
find_where = find_cfg.get("where", ["."])   # default: repo root
find_exclude = find_cfg.get("exclude", [])

uses_src = os.path.isdir("src")

for vf in version_files:
    parts = vf.replace("\\", "/").split("/")

    # Case 1: root-level __init__.py (e.g. __init__.py with no package parent)
    if parts == ["__init__.py"]:
        print(f"FAIL: {vf} — root __init__.py never ships in any layout")
        print("  Fix: move __version__ into a package under src/, or drop it if no canonical package exists")
        continue

    # Case 2: standalone module (e.g. src/eia.py or eia.py)
    if len(parts) == 1 or (len(parts) == 2 and parts[0] in find_where):
        mod = parts[-1].replace(".py", "")
        if mod in py_modules:
            print(f"OK: {vf} — module '{mod}' ships via py-modules")
        else:
            print(f"FAIL: {vf} — module '{mod}' not listed in py-modules, will not ship")
        continue

    # Case 3: package __init__.py (e.g. src/mypkg/__init__.py or mypkg/__init__.py)
    if parts[-1] == "__init__.py":
        # Determine the package root relative to the find_where directory
        if parts[0] in find_where:
            pkg_name = parts[1] if len(parts) > 2 else None
        else:
            pkg_name = parts[0]

        if not pkg_name:
            print(f"FAIL: {vf} — could not determine package name")
            continue

        excluded = any(
            re.fullmatch(pat.replace("*", ".*"), pkg_name) for pat in find_exclude
        )
        if excluded:
            print(f"FAIL: {vf} — package '{pkg_name}' is excluded by packages.find exclude config")
            print("  Fix: remove the exclude rule or move __version__ to a package that ships")
        else:
            # Check the package directory actually exists under find_where
            for w in find_where:
                pkg_path = os.path.join(w, pkg_name) if w != "." else pkg_name
                if os.path.isdir(pkg_path):
                    print(f"OK: {vf} — package '{pkg_name}' is under '{w}/' and will ship in the wheel")
                    break
            else:
                print(f"FAIL: {vf} — package directory '{pkg_name}' not found under {find_where}")
    else:
        print(f"INFO: {vf} — unexpected location, inspect manually")
PYEOF
```

**When to drop `__version__` instead:** if the repo ships multiple unrelated packages/modules under
one distribution name with no canonical top-level package (e.g. codejail-includes ships `loncapa`,
`verifiers`, and `eia` independently), there is no natural home for `__version__`. In that case,
dropping it is cleaner than inventing a new package directory just to hold it.


### Test 90 — No stale files on disk

```bash
for f in setup.py setup.cfg .coveragerc pytest.ini; do
  [ -f "$f" ] && echo "STALE: $f still exists — config should be in pyproject.toml" || echo "OK: $f absent"
done
[ -d requirements ] && echo "STALE: requirements/ still exists" || echo "OK: requirements/ absent"

# CHANGELOG.rst — never created, never deleted. If present it must be deprecated and must NOT be wired to PSR.
if grep -rq "changelog-insertion-marker" CHANGELOG.rst pyproject.toml 2>/dev/null; then
  echo "FAIL: changelog-insertion-marker found — CHANGELOG.rst must not be wired to semantic-release"
elif grep -q "tool.semantic_release.changelog" pyproject.toml 2>/dev/null; then
  echo "FAIL: [tool.semantic_release.changelog] present — remove it; changelog is not PSR-managed"
elif [ -f CHANGELOG.rst ]; then
  grep -qi "DEPRECATED" CHANGELOG.rst \
    && echo "OK: CHANGELOG.rst present with deprecation note" \
    || echo "FAIL: CHANGELOG.rst present but missing deprecation note (see Step 3.4)"
else
  echo "OK: CHANGELOG.rst absent — leave it absent"
fi

# pylintrc / pylintrc_tweaks must be KEPT this cycle (ruff out of scope)
for f in pylintrc pylintrc_tweaks; do
  if git show master:"$f" &>/dev/null 2>&1; then
    [ -f "$f" ] && echo "OK: $f kept" || echo "REGRESSION: $f was deleted — ruff is out of scope, restore it"
  fi
done
```

Any `STALE:`, `MISSING:`, `FAIL:`, or `REGRESSION:` line is a failure.

### Test 100 — GitHub Actions workflow YAML validity

```bash
brew install actionlint   # macOS
actionlint .github/workflows/ci.yml .github/workflows/release.yml
```

Use `actionlint`, not `yamllint` — `yamllint`'s 80-char line limit flags every SHA-pinned action line as an error.

### Test 110 — SHA pinning audit

**Gated: only run this test when the user explicitly asks for it.** Skip it in all other test runs and record the row as `⏭️ Skipped (gated — run explicitly to check SHA pinning)`.

Scan only workflow files that were **added or modified by this PR** for GitHub Actions references that are not SHA-pinned. Pre-existing workflow files unchanged from master are out of scope.

```bash
# Identify workflow files changed by this PR
git diff master...HEAD --name-only -- '.github/workflows/*.yml' '.github/workflows/*.yaml'
```

For each changed workflow file, check for un-pinned references — **excluding only org-internal reusable workflow calls** (which use floating version tags). Every third-party action, including `python-semantic-release`, must be SHA-pinned:

```bash
git diff master...HEAD --name-only -- '.github/workflows/*.yml' '.github/workflows/*.yaml' \
  | xargs grep -E 'uses:\s+\S+@' \
  | grep -v '@[0-9a-f]\{40\}' \
  | grep -v '^#' \
  | grep -v 'uses:\s\+openedx/\.github/'
```

**SHA pinning expectations:**
- `python-semantic-release/python-semantic-release` — **SHA-pin it** (with a `# vX.Y.Z` comment), matching the `openedx/sample-plugin` standard. Even though it runs only on push to the default branch, it is pinned for consistency so every third-party `uses:` in the file is verifiable. (The GitHub Release itself is created by a `gh release create` shell step, which has no action reference to pin.)
- `pypa/gh-action-pypi-publish` — **must be SHA-pinned** with a verified commit SHA (not a tag-object SHA). A floating ref on this action caused a real production incident; verify the SHA resolves via `gh api repos/pypa/gh-action-pypi-publish/commits/<sha>` before accepting.

**Pass:** No un-pinned third-party action references in any workflow file added or modified by the PR — every third-party action, including `python-semantic-release` and `gh-action-pypi-publish`, is SHA-pinned with a `# vX.Y.Z` comment. Only org-internal reusable workflow calls (`openedx/.github/...`) may use a floating ref.

### Test 120 — Logic change audit (informational only)

```bash
git diff main...HEAD -- '*.py'
```

Read every modified `.py` file in the diff. Classify each change as mechanical rename, dead code removal, logic change, or new behaviour. This test is **informational only** — record as `ℹ️ Info`.

### Test 140 — Makefile target and CI parity

**Makefile parity:**

```bash
grep -E '^[a-zA-Z_-]+:' Makefile | sed 's/:.*//'
```

For each target from the pre-migration state:
- If it invoked a deleted tool (pip-compile, setup.py) → confirm an equivalent target exists using uv
- If it invoked a retained tool (pytest, pylint, isort, pycodestyle, mypy, sphinx) → confirm the target still exists
- A target that was **renamed** is a violation regardless of whether a local caller exists — per the "targets are sacred, never rename" rule, and because branch-protection gates and org-level tooling can reference a target name invisibly to a single-repo grep. Two valid remedies:
  - **Keep the old name** with the new implementation (e.g. `check-setup.py:` still, but its body validates `pyproject.toml`), or
  - **Delete the target** if its purpose is genuinely obsolete, and document the removal in the PR description under "Removed Makefile targets".
  - Do a repo grep (`grep -rn '<old-target>' .github/ Makefile`) only to gauge *blast radius* for the finding's severity note — not as grounds to wave the rename through.
- Any target dropped (without being a story-replaced target like the pip-compile family) or renamed is a regression.

**CI parity:**

```bash
grep -A5 'toxenv:' .github/workflows/ci.yml  # or python-tests.yml
```

Every tool that ran in the old CI must run in the new CI toxenv matrix.


### Test 155 — setup.py / setup.cfg migration parity

Verify that every configuration field from master's `setup.py` and `setup.cfg` is present in the modernized `pyproject.toml`. This catches fields silently dropped during migration.

Checks (ordered by severity):

- **FAIL:** name mismatch, description missing, `requires-python` missing, entry points dropped, `[project].dependencies` absent
- **WARN:** license missing, classifiers absent, isort config not migrated, mypy config not migrated, coverage config not migrated, pytest config not migrated
- **info:** License classifier dropped, individual classifiers dropped, `include_package_data` not set, minor field differences

```bash
python3 << 'PYEOF'
import re, subprocess, tomllib, configparser

FAIL = "FAIL"; WARN = "WARN"; INFO = "info"
findings = []

def add(sev, msg): findings.append((sev, msg))

# Detect base branch
BASE = None
for b in ("main", "master"):
    r = subprocess.run(["git", "show-ref", "--verify", "--quiet", f"refs/heads/{b}"], capture_output=True)
    if r.returncode == 0:
        BASE = b; break
if not BASE:
    for remote in ("upstream", "origin"):
        for b in ("main", "master"):
            r = subprocess.run(["git", "ls-remote", "--exit-code", "--heads", remote, b], capture_output=True)
            if r.returncode == 0:
                BASE = f"{remote}/{b}"; break
        if BASE: break
if not BASE:
    print("SKIP: no main/master branch found — cannot compare against master")
    raise SystemExit(0)

print(f"Comparing against: {BASE}\n")

def git_show(path):
    r = subprocess.run(["git", "show", f"{BASE}:{path}"], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None

def extract_setup_py_field(content, field):
    if not content: return None
    m = re.search(rf'{field}\s*=\s*\[([^\]]+)\]', content, re.DOTALL)
    if m:
        return re.findall(r'["\']([^"\']+)["\']', m.group(1)) or None
    m = re.search(rf'{field}\s*=\s*["\']([^"\']+)["\']', content)
    return m.group(1) if m else None

try:
    with open("pyproject.toml", "rb") as f:
        toml = tomllib.load(f)
except Exception as e:
    print(f"FAIL: cannot read pyproject.toml — {e}"); raise SystemExit(1)

project = toml.get("project", {}); tool = toml.get("tool", {})
setup_cfg = git_show("setup.cfg"); setup_py = git_show("setup.py")
coveragerc = git_show(".coveragerc")

cfg = configparser.ConfigParser()
if setup_cfg: cfg.read_string(setup_cfg)

def cfg_meta(key):
    for section in ("metadata", "options"):
        if cfg.has_section(section) and cfg.has_option(section, key):
            return cfg.get(section, key).strip()
    return extract_setup_py_field(setup_py, key)

# ── 1. name ──────────────────────────────────────────────────────────────────
master_name = cfg_meta("name")
pr_name = project.get("name", "")
if master_name and pr_name:
    if master_name.replace("_","-").lower() != pr_name.replace("_","-").lower():
        add(FAIL, f"[project].name mismatch: master={master_name!r} PR={pr_name!r}")
    else:
        print(f"  ok  name = {pr_name!r}")
elif not pr_name:
    add(FAIL, "[project].name missing")

# ── 2. description ───────────────────────────────────────────────────────────
master_desc = cfg_meta("description")
if master_desc and not project.get("description"):
    add(FAIL, f"[project].description missing (master had: {master_desc!r})")
elif project.get("description"):
    print(f"  ok  description present")

# ── 3. requires-python ───────────────────────────────────────────────────────
master_py = cfg_meta("python_requires")
if master_py and not project.get("requires-python"):
    add(FAIL, f"[project].requires-python missing (master had: {master_py!r})")
elif project.get("requires-python"):
    print(f"  ok  requires-python = {project['requires-python']!r}")

# ── 4. license ───────────────────────────────────────────────────────────────
master_license = cfg_meta("license")
pr_license = project.get("license", "")

INVALID_SPDX = {"AGPL-3.0", "GPL-3.0", "GPL-2.0", "LGPL-2.1", "LGPL-3.0"}  # deprecated bare forms
if master_license and not pr_license:
    add(WARN, f"[project].license missing (master had: {master_license!r})")
elif pr_license in INVALID_SPDX:
    add(FAIL, f"[project].license = {pr_license!r} is a deprecated SPDX identifier — "
              f"use the -only or -or-later suffix (e.g. 'AGPL-3.0-only'). "
              f"Check master's license= field and classifiers to determine which applies; "
              f"the LICENSE file appendix text is not a grant and must be ignored.")
elif pr_license:
    print(f"  ok  license = {pr_license!r}")

# ── 5. classifiers ───────────────────────────────────────────────────────────
master_cls_raw = cfg_meta("classifiers")
if master_cls_raw:
    master_cls = [c.strip() for c in master_cls_raw.splitlines() if c.strip() and not c.startswith("#")]
else:
    master_cls = extract_setup_py_field(setup_py, "classifiers") or []
pr_cls = project.get("classifiers", [])
if master_cls and not pr_cls:
    add(WARN, f"No classifiers in [project] (master had {len(master_cls)} classifiers)")
elif pr_cls:
    master_license_cls = [c for c in master_cls if "License ::" in c]
    pr_license_cls = [c for c in pr_cls if "License ::" in c]
    if master_license_cls and not pr_license_cls:
        add(INFO, f"License classifier dropped — master had: {master_license_cls[0]!r}")
    elif pr_license_cls:
        print(f"  ok  License classifier: {pr_license_cls[0]!r}")
    important_dropped = {c for c in master_cls if "Python :: 3." not in c and "License ::" not in c} - set(pr_cls)
    for d in sorted(important_dropped):
        add(INFO, f"Classifier dropped: {d!r}")

# ── 6. entry points ──────────────────────────────────────────────────────────
master_eps = {}
for section in ("options.entry_points", "entry_points"):
    if cfg.has_section(section):
        for k, v in cfg.items(section): master_eps[k] = v.strip()
if setup_py and not master_eps:
    m = re.search(r'entry_points\s*=\s*\{([^}]+)\}', setup_py, re.DOTALL)
    if m:
        for km in re.finditer(r'["\']([^"\']+)["\']\s*:\s*\[([^\]]+)\]', m.group(1), re.DOTALL):
            master_eps[km.group(1)] = km.group(2)
pr_scripts = project.get("scripts", {})
pr_eps = project.get("entry-points", {})
if "console_scripts" in master_eps:
    if not pr_scripts:
        add(FAIL, f"[project.scripts] missing — master had console_scripts")
    else:
        print(f"  ok  [project.scripts] = {list(pr_scripts.keys())}")
for ep_key in master_eps:
    if ep_key == "console_scripts": continue
    if ep_key not in str(pr_eps):
        add(WARN, f"Entry point group {ep_key!r} from master not in [project.entry-points]")

# ── 7. dependencies ──────────────────────────────────────────────────────────
if project.get("dependencies") is None:
    add(FAIL, "[project].dependencies missing")
else:
    print(f"  ok  [project].dependencies ({len(project['dependencies'])} packages)")

# ── 8. [isort] → [tool.isort] ────────────────────────────────────────────────
if cfg.has_section("isort"):
    if "isort" not in tool:
        add(WARN, "[isort] in master's setup.cfg not migrated to [tool.isort]")
    else:
        print("  ok  [tool.isort] present")
        for key in ("multi_line_output", "line_length", "include_trailing_comma"):
            mv = cfg.get("isort", key, fallback=None)
            pv = str(tool.get("isort", {}).get(key, ""))
            if mv is not None and pv.lower().strip() != mv.lower().strip():
                add(WARN, f"[tool.isort].{key}: master={mv!r} PR={pv!r}")

# ── 9. [mypy] → [tool.mypy] ──────────────────────────────────────────────────
has_mypy = cfg.has_section("mypy") or any(s.startswith("mypy-") for s in cfg.sections())
if has_mypy:
    if "mypy" not in tool:
        add(WARN, "[mypy] in master's setup.cfg not migrated to [tool.mypy]")
    else:
        print("  ok  [tool.mypy] present")
        for key in ("python_version", "ignore_missing_imports", "check_untyped_defs"):
            mv = cfg.get("mypy", key, fallback=None)
            pv = str(tool.get("mypy", {}).get(key, ""))
            if mv is not None and pv.lower().strip() != mv.lower().strip():
                add(INFO, f"[tool.mypy].{key}: master={mv!r} PR={pv!r}")

# ── 10. pytest → [tool.pytest.ini_options] ───────────────────────────────────
has_pytest = cfg.has_section("tool:pytest") or cfg.has_section("pytest")
if not has_pytest:
    tox_ini = git_show("tox.ini")
    if tox_ini:
        tox_cfg = configparser.ConfigParser()
        tox_cfg.read_string(tox_ini)
        has_pytest = tox_cfg.has_section("pytest")
if has_pytest:
    if "pytest" not in tool:
        add(WARN, "[tool:pytest] config on master not migrated to [tool.pytest.ini_options]")
    else:
        print("  ok  [tool.pytest.ini_options] present")

# ── 11. .coveragerc / [coverage:*] → [tool.coverage] ────────────────────────
has_coverage = bool(coveragerc) or cfg.has_section("coverage:run") or cfg.has_section("coverage:report")
if has_coverage:
    if "coverage" not in tool:
        add(WARN, "Coverage config on master (.coveragerc / setup.cfg [coverage:*]) not migrated to [tool.coverage]")
    else:
        print("  ok  [tool.coverage] present")
        if coveragerc:
            cov_cfg = configparser.ConfigParser()
            cov_cfg.read_string(coveragerc)
            for key in ("branch", "source", "omit"):
                mv = cov_cfg.get("run", key, fallback=None)
                pv = tool.get("coverage", {}).get("run", {}).get(key)
                if mv and pv is None:
                    add(INFO, f"[tool.coverage.run].{key} not set (master .coveragerc had {key} = {mv!r})")

# ── 12. include_package_data ─────────────────────────────────────────────────
master_ipd = cfg.get("options", "include_package_data", fallback=None)
if not master_ipd and setup_py:
    if re.search(r'include_package_data\s*=\s*True', setup_py):
        master_ipd = "True"
if master_ipd and master_ipd.lower() in ("true", "1", "yes"):
    if not tool.get("setuptools", {}).get("include-package-data"):
        add(INFO, "[tool.setuptools] include-package-data = true not set (master had include_package_data=True)")

# ── 13. authors ───────────────────────────────────────────────────────────────
EXPECTED_AUTHORS = [{"name": "Open edX Project", "email": "oscm@openedx.org"}]
pr_authors = project.get("authors", [])
if pr_authors != EXPECTED_AUTHORS:
    add(FAIL, f"[project].authors must be exactly {EXPECTED_AUTHORS!r} — got {pr_authors!r}")
else:
    print(f"  ok  authors = {pr_authors!r}")

# ── Summary ───────────────────────────────────────────────────────────────────
print()
fails = [f for f in findings if f[0] == FAIL]
warns = [f for f in findings if f[0] == WARN]
infos = [f for f in findings if f[0] == INFO]
for sev, msg in findings:
    print(f"  [{sev}]  {msg}")
print(f"\n  setup.py/setup.cfg parity: {len(fails)} FAIL, {len(warns)} WARN, {len(infos)} info")
if fails:
    raise SystemExit(1)
PYEOF
```

**Pass:** No `[FAIL]` lines. All metadata, entry points, and tool config sections from master are present in `pyproject.toml`.

**Fail:** Any field that existed on master is absent or mismatched in the PR — a hard migration gap.

---

### Test 160 — Dependency package parity

Run from the repo root (requires Python 3.11+ for `tomllib`):

```bash
python3 << 'PYEOF'
import re, subprocess, tomllib

# Tools legitimately removed by this migration (replaced by uv's own machinery).
REPLACED_BY_MIGRATION = {
    'pip-tools',
}

# Build/publish bootstrap tools that uv subsumes or that are irrelevant for non-PyPI
# services. Missing these is not a hard failure — emit a WARN so the author can confirm
# the drop was intentional rather than accidental.
WARN_IF_MISSING = {
    'pip', 'wheel', 'setuptools', 'twine',
}

# Packages legitimately added to specific groups by this migration that were not
# in the original .in files. Keyed by group name → set of normalized package names.
# tox-uv: the migration template always adds tox-uv to the ci group even when
# ci.in only had tox, because uv-venv-lock-runner requires it.
ADDED_BY_MIGRATION = {
    'ci': {'tox-uv'},
}

def normalize(name):
    # Strip version specifiers/markers first so a PR entry like "Django>=5.2,<6.0"
    # matches master's bare "django" (else it reads as a spurious missing package).
    name = re.split(r'[><=!~\s;@]', name)[0]
    name = re.sub(r'\[.*?\]', '', name).strip()
    return name.lower().replace('_', '-').replace('.', '-')

# Packages still resolvable transitively via uv.lock. A master direct-dep that is no
# longer explicitly declared is only a hard regression if it has ALSO fallen out of the
# resolved environment. If it is still in uv.lock (pulled in transitively, e.g. isort via
# edx-lint), the environment is intact — losing the explicit declaration is a WARN
# (reproducibility/explicitness), not a FAIL. This is repo-agnostic: no tool is hardcoded.
def load_locked_packages():
    try:
        with open('uv.lock', 'rb') as f:
            lock = tomllib.load(f)
    except (FileNotFoundError, tomllib.TOMLDecodeError):
        return set()
    return {normalize(p.get('name', '')) for p in lock.get('package', []) if p.get('name')}

LOCKED = load_locked_packages()

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

with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)

# ── Step 1 — Overall parity: no package dropped or gained across all .in files ──

# Discover the repo's ACTUAL .in files instead of assuming canonical cookiecutter
# names — legacy repos use bespoke names (e.g. sandbox.in, testing.in, tox.in). A
# hardcoded ['base.in','test.in',...] list reads nothing for those repos and passes
# vacuously, hiding real drift. Glob what master actually has.
ls = subprocess.run(['git', 'ls-tree', '--name-only', 'master:requirements'],
                    capture_output=True, text=True)
in_files = [f for f in ls.stdout.split() if f.endswith('.in')]
if not in_files:
    print("SKIP: no requirements/*.in files on master — nothing to compare")
    raise SystemExit(0)
print(f"Discovered master .in files: {sorted(in_files)}")
master_pkgs = set()
for f in in_files:
    r = subprocess.run(['git', 'show', f'master:requirements/{f}'], capture_output=True, text=True)
    if r.returncode == 0:
        master_pkgs |= parse_in_file(r.stdout)

pr_pkgs = set()
for dep in data.get('project', {}).get('dependencies', []):
    pr_pkgs.add(normalize(dep.split('@')[0]))
for group_deps in data.get('dependency-groups', {}).values():
    for dep in group_deps:
        if isinstance(dep, str):
            pr_pkgs.add(normalize(dep.split('@')[0]))

missing = master_pkgs - pr_pkgs - REPLACED_BY_MIGRATION
added   = pr_pkgs - master_pkgs

# Packages in WARN_IF_MISSING are treated as warnings regardless of uv.lock presence —
# uv subsumes pip/setuptools/wheel, and twine is irrelevant for non-PyPI services.
missing_warn_only  = {p for p in missing if p in WARN_IF_MISSING}
missing_real       = missing - missing_warn_only

# Split real missing into hard failures (gone from the resolved env too) and soft warnings
# (still transitively present in uv.lock — declaration lost but environment intact).
missing_gone       = {p for p in missing_real if p not in LOCKED}
missing_transitive = {p for p in missing_real if p in LOCKED}

print("Step 1 — Overall parity:")
print("  MISSING & GONE (in master .in files, not in pyproject.toml, not in uv.lock):")
for p in sorted(missing_gone): print(f"    FAIL: {p}")
if not missing_gone: print("    (none)")

print("  MISSING but TRANSITIVELY AVAILABLE (dropped explicit declaration, still in uv.lock):")
for p in sorted(missing_transitive): print(f"    WARN: {p}  — re-declare explicitly for reproducibility, or confirm the drop is intentional")
if not missing_transitive: print("    (none)")

print("  MISSING build/publish bootstrap tools (uv subsumes these; WARN only):")
for p in sorted(missing_warn_only): print(f"    WARN: {p}  — uv provides pip/setuptools/wheel implicitly; twine is only needed for PyPI publishing. Confirm the drop is intentional.")
if not missing_warn_only: print("    (none)")

print("  ADDED in PR (not in any master .in file):")
for p in sorted(added): print(f"    ADDED: {p}")
if not added: print("    (none)")

print(f"\n  Master total: {len(master_pkgs)} | PR total: {len(pr_pkgs)}")
if missing_gone:
    raise SystemExit(f"\nFAIL: {len(missing_gone)} package(s) missing from pyproject.toml AND absent from uv.lock")

# ── Step 2 — Per-.in accountability (no silent skips) ──
# Derived from the .in files actually discovered in Step 1 (not a hardcoded canonical
# list). Two modes per file:
#   • basename matches a group (canonical: test.in→test) → exact name-based parity.
#   • non-canonical name (legacy: sandbox/testing/tox) → the migration reorganizes its
#     packages, so instead of a vacuous skip we ATTRIBUTE each package to where it
#     landed (which group / runtime) and FAIL any package left genuinely unaccounted.
dep_groups = data.get('dependency-groups', {})
step2_failures = []

# Reverse index: normalized package name → every destination declaring it.
pkg_dest = {}
for dep in data.get('project', {}).get('dependencies', []):
    if isinstance(dep, str):
        pkg_dest.setdefault(normalize(dep.split('@')[0]), []).append('[project.dependencies]')
for gname, gdeps in dep_groups.items():
    for dep in gdeps:
        if isinstance(dep, str):
            pkg_dest.setdefault(normalize(dep.split('@')[0]), []).append(gname)

for in_filename in sorted(in_files):
    group_name = in_filename[:-3]  # strip ".in"
    if group_name == 'base':
        continue  # base.in → [project].dependencies, already covered by Step 1
    r = subprocess.run(['git', 'show', f'master:requirements/{in_filename}'], capture_output=True, text=True)
    if r.returncode != 0:
        continue
    if group_name not in dep_groups:
        # Non-canonical name: no same-named group by design. Attribute every package to
        # its destination(s); FAIL any that is unaccounted (not in a group/runtime AND
        # not resolvable via uv.lock). This replaces the old silent skip.
        pkgs = parse_in_file(r.stdout) - REPLACED_BY_MIGRATION
        print(f"\nStep 2 — {in_filename} (non-canonical name; per-package attribution):")
        if not pkgs:
            print(f"  (no direct packages — '-r'-only or documented-drop)")
            continue
        for p in sorted(pkgs):
            dests = pkg_dest.get(p)
            if dests:
                print(f"  ok  {p} → {dests}")
            elif p in LOCKED:
                print(f"  WARN: {p} — not declared in any group/runtime but present in uv.lock (re-declare or confirm intentional)")
            else:
                print(f"  FAIL: {p} — in master {in_filename} but UNACCOUNTED: not in any group/runtime AND not in uv.lock")
                step2_failures.append(p)
        continue
    master_group_pkgs = parse_in_file(r.stdout) - REPLACED_BY_MIGRATION
    pr_group_pkgs = set()
    for dep in dep_groups.get(group_name, []):
        if isinstance(dep, str):
            pr_group_pkgs.add(normalize(dep.split('@')[0]))
    allowed_extras = ADDED_BY_MIGRATION.get(group_name, set())
    missing_from_group = master_group_pkgs - pr_group_pkgs
    extra_in_group     = (pr_group_pkgs - master_group_pkgs) - allowed_extras
    # A package missing from its named group but still resolvable in uv.lock is a WARN
    # (declaration moved/dropped but environment intact), not a hard group-parity FAIL.
    group_gone        = {p for p in missing_from_group if p not in LOCKED}
    group_transitive  = missing_from_group - group_gone
    print(f"\nStep 2 — {in_filename} vs [dependency-groups.{group_name}]:")
    for p in sorted(group_gone):
        print(f"  FAIL: {p}  (in master {in_filename}, absent from {group_name} group AND from uv.lock)")
    for p in sorted(group_transitive):
        print(f"  WARN: {p}  (in master {in_filename}, not declared in {group_name} group but present in uv.lock)")
    for p in sorted(extra_in_group):
        print(f"  EXTRA: {p}  (in {group_name} group but not in master {in_filename})")
    if not missing_from_group and not extra_in_group:
        print(f"  (ok — exact parity)")
    # Only hard failures (gone from lock) and unexplained extras gate the test.
    step2_failures.extend(group_gone)
    step2_failures.extend(extra_in_group)

if step2_failures:
    raise SystemExit(f"\nFAIL: {len(step2_failures)} package(s) with group parity violations")
PYEOF
```

**Pass:** No `FAIL:` or `EXTRA:` lines, exit code 0. Step 1 confirms aggregate coverage; Step 2 accounts for **every** discovered `.in` file — either exact name-parity (canonical basename matches a group) or per-package attribution showing where each package landed (non-canonical/legacy names). `WARN:` lines do not fail the test — they surface cases where a package's explicit declaration was dropped but the environment is still intact (transitively in `uv.lock`), or where a build/publish bootstrap tool (`pip`, `wheel`, `setuptools`, `twine`) was dropped because uv subsumes it or it is irrelevant for a non-PyPI service.

**Fail:** any package from a master `.in` file is unaccounted — absent from every dependency group / `[project].dependencies` **and** from `uv.lock` (Step 1 `MISSING & GONE`, or a Step 2 per-package `FAIL`), or a group has an `EXTRA` package not in its `.in` and not in the migration allowlist. Missing `pip`/`wheel`/`setuptools`/`twine` never causes a failure — only a warning.

### Test 170 — Constraints migration

**Step 1 — Read the old constraints file:**

```bash
git show master:requirements/constraints.txt 2>/dev/null || git show main:requirements/constraints.txt 2>/dev/null || echo "No constraints.txt on base branch"
```

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

**Pass:** `[tool.edx_lint].uv_constraints` is a TOML array; `[tool.uv].constraint-dependencies` is non-empty; all repo-specific pins from the old `constraints.txt` appear in `constraint-dependencies`; constrained packages in `uv.lock` respect the pins.

### Test 180 — release.yml structure: CI first, immutable-safe release, then OIDC publish only

Skip (with reason) if the repo is in the hardcoded non-PyPI list — in that case `release.yml` is not added. Otherwise verify that `release.yml` (a) runs the CI workflow first via a reusable-workflow call, (b) creates the GitHub Release in an **immutable-safe** way — PSR builds/tags but does not publish the release (`vcs_release: "false"`) and a `gh release create` step attaches the dists to a draft before publishing (never `python-semantic-release/publish-action`), and (c) publishes to PyPI using **OIDC trusted publishing only** — no token auth anywhere.

```bash
echo "=== run_tests / run_ci job calling CI workflow ==="
grep -n "uses:.*ci\.yml\|uses:.*python-tests\.yml" .github/workflows/release.yml \
  || echo "(none — FAIL: release.yml must call the CI workflow as a reusable workflow)"

echo "=== immutable-safe release: PSR must NOT publish the release itself ==="
grep -nE 'vcs_release:\s*"?false"?' .github/workflows/release.yml \
  || echo "(none — FAIL: PSR step must set vcs_release: \"false\" so the release is created draft-first)"

echo "=== changelog disabled in release.yml (required) ==="
# changelog: "false" must be set as an action input in release.yml — that is the
# canonical location. Putting it in pyproject.toml is an anti-pattern (release
# policy scattered across two files, can drift silently).
workflow_ok=$(grep -nE 'changelog:\s*"?false"?' .github/workflows/release.yml 2>/dev/null | head -1)
if [ -n "$workflow_ok" ]; then
  echo "OK: changelog disabled in release.yml (${workflow_ok})"
else
  echo "FAIL: changelog not disabled in release.yml — add 'changelog: \"false\"' as an action input to the python-semantic-release step; without it PSR overwrites the repo's CHANGELOG file on every release"
fi

echo "=== changelog = false must NOT be in pyproject.toml (anti-pattern) ==="
# release policy belongs in the workflow, not the package config.
pyproject_bad=$(grep -nE '^\s*changelog\s*=\s*false' pyproject.toml 2>/dev/null | head -1)
if [ -n "$pyproject_bad" ]; then
  echo "FAIL: 'changelog = false' found in pyproject.toml (line: ${pyproject_bad}) — remove it; changelog is controlled via 'changelog: \"false\"' in release.yml only"
else
  echo "OK: changelog = false absent from pyproject.toml"
fi

echo "=== immutable-safe release: gh release create attaches assets before publishing ==="
grep -n "gh release create" .github/workflows/release.yml \
  || echo "(none — FAIL: release must be created via 'gh release create' with the dists as args)"

echo "=== old immutable-UNSAFE pattern must be gone ==="
grep -n "python-semantic-release/publish-action" .github/workflows/release.yml \
  && echo "FAIL: publish-action attaches assets AFTER publish — breaks on immutable releases; replace with gh release create" \
  || echo "(none — OK)"

echo "=== id-token permission (must be present on publish_to_pypi) ==="
grep -n "id-token" .github/workflows/release.yml || echo "(none — FAIL)"
echo "=== password / PYPI_UPLOAD_TOKEN (must be absent) ==="
grep -nE "password:|PYPI_UPLOAD_TOKEN" .github/workflows/release.yml || echo "(none — OK)"
echo "=== workflow filename ==="
[ -f .github/workflows/release.yml ] && echo "OK: named release.yml" || echo "FAIL: release workflow is not named release.yml"

echo "=== release.yml branch matches repo default branch ==="
# The template ships with `branches: [master]` and two `if: github.ref_name == 'master'` guards.
# Repos whose default branch is NOT master (e.g. edx_release, main) will never trigger a release.
# Always verify the branch name in release.yml against the actual repo default branch.
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo "unknown")
echo "Repo default branch: $DEFAULT_BRANCH"
RELEASE_PUSH_BRANCH=$(grep -E '^\s+branches:\s*\[' .github/workflows/release.yml | head -1 | tr -d ' []' | cut -d: -f2)
echo "release.yml push branch: $RELEASE_PUSH_BRANCH"
if [ "$DEFAULT_BRANCH" = "unknown" ]; then
  echo "WARN: could not determine repo default branch (gh not available?)"
elif [ "$RELEASE_PUSH_BRANCH" != "$DEFAULT_BRANCH" ]; then
  echo "FAIL: release.yml listens on '$RELEASE_PUSH_BRANCH' but the repo default branch is '$DEFAULT_BRANCH'."
  echo "  PSR and PyPI publish will never run. Fix: replace all occurrences of '$RELEASE_PUSH_BRANCH' with '$DEFAULT_BRANCH' in release.yml."
  echo "  Also check: 'if: github.ref_name == \"$RELEASE_PUSH_BRANCH\"' guards (typically on the release and publish_to_pypi jobs)."
else
  echo "OK: release.yml branch '$RELEASE_PUSH_BRANCH' matches repo default branch."
fi
```

**Pass:** A `run_tests` or `run_ci` job calls the CI workflow via `uses:`; `release` and `publish_to_pypi` declare `needs:`; the PSR step sets `vcs_release: "false"` and `changelog: "false"` and a `gh release create` step attaches `dist/*` to the release; **no** `python-semantic-release/publish-action` step remains; `id-token: write` present in `publish_to_pypi`; **no** `password:` input and **no** `PYPI_UPLOAD_TOKEN`; the workflow is named `release.yml`; `changelog: "false"` set as an action input in `release.yml` (the only correct location); `changelog = false` is **absent** from `[tool.semantic_release]` in `pyproject.toml` (putting it there is an anti-pattern — release policy belongs in the workflow); the branch name in `release.yml` matches the repo's actual default branch (not hardcoded to `master` when the repo uses e.g. `edx_release` or `main`). (PyPI trusted publisher / OIDC is already configured on all repos, so it is not a merge blocker to flag.)

**Non-master default branch:** Repos whose default branch is not `master` (e.g. `edx_release`, `main`) require special attention. The standard template ships with `branches: [master]` and `if: github.ref_name == 'master'` guards — if left unchanged, PSR and PyPI publish will never trigger. Always run `gh repo view --json defaultBranchRef` and update all three occurrences in `release.yml`. Also check `ci.yml` — if it has a `push: branches: [master]` trigger alongside `workflow_call:`, fix the branch there too or drop the `push:` trigger entirely (see Test#445). First seen in [openedx/django-wiki#329](https://github.com/openedx/django-wiki/pull/329) where the default branch is `edx_release`.

**Why the immutable-safe pattern is required:** the openedx org has [immutable releases](https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/immutable-releases) enabled, which freezes a release's assets the moment it is published. The old flow (PSR publishes the release, then `publish-action` uploads assets afterward) now fails with `422 Cannot upload assets to an immutable release`, and the artifact-less release aborts the job so PyPI/npm publish never runs. `gh release create <tag> ... dist/*` creates the release as a draft, uploads the assets, then publishes — the only ordering immutable releases allow. See [openedx/sample-plugin#57](https://github.com/openedx/sample-plugin/pull/57).

### Test 190 — Configuration thresholds must maintain parity with master

```bash
# Check old .coveragerc for fail_under
git show master:.coveragerc 2>/dev/null | grep -i "fail_under" || echo "(none)"

# Check old setup.cfg for any thresholds
git show master:setup.cfg 2>/dev/null | grep -E "fail_under|threshold|limit" || echo "(none)"

# Check new pyproject.toml for fail_under in coverage config
grep "fail_under" pyproject.toml || echo "(none)"
```

**Pass:** All configuration thresholds in pyproject.toml match what was in master's old config files. No new limits added.

### Test 210 — PR description completeness

**Gated: only run this test when the user explicitly asks for it.** Skip it in all other test runs and record the row as `⏭️ Skipped (gated — run explicitly to check PR description)`.

```bash
gh pr view <number> --json body --jq '.body' > /tmp/pr_body.txt
```

Then run the section checks from the [PR description format](#pr-description-format) template.

### Test 220 — src/ layout (conditional on PyPI publishing)

Check whether the repo is in the hardcoded non-PyPI list (credentials-themes, mockprock, edx-repo-health, openedx-webhooks-data-schema, enterprise-catalog, enterprise-access, enterprise-subsidy, xapi-db-load, codejail-service, openedx-user-groups, cc2olx, pr_watcher_notifier). If it is NOT in that list (i.e. it is a PyPI repo), `src/` layout is required; if it IS in the list, it is optional but the PR description must document the decision.

```bash
PKG=$(python3 -c "import tomllib; d=tomllib.load(open('pyproject.toml','rb')); print(d['project']['name'].replace('-','_'))" 2>/dev/null)
[ -d "src/$PKG" ] && echo "OK: src/$PKG present" || echo "FAIL: src/$PKG missing"
if [ -d "$PKG" ] && [ "$PKG" != "src" ]; then echo "FAIL: top-level $PKG/ still exists — package was not moved, it was duplicated"; else echo "OK: no stray top-level $PKG/"; fi
```

**Pass conditions:**
- **PyPI repo:** `src/<pkg>/` exists; no stray top-level `<pkg>/`; `where = ["src"]`; the package imports cleanly.
- **Non-PyPI repo without src/ layout:** Package remains at top level; `where` is not set; PR description documents why `src/` layout was not adopted.


### Test 230 — Mypy not introduced (or retained if already present)

First determine whether master used mypy — check the Makefile, tox.ini, and setup.cfg on the master branch:

```bash
echo "=== mypy in master Makefile ==="
git show origin/master:Makefile 2>/dev/null | grep -i mypy || echo "(none)"
echo "=== mypy in master tox.ini ==="
git show origin/master:tox.ini 2>/dev/null | grep -i mypy || echo "(none)"
echo "=== mypy in master setup.cfg ==="
git show origin/master:setup.cfg 2>/dev/null | grep -i mypy || echo "(none)"
```

**If master did NOT use mypy** (none of those commands output anything): ⏭️ Skip this test with reason `master did not use mypy`. Then verify mypy was not introduced:

```bash
echo "=== mypy in PR pyproject.toml ==="
grep -n 'mypy' pyproject.toml || echo "(none)"
echo "=== mypy in PR tox.ini ==="
grep -n 'mypy' tox.ini 2>/dev/null || echo "(none)"
echo "=== mypy in PR Makefile ==="
grep -n 'mypy' Makefile 2>/dev/null || echo "(none)"
echo "=== mypy in PR uv.lock ==="
grep -c 'name = "mypy"' uv.lock 2>/dev/null && echo "FAIL: mypy present in uv.lock" || echo "(none)"
```

**Pass (master had no mypy):** `[tool.mypy]` absent from `pyproject.toml`; no `mypy` dependency in any dependency group; no `mypy` tox env; no `mypy` make target; `mypy` does not appear as a package in `uv.lock`. Record as ⏭️ Skipped (master did not use mypy — confirmed mypy not introduced).

**Fail (master had no mypy, but PR introduced it):** Report exactly what was introduced (which file, which line) and state it must be removed.

**If master DID use mypy:** Verify it is retained in the PR.

```bash
python3 << 'PYEOF'
import tomllib, subprocess, configparser

# Check master's setup.cfg for [mypy] sections
cfg_raw = subprocess.run(['git', 'show', 'origin/master:setup.cfg'],
                         capture_output=True, text=True).stdout
cfg = configparser.ConfigParser()
cfg.read_string(cfg_raw)
master_has_mypy_cfg = cfg.has_section('mypy') or any(s.startswith('mypy-') for s in cfg.sections())

with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)

tool = data.get('tool', {})
groups = data.get('dependency-groups', {})

# Check [tool.mypy] present if master had mypy config
if master_has_mypy_cfg:
    if 'mypy' not in tool:
        print("FAIL: master had [mypy] in setup.cfg but [tool.mypy] is absent from pyproject.toml")
    else:
        print("OK: [tool.mypy] present")

# Check mypy appears as a dependency
all_deps = '|'.join(str(d) for g in groups.values() for d in g).lower()
if 'mypy' not in all_deps:
    print("FAIL: mypy not in any dependency group — was it dropped?")
else:
    print("OK: mypy present in dependency groups")
PYEOF

echo "=== mypy tox envs on master ==="
git show origin/master:tox.ini 2>/dev/null | grep -E '^\[testenv.*mypy' || echo "(none)"
echo "=== mypy tox envs in PR ==="
grep -E '^\[testenv.*mypy' tox.ini 2>/dev/null || echo "(none)"
```

**Pass (master had mypy):** `[tool.mypy]` present (with config migrated from master's setup.cfg); mypy in a dependency group; any mypy tox env from master preserved with the same name.

**Fail (master had mypy, but PR dropped it):** Report what is missing and that it must be restored.


### Test 240 — Versioning strategy (consolidated)

```bash
python3 << 'PYEOF'
import tomllib
import subprocess, re

# Repos confirmed NOT published to PyPI — all others are treated as PyPI repos
NON_PYPI_REPOS = {
    'credentials-themes', 'mockprock', 'edx-repo-health',
    'openedx-webhooks-data-schema', 'enterprise-catalog', 'enterprise-access',
    'enterprise-subsidy', 'xapi-db-load', 'codejail-service',
    'openedx-user-groups', 'cc2olx', 'pr_watcher_notifier',
}
remote = subprocess.run(['git', 'remote', 'get-url', 'origin'],
                        capture_output=True, text=True).stdout.strip()
m = re.search(r'/([^/]+?)(?:\.git)?$', remote)
repo_name = m.group(1) if m else ''
gate = "no-pypi" if repo_name in NON_PYPI_REPOS else "pypi"
print(f"Repo: {repo_name!r} → gate={gate}")

with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)

project = data.get('project', {})
dynamic = project.get('dynamic', [])
version = project.get('version')
build_requires = data.get('build-system', {}).get('requires', [])
sr = data.get('tool', {}).get('semantic_release', {})

import re
for req in build_requires:
    if re.match(r'^setuptools\s*[><=!]', req):
        print(f"FAIL: [build-system].requires contains versioned setuptools ({req!r}) — use bare 'setuptools'")
        break

if gate == "pypi":
    has_scm = any('setuptools-scm' in req for req in build_requires)
    if not has_scm:
        print("FAIL: PyPI repo missing setuptools-scm in build-system.requires")
    elif 'version' not in dynamic:
        print("FAIL: PyPI repo must have dynamic = ['version']")
    else:
        tag_result = subprocess.run(['git', 'tag', '--sort=version:refname'],
                                    capture_output=True, text=True)
        tags = [t.lstrip('v') for t in tag_result.stdout.strip().split('\n')
                if t and (t[0].isdigit() or t.startswith('v'))]
        allow_zero = sr.get('allow_zero_version')
        major_on_zero = sr.get('major_on_zero')
        if not tags or tags[-1][0] == '0':
            if allow_zero is not True or major_on_zero is not False:
                label = f"latest tag {tags[-1]!r}" if tags else "no release tags"
                print(f"FAIL: 0.x PyPI repo ({label}) missing zero-version guard in [tool.semantic_release]")
            else:
                print(f"OK: PyPI repo (0.x) versioned via setuptools-scm with zero-version guard")
        else:
            if allow_zero is not None or major_on_zero is not None:
                print(f"FAIL: 1.x+ PyPI repo has spurious zero-version guard settings in [tool.semantic_release]")
            else:
                print("OK: PyPI repo (1.x+) versioned via setuptools-scm, no zero-version guard needed")
else:
    has_scm = any('setuptools-scm' in req for req in build_requires)
    has_scm_config = 'setuptools_scm' in data.get('tool', {})
    if has_scm:
        print("FAIL: no-PyPI repo has setuptools-scm in build-system.requires — remove it; no PyPI publishing means build-time version resolution from git tags serves no purpose")
    if has_scm_config:
        print("FAIL: no-PyPI repo has [tool.setuptools_scm] section — remove it")
    if not version:
        print("FAIL: no-PyPI repo missing static version in [project]")
    elif 'version' in dynamic:
        print("FAIL: no-PyPI repo should not have dynamic version")
    else:
        # Verify version is not a placeholder and matches master
        if version in ('', 'x.y.z', '0.0.0', 'PLACEHOLDER'):
            print(f"FAIL: no-PyPI repo has placeholder version {version!r} — set the real version from master")
        else:
            # Cross-check against master's version sources
            master_version = None
            # 1. setup.cfg [metadata] version=
            r = subprocess.run(['git', 'show', 'upstream/main:setup.cfg'], capture_output=True, text=True)
            if r.returncode == 0:
                m = re.search(r'^\s*version\s*=\s*(\S+)', r.stdout, re.MULTILINE)
                if m:
                    master_version = m.group(1).strip()
            # 2. package __init__.py __version__ = "x.y.z"
            if not master_version:
                pkg_name = data.get('project', {}).get('name', '').replace('-', '_')
                for init_path in (f'{pkg_name}/__init__.py', f'src/{pkg_name}/__init__.py'):
                    r = subprocess.run(['git', 'show', f'upstream/main:{init_path}'], capture_output=True, text=True)
                    if r.returncode == 0:
                        m = re.search(r"__version__\s*=\s*['\"]([^'\"]+)['\"]", r.stdout)
                        if m:
                            master_version = m.group(1)
                            break
            if master_version and master_version != version:
                print(f"FAIL: no-PyPI repo version {version!r} does not match master version {master_version!r} — use the master version")
            elif master_version:
                print(f"OK: no-PyPI repo has static version = {version!r} (matches master)")
            else:
                print(f"OK: no-PyPI repo has static version = {version!r} (could not locate master version to cross-check)")

    # readme must be a static field, not dynamic
    readme_static = project.get('readme')
    if 'readme' in dynamic:
        print("FAIL: no-PyPI repo has 'readme' in dynamic — set readme = 'README.rst' as a static field in [project] instead; no PyPI publishing means the dynamic readme setup has no consumer")
    elif not readme_static:
        print("WARN: no-PyPI repo has no readme field — consider adding readme = 'README.rst' to [project]")
    else:
        print(f"OK: no-PyPI repo has static readme = {readme_static!r}")

    # [tool.setuptools.dynamic] must not exist (it only serves the dynamic readme / PyPI description)
    if 'dynamic' in data.get('tool', {}).get('setuptools', {}):
        print("FAIL: no-PyPI repo has [tool.setuptools.dynamic] — remove it; this section only populates the PyPI long-description and has no consumer for a non-publishing repo")
PYEOF
```

**Pass:** `setuptools` has no version specifier; PyPI repos use setuptools-scm with `dynamic = ["version"]`; 0.x repos have the zero-version guard; 1.x+ repos do not. No-PyPI repos use a static `version` field with no `setuptools-scm` present.

### Test 245 — PSR `tag_format` matches existing release tags (manual baseline tag required on mismatch)

python-semantic-release determines the last released version by reading **git tags only** — never PyPI, never a version file. It inverts `tag_format` into a regex (default `tag_format = "v{version}"` → `^v(?P<version>.+)$`) and **silently discards every tag that does not match**. A repo whose historical tags are bare (`0.4.3`, `0.4.2`, …) is therefore invisible to a default-config PSR: it re-derives versions from `0.0.0`, so it either refuses to release (`No release will be made, X already released`) or publishes a wrong/duplicate version. Detect the mismatch and, if present, **fail** and emit the exact `v`-prefixed baseline tag that must be published manually before the first automated release.

```bash
python3 << 'PYEOF'
import tomllib, subprocess, re

# Gate: only PyPI repos use python-semantic-release for versioning/releases
NON_PYPI_REPOS = {
    'credentials-themes', 'mockprock', 'edx-repo-health',
    'openedx-webhooks-data-schema', 'enterprise-catalog', 'enterprise-access',
    'enterprise-subsidy', 'xapi-db-load', 'codejail-service',
    'openedx-user-groups', 'cc2olx', 'pr_watcher_notifier',
}
remote = subprocess.run(['git', 'remote', 'get-url', 'origin'],
                        capture_output=True, text=True).stdout.strip()
m = re.search(r'/([^/]+?)(?:\.git)?$', remote)
repo_name = m.group(1) if m else ''
if repo_name in NON_PYPI_REPOS:
    print(f"SKIP: {repo_name!r} is a non-PyPI repo — python-semantic-release tag history does not apply")
    raise SystemExit

with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)
sr = data.get('tool', {}).get('semantic_release', {})

# PSR default when tag_format is unset
tag_format = sr.get('tag_format', 'v{version}')
if '{version}' not in tag_format:
    print(f"FAIL: [tool.semantic_release].tag_format = {tag_format!r} has no {{version}} placeholder")
    raise SystemExit

# Replicate PSR's VersionTranslator._invert_tag_format_to_re: escape, then sub {version}
psr_re = re.compile('^' + re.escape(tag_format).replace(re.escape('{version}'), r'(?P<version>.+)') + '$')

def find_ver(s):
    # Extract an X.Y.Z anywhere in the tag, so this works for ANY tag_format prefix
    # (v0.4.3, 0.4.3, release-0.4.3, ...), not just the default 'v{version}'.
    mm = re.search(r'(\d+)\.(\d+)\.(\d+)', s)
    return tuple(int(x) for x in mm.groups()) if mm else None

tags = subprocess.run(['git', 'tag'], capture_output=True, text=True).stdout.split()

all_vers = {}   # version tuple -> raw tag  (across ALL release tags on the repo)
psr_vers = {}   # version tuple -> raw tag  (only tags PSR can see via tag_format)
for t in tags:
    v = find_ver(t)
    if v is None:
        continue
    all_vers.setdefault(v, t)
    if psr_re.match(t):
        psr_vers.setdefault(v, t)

if not all_vers:
    print("OK: no release tags yet — PSR will start fresh; the first automated release creates the baseline tag")
    raise SystemExit

true_latest = max(all_vers)
psr_latest = max(psr_vers) if psr_vers else None

if psr_latest == true_latest:
    print(f"OK: latest release tag {all_vers[true_latest]!r} matches tag_format {tag_format!r} — PSR sees the correct baseline")
else:
    ver_str = '.'.join(map(str, true_latest))
    suggest_tag = tag_format.format(version=ver_str)   # e.g. 'v0.4.3'
    latest_raw = all_vers[true_latest]
    seen = psr_vers[psr_latest] if psr_latest else '(none — PSR would restart from 0.0.0)'
    print("FAIL: python-semantic-release cannot see the repo's true latest release.")
    print(f"      Latest release tag on the repo:        {latest_raw!r}  (version {ver_str})")
    print(f"      Highest tag PSR sees via tag_format {tag_format!r}: {seen}")
    print( "      PSR reads git tags ONLY; tags not matching tag_format are ignored, so it will")
    print( "      re-derive versions from scratch and either refuse to release or publish a wrong version.")
    print( "      REQUIRED MANUAL STEP before the first automated release —")
    print(f"      publish a matching baseline tag (starts with 'v' per PSR's default tag_format):")
    print(f"          SUGGEST-TAG: {suggest_tag}")
    print(f"          git tag {suggest_tag} <latest-released-commit-sha>")
    print(f"          git push origin {suggest_tag}")
PYEOF
```

**Pass:** the highest release version present on the repo is carried by a tag that matches `[tool.semantic_release].tag_format` (or the repo has no release tags yet). **Fail:** the true latest release is on a tag PSR cannot parse (e.g. bare `0.4.3` under the default `v{version}` format) — the report must surface the printed `SUGGEST-TAG` and state that manually publishing that `v`-prefixed tag on the latest released commit is required before automated releases will work.

### Test 246 — PSR baseline tag exists for the latest PyPI release (ground-truth anchor)

Test 245 is offline and compares tags against each other, so it can pass on a repo whose release history was already corrupted by broken PSR runs (a stray `v0.4.5` masks that PyPI is really at `0.4.3`). This test anchors on the **actual published state**: it fetches the latest version from PyPI and fails unless a `tag_format`-matching git tag exists for it. Network-dependent, so it **SKIPs** (does not error) when PyPI is unreachable, preserving the suite's determinism.

```bash
python3 << 'PYEOF'
import tomllib, subprocess, json, re

NON_PYPI_REPOS = {
    'credentials-themes', 'mockprock', 'edx-repo-health',
    'openedx-webhooks-data-schema', 'enterprise-catalog', 'enterprise-access',
    'enterprise-subsidy', 'xapi-db-load', 'codejail-service',
    'openedx-user-groups', 'cc2olx', 'pr_watcher_notifier',
}
remote = subprocess.run(['git', 'remote', 'get-url', 'origin'],
                        capture_output=True, text=True).stdout.strip()
m = re.search(r'/([^/]+?)(?:\.git)?$', remote)
repo_name = m.group(1) if m else ''
if repo_name in NON_PYPI_REPOS:
    print(f"SKIP: {repo_name!r} is a non-PyPI repo"); raise SystemExit

with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)
sr = data.get('tool', {}).get('semantic_release', {})
tag_format = sr.get('tag_format', 'v{version}')     # PSR default when unset
pkg = data.get('project', {}).get('name', repo_name)

# Ground truth: latest published version on PyPI (curl avoids Python SSL-store issues)
r = subprocess.run(['curl', '-fsS', f'https://pypi.org/pypi/{pkg}/json'],
                   capture_output=True, text=True)
if r.returncode != 0 or not r.stdout.strip():
    print(f"SKIP: could not reach PyPI for {pkg!r} (offline or unpublished) — rely on Test 245"); raise SystemExit
pypi_latest = json.loads(r.stdout)['info']['version']

tags = set(subprocess.run(['git', 'tag'], capture_output=True, text=True).stdout.split())
expected = tag_format.format(version=pypi_latest)
if expected in tags:
    print(f"OK: baseline tag {expected!r} exists for the latest PyPI release ({pypi_latest})")
else:
    psr_re = re.compile('^' + re.escape(tag_format).replace(re.escape('{version}'), r'(?P<version>.+)') + '$')
    visible = sorted(t for t in tags if psr_re.match(t))
    print(f"FAIL: python-semantic-release cannot see the latest PUBLISHED release ({pypi_latest}).")
    print(f"      Expected a tag_format {tag_format!r} tag: {expected!r} — not found.")
    print(f"      Tags PSR can currently see: {visible or '(none — PSR would restart from 0.0.0)'}")
    print(f"      PSR reads git tags ONLY (never PyPI); it will not treat {pypi_latest} as released and will mis-version the next release.")
    print(f"      REQUIRED MANUAL STEP — publish the baseline tag (starts with 'v' per PSR's default tag_format):")
    print(f"          SUGGEST-TAG: {expected}")
    print(f"          git tag {expected} <commit-of-{pypi_latest}> && git push origin {expected}")
PYEOF
```

**Pass:** a `tag_format`-matching tag exists for the version currently on PyPI (or PyPI is unreachable/unpublished → SKIP). **Fail:** no matching tag exists for the latest published version — surface the printed `SUGGEST-TAG` and require manually publishing that `v`-prefixed tag on the released commit before automated releases will compute the right version.

### Test 247 — PSR commit-parser tags use the #506 default (no sample-plugin override)

`public-engineering#506` (Step 3) states: *"The sample plugin overrides `minor_tags` because it wants to publish new minor versions on docs changes. That is not needed in our other libraries. They should use the default value unless you know for sure you need to use something different."* So the org-canonical `backend-plugin-sample` — which sets `minor_tags = ["feat", "docs"]` and `patch_tags = ["fix", "perf", "build"]` — is a **deliberate exception**, and other repos must NOT copy it. The expected state for a modernized library is **no `[tool.semantic_release.commit_parser_options]` block at all** (PSR defaults: minor=`feat`, patch=`fix`/`perf`). This test fails when the sample-plugin override has been copy-pasted in without justification.

```bash
python3 << 'PYEOF'
import tomllib, subprocess, re

# Gate: only PyPI repos use python-semantic-release for versioning/releases
NON_PYPI_REPOS = {
    'credentials-themes', 'mockprock', 'edx-repo-health',
    'openedx-webhooks-data-schema', 'enterprise-catalog', 'enterprise-access',
    'enterprise-subsidy', 'xapi-db-load', 'codejail-service',
    'openedx-user-groups', 'cc2olx', 'pr_watcher_notifier',
}
remote = subprocess.run(['git', 'remote', 'get-url', 'origin'],
                        capture_output=True, text=True).stdout.strip()
m = re.search(r'/([^/]+?)(?:\.git)?$', remote)
repo_name = m.group(1) if m else ''
if repo_name in NON_PYPI_REPOS:
    print(f"SKIP: {repo_name!r} is a non-PyPI repo — no python-semantic-release config"); raise SystemExit

# The sample-plugin override that #506 says NOT to copy into other libraries
SAMPLE_MINOR = ["feat", "docs"]
SAMPLE_PATCH = ["fix", "perf", "build"]

with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)
opts = data.get('tool', {}).get('semantic_release', {}).get('commit_parser_options')

if opts is None:
    print("OK: no commit_parser_options override — uses PSR defaults per #506")
    raise SystemExit

minor = opts.get('minor_tags')
patch = opts.get('patch_tags')
# Flag the sample-plugin copy-paste (the case #506 explicitly warns against)
if minor == SAMPLE_MINOR or patch == SAMPLE_PATCH:
    print("FAIL: [tool.semantic_release.commit_parser_options] copies the "
          "backend-plugin-sample override — #506 says other libraries must use "
          "the DEFAULT (minor: feat; patch: fix, perf). Remove the block unless "
          "this repo has a documented reason to release on other commit types.")
    print(f"      Found minor_tags={minor!r}, patch_tags={patch!r}")
else:
    # A different, presumably deliberate custom policy — allowed by #506's
    # "unless you know for sure you need to use something different".
    print(f"WARN: custom commit_parser_options present (minor={minor!r}, "
          f"patch={patch!r}) — allowed only if intentional per #506; else remove it")
PYEOF
```

**Pass:** no `commit_parser_options` block (PSR defaults, the #506 standard for other libraries) → SKIP for non-PyPI. **Fail:** the block copies the `backend-plugin-sample` override (`minor_tags`/`patch_tags` equal to the sample's values) without justification. **Warn:** a different custom override is present — permitted only when the repo genuinely needs it per #506.

### Test 250 — uv run tox in CI (not bare tox), `--locked` on uv sync only

```bash
for workflow in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ ! -f "$workflow" ] && continue

  # Check 1: bare tox (not via uv run)
  if grep -E '^\s+run:\s+tox\b' "$workflow" > /dev/null; then
    echo "FAIL: bare tox in $(basename $workflow) — use 'uv run tox'"
  fi

  # Check 2: uv sync --group ci missing --locked
  if grep -E 'uv sync\b' "$workflow" | grep -v '\-\-locked' | grep -v 'upgrade' > /dev/null; then
    echo "FAIL: $(basename $workflow) has 'uv sync' without --locked — CI will silently relock on a stale uv.lock instead of failing"
  fi
done

# Check 3: uv run must NOT carry --locked (CI workflows and Makefile)
# (capture output: grep exits 2 when any path is missing, even if it matched)
locked_run=$(grep -nsE 'uv run\b.*--locked' .github/workflows/*.yml .github/workflows/*.yaml Makefile)
if [ -n "$locked_run" ]; then
  echo "$locked_run"
  echo "FAIL: 'uv run --locked' found above — drop --locked from uv run; the uv sync --locked step already guards the lockfile"
fi
echo "OK: CI runs tox via 'uv run tox', uv sync uses --locked, uv run never does"
```

**Why `--locked` on `uv sync` matters:** without it, `uv sync` silently re-resolves and relocks in the ephemeral CI runner when `uv.lock` is out of sync with `pyproject.toml` — CI passes and the drift goes unnoticed. With `--locked`, CI fails fast on a stale lockfile, forcing the developer to commit a fresh `uv lock` before merge. `uv run` comes after that step, so `--locked` on it is redundant — keep it off. This does **not** affect package upgrades — those happen only via `make upgrade` (`uv lock --upgrade`).

### Test 260 — Python < 3.12 dropped

```bash
grep -E 'py3(8|9|10|11)' tox.ini && echo "FAIL: old Python in tox" || echo "OK: tox uses 3.12+"
grep -rE '"3\.(8|9|10|11)"' .github/workflows/ && echo "FAIL: old Python in CI" || echo "OK: CI uses 3.12+"
grep -E 'Programming Language :: Python :: 3\.(8|9|10|11)' pyproject.toml && echo "FAIL: old classifier" || echo "OK: classifiers use 3.12+"
```

### Test 270 — Static dependencies declared

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

### Test 280 — Quality dependency group retains original linters

```bash
python3 << 'PYEOF'
import tomllib
with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)
quality = data.get('dependency-groups', {}).get('quality', [])
if not quality:
    print("FAIL: quality group missing")
else:
    deps_str = '|'.join(str(d) for d in quality).lower()
    has_linters = any(l in deps_str for l in ['pylint', 'isort', 'pycodestyle', 'pydocstyle'])
    if has_linters:
        print("OK: quality group has original linters")
    else:
        print("WARN: no standard linters detected — verify manually that the repo's original linters are present")
PYEOF
```

### Test 290 — No GitHub Actions version downgrades vs main/master

```python
python3 << 'PYEOF'
import re, subprocess

def extract_action_versions(content):
    actions = {}
    for line in content.splitlines():
        m = re.search(r'uses:\s+([^@\s]+)@[0-9a-f]{40}\s+#\s*(v[\d.]+)', line)
        if m:
            action, ver = m.group(1), m.group(2)
            actions[action] = ver
    return actions

def parse_version(v):
    parts = v.lstrip('v').split('.')
    try:
        return tuple(int(p) for p in parts)
    except ValueError:
        return (0,)

base_branch = None
for branch in ('main', 'master'):
    r = subprocess.run(['git', 'ls-tree', branch, '.github/workflows/'],
                       capture_output=True, text=True)
    if r.returncode == 0:
        base_branch = branch
        break

if not base_branch:
    print("INFO: no main/master branch found — skipping comparison")
    raise SystemExit(0)

base_actions = {}
for line in subprocess.run(['git', 'ls-tree', base_branch, '.github/workflows/'],
                            capture_output=True, text=True).stdout.splitlines():
    parts = line.split('\t')
    if len(parts) == 2 and parts[1].endswith(('.yml', '.yaml')):
        r = subprocess.run(['git', 'show', f'{base_branch}:{parts[1]}'],
                           capture_output=True, text=True)
        if r.returncode == 0:
            for action, ver in extract_action_versions(r.stdout).items():
                if action not in base_actions or parse_version(ver) > parse_version(base_actions[action]):
                    base_actions[action] = ver

changed = subprocess.run(
    ['git', 'diff', f'{base_branch}...HEAD', '--name-only', '--', '.github/workflows/'],
    capture_output=True, text=True
).stdout.strip().split('\n')

pr_actions = {}
for wf in changed:
    wf = wf.strip()
    if not wf:
        continue
    try:
        content = open(wf).read()
    except FileNotFoundError:
        continue
    for action, ver in extract_action_versions(content).items():
        if action not in pr_actions or parse_version(ver) > parse_version(pr_actions[action]):
            pr_actions[action] = ver

downgrades = []
for action, pr_ver in pr_actions.items():
    if action in base_actions:
        base_ver = base_actions[action]
        if parse_version(pr_ver) < parse_version(base_ver):
            downgrades.append((action, base_ver, pr_ver))

if downgrades:
    for action, base_ver, pr_ver in downgrades:
        print(f"FAIL: {action} downgraded from {base_ver} (main) to {pr_ver} (PR)")
    raise SystemExit(1)
else:
    print("OK: no action version downgrades vs main/master")
PYEOF
```

**Pass:** Every action in PR-modified workflow files has a version ≥ what main/master used for that action.

**Fail:** Any action in a PR-modified file has a lower version than what main/master already pinned.

### Test 300 — CI toxenv uses `py` (not `py312`) and Codecov condition is compound

Use `py` for the bare Python test env; the `python-version` matrix drives the interpreter. The Codecov upload condition must be compound — `matrix.toxenv == 'py' && matrix.python-version == '3.12'` — so it pins exactly one job even when the matrix grows.

```bash
python3 << 'PYEOF'
import re, glob

failures = []
for wf_path in glob.glob('.github/workflows/*.yml') + glob.glob('.github/workflows/*.yaml'):
    try:
        content = open(wf_path).read()
    except FileNotFoundError:
        continue
    # Fail if bare py3XX (e.g. py312) appears as a toxenv matrix entry
    for m in re.finditer(r'\bpy3\d{1,2}\b(?![-\w])', content):
        surrounding = content[max(0, m.start()-300):m.end()+50]
        if 'toxenv' in surrounding or 'matrix' in surrounding:
            failures.append(f"{wf_path}: bare toxenv entry '{m.group(0)}' — use 'py' instead")
            break
    # Check Codecov condition is compound
    codecov_m = re.search(r"if:\s*matrix\.toxenv\s*==\s*['\"]([^'\"]+)['\"]", content)
    if codecov_m and not re.search(r"matrix\.python-version\s*==", content):
        failures.append(f"{wf_path}: Codecov condition missing matrix.python-version check — use compound condition")

if failures:
    for f in failures:
        print(f"FAIL: {f}")
else:
    print("OK: toxenv uses 'py' and Codecov condition is compound")
PYEOF
```

**Pass:** `toxenv` matrix uses `py`; Codecov `if:` includes both `matrix.toxenv` and `matrix.python-version`.

**Fail:** `py3XX` in toxenv matrix, or Codecov condition is missing the `matrix.python-version` check.

### Test 305 — CI `fail-fast` not set and `strategy:` in parity with master

`fail-fast` defaults to `true`, so the modernized CI must **not** set it — neither `fail-fast: true` nor `fail-fast: false`. Setting it explicitly is a needless deviation from master. The matrix `strategy:` block must stay in parity with master: if master omitted `fail-fast`, the PR must omit it too.

```bash
python3 << 'PYEOF'
import re, subprocess, glob

failures = []

# 1. No workflow in the PR may set fail-fast (it defaults to true).
for wf_path in glob.glob('.github/workflows/*.yml') + glob.glob('.github/workflows/*.yaml'):
    try:
        content = open(wf_path).read()
    except FileNotFoundError:
        continue
    m = re.search(r'^\s*fail-fast\s*:\s*(\S+)', content, re.MULTILINE)
    if m:
        failures.append(f"{wf_path}: sets 'fail-fast: {m.group(1)}' — remove it (defaults to true; deviates from master)")

# 2. Parity: master's fail-fast presence must equal the PR's.
base = next((b for b in ('main','master')
             if subprocess.run(['git','show-ref','--verify','--quiet',f'refs/heads/{b}'],
                               capture_output=True).returncode == 0), None)
if base:
    for wf in ('ci.yml','python-tests.yml'):
        r = subprocess.run(['git','show',f'{base}:.github/workflows/{wf}'],
                           capture_output=True, text=True)
        if r.returncode == 0:
            master_has = bool(re.search(r'^\s*fail-fast\s*:', r.stdout, re.MULTILINE))
            try:
                pr = open('.github/workflows/ci.yml').read()
            except FileNotFoundError:
                pr = ''
            pr_has = bool(re.search(r'^\s*fail-fast\s*:', pr, re.MULTILINE))
            if master_has != pr_has:
                failures.append(f"fail-fast parity broken vs {base}:{wf} — master {'set' if master_has else 'omitted'} it, PR {'sets' if pr_has else 'omits'} it")
            break

if failures:
    for f in failures:
        print(f"FAIL: {f}")
else:
    print("OK: no fail-fast set in any workflow; strategy in parity with master")
PYEOF
```

**Pass:** No workflow sets `fail-fast` (neither `true` nor `false`), and master's `fail-fast` presence matches the PR's (master omitted → PR omits).

**Fail:** Any workflow sets `fail-fast` explicitly, or the PR adds/removes `fail-fast` relative to master, breaking `strategy:` parity.

### Test 306 — Matrix list style parity (no block→flow reformat)

Feanil's rule (openedx-webhooks #440): a matrix list master wrote in block form
(`os:\n  - ubuntu-latest`) must **not** be collapsed to flow form (`os: [ubuntu-latest]`).
Block form keeps the diff clean — a new version is a single added line, not an edit to an
existing line — and is easier to extend. Applies to every matrix list: `os`, `python-version`,
`toxenv`, `django-version`, etc. Only flags keys present in both master and the PR; genuinely new
keys are exempt.

```bash
python3 << 'PYEOF'
import re, subprocess

base = next((b for b in ('main','master')
             if subprocess.run(['git','show-ref','--verify','--quiet',f'refs/heads/{b}'],
                               capture_output=True).returncode == 0), None)

def list_styles(text):
    """Map each matrix key to 'flow' (key: [..]) or 'block' (key:\\n  - ..)."""
    styles = {}
    lines = text.splitlines()
    for i, line in enumerate(lines):
        m = re.match(r'^(\s*)([\w-]+)\s*:\s*(.*)$', line)
        if not m:
            continue
        indent, key, rest = m.group(1), m.group(2), m.group(3).strip()
        if rest.startswith('['):
            styles[key] = 'flow'
        elif rest == '':
            # look ahead: next non-blank more-indented line a '- ' item?
            for nxt in lines[i+1:]:
                if not nxt.strip():
                    continue
                if len(nxt) - len(nxt.lstrip()) > len(indent) and nxt.lstrip().startswith('- '):
                    styles[key] = 'block'
                break
    return styles

failures = []
if base:
    r = subprocess.run(['git','show',f'{base}:.github/workflows/ci.yml'],
                       capture_output=True, text=True)
    if r.returncode != 0:
        r = subprocess.run(['git','show',f'{base}:.github/workflows/python-tests.yml'],
                           capture_output=True, text=True)
    if r.returncode == 0:
        master = list_styles(r.stdout)
        try:
            pr = list_styles(open('.github/workflows/ci.yml').read())
        except FileNotFoundError:
            pr = {}
        for key, m_style in master.items():
            if m_style == 'block' and pr.get(key) == 'flow':
                failures.append(f"matrix '{key}': master used block form, PR collapsed to flow "
                                f"[...] — restore block form (see Feanil openedx-webhooks#440)")

if failures:
    for f in failures:
        print(f"FAIL: {f}")
else:
    print("OK: no matrix list reformatted from block to flow vs master")
PYEOF
```

**Pass:** No matrix list that master wrote in block form is collapsed to flow form in the PR.

**Fail:** Any block-form matrix list (`key:\n  - item`) on master appears as flow form (`key: [item]`) in the PR.

### Test 310 — No empty or header-only `codecov.yml` introduced

Feanil's rule (mockprock #66): "Why add this empty file?" An empty `codecov.yml` adds noise with no value. If it does not exist on master, it must not be introduced by the PR.

```bash
# Determine base branch
BASE=$(for b in main master; do git show-ref --verify --quiet refs/heads/$b && echo $b && break; done)
[ -z "$BASE" ] && BASE="main"

MASTER_HAS=$(git show "$BASE:codecov.yml" &>/dev/null 2>&1 && echo "yes" || echo "no")

if [ "$MASTER_HAS" = "no" ]; then
    if [ -f "codecov.yml" ]; then
        # Count non-comment, non-empty lines
        LINES=$(grep -v '^#' codecov.yml | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')
        if [ "$LINES" -eq 0 ]; then
            echo "FAIL: empty codecov.yml introduced — remove it (master had none)"
        else
            echo "FAIL: codecov.yml introduced when master didn't have one — only add if there is meaningful configuration"
        fi
    else
        echo "OK: codecov.yml absent on $BASE and absent in PR"
    fi
else
    echo "OK: codecov.yml existed on $BASE — PR may retain or update it (but must not add invented thresholds, see Test 190)"
fi
```

**Pass:** `codecov.yml` absent on master → absent in PR. If present on master → PR may keep or update it (Test 190 guards against invented thresholds).

**Fail:** `codecov.yml` did not exist on master but the PR creates one — even an empty file.

### Test 320 — Tox env names match master (no renames)

Feanil's rule (mockprock #66, forum #281): do not rename tox environments. `quality` must stay `quality`, not become `lint`. `test-mypy` must stay `test-mypy`, not become `mypy`. Branch-protection checks are often tied to exact tox env names; silently renaming them breaks CI gates.

```bash
python3 << 'PYEOF'
import subprocess, re

def get_named_tox_envs(content):
    envs = set()
    for line in content.splitlines():
        m = re.match(r'^\[testenv:(.+)\]', line.strip())
        if m:
            envs.add(m.group(1))
    return envs

base = None
for b in ('main', 'master'):
    r = subprocess.run(['git', 'show', f'{b}:tox.ini'], capture_output=True, text=True)
    if r.returncode == 0:
        base = b
        master_envs = get_named_tox_envs(r.stdout)
        break

if base is None:
    print("INFO: no tox.ini on main/master — skipping")
    raise SystemExit(0)

with open('tox.ini') as f:
    pr_envs = get_named_tox_envs(f.read())

removed = master_envs - pr_envs
added = pr_envs - master_envs

if removed:
    for env in sorted(removed):
        print(f"FAIL: tox env '[testenv:{env}]' present on {base} but missing in PR — do not rename or drop named tox envs")
    # Hint at likely renames
    for r in sorted(removed):
        for a in sorted(added):
            if len(r) > 2 and (r in a or a in r or r.replace('-','') == a.replace('-','')):
                print(f"HINT: looks like '{r}' was renamed to '{a}' — revert the rename")
    raise SystemExit(1)
elif added:
    for env in sorted(added):
        print(f"INFO: new tox env '[testenv:{env}]' added in PR — verify this is intentional, not a rename")
    print("OK: all master tox env names preserved")
else:
    print("OK: tox env names unchanged vs master")
PYEOF
```

**Pass:** Every `[testenv:name]` in master's `tox.ini` exists unchanged in the PR.

**Fail:** Any named tox env present on master is absent or renamed in the PR.

### Test 330 — tox commands invoke make targets (not tools directly)

Feanil's rule (forum #281): "We should be calling make targets from inside tox so that we can run those targets outside of tox easily as well in a reproducible way. We shouldn't force tox for when we're trying to iterate quickly in a local dev environment."

The tooling flow is: **Makefile defines commands → tox.ini invokes Makefile targets → CI invokes tox envs**. If tox runs pytest or pylint directly, developers can't run the same command without tox.

```bash
python3 << 'PYEOF'
import re

with open('tox.ini') as f:
    content = f.read()

in_commands = False
current_env = '[testenv]'
failures = []

for line in content.splitlines():
    env_match = re.match(r'^\[testenv(:[^\]]+)?\]', line)
    if env_match:
        current_env = line.strip()
        in_commands = False
        continue

    if re.match(r'^commands\s*=', line):
        in_commands = True
    elif in_commands and line and not line[0].isspace():
        in_commands = False

    if in_commands:
        cmd = line.strip()
        if not cmd or cmd.startswith('#') or cmd.startswith('commands'):
            continue
        direct_tools = re.search(r'\b(pytest|py\.test|pylint|isort|pycodestyle|pydocstyle|sphinx-build|mypy)\b', cmd)
        calls_make = re.search(r'\bmake\b', cmd)
        calls_uv_run_tox = re.search(r'uv\s+run\s+tox\b', cmd)

        if direct_tools and not calls_make:
            tool = direct_tools.group(1)
            failures.append(f"{current_env}: runs '{tool}' directly — should call 'make <target>' instead so it can be run outside tox")
        if calls_uv_run_tox:
            failures.append(f"{current_env}: calls 'uv run tox' inside tox — this is tox-in-tox; use 'make <target>'")

if failures:
    for f in failures:
        print(f"FAIL: {f}")
else:
    print("OK: all tox commands invoke make targets (tooling flow preserved)")
PYEOF
```

**Pass:** Every `commands =` line in `tox.ini` calls `make <target>`. No tox command runs pytest, pylint, or other tools directly. No tox-inside-tox.

**Fail:** Any tox env's `commands =` runs a tool (pytest, pylint, isort, sphinx-build, mypy) without going through `make`.

### Test 340 — Dependency groups use `include-group` for `-r` references (not flattened)

Feanil's rule (mockprock #66): "This should be an `include-group` of the base dependencies." When a `.in` file has `-r other.in`, the corresponding dependency group must use `{include-group = "other"}` — not copy the referenced packages inline. Flattening loses the structural relationship and will drift over time.

Two distinct failure modes are separated so the test stays generic (no per-package special-casing):
- **Flattened** — the referenced group's packages were copied inline into the consuming group. This is the exact anti-pattern the rule targets → **FAIL**.
- **Omitted** — the reference was dropped and the packages are *not* inlined. Whether that matters is repo-specific, so it is decided by evidence: if the consuming group's own code actually imports a referenced package it is a **FAIL** (lost a real dependency); otherwise it is a **WARN** (confirm the drop was intentional). `base` is always exempt — those are the project's own deps, installed via the editable package, not a dependency group.

```bash
python3 << 'PYEOF'
import subprocess, re, tomllib, pathlib

def normalize(name):
    name = re.sub(r'\[.*?\]', '', name).strip()
    return name.lower().replace('_', '-').replace('.', '-')

def parse_r_refs(content):
    return [m.group(1) for line in content.splitlines()
            if (m := re.match(r'^-r\s+(\S+?)\.in\s*(?:#.*)?$', line.strip()))]

def parse_pkgs(content):
    pkgs = set()
    for line in content.splitlines():
        line = line.strip()
        if not line or line.startswith(('#', '-r', '-c', '-e')):
            continue
        name = re.split(r'[><=!~\s;@\[]', line)[0]
        if name:
            pkgs.add(normalize(name))
    return pkgs

def get_include_groups(group_deps):
    return {d['include-group'] for d in group_deps
            if isinstance(d, dict) and 'include-group' in d}

def inline_pkgs(group_deps):
    return {normalize(d.split('@')[0]) for d in group_deps if isinstance(d, str)}

# For the omission case: does the consuming group's own code import any referenced package?
# Only well-defined for the test group (consumer = the test suite). Import name ≈ normalized
# package name with '-'→'_'; grep is a heuristic upgrade of WARN→FAIL, never the sole gate.
def consumer_imports_any(group_name, ref_pkgs):
    if group_name != 'test':
        return False
    roots = [p for p in ('tests', 'test') if pathlib.Path(p).is_dir()]
    if not roots:
        return False
    tokens = {p.replace('-', '_') for p in ref_pkgs}
    for root in roots:
        for py in pathlib.Path(root).rglob('*.py'):
            try:
                text = py.read_text(encoding='utf-8', errors='ignore')
            except OSError:
                continue
            for tok in tokens:
                if re.search(rf'^\s*(import|from)\s+{re.escape(tok)}(\.|\s|$)', text, re.MULTILINE):
                    return True
    return False

with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)

dep_groups = data.get('dependency-groups', {})
failures, warnings = [], []

for group_name in ['test', 'test-base', 'dev', 'quality', 'doc', 'ci']:
    r = subprocess.run(['git', 'show', f'master:requirements/{group_name}.in'],
                       capture_output=True, text=True)
    if r.returncode != 0:
        continue
    r_refs = parse_r_refs(r.stdout)
    if not r_refs:
        continue
    pr_group = dep_groups.get(group_name, [])
    pr_includes = get_include_groups(pr_group)
    pr_inline = inline_pkgs(pr_group)
    for ref in r_refs:
        if ref == 'base':
            continue  # project's own deps — installed via the editable package, not a group
        if ref in pr_includes:
            continue  # correctly represented as an include-group
        ref_pkgs = parse_pkgs(
            subprocess.run(['git', 'show', f'master:requirements/{ref}.in'],
                           capture_output=True, text=True).stdout)
        if ref_pkgs & pr_inline:
            failures.append(
                f"[dependency-groups.{group_name}] flattened '-r {ref}.in' — packages "
                f"{sorted(ref_pkgs & pr_inline)} inlined instead of {{include-group = \"{ref}\"}}")
        elif consumer_imports_any(group_name, ref_pkgs):
            failures.append(
                f"[dependency-groups.{group_name}] dropped '-r {ref}.in' but the test suite "
                f"imports a package from '{ref}' — add {{include-group = \"{ref}\"}}")
        else:
            warnings.append(
                f"[dependency-groups.{group_name}] dropped '-r {ref}.in' (packages not inlined, "
                f"not imported by the consumer) — confirm intentional or add {{include-group = \"{ref}\"}}")

for f in failures:
    print(f"FAIL: {f}")
for w in warnings:
    print(f"WARN: {w}")
if not failures and not warnings:
    print("OK: all -r references represented as include-group entries")
if failures:
    raise SystemExit(1)
PYEOF
```

**Pass:** No `FAIL:` lines. Every `-r X.in` is either represented as `{include-group = "X"}`, exempt (`base`), or dropped without being inlined and without the consumer importing it. `WARN:` lines (a reference dropped entirely, not inlined, not imported) do not fail the test — surface them for the author to confirm.

**Fail:** A `-r X.in` reference was flattened (packages inlined instead of an include-group), or dropped while the consuming group's code still imports one of its packages.

### Test 350 — Makefile targets run tools directly (not via tox)

Feanil's rule (mockprock #66, updated 2026-09-28): Makefile targets must invoke tools directly — not via tox. Delegating from Makefile to tox makes local iteration painful — developers must spin up a full tox environment just to run a quick test. The Makefile is the direct interface; tox is the CI wrapper. (For the complementary rule that Makefile targets must also not use `uv run` as a prefix, see Test 355.)

```bash
python3 << 'PYEOF'
import re

with open('Makefile') as f:
    content = f.read()

# Targets where calling tox is a regression
DIRECT_TARGETS = {'test', 'lint', 'quality', 'test-with-coverage', 'docs', 'test-mypy', 'mypy'}

in_target = False
current_target = ''
failures = []

for line in content.splitlines():
    target_match = re.match(r'^([a-zA-Z_-]+):', line)
    if target_match:
        current_target = target_match.group(1)
        in_target = True
        continue

    if in_target and line.startswith('\t'):
        cmd = line.strip()
        # Flag if this make target calls tox instead of tools directly
        if current_target in DIRECT_TARGETS:
            if re.search(r'\buv\s+run\s+tox\b|\btox\s+-e\b|\btox\b', cmd):
                failures.append(
                    f"make {current_target}: delegates to tox ({cmd!r}) — "
                    f"run the tool directly instead (e.g. 'uv run pytest', 'uv run pylint')"
                )
    elif in_target and not line.startswith('\t') and line.strip():
        in_target = False

if failures:
    for f in failures:
        print(f"FAIL: {f}")
else:
    print("OK: Makefile targets run tools directly (not via tox)")
PYEOF
```

**Pass:** Core Makefile targets (`test`, `lint`/`quality`, `test-with-coverage`, `docs`) invoke tools directly (bare tool names — no `uv run` prefix), not by calling tox.

**Fail:** A core Makefile target delegates to tox (`uv run tox -e ...`) — this forces tox for local dev and defeats the purpose of having Makefile targets.

### Test 355 — No `uv run` in Makefile targets (except `upgrade`); CI calls `make` via `uv run`

Feanil's rule (2026-09-28): Makefiles must not force or assume a uv environment. The `uv run` prefix belongs in the caller, not the Makefile. Two complementary checks:

**Part A — Makefile:** Strip `uv run` from every target body except `upgrade`. Locally the developer activates the venv; the Makefile just runs the bare tool.

**Part B — CI workflows:** Any workflow step that calls `make <target>` directly (i.e. not routed through `uv run tox`) must prefix with `uv run make <target>` so the uv-managed environment is active. The standard modernized CI calls `uv run tox -e <env>` (which already activates the env), so Part B only applies to repos whose CI calls `make` directly.

```bash
python3 << 'PYEOF'
import re, glob

failures = []

# ── Part A: no uv run in Makefile targets (except upgrade) ──────────────────
try:
    makefile = open('Makefile').read()
    current_target = None
    for line in makefile.splitlines():
        m = re.match(r'^([a-zA-Z_][a-zA-Z0-9_.-]*)\s*:', line)
        if m and not line.startswith('\t'):
            current_target = m.group(1)
            continue
        if line.startswith('\t') and current_target != 'upgrade':
            if re.search(r'\buv\s+run\b', line):
                failures.append(f"  [Makefile] make {current_target}: {line.strip()!r}")
    if not any('[Makefile]' in f for f in failures):
        print("Part A OK: no 'uv run' in Makefile targets (upgrade exempt)")
except FileNotFoundError:
    print("Part A SKIP: no Makefile found")

# ── Part B: CI steps that call make directly must use uv run make ────────────
for wf_path in glob.glob('.github/workflows/*.yml') + glob.glob('.github/workflows/*.yaml'):
    try:
        content = open(wf_path).read()
    except FileNotFoundError:
        continue
    lines = content.splitlines()
    for i, line in enumerate(lines):
        # A `run:` step whose value starts with bare `make` (not `uv run make`, not `uv run tox`)
        m = re.match(r'^\s*run:\s*(make\b.*)', line)
        if m:
            cmd = m.group(1).strip()
            failures.append(
                f"  [CI] {wf_path}:{i+1}: bare 'make' call — use 'uv run make ...' instead: {cmd!r}"
            )
        # Multi-line run block: look for a line that is just `make <target>` inside a | block
        if re.match(r'^\s*run:\s*\|', line):
            for j in range(i+1, min(i+20, len(lines))):
                sub = lines[j]
                if re.match(r'^\s{8,}make\b', sub) and not re.search(r'uv\s+run\s+make\b', sub):
                    failures.append(
                        f"  [CI] {wf_path}:{j+1}: bare 'make' in multi-line run — use 'uv run make ...': {sub.strip()!r}"
                    )
                elif sub.strip() and not sub.startswith(' ' * 8):
                    break

if failures:
    makefile_fails = [f for f in failures if '[Makefile]' in f]
    ci_fails = [f for f in failures if '[CI]' in f]
    if makefile_fails:
        print("Part A FAIL: 'uv run' found in Makefile targets outside 'upgrade'.")
        print("  Strip 'uv run' and use bare tool names. The 'upgrade' target is the only exception.")
        for f in makefile_fails: print(f)
    if ci_fails:
        print("Part B FAIL: CI workflow step calls bare 'make' without 'uv run'.")
        print("  Change 'run: make <target>' to 'run: uv run make <target>' so the uv venv is active.")
        for f in ci_fails: print(f)
    raise SystemExit(1)
else:
    print("Part B OK: all CI 'make' calls use 'uv run make'  (or CI routes through 'uv run tox')")
PYEOF
```

**Pass:**
- Part A: No `uv run` in any Makefile target body except `upgrade`. (`uv sync` and `uv lock` are fine — they are package-management commands, not tool runners.)
- Part B: No CI workflow step calls bare `make` directly — either it goes through `uv run tox` (standard pattern) or it uses `uv run make <target>`.

**Fail:**
- Part A: A Makefile target (other than `upgrade`) contains `uv run` — strip the prefix.
- Part B: A CI `run:` step calls `make <target>` without `uv run` — prepend `uv run` to the step's `run:` value.

---

### Test 360 — isort import style unchanged from master

Feanil's rule (forum #281): "I think we prefer multi-line imports with one import per line over this version. Let's update the config so that we don't do this kind of change if we can." The migration must not cause isort to reformat existing import blocks — any `multi_line_output` setting or other style-affecting isort config must match what master had.

**Skip this test** if master had no isort configuration in `setup.cfg`, `tox.ini`, or `.isort.cfg`. Record as `⏭️ Skipped (no isort config on master — style already matched isort defaults)`.

```bash
python3 << 'PYEOF'
import subprocess, re, tomllib

def parse_isort_from_setup_cfg(content):
    settings = {}
    in_section = False
    for line in content.splitlines():
        if re.match(r'^\[isort\]', line):
            in_section = True; continue
        if in_section and re.match(r'^\[', line):
            in_section = False; continue
        if in_section:
            m = re.match(r'^(\w+)\s*=\s*(.+)', line.strip())
            if m:
                settings[m.group(1)] = m.group(2).strip()
    return settings

master_isort = {}
for base in ('main', 'master'):
    for cfg_path in ('setup.cfg', 'tox.ini', '.isort.cfg'):
        r = subprocess.run(['git', 'show', f'{base}:{cfg_path}'], capture_output=True, text=True)
        if r.returncode == 0:
            master_isort.update(parse_isort_from_setup_cfg(r.stdout))

if not master_isort:
    print("SKIP: no isort configuration found on master — style matches isort defaults")
    raise SystemExit(0)

# Read PR isort config from pyproject.toml
try:
    with open('pyproject.toml', 'rb') as f:
        data = tomllib.load(f)
    pr_isort = {k: str(v) for k, v in data.get('tool', {}).get('isort', {}).items()}
except Exception as e:
    print(f"FAIL: could not read pyproject.toml — {e}")
    raise SystemExit(1)

style_keys = ['multi_line_output', 'force_sort_within_sections', 'line_length',
              'known_third_party', 'skip', 'skip_glob', 'sections']
failures = []
for key in style_keys:
    master_val = master_isort.get(key)
    pr_val = pr_isort.get(key)
    if master_val is not None and pr_val != master_val:
        failures.append(f"isort.{key}: was {master_val!r} on master, now {pr_val!r} in PR — restore original value to avoid import reformatting")
    if master_val is None and pr_val is not None:
        failures.append(f"isort.{key}: newly introduced in PR ({pr_val!r}) — verify this does not cause import reformatting vs master's implicit default")

if failures:
    for f in failures:
        print(f"FAIL: {f}")
else:
    print(f"OK: isort config unchanged (master settings: {master_isort})")
PYEOF
```

**Pass:** All isort style settings (`multi_line_output`, `force_sort_within_sections`, etc.) match master's values exactly. No new isort settings introduced that alter import formatting.

**Fail:** Any isort style setting changed vs master — this will cause the linter to reformat existing import blocks, producing noisy diffs and unexpected CI failures.

### Test 370 — No source-tracing comments in `[dependency-groups]`

Comments like `# From requirements/ci.in` or `# Each group mirrors its requirements/*.in file exactly.` trace the migration origin but add no value — the group names and `include-group` entries already document the structure. They should not appear in the committed file.

```bash
python3 << 'PYEOF'
import re

try:
    content = open('pyproject.toml').read()
except FileNotFoundError:
    print("SKIP: no pyproject.toml found")
    raise SystemExit(0)

dep_groups_match = re.search(r'^\[dependency-groups\]', content, re.MULTILINE)
if not dep_groups_match:
    print("SKIP: no [dependency-groups] section found")
    raise SystemExit(0)

next_section = re.search(r'^\[', content[dep_groups_match.end():], re.MULTILINE)
dep_groups_content = content[dep_groups_match.start(): dep_groups_match.end() + (next_section.start() if next_section else len(content))]

BAD_PATTERNS = [
    (r'#.*\bFrom requirements/', 'source-tracing comment referencing old requirements file'),
    (r'#.*requirements/.*\.in', 'source-tracing comment referencing old .in file'),
    (r'#.*Each group mirrors', 'boilerplate migration comment'),
    (r'#.*-r \S+\.in.*include-group', 'migration mechanics comment explaining .in syntax'),
    (r'#.*Direct packages.*listed verbatim', 'obvious statement comment'),
]

failures = []
for line in dep_groups_content.splitlines():
    stripped = line.strip()
    if not stripped.startswith('#'):
        continue
    for pattern, description in BAD_PATTERNS:
        if re.search(pattern, stripped, re.IGNORECASE):
            failures.append(f"  {description}: {stripped!r}")
            break

if failures:
    print("FAIL: source-tracing/unimportant comments found in [dependency-groups]:")
    for f in failures: print(f)
    print("  Remove these — group names and include-group entries already document the structure.")
    raise SystemExit(1)
else:
    print("OK: no source-tracing comments in [dependency-groups]")
PYEOF
```

**Pass:** No comments inside `[dependency-groups]` reference old `.in` files, explain migration mechanics, or state obvious facts about the file format.

**Fail:** Any such comment is found — remove it. Comments inside `[dependency-groups]` are only warranted when explaining a non-obvious structural decision (e.g. why a legacy Django group exists).

### Test 380 — Required tox environments present (py, quality, docs)

All modernized repos must have three core tox environments: a default test env (`[testenv]`, run as `py` in CI), a quality/lint env, and a docs env. Their absence means CI cannot run the full test matrix and local developers lose the standard entry points.

If `docs` is absent but the repo has no docs infrastructure whatsoever (no `docs/` directory, no `make docs` target, no Sphinx configuration), the omission is acceptable **only if** it is explicitly documented in the PR's `## Important Notes` section.

```bash
python3 << 'PYEOF'
import re

try:
    content = open('tox.ini').read()
except FileNotFoundError:
    print("FAIL: tox.ini not found")
    raise SystemExit(1)

# [testenv] (no suffix) is the default / py env
has_py = bool(re.search(r'^\[testenv\]', content, re.MULTILINE))
# quality or lint are both acceptable names
has_quality = bool(re.search(r'^\[testenv:(quality|lint)\]', content, re.MULTILINE))
# docs env
has_docs = bool(re.search(r'^\[testenv:docs\]', content, re.MULTILINE))

failures = []
if not has_py:
    failures.append("Missing [testenv] (py env) — all repos must have a default test environment")
if not has_quality:
    failures.append("Missing [testenv:quality] (or [testenv:lint]) — all repos must have a quality/lint environment")
if not has_docs:
    failures.append(
        "Missing [testenv:docs] — add it, or if the repo has absolutely no docs infrastructure "
        "(no docs/ dir, no make docs target, no Sphinx config), verify the omission is documented "
        "in ## Important Notes of the PR"
    )

if failures:
    for f in failures:
        print(f"FAIL: {f}")
    raise SystemExit(1)
else:
    print(f"OK: required tox environments present (py={has_py}, quality/lint={has_quality}, docs={has_docs})")
PYEOF
```

**Pass:** `tox.ini` contains `[testenv]` (default/py env), `[testenv:quality]` or `[testenv:lint]`, and `[testenv:docs]`.

**Fail:** Any of the three required environments is absent — add the missing env, or (for `docs` only) confirm the PR description documents why it cannot be added.

### Test 390 — No manual venv `GITHUB_PATH` echo in CI workflows

When using `astral-sh/setup-uv`, tools must be invoked via `uv run <tool>` — uv handles venv activation automatically. An `echo "$PWD/.venv/bin" >> "$GITHUB_PATH"` line is a sign that tools are still called as bare commands, which defeats the purpose of the uv migration.

```bash
python3 << 'PYEOF'
import re, glob

failures = []
for wf_path in glob.glob('.github/workflows/*.yml') + glob.glob('.github/workflows/*.yaml'):
    try:
        content = open(wf_path).read()
    except FileNotFoundError:
        continue
    for i, line in enumerate(content.splitlines(), 1):
        if re.search(r'echo\s+.*\.venv[/\\]bin.*GITHUB_PATH', line):
            failures.append(f"{wf_path}:{i}: {line.strip()!r}")

if failures:
    for f in failures:
        print(f"FAIL: manual venv PATH echo found — {f}")
    print("  Remove these echoes and use 'uv run <tool>' instead.")
else:
    print("OK: no manual .venv/bin GITHUB_PATH echoes in CI workflows")
PYEOF
```

**Pass:** No `echo "$PWD/.venv/bin" >> "$GITHUB_PATH"` (or similar `.venv/bin` path injection) in any workflow file.

**Fail:** Such an echo exists — remove it and update the tool invocation to use `uv run <tool>`.

### Test 395 — No unnecessary `fetch-depth: 0` in CI checkout

The org reference CI workflows ([openedx/sample-plugin](https://github.com/openedx/sample-plugin/blob/main/.github/workflows/backend-ci.yml) and [openedx/xblocks-extra](https://github.com/openedx/xblocks-extra/blob/main/.github/workflows/ci.yml)) use the **default shallow checkout** — they do **not** set `fetch-depth: 0` — even though both use the same `setuptools-scm` + `fallback_version` versioning setup. A full-history checkout (`fetch-depth: 0`) fetches every commit and tag, which only slows the CI workflow, and it is not required for correctness:

- `setuptools-scm` simply falls back to `fallback_version` for the throwaway build artifact produced by the `quality`/`docs` jobs — nothing in the test suite asserts a specific `__version__`, and CI never publishes that artifact.
- The real release (`release.yml`) sets `SETUPTOOLS_SCM_PRETEND_VERSION=$NEW_VERSION`, so publishing does not depend on checkout depth at all.

So `fetch-depth: 0` is an unnecessary deviation from the reference standard and should be removed. This applies to **`release.yml` too** — the sample-plugin `release.yml` omits it, and `python-semantic-release` converts a shallow clone to a full one itself when it needs history/tags. The test covers `ci.yml` / `python-tests.yml` and `release.yml`.

```bash
python3 << 'PYEOF'
import re, glob, os

# CI test workflow and release.yml — sample-plugin omits fetch-depth in both; PSR unshallows itself.
CI_WORKFLOWS = [p for p in glob.glob('.github/workflows/*.yml') + glob.glob('.github/workflows/*.yaml')
                if re.search(r'(ci|python-tests|release)\.ya?ml$', os.path.basename(p))]

failures = []
for wf in CI_WORKFLOWS:
    try:
        content = open(wf).read()
    except FileNotFoundError:
        continue
    for i, line in enumerate(content.splitlines(), 1):
        if re.search(r'^\s*fetch-depth\s*:\s*0\s*(#.*)?$', line):
            failures.append(f"{wf}:{i}: sets 'fetch-depth: 0' — unnecessary full-history checkout")

if not CI_WORKFLOWS:
    print("SKIP: no ci.yml / python-tests.yml found")
elif failures:
    for f in failures:
        print(f"FAIL: {f}")
    print("  Remove 'fetch-depth: 0' from the CI checkout step. The reference CI workflows")
    print("  (openedx/sample-plugin, openedx/xblocks-extra) use the default shallow checkout with the")
    print("  same setuptools-scm + fallback_version setup. Full history only slows CI: setuptools-scm")
    print("  falls back to fallback_version for the throwaway build artifact, and the real release uses")
    print("  SETUPTOOLS_SCM_PRETEND_VERSION. release.yml is exempt (PSR needs history).")
else:
    print("OK: CI checkout uses default shallow depth (no unnecessary fetch-depth: 0)")
PYEOF
```

**Pass:** The CI test workflow's `actions/checkout` step does not set `fetch-depth: 0` (or no CI workflow exists → SKIP).

**Fail:** `ci.yml`, `python-tests.yml` or `release.yml` sets `fetch-depth: 0` on its checkout — remove it to match the reference standard.

### Test 400 — `upgrade-python-requirements.yml` not deleted

Feanil's explicit requirement (flagged in i18n-tools PR #288): never delete `.github/workflows/upgrade-python-requirements.yml`. The shared `openedx/.github` workflow it calls installs uv and runs plain `make upgrade` — the uv path — so it does NOT depend on pip-compile. Removing it kills weekly automated dependency upgrades. On repos where this workflow was previously broken (pip-tools vs current pip), migrating to uv *fixes* it.

SKIP this test if master did not have `upgrade-python-requirements.yml` (i.e. the repo never had one — don't invent it).

```bash
python3 << 'PYEOF'
import os, subprocess

# Check if main/master had the file
main_branch = "main"
result = subprocess.run(
    ["git", "show", f"origin/{main_branch}:.github/workflows/upgrade-python-requirements.yml"],
    capture_output=True
)
if result.returncode != 0:
    # Try master
    result = subprocess.run(
        ["git", "show", "origin/master:.github/workflows/upgrade-python-requirements.yml"],
        capture_output=True
    )
    if result.returncode != 0:
        print("SKIP: upgrade-python-requirements.yml was not present on main/master — nothing to preserve")
        exit(0)

# File existed on main — check it's still present in the PR branch
if os.path.exists(".github/workflows/upgrade-python-requirements.yml"):
    print("OK: upgrade-python-requirements.yml is present in PR branch")
else:
    print("FAIL: upgrade-python-requirements.yml was deleted from the PR branch")
    print("  Restore it: git show origin/main:.github/workflows/upgrade-python-requirements.yml > .github/workflows/upgrade-python-requirements.yml")
    print("  Reason: this workflow uses openedx/.github's shared workflow which installs uv")
    print("  and runs plain 'make upgrade' — it does NOT depend on pip-compile. Removing it")
    print("  kills weekly automated dependency upgrades. (Feanil, i18n-tools PR #288)")
PYEOF
```

**Pass:** File is present in the PR branch (or was never on main → SKIP).

**Fail:** File was on main but is missing from the PR branch — restore it from main.

---

### Test 405 — Coverage `source` config correct for layout

For repos with a `src/` layout, `[tool.coverage.run]` must use `source = ["src"]` (pointing at
the directory). Using `source_pkgs = ["pkg"]` resolves by import name — any package that pytest
never imports is silently dropped from the report (e.g. a package containing only standalone
scripts). `source = ["src"]` tracks every `.py` file under `src/` by path regardless of imports.

The only wrong form is `source = ["<pkg_name>"]` where `<pkg_name>` is a package directory that
lives under `src/` — that directory doesn't exist at the repo root so coverage measures nothing.

SKIP this test if the repo does not use a `src/` layout (no `src/` directory).

```bash
python3 << 'PYEOF'
import os, tomllib

if not os.path.isdir("src"):
    print("SKIP: repo does not use src/ layout — source= is correct for flat layout")
    raise SystemExit(0)

try:
    with open("pyproject.toml", "rb") as f:
        data = tomllib.load(f)
except Exception as e:
    print(f"FAIL: could not read pyproject.toml — {e}")
    raise SystemExit(1)

cov_run = data.get("tool", {}).get("coverage", {}).get("run", {})
src_subdirs = {d for d in os.listdir("src") if os.path.isdir(os.path.join("src", d))}

source = cov_run.get("source", [])
source_pkgs = cov_run.get("source_pkgs", [])

if not source and not source_pkgs:
    print("SKIP: no [tool.coverage.run].source or source_pkgs found — nothing to verify")
    raise SystemExit(0)

# Preferred: source = ["src"]
if source == ["src"]:
    print("OK: [tool.coverage.run] uses source = ['src'] (correct — tracks all files under src/ by path)")
    raise SystemExit(0)

# Also acceptable: source_pkgs pointing at real packages
if source_pkgs:
    bad = [p for p in source_pkgs if p in src_subdirs]
    if bad:
        print(f"WARN: source_pkgs = {source_pkgs!r} — packages {bad!r} exist under src/ but may be")
        print(f"  silently dropped if pytest never imports them. Prefer source = ['src'] instead.")
    else:
        print(f"OK: [tool.coverage.run] uses source_pkgs = {source_pkgs!r}")
    raise SystemExit(0)

# source = ["<pkg_name>"] where pkg_name is a subdir of src/ — the broken case
bad_source = [s for s in source if s in src_subdirs]
if bad_source:
    print(f"FAIL: [tool.coverage.run] uses source = {source!r} but {bad_source!r} live under src/")
    print(f"  Fix: change to source = ['src']")
    print(f"  Reason: source= resolves by path from repo root; the directory doesn't exist there.")
else:
    print(f"OK: [tool.coverage.run] uses source = {source!r}")
PYEOF
```

```python
python3 << 'PYEOF'
import re, glob, tomllib

# Check that addopts doesn't have --cov <dir> overriding source
addopts = None

# Check pyproject.toml [tool.pytest.ini_options]
try:
    with open("pyproject.toml", "rb") as f:
        data = tomllib.load(f)
    addopts = data.get("tool", {}).get("pytest", {}).get("ini_options", {}).get("addopts", "")
except Exception:
    pass

# Fallback: check pytest.ini
if not addopts:
    for path in ["pytest.ini", "setup.cfg"]:
        try:
            content = open(path).read()
            m = re.search(r'addopts\s*=\s*(.+)', content)
            if m:
                addopts = m.group(1).strip()
                break
        except OSError:
            continue

if addopts:
    m = re.search(r'--cov\s+(\S+)', str(addopts))
    if m:
        cov_dir = m.group(1)
        if not cov_dir.startswith('-'):
            print(f"FAIL: addopts contains '--cov {cov_dir}' which overrides [tool.coverage.run] source.")
            print(f"  Fix: change to bare '--cov' so pyproject.toml's source = [\"src\"] takes effect.")
            print(f"  Reason: '--cov <dir>' measures that directory instead of the package — coverage")
            print(f"  reports the test files at 99%+ while src/i18n/* goes unmeasured.")
        else:
            print("OK: addopts uses bare --cov (no directory override)")
    else:
        print("OK: addopts has no --cov argument (or no addopts)")
else:
    print("OK: no addopts found")
PYEOF
```

**Pass:** `source = ["src"]` is used (preferred), or `source_pkgs` pointing at valid package names, or repo is flat layout → SKIP.

**Fail (source):** `source = ["<pkg_name>"]` where `<pkg_name>` is a subdirectory of `src/` — that directory doesn't exist at the repo root so coverage silently measures nothing. Fix: `source = ["src"]`.

**Fail (addopts):** `addopts` contains `--cov <dir>` — overrides `source` and measures the wrong directory. Fix: use bare `--cov`.

---

### Test 407 — pytest multi-value options are TOML arrays, not space-joined strings

**Why this matters:** In `tox.ini`/`pytest.ini` (INI format), multi-value pytest options like `norecursedirs`, `filterwarnings`, and `markers` are space- or newline-separated strings. When migrated to `[tool.pytest.ini_options]` in TOML, they must be **arrays of strings**. Copying the INI value verbatim produces a single-element array with a space-joined string (e.g. `[".* docs requirements site-packages"]`), which pytest treats as one pattern containing literal spaces — silently matching nothing. Additionally, directories deleted during migration (e.g. `requirements/`) must be dropped from `norecursedirs`.

SKIP this test if `[tool.pytest.ini_options]` is not present in `pyproject.toml`.

```python
python3 << 'PYEOF'
import os, sys, tomllib

MULTI_VALUE_KEYS = ["norecursedirs", "filterwarnings", "markers", "testpaths", "collect_ignore"]

if not os.path.exists("pyproject.toml"):
    print("SKIP: no pyproject.toml found")
    sys.exit(0)

with open("pyproject.toml", "rb") as f:
    data = tomllib.load(f)

ini_opts = data.get("tool", {}).get("pytest", {}).get("ini_options", {})
if not ini_opts:
    print("SKIP: no [tool.pytest.ini_options] section found")
    sys.exit(0)

failures = []

for key in MULTI_VALUE_KEYS:
    val = ini_opts.get(key)
    if val is None:
        continue
    if isinstance(val, list):
        # Correct type — check for space-joined strings inside the list
        for item in val:
            if isinstance(item, str) and ' ' in item.strip() and not item.strip().startswith('#'):
                failures.append(
                    f"  '{key}': contains space-joined string {item!r} — "
                    f"should be split into separate list entries"
                )
    elif isinstance(val, str):
        failures.append(
            f"  '{key}': is a plain string {val!r} — must be a TOML array of strings"
        )

# Check norecursedirs for directories deleted by the migration (e.g. requirements/)
# Do NOT flag well-known conventions that don't need to exist locally (site-packages, node_modules, etc.)
MIGRATION_DELETED = {"requirements", "requirements/"}
if "norecursedirs" in ini_opts:
    val = ini_opts["norecursedirs"]
    entries = val if isinstance(val, list) else [val]
    for entry in entries:
        for part in (entry.split() if isinstance(entry, str) else [entry]):
            part = part.strip('"\' ')
            if part in MIGRATION_DELETED and not os.path.isdir(part):
                failures.append(
                    f"  'norecursedirs': entry {part!r} refers to a directory deleted by the migration — remove it"
                )

if failures:
    print("FAIL: [tool.pytest.ini_options] has incorrectly migrated multi-value options:")
    for line in failures:
        print(line)
    print()
    print("  Fix: split space-separated INI strings into TOML string arrays, e.g.:")
    print('    norecursedirs = [".*", "docs", "site-packages"]')
    sys.exit(1)
else:
    print("PASS: pytest multi-value options are correctly expressed as TOML arrays")
PYEOF
```

**Pass:** All multi-value `[tool.pytest.ini_options]` options are proper TOML arrays, each entry is a single pattern, and `norecursedirs` contains no deleted directories.

**Fail:** A multi-value option is a plain string or a single-element list with spaces inside — split it into a proper TOML array. Also remove any `norecursedirs` entries for directories no longer present in the repo.

---

### Test 410 — `.readthedocs.yaml` uses uv install method (not pip)

When the repo uses uv (i.e. has `uv.lock`), `.readthedocs.yaml` must install doc dependencies via `method: uv / command: sync / groups: [doc]`. Using `method: pip` with `extra_requirements` requires pip extras (`[project.optional-dependencies]`), which do not exist in a uv-migrated repo that uses PEP 735 dependency groups — RTD will fail to install Sphinx and the docs build will error.

SKIP this test if `.readthedocs.yaml` does not exist in the repo.

```bash
python3 << 'PYEOF'
import os, re

if not os.path.exists(".readthedocs.yaml") and not os.path.exists(".readthedocs.yml"):
    print("SKIP: no .readthedocs.yaml found")
    raise SystemExit(0)

rtd_file = ".readthedocs.yaml" if os.path.exists(".readthedocs.yaml") else ".readthedocs.yml"
content = open(rtd_file).read()

if not os.path.exists("uv.lock"):
    print("SKIP: no uv.lock found — repo may not be uv-migrated yet")
    raise SystemExit(0)

# Check for pip method (old pattern)
if re.search(r'method:\s*pip', content):
    print(f"FAIL: {rtd_file} uses 'method: pip' but repo has uv.lock")
    print("  RTD won't find any pip extras since dependencies moved to PEP 735 groups.")
    print("  Fix: replace the python.install block with:")
    print("    python:")
    print("      install:")
    print("        - method: uv")
    print("          command: sync")
    print("          groups:")
    print("            - doc")
    print("  (Use the group name as declared in [dependency-groups] in pyproject.toml — typically 'doc', not 'docs')")
elif re.search(r'method:\s*uv', content):
    # Check it uses groups, not extra_requirements
    if re.search(r'extra_requirements', content):
        print(f"FAIL: {rtd_file} uses 'method: uv' but still has 'extra_requirements' — should use 'groups' instead")
    else:
        # Cross-check: if RTD uses uv groups, there must be no [project.optional-dependencies] docs block
        # (RTD doesn't use pip extras in this setup, so publishing a docs extra is misleading and unused)
        if os.path.exists("pyproject.toml"):
            import tomllib
            with open("pyproject.toml", "rb") as f:
                pdata = tomllib.load(f)
            opt_deps = pdata.get("project", {}).get("optional-dependencies", {})
            # Parse RTD group names from both inline ([doc]) and block list (- doc) YAML syntax
            rtd_group_names = re.findall(r'groups:\s*\[([^\]]+)\]', content)
            rtd_group_names = [g.strip().strip('"\'') for grp in rtd_group_names for g in grp.split(',')]
            # Also parse block-list form: lines starting with "- <name>" under a "groups:" key
            in_groups = False
            for line in content.splitlines():
                stripped = line.strip()
                if stripped == 'groups:':
                    in_groups = True
                elif in_groups:
                    m = re.match(r'^-\s+(\S+)', stripped)
                    if m:
                        rtd_group_names.append(m.group(1).strip('"\''))
                    elif stripped and not stripped.startswith('#'):
                        in_groups = False
            dep_groups = pdata.get("dependency-groups", {})
            rtd_pkgs = set()
            for g in rtd_group_names:
                for entry in dep_groups.get(g, []):
                    if isinstance(entry, str):
                        rtd_pkgs.add(entry.lower().split('[')[0].split('>')[0].split('<')[0].split('=')[0].strip())
            invented = []
            for extra_name, extra_pkgs in opt_deps.items():
                extra_canonical = {p.lower().split('[')[0].split('>')[0].split('<')[0].split('=')[0].strip() for p in extra_pkgs}
                overlap = extra_canonical & rtd_pkgs
                if overlap:
                    invented.append(f"  '{extra_name}' extra overlaps with RTD group packages: {sorted(overlap)}")
            if invented:
                print(f"FAIL: {rtd_file} uses 'method: uv' with groups, but pyproject.toml also has [project.optional-dependencies] entries whose packages duplicate what RTD installs via dependency groups. These extras are unused by RTD and were likely invented during migration (not ported from extras_require).")
                for line in invented:
                    print(line)
                print("  Fix: remove the overlapping [project.optional-dependencies] block(s) and re-lock.")
            else:
                print(f"OK: {rtd_file} uses uv install method with groups")
        else:
            print(f"OK: {rtd_file} uses uv install method with groups")
else:
    print(f"INFO: {rtd_file} install method is neither pip nor uv — manual inspection required")
PYEOF
```

**Pass:** `.readthedocs.yaml` uses `method: uv` with `groups` (or file is absent → SKIP), and no `[project.optional-dependencies]` block duplicates what RTD installs via dependency groups.

**Fail:** `method: pip` is used in a uv-migrated repo — switch to the uv install method. Or: `[project.optional-dependencies]` contains extras that duplicate RTD's dependency-group packages — remove the extras block.

### Test 415 — `uv sync` scope matches original pip-sync scope

A bare `uv sync` installs the `dev` dependency group by default (uv's implicit default), pulling in
tox, twine, pylint, pytest, Sphinx, and the full doc tree — typically 3× more packages than the
runtime set. A Makefile target that previously used `pip-sync requirements/base.txt` (runtime only)
must migrate to `uv sync --locked --no-default-groups`, not bare `uv sync`.

This test has two parts:

**Part A — Makefile pattern check:** any `uv sync` call without a `--group` or `--no-default-groups`
flag is a bare sync and installs too much for a runtime-only target.

**Part B — Package count approximation:** count packages in the old `requirements/base.txt` from
master and compare against `uv export --no-default-groups` in the PR branch. The counts should be
within 25% of each other. A large divergence means the scope changed.

```bash
python3 << 'PYEOF'
import subprocess, re, os, sys

# --- Part A: Makefile bare uv sync check ---
if not os.path.exists("Makefile"):
    print("SKIP Part A: no Makefile found")
else:
    content = open("Makefile").read()
    lines = content.splitlines()
    bare_sync_lines = []
    for i, line in enumerate(lines, 1):
        # Match uv sync that has no --group, --no-default-groups, or --all-groups flag
        if re.search(r'\buv sync\b', line) and not re.search(
            r'--group|--no-default-groups|--all-groups', line
        ):
            bare_sync_lines.append((i, line.strip()))

    if bare_sync_lines:
        print("FAIL Part A: bare 'uv sync' found in Makefile (installs dev group by default):")
        for lineno, text in bare_sync_lines:
            print(f"  Line {lineno}: {text}")
        print("  Fix: replace with 'uv sync --locked --no-default-groups' for runtime-only targets,")
        print("  or 'uv sync --locked --group <name>' for a specific group (test/quality/doc/dev).")
    else:
        print("OK Part A: no bare 'uv sync' in Makefile")

# --- Part B: package count approximation ---
# Get old requirements/base.txt from master
base_result = subprocess.run(
    ["git", "show", "origin/main:requirements/base.txt"],
    capture_output=True, text=True
)
if base_result.returncode != 0:
    base_result = subprocess.run(
        ["git", "show", "origin/master:requirements/base.txt"],
        capture_output=True, text=True
    )

if base_result.returncode != 0:
    print("SKIP Part B: no requirements/base.txt on main/master to compare against")
    raise SystemExit(0)

old_lines = [
    l for l in base_result.stdout.splitlines()
    if l.strip() and not l.startswith("#") and not l.startswith("-")
]
old_count = len(old_lines)

# Count packages uv would install with --no-default-groups
export_result = subprocess.run(
    ["uv", "export", "--no-default-groups", "--no-hashes", "--quiet"],
    capture_output=True, text=True
)
if export_result.returncode != 0:
    print(f"SKIP Part B: 'uv export --no-default-groups' failed — {export_result.stderr.strip()[:120]}")
    raise SystemExit(0)

new_lines = [
    l for l in export_result.stdout.splitlines()
    if l.strip() and not l.startswith("#") and not l.startswith("-")
]
new_count = len(new_lines)

delta = abs(new_count - old_count)
pct = (delta / old_count * 100) if old_count else 0

print(f"INFO Part B: old requirements/base.txt = {old_count} packages, "
      f"uv export --no-default-groups = {new_count} packages ({pct:.0f}% delta)")

if pct > 25:
    print(f"FAIL Part B: package count diverged by {pct:.0f}% (>{25}% threshold).")
    print(f"  If new count is much higher: a Makefile target may be using bare 'uv sync' (dev group)")
    print(f"  or the scope of [project].dependencies changed significantly.")
    print(f"  If new count is much lower: runtime dependencies may have been accidentally dropped.")
else:
    print(f"OK Part B: package count is within 25% of master's requirements/base.txt")
PYEOF
```

**Pass:** No bare `uv sync` in Makefile AND package count within 25% of old `requirements/base.txt`.

**Fail (Part A):** Bare `uv sync` found — installs dev group (~3× runtime count). Fix: `uv sync --locked --no-default-groups` for runtime-only targets.

**Fail (Part B):** Package count diverged >25% — scope likely changed. Investigate whether runtime deps were dropped or dev deps were accidentally included.

---

### Test 420 — Lock file is current (upgrade workflow covers staleness)

**Why this matters:** `uv lock --upgrade` is only run explicitly (via `make upgrade`). If the lock was generated weeks or months ago and an upstream package released a new major version since then, CI passes (it uses `--locked`) but every consumer who installs the package fresh today gets the new breaking version. This test checks whether the repo has a weekly `upgrade-python-requirements.yml` workflow to handle this automatically — if it does, stale bumps are covered and the test passes. If it does not, the test flags major version bumps that need manual attention.

This is exactly how Feanil caught the `path` 16→17 API break in i18n-tools: he ran `uv lock --upgrade-package path`, saw 17.1.1 resolve, and found `AttributeError: 'Path' object has no attribute 'abspath'` in the test suite. The fix was to update the code **and** commit the upgraded lock. Repos with the weekly cron would have caught this automatically on the next run.

```python
python3 << 'PYEOF'
import subprocess, re, sys, os, glob

if not os.path.exists('uv.lock'):
    print("SKIP: no uv.lock found")
    sys.exit(0)

# Check whether the weekly upgrade workflow is present
upgrade_workflows = glob.glob('.github/workflows/upgrade-python-requirements.yml')
has_upgrade_workflow = bool(upgrade_workflows)

# Save current lock
with open('uv.lock', 'r') as f:
    original = f.read()

def major(v):
    try:
        return int(v.split('.')[0].lstrip('v'))
    except Exception:
        return 0

try:
    result = subprocess.run(
        ['uv', 'lock', '--upgrade'],
        capture_output=True, text=True, timeout=180
    )
    combined = result.stdout + result.stderr
    updated = re.findall(r'Updated (\S+) v(\S+) -> v(\S+)', combined)

    if not updated:
        print("PASS: uv.lock is current — uv lock --upgrade changed nothing")
        sys.exit(0)

    major_bumps = [(p, o, n) for p, o, n in updated if major(n) > major(o)]
    minor_bumps  = [(p, o, n) for p, o, n in updated if (p, o, n) not in major_bumps]

    if major_bumps and has_upgrade_workflow:
        print(f"PASS: {len(major_bumps)} major version bump(s) exist but are covered by upgrade-python-requirements.yml (weekly cron):")
        for pkg, old, new in major_bumps:
            print(f"  {pkg}: v{old} -> v{new}  (major — will be caught and committed by weekly upgrade run)")
    elif major_bumps:
        print(f"WARN: {len(major_bumps)} MAJOR version bump(s) found and NO upgrade-python-requirements.yml present:")
        for pkg, old, new in major_bumps:
            print(f"  {pkg}: v{old} -> v{new}  <- MAJOR, API may have changed")
        print()
        print("Action for each major bump:")
        print("  1. Run: uv lock --upgrade-package <pkg>")
        print("  2. Run the full test suite — fix any AttributeError / ImportError")
        print("  3. Commit the upgraded uv.lock so CI validates current versions")
        print("  OR: add an upper-bound pin in [tool.uv].constraint-dependencies and document why")

    if minor_bumps:
        print(f"INFO: {len(minor_bumps)} minor/patch update(s) available (covered by weekly upgrade cron):")
        for pkg, old, new in minor_bumps:
            print(f"  {pkg}: v{old} -> v{new}")

finally:
    with open('uv.lock', 'w') as f:
        f.write(original)
    print("(uv.lock restored to pre-test state)")
PYEOF
```

**Pass:** `uv lock --upgrade` changes nothing (lock is already current), OR bumps exist but `upgrade-python-requirements.yml` is present — the weekly cron will catch and commit them automatically.

**Warn:** Major version bumps exist AND there is no `upgrade-python-requirements.yml`. Manual upgrade + test verification required before merge.

**Skip:** No `uv.lock` present (shouldn't happen in a completed modernize PR).

### Test 425 — README and docs stale installation instructions

**Why this matters:** The modernization deletes `setup.py`, `setup.cfg`, and the `requirements/` directory. Any README or docs file that still tells users to `python setup.py install`, `pip install -r requirements/...`, or references other deleted artifacts will be broken on PyPI (where the README is the long description) and confusing to new contributors. This is exactly the gap that let i18n-tools PR #288 ship `README.rst:11` with `python setup.py install` — a reviewer caught it in code review, not in pre-flight.

```python
python3 << 'PYEOF'
import re, glob, subprocess, sys

STALE_PATTERNS = [
    (r'python\s+setup\.py\s+install', "refers to deleted setup.py — replace with `pip install <package-name>`"),
    (r'python\s+setup\.py\b',         "refers to deleted setup.py — update installation instructions"),
    (r'pip\s+install\s+-r\s+requirements/', "refers to deleted requirements/ directory — update with pip install instructions"),
    (r'pip-compile\b',                 "refers to pip-compile (replaced by uv) — update tooling notes"),
    (r'\brequirements/\w+\.txt\b',     "refers to deleted requirements/*.txt files — update accordingly"),
]

readme_files = []
for pat in ['README.rst', 'README.md', 'README.txt', 'readme.rst', 'readme.md']:
    readme_files += glob.glob(pat)
for pat in ['docs/*.rst', 'docs/**/*.rst']:
    readme_files += glob.glob(pat, recursive=True)

if not readme_files:
    print("SKIP: no README or docs/*.rst files found")
    sys.exit(0)

failures = []
seen_files = set()
for path in readme_files:
    # Deduplicate case-insensitive filenames (e.g. README.rst and readme.rst on case-insensitive FS)
    real = path.lower()
    if real in seen_files:
        continue
    seen_files.add(real)
    try:
        lines = open(path).readlines()
    except OSError:
        continue
    for i, line in enumerate(lines, 1):
        matched = set()
        for regex, reason in STALE_PATTERNS:
            if re.search(regex, line, re.IGNORECASE):
                # Use the first (most specific) match per line to avoid double-reporting
                if i not in matched:
                    failures.append(f"  {path}:{i}: {line.rstrip()!r}\n    → {reason}")
                    matched.add(i)
                    break

if failures:
    print("FAIL: README/docs contain stale references to deleted files or tooling:")
    for f in failures:
        print(f)
    sys.exit(1)
else:
    print(f"PASS: no stale installation/tooling references found in: {readme_files}")
PYEOF
```

**Pass:** No README or docs file references `setup.py`, `pip install -r requirements/`, `pip-compile`, or deleted `requirements/*.txt` files.

**Fail:** One or more stale lines found — update each to match the new tooling (e.g. `pip install <package-name>` instead of `python setup.py install`).

**Skip:** No README or docs files present (unusual — flag it).

---

### Test 430 — No invented `[project.optional-dependencies]`

**Why this matters:** `[project.optional-dependencies]` extras are published on PyPI and consumed by installers. Creating new extras that were not present in the original `setup.py`/`setup.cfg` `extras_require` introduces a PyPI-visible surface that 2.0.0 never had. The canonical mistake: seeing a `doc.in` / `doc` dependency group and incorrectly adding a matching `[project.optional-dependencies]` docs block — dependency groups (PEP 735) are for local/CI use, not PyPI extras (PEP 508).

SKIP this test if the original `setup.py`/`setup.cfg` had `extras_require` (the extras were ported, not invented).

```python
python3 << 'PYEOF'
import ast, os, re, sys, tomllib

# --- Read new optional-dependencies ---
if not os.path.exists("pyproject.toml"):
    print("SKIP: no pyproject.toml found")
    sys.exit(0)

with open("pyproject.toml", "rb") as f:
    pdata = tomllib.load(f)

new_extras = set(pdata.get("project", {}).get("optional-dependencies", {}).keys())

# --- Read original extras_require from setup.py or setup.cfg ---
old_extras = set()

if os.path.exists("setup.cfg"):
    content = open("setup.cfg").read()
    # [options.extras_require] section
    if re.search(r'^\[options\.extras_require\]', content, re.MULTILINE):
        for line in re.findall(r'^\[options\.extras_require\](.*?)(?=^\[|\Z)', content, re.DOTALL | re.MULTILINE):
            for key in re.findall(r'^(\w[\w\-]*)[\s]*=', line, re.MULTILINE):
                old_extras.add(key)

if os.path.exists("setup.py"):
    src = open("setup.py").read()
    # Look for extras_require = {...} in setup() call
    m = re.search(r'extras_require\s*=\s*(\{[^}]+\})', src, re.DOTALL)
    if m:
        try:
            er = ast.literal_eval(m.group(1))
            old_extras.update(er.keys())
        except Exception:
            # Can't parse statically — record as "had some extras"
            old_extras.add("__unparseable__")

if not old_extras and new_extras:
    print(f"FAIL: pyproject.toml has [project.optional-dependencies] with extras {sorted(new_extras)}, but the original setup.py/setup.cfg had no extras_require.")
    print("  These extras were invented during migration, not ported from the original.")
    print("  Fix: remove the [project.optional-dependencies] block entirely and re-lock.")
    sys.exit(1)
elif old_extras:
    print(f"SKIP: original had extras_require {sorted(old_extras)} — extras parity checked by Test 440")
else:
    print("PASS: no [project.optional-dependencies] block and original had no extras_require")
PYEOF
```

**Pass:** No `[project.optional-dependencies]` in `pyproject.toml`, and original had no `extras_require`.

**Skip:** Original `setup.py`/`setup.cfg` had `extras_require` — extras were ported, not invented (Test 440 checks parity).

**Fail:** `pyproject.toml` has `[project.optional-dependencies]` but original had no `extras_require`. Remove the block and re-lock.

---

### Test 435 — No package duplication across extras and dependency groups

**Why this matters:** `[project.optional-dependencies]` and `[dependency-groups]` are two separate mechanisms. If the same package (e.g. `Sphinx`, `doc8`) appears in both, it is a reliable signal that an extra was accidentally invented by mirroring a dependency group rather than porting from `extras_require`. Even when extras legitimately exist, their packages should not duplicate the dependency groups — the groups are the install source for CI/RTD, and the extras are for downstream consumers installing the package with optional features.

SKIP this test if `pyproject.toml` has no `[project.optional-dependencies]` block.

```python
python3 << 'PYEOF'
import sys, tomllib

if not __import__("os").path.exists("pyproject.toml"):
    print("SKIP: no pyproject.toml found")
    sys.exit(0)

with open("pyproject.toml", "rb") as f:
    pdata = tomllib.load(f)

opt_deps = pdata.get("project", {}).get("optional-dependencies", {})
if not opt_deps:
    print("SKIP: no [project.optional-dependencies] block")
    sys.exit(0)

dep_groups = pdata.get("dependency-groups", {})

def canonical(pkg):
    return pkg.lower().split('[')[0].split('>')[0].split('<')[0].split('=')[0].split('!')[0].strip()

# Collect all packages in all dependency groups (non-include-group entries)
group_pkgs = set()
for group_name, entries in dep_groups.items():
    for entry in entries:
        if isinstance(entry, str):
            group_pkgs.add(canonical(entry))

failures = []
for extra_name, extra_pkgs in opt_deps.items():
    for pkg in extra_pkgs:
        c = canonical(pkg)
        if c in group_pkgs:
            failures.append(f"  '{pkg}' in [project.optional-dependencies].{extra_name} also appears in [dependency-groups]")

if failures:
    print("FAIL: packages duplicated across [project.optional-dependencies] and [dependency-groups]:")
    for line in failures:
        print(line)
    print("  Dependency groups are for CI/local/RTD use. Extras are for PyPI consumers.")
    print("  If the extras were invented (not ported from extras_require), remove them entirely.")
    print("  If the extras are legitimate, their packages must not mirror the dependency groups.")
    sys.exit(1)
else:
    print(f"PASS: no package duplication between [project.optional-dependencies] and [dependency-groups]")
PYEOF
```

**Pass:** No package appears in both `[project.optional-dependencies]` and `[dependency-groups]`.

**Skip:** No `[project.optional-dependencies]` block present.

**Fail:** One or more packages duplicated across both. If the extras were invented, remove them. If legitimate, deduplicate.

---

### Test 440 — Extras count parity with original `extras_require`

**Why this matters:** When a repo legitimately had `extras_require` in `setup.py`/`setup.cfg`, every extra must be ported to `[project.optional-dependencies]` — no extras added, none dropped. An extra added on top of what the original had expands the PyPI surface unintentionally; an extra dropped silently breaks downstream users who installed `package[extra]`.

SKIP this test if the original had no `extras_require` (handled by Test 430).

```python
python3 << 'PYEOF'
import ast, os, re, sys, tomllib

# --- Read new optional-dependencies ---
if not os.path.exists("pyproject.toml"):
    print("SKIP: no pyproject.toml found")
    sys.exit(0)

with open("pyproject.toml", "rb") as f:
    pdata = tomllib.load(f)

new_extras = set(pdata.get("project", {}).get("optional-dependencies", {}).keys())

# --- Read original extras_require ---
old_extras = set()
unparseable = False

if os.path.exists("setup.cfg"):
    content = open("setup.cfg").read()
    if re.search(r'^\[options\.extras_require\]', content, re.MULTILINE):
        for block in re.findall(r'^\[options\.extras_require\](.*?)(?=^\[|\Z)', content, re.DOTALL | re.MULTILINE):
            for key in re.findall(r'^(\w[\w\-]*)[\s]*=', block, re.MULTILINE):
                old_extras.add(key)

if os.path.exists("setup.py"):
    src = open("setup.py").read()
    m = re.search(r'extras_require\s*=\s*(\{[^}]+\})', src, re.DOTALL)
    if m:
        try:
            er = ast.literal_eval(m.group(1))
            old_extras.update(er.keys())
        except Exception:
            unparseable = True

if not old_extras and not unparseable:
    print("SKIP: original had no extras_require — Test 430 applies instead")
    sys.exit(0)

if unparseable:
    print("WARN: could not statically parse extras_require from setup.py — manual inspection required")
    sys.exit(0)

added = new_extras - old_extras
dropped = old_extras - new_extras
if added:
    print(f"FAIL: [project.optional-dependencies] has extras not in original extras_require: {sorted(added)}")
    print("  These were invented during migration. Remove them.")
if dropped:
    print(f"FAIL: [project.optional-dependencies] is missing extras that were in original extras_require: {sorted(dropped)}")
    print("  These were dropped during migration. Port them.")
if added or dropped:
    sys.exit(1)
else:
    print(f"PASS: extras parity — original and new both have: {sorted(old_extras)}")
PYEOF
```

**Pass:** `[project.optional-dependencies]` contains exactly the same set of extra names as the original `extras_require`.

**Skip:** Original had no `extras_require` (Test 430 covers that path).

**Fail:** Added extras (invented, remove them) or dropped extras (were ported incorrectly, restore them).

---

### Test 445 — No double-run: `ci.yml` must not have `push:` trigger when `release.yml` uses `workflow_call`

**Why this matters:** When `release.yml` calls `ci.yml` via `workflow_call`, every push to the default branch fires CI twice — once from `release.yml` → `workflow_call`, and once from the bare `push:` trigger in `ci.yml`. Both concurrent runs try to push to the coverage data branch, causing race-condition failures. This bug was introduced in `platform-plugin-aspects` PR #253 and fixed in PR [#257](https://github.com/openedx/platform-plugin-aspects/pull/257) (bmtcril). PyPI repos must not have a `push:` trigger in `ci.yml`; non-PyPI repos (no `release.yml`) should keep it.

**Important:** A dead `push: branches: [master]` trigger (wrong branch name) masks this bug — CI only runs once because the push trigger never fires. Once the branch name is corrected (see Test#180 non-master default branch note), the double-run activates. Always fix Test#180 and Test#445 together when the default branch is not `master`. See [openedx/django-wiki#329](https://github.com/openedx/django-wiki/pull/329).

```python
python3 << 'PYEOF'
import os, sys

try:
    import yaml
except ImportError:
    print("SKIP: PyYAML not installed — install with: pip install pyyaml")
    sys.exit(0)

ci_path = ".github/workflows/ci.yml"
release_path = ".github/workflows/release.yml"

if not os.path.exists(ci_path):
    print("SKIP: no ci.yml found")
    sys.exit(0)

with open(ci_path) as f:
    ci = yaml.safe_load(f)

with open(release_path) as f:
    release = yaml.safe_load(f) if os.path.exists(release_path) else None

on_triggers = ci.get("on") or ci.get(True) or {}
if isinstance(on_triggers, str):
    on_triggers = {on_triggers: None}

has_push_trigger = "push" in on_triggers
has_workflow_call = "workflow_call" in on_triggers

# Check if release.yml calls ci.yml via workflow_call
release_calls_ci = False
if release:
    for job in (release.get("jobs") or {}).values():
        uses = job.get("uses", "")
        if "ci.yml" in uses:
            release_calls_ci = True
            break

if release_calls_ci and has_push_trigger and has_workflow_call:
    print("FAIL: ci.yml has a `push:` trigger AND is called via workflow_call from release.yml.")
    print("  This fires CI twice on every push to the default branch, racing to update the coverage data branch.")
    print("  Fix: remove the `push:` block from ci.yml (release.yml's workflow_call covers it).")
    sys.exit(1)
elif not release_calls_ci and not has_push_trigger:
    print("WARN: release.yml does NOT call ci.yml, but ci.yml also has no push trigger.")
    print("  Coverage will not run on merges to main/master. Add a push: trigger if this is unintentional.")
else:
    if release_calls_ci:
        print("PASS: release.yml calls ci.yml via workflow_call and ci.yml has no redundant push: trigger.")
    else:
        print("PASS: no release.yml (non-PyPI repo) — push: trigger in ci.yml is correct for coverage on merges.")
PYEOF
```

**Pass:**
- PyPI repo: `release.yml` calls `ci.yml` via `workflow_call` AND `ci.yml` has no `push:` trigger.
- Non-PyPI repo: no `release.yml` present AND `ci.yml` has a `push:` trigger (coverage on merges).

**Fail:** `ci.yml` has both `workflow_call` (called by `release.yml`) and a `push:` trigger — remove the `push:` block.

**Warn:** No `release.yml` and no `push:` trigger — coverage will not run on merges; verify this is intentional.

**Skip:** `ci.yml` not present, or PyYAML not installed.

---

### Test 450 — `uv sync` in CI workflows and Makefile must use `--locked`

**Why this matters:** Without `--locked`, if `uv.lock` has drifted from `pyproject.toml` (e.g. a dependency was bumped but `uv lock` was not re-run), `uv sync` silently regenerates the lockfile and the run passes. The committed lockfile is then stale — the next developer gets different packages than what CI tested. `--locked` turns this silent corruption into a hard failure, forcing the lockfile to be committed before anything merges. The Makefile uses it too so local install targets (`make requirements`, `make requirements-test`, …) behave exactly like CI. First applied in [openedx/edx-proctoring#1340](https://github.com/openedx/edx-proctoring/pull/1340) (commit `e3445135`).

**Scope:**
- Every `uv sync` line in `.github/workflows/*.yml` / `*.yaml`.
- Every `uv sync` line in the `Makefile`, **except inside the `upgrade` target**. `upgrade` exists to change the lockfile (`edx_lint write_uv_constraints` + `uv lock --upgrade`); `--locked` there would make it fail. It normally has no `uv sync` at all — if one appears there, leave it without `--locked`.
- `uv run` is not checked here — it must **not** carry `--locked`; Test 250 Check 3 enforces that.

```python
python3 << 'PYEOF'
import os, re, sys

workflows_dir = ".github/workflows"
if os.path.exists(workflows_dir):
    for fname in sorted(os.listdir(workflows_dir)):
        if not fname.endswith((".yml", ".yaml")):
            continue
        fpath = os.path.join(workflows_dir, fname)
        for lineno, line in enumerate(open(fpath), 1):
            if re.search(r'\buv sync\b', line) and '--locked' not in line:
                failures.append((f"{workflows_dir}/{fname}", lineno, line.strip()))
else:
    print("SKIP (workflows): no .github/workflows/ directory found")

# --- Makefile (upgrade target exempt) ---
if os.path.exists("Makefile"):
    target = None
    for lineno, line in enumerate(open("Makefile"), 1):
        m = re.match(r'^([A-Za-z0-9_.-]+)\s*:(?!=)', line)
        if m:
            target = m.group(1)
        if target == "upgrade":
            continue
        if re.search(r'\buv sync\b', line) and '--locked' not in line:
            failures.append((f"Makefile ({target})", lineno, line.strip()))
else:
    print("SKIP (Makefile): no Makefile found")

if failures:
    print("FAIL: the following uv sync calls are missing --locked:")
    for where, lineno, text in failures:
        print(f"  {where}:{lineno}: {text}")
    print()
    print("  Fix: add --locked to each uv sync call, e.g.:")
    print("    uv sync --locked --group dev")
    sys.exit(1)
else:
    print("PASS: all uv sync calls in CI workflows and Makefile (outside 'upgrade') include --locked")
PYEOF
```

**Pass:** Every `uv sync` in `.github/workflows/` and in the Makefile (outside `upgrade`) includes `--locked`.

**Fail:** One or more `uv sync` calls are missing `--locked` — add the flag to each listed line.

**Skip:** Neither `.github/workflows/` nor a `Makefile` is present.

### Test 455 — `extract_translations` Makefile target must not use `uv`

**Why this matters:** The `openedx-translations` workflow clones the target repo and runs `make extract_translations` on a runner that has Python/pip but **no uv installed**. If `extract_translations` or its `translation-requirements` prerequisite calls any `uv` command, the step fails silently (`continue-on-error: true`) and the repo's strings stop updating on Transifex. The fix is `pip install --group translations` (pip 25.1+ supports PEP 735 dependency groups natively).

**Scope:** The `Makefile` `translation-requirements` target and the `extract_translations` target body — any `uv` call in either of these targets fails this test.

```python
python3 << 'PYEOF'
import re, sys

try:
failures = []

# --- CI workflows ---
    makefile = open("Makefile").read()
except FileNotFoundError:
    print("SKIP: no Makefile found")
    sys.exit(0)

# Extract the translation-requirements and extract_translations target bodies
# A target body is all lines after "target:" up to the next non-indented line
targets_to_check = ["translation-requirements", "extract_translations"]
lines = makefile.splitlines()

in_target = False
current_target = None
target_lines = {}  # target_name -> list of (lineno, line)

for i, line in enumerate(lines, 1):
    # Check if this line starts one of the targets we care about
    for t in targets_to_check:
        if re.match(rf'^{re.escape(t)}[\s:]', line):
            in_target = True
            current_target = t
            target_lines.setdefault(t, [])
            break
    print("  (Do NOT add --locked to the Makefile 'upgrade' target.)")
    else:
        if in_target:
            if line.startswith('\t') or line.startswith(' '):
                target_lines[current_target].append((i, line))
            else:
                in_target = False
                current_target = None

if not target_lines:
    print("SKIP: no extract_translations or translation-requirements target found in Makefile")
    sys.exit(0)

failures = []
for target, body_lines in target_lines.items():
    for lineno, line in body_lines:
        if re.search(r'\buv\b', line):
            failures.append((target, lineno, line.strip()))

if failures:
    print("FAIL: extract_translations/translation-requirements targets use uv — openedx-translations runner has no uv:")
    for target, lineno, text in failures:
        print(f"  Makefile:{lineno} (in {target}): {text}")
    print()
    print("  Fix: replace uv sync calls with pip install --group <name> (pip 25.1+)")
    print("  e.g.: pip install --group translations")
    sys.exit(1)
else:
    print("PASS: extract_translations and translation-requirements targets do not use uv")
PYEOF
```

**Pass:** Neither `extract_translations` nor `translation-requirements` target bodies contain any `uv` call.

**Fail:** A `uv` call is found in one of those targets — replace it with `pip install --group <name>` so it works on the openedx-translations runner which has no uv.

**Skip:** No `Makefile` present; or neither target exists in the Makefile.
