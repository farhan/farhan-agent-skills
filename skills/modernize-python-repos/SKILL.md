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
| CI action SHAs | e.g. `actions/checkout@<SHA> # v4.1.0` |

**Reference — cross-check pyproject.toml structure against the org reference repo:**
`openedx/sample-plugin` → `backend-plugin-sample/pyproject.toml` is the org-canonical example for `[build-system]`, `[tool.setuptools_scm]`, `[tool.semantic_release]`, and action SHA pinning style. Read it and match its structure for those sections.

**Also produce two inventory tables before touching any file:**

**Table A — Makefile targets (current state):** list every `make` target (from command #6 above), what tool it invokes, and whether that tool is being removed by this migration. Mark only pip-compile/setup.py targets as "removed"; everything else is "keep + adapt". This is the baseline for the Makefile audit and the removed-targets table in the PR description.

**Table B — CI steps (current state):** list every step in the existing CI workflow (from command #10 above) and what it runs. This is the baseline for CI parity — every tool that ran in the old CI must appear in the new CI matrix.

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
license = "AGPL-3.0"             # SPDX identifier — verify against setup.cfg; may be "Apache-2.0"
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

[tool.semantic_release.commit_parser_options]
# Because this repo is meant to be an example, docs changes are relevant
# feature changes and so should produce new releases.
minor_tags = ["feat", "docs"]

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
- Set `license` to the correct SPDX identifier from `setup.cfg` (e.g. `"Apache-2.0"`)
- Verify the README filename on disk (`README.rst` vs `README.md`) and update `[tool.setuptools.dynamic]`; remove `readme` from `dynamic` if you set it as a static `readme =` field above
- Remove `[project.entry-points]` sections that have no entries on master
- Keep only the Django `Framework ::` classifiers that match the versions actually tested
- Populate `dependencies` from `requirements/base.in` (static list, no version pins)
- Adapt `[dependency-groups]` to mirror the actual `.in` files — remove groups whose `.in` doesn't exist, add packages from each `.in` file exactly; remove `django42`/`conflicts` if only one Django version is tested
- Add `[tool.setuptools.package-data]` entries from master's `MANIFEST.in` non-`.py` asset patterns
- Add zero-version guard to `[tool.semantic_release]` only if latest git tag starts with `0.`

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
license = "AGPL-3.0"
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
source = [""]   # package import name from [run] source= in .coveragerc
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
from importlib.metadata import PackageNotFoundError, version

try:
    __version__ = version("<package-name>")
except PackageNotFoundError:  # pragma: no cover
    __version__ = "unknown"
```

The `# pragma: no cover` is **required** on the `except` line — the package is always installed during test runs, so this branch is unreachable in tests and will cause codecov failures if not excluded.

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
- Update CI to install uv via `astral-sh/setup-uv`, install deps via `uv sync --group ci`, and run tests via `uv run tox`

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
- Every other `.in` file → a dependency group with the same base name (e.g. `test.in` → `test`, `ci.in` → `ci`, `dev.in` → `dev`)
- `-r other.in` in any `.in` file → `{include-group = "other"}` in the corresponding group
- If `ci.in` does not exist on master, create a `ci` group with `tox` and `tox-uv` as the only entries
- If only one Django version is tested, include `Django>=X.Y,<X+1.0` directly in `test` — no `test-base` split needed
- If multiple Django versions are tested, split into `test-base` (non-Django packages) + one group per Django version; `test` should be the highest-supported version

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
	uv sync --group dev

upgrade: ## update python dependencies
	uv run --with edx-lint edx_lint write_uv_constraints pyproject.toml
	uv lock --upgrade
```

**Do NOT add `uv tool install tox --with tox-uv` to the `requirements` target.** CI uses `uv sync --group ci` + `uv run tox` (the locked, pinned tox from the `ci` dependency group). Installing a separate unpinned global tox via `uv tool install` is redundant and creates a version mismatch footgun — the global tox is outside `uv.lock` and can silently drift.

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
| `pip install -r requirements/base.txt` | `uv sync` (no group — runtime deps only from `[project].dependencies`) |
| `pip install -r requirements/test.txt` | `uv sync --group test` |
| `pip install -r requirements/quality.txt` | `uv sync --group quality` |
| `pip install -r requirements/doc.txt` | `uv sync --group doc` |
| `pip install -r requirements/dev.txt` | `uv sync --group dev` |

**Do NOT map a narrow-scope target (e.g. `base_requirements`) to `uv sync --group dev`.** That installs all dev/test/quality packages where only runtime deps were intended.

**Keep and do not rename** everything else: `lint`, `test`, `test-with-coverage`, `docs`, and all other targets on master. Their implementations can stay as-is — they call the linters/pytest directly, and tox manages the environment around them.

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
  push:
    branches: [main]   # match master's default branch name
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
        run: uv sync --group ci

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
- SHA-pin ALL actions — no mutable version tags (e.g. `@v4`)
- **Never downgrade a SHA** — for any action already on master, use its exact SHA or a newer one. Running with an older SHA than master is a regression.
- **Use `py` for the bare Python test env** (no Django suffix). The `python-version` matrix entry drives the interpreter. With Django matrix: use `django42`, `django52` etc.
- **Codecov `if:` condition** — use a compound condition that pins both the env name and the Python version: `if: matrix.toxenv == 'py' && matrix.python-version == '3.12'`. For Django matrix: `if: matrix.toxenv == 'django52' && matrix.python-version == '3.12'`.
- Keep any `env:` variables or step conditions from master's CI (e.g. `DJANGO_SETTINGS_MODULE`)
- If master's CI checked branch protection under specific job names, the new `name:` field on the matrix job must match exactly — check with repo owner before changing
- If master had no Codecov step, do not add one
- Do not add an `actions/setup-python` step — `astral-sh/setup-uv` handles Python installation via `python-version`
- **Never use `uv pip install` to override Django (or any package) version in CI.** `uv pip install "django~=X.Y.0"` bypasses the lockfile and is an anti-pattern for this modernization work. Django version selection must happen entirely through `uv sync --group djangoXY` or `uv run tox -e djangoXY` — both of which pull the pinned version from `uv.lock`. If you see a step like `uv pip install "django~=${{ matrix.django-version }}.0"` on master, replace it with the correct `uv sync --group ...` approach.
- **Preserve master's YAML list style — do not collapse a multi-line block list into a flow list.** If master writes a matrix list in block form (`os:\n  - ubuntu-latest`), keep it in block form; do not reformat it to flow form (`os: [ubuntu-latest]`). Block form keeps the diff clean — adding a new version (e.g. a new Python or OS entry) shows up as a single added line rather than editing an existing line, which is easier to read and to extend. This applies to every matrix list (`os`, `python-version`, `toxenv`, `django-version`, etc.). The template blocks in this skill use flow form only for brevity; match whatever style master already uses.
- **`codecov.yml` — do not create if absent.** Do not introduce a `codecov.yml` file if it does not already exist on master/main — an empty or header-only file adds noise with no value. If the repo already has one, read it (`git show master:codecov.yml`) and copy its settings verbatim; do not add any threshold, target, or key that is not already there (in particular, do not invent `coverage.status.patch.target` or any numeric threshold).

---

### Step 3 — Phase 3: semantic-release

**Skip this entire step for non-PyPI repos.** Document in `## Important Notes` of the PR: "This repo has no PyPI publish workflow on master, so `python-semantic-release` and `release.yml` were not added."

**Story tasks (PyPI repos only):**
- Add `[tool.semantic_release]` config to `pyproject.toml`
- Add `release.yml` workflow that runs CI then publishes to PyPI via OIDC
- Add `commitlint.yml` workflow to enforce conventional commits on PRs
- Flag that PyPI trusted publisher (OIDC) must be configured before merging

#### 3.1 — Add semantic-release config to pyproject.toml

```toml
[tool.semantic_release]
build_command = "pip install build && SETUPTOOLS_SCM_PRETEND_VERSION=$NEW_VERSION python -m build"

# Do NOT add a [tool.semantic_release.changelog] section. We no longer manage a
# changelog file with PSR. Release notes live only on the GitHub Release page
# (PSR still creates the GitHub Release by default). See Step 3.4.

# Zero-version guard — add ONLY if latest git tag starts with 0.x (e.g. v0.3.1)
# Omit entirely for 1.x+ repos
allow_zero_version = true
major_on_zero = false
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
        uses: actions/checkout@SHA_VERSION # TODO: Update master version or latest version
        with:
          ref: ${{ github.ref_name }}

      - name: Force branch to workflow sha
        run: git reset --hard ${{ github.sha }}

      - name: Run Semantic Release
        id: release
        uses: python-semantic-release/python-semantic-release@v<PSR_VERSION>
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          git_committer_name: "github-actions"
          git_committer_email: "actions@users.noreply.github.com"

      - name: Upload to GitHub Release Assets
        uses: python-semantic-release/publish-action@v<PSR_VERSION>
        if: steps.release.outputs.released == 'true'
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          tag: ${{ steps.release.outputs.tag }}

      - name: Upload distribution artifacts
        uses: actions/upload-artifact@SHA_VERSION # TODO: Update master version or latest version
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
        uses: actions/download-artifact@SHA_VERSION # TODO: Update master version or latest version
        with:
          name: distribution-artifacts
          path: dist

      - name: Publish to PyPI
        uses: pypa/gh-action-pypi-publish@<VERIFIED_COMMIT_SHA> # v<VERSION>
        # No user/password — OIDC trusted publisher. Configure on PyPI before merging.
```

Get the current verified **commit** SHA for `pypa/gh-action-pypi-publish` (must be a real commit SHA, not a tag-object SHA):
```bash
# Get the latest release tag
gh api repos/pypa/gh-action-pypi-publish/releases/latest --jq '.tag_name'
# Then resolve to a real commit SHA (not the tag object SHA):
gh api repos/pypa/gh-action-pypi-publish/commits/<TAG> --jq '.sha'
# Verify it resolves (returns 200, not 422):
gh api repos/pypa/gh-action-pypi-publish/commits/<SHA> --jq '.sha'
```

**SHA pinning rules for release.yml:**
- `pypa/gh-action-pypi-publish` — **must use a verified commit SHA** (not a floating tag). A floating `@release/v1` branch on this action caused a real production incident; SHA-pinning is non-negotiable here. Verify the SHA resolves via `gh api .../commits/<sha>` before using it.
- `python-semantic-release/python-semantic-release` and `python-semantic-release/publish-action` — use **floating version tags** (e.g. `@v10.6.1`), not SHA pins. These actions run only on push to default branch (never in PR CI), so a supply-chain SHA pin adds friction without meaningful protection. `openedx/XBlock`'s reference implementation uses floating tags for PSR actions.
- All other actions (e.g. `actions/checkout`, `actions/upload-artifact`, `actions/download-artifact`) — **SHA-pin as usual**.

If master had a legacy `pypi-publish.yml` or similar workflow: `git rm .github/workflows/pypi-publish.yml`.

**Never delete cross-repo or release-automation workflows unless they directly depend on deleted functionality.** Workflows triggered on tag push or that call external services read from `$GITHUB_REF` or API calls — they are unaffected by this migration. Only delete a workflow if it explicitly reads/writes the hardcoded `__version__`, invokes pip-compile, or references a deleted file (e.g. `requirements/base.in`). When in doubt, keep it. Document every deleted workflow in the PR description with the precise reason.

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

# NEVER delete CHANGELOG.rst — if it exists, Step 3.4 prepends a deprecation note (it is not wired to PSR).

# NEVER delete — ruff is out of scope:
# pylintrc, pylintrc_tweaks — leave exactly as on master
```

Verify:
```bash
for f in setup.py setup.cfg .coveragerc; do
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
for f in setup.py setup.cfg .coveragerc; do
  [ -f "$f" ] && echo "FAIL: $f still exists" || echo "OK: $f absent"
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

# --- Check 17: pragma: no cover on PackageNotFoundError except branch ---
echo "--- Check 17: pragma: no cover on PackageNotFoundError ---"
python3 << 'PYEOF'
import re, glob

failures = []
for py_file in glob.glob('src/**/*.py', recursive=True) + glob.glob('*.py') + glob.glob('[!.]*/**/__init__.py', recursive=True):
    try:
        lines = open(py_file).readlines()
    except Exception:
        continue
    for i, line in enumerate(lines):
        if 'except PackageNotFoundError' in line and '# pragma: no cover' not in line:
            failures.append(f"{py_file}:{i+1}: missing '# pragma: no cover' on except PackageNotFoundError branch")

if failures:
    for f in failures:
        print(f"FAIL: {f}")
else:
    print("OK: all PackageNotFoundError except branches have pragma: no cover")
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
          "Remove it; CI uses 'uv sync --group ci' + 'uv run tox' (the locked tox from the ci dependency group).")
else:
    print("OK: no 'uv tool install tox' in Makefile")
PYEOF

# --- Check 21: no uv pip install in CI workflows ---
echo "--- Check 21: no uv pip install in CI workflows ---"
if grep -rqE 'uv pip install' .github/workflows/ 2>/dev/null; then
  echo "FAIL: 'uv pip install' found in CI workflow(s) — this is an anti-pattern:"
  grep -rnE 'uv pip install' .github/workflows/
  echo "  Use 'uv sync --group <name>' or 'uv run tox -e <env>' instead — both pull from uv.lock."
else
  echo "OK: no uv pip install in CI workflows"
fi

# --- Check 20: no stray pip install -r requirements/ in Makefile ---
echo "--- Check 20: no stray pip install -r requirements/ in Makefile ---"
if grep -qE 'pip install.*requirements/' Makefile 2>/dev/null; then
  echo "FAIL: Makefile still references requirements/ files via pip install:"
  grep -nE 'pip install.*requirements/' Makefile
  echo "  requirements/ is deleted — migrate each target to 'uv sync [--group <name>]' using the correct scope"
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
- [ ] Makefile `upgrade` → `edx_lint write_uv_constraints` + `uv lock --upgrade`
- [ ] Makefile `requirements` → `uv sync --group dev` only — **no `uv tool install tox`** (that installs an unpinned global tox outside uv.lock)
- [ ] No Makefile targets dropped (except pip-compile targets) and none renamed; `*.py` glob change documented if removed
- [ ] CI uses `astral-sh/setup-uv`, `uv sync --group ci`, `uv run tox`, named `ci.yml`
- [ ] CI does **not** set `fail-fast` (it defaults to `true`); `strategy:` block in parity with master
- [ ] CI toxenv matrix uses `py` (not `py312`) for the bare Python test env; Codecov `if:` uses compound condition (`matrix.toxenv == 'py' && matrix.python-version == '3.12'`)
- [ ] Codecov `if:` condition references the exact toxenv name used in the matrix
- [ ] All actions SHA-pinned; no SHA is older than what master used
- [ ] **pylint/isort/pycodestyle retained in quality group — no ruff introduced**
- [ ] `pylintrc`/`pylintrc_tweaks` still exist on disk
- [ ] `make lint` exits 0
- [ ] `make test` exits 0
- [ ] `uv lock --check` exits 0
- [ ] **Step 5a pre-PR validation: zero `FAIL:` lines** (includes Check 9: setup.py/setup.cfg migration parity, Check 11: tox env order, Check 12: no new tox envs, Check 13: Makefile target order, Check 14: Makefile changes in scope)
- [ ] Coverage thresholds match master (no invented `fail_under`)
- [ ] No source-tracing comments in `[dependency-groups]` (no `# From requirements/ci.in` style lines)
- [ ] `__version__` in package `__init__.py` uses `importlib.metadata` pattern with `# pragma: no cover` on the `except PackageNotFoundError` line — never remove `__version__` entirely
- [ ] **PyPI repos:** `release.yml` + `commitlint.yml` added; `[tool.semantic_release]` in pyproject.toml with NO `[tool.semantic_release.changelog]` section; `CHANGELOG.rst` not wired to PSR (deprecation note prepended if it exists, otherwise left absent); zero-version guard only if 0.x; `## Important Notes` flags OIDC trusted publisher config required
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
- **Updated Makefile targets table:** include only if targets were updated (not removed). Omit the section entirely if no targets changed. For the `requirements` target, the entry must describe `uv sync --group dev` — if the `=== uv tool install tox ===` check in Step 1 flagged a hit, do NOT document it as correct in the table; flag it as a bug to fix before the PR is merged.
- **`## Python X.Y dropped` section:** present if and only if `requires-python` changed vs master. Omit otherwise.
- **Versioning section:** write the `[Static]` paragraph if no `setuptools-scm` in `pyproject.toml`; write the `[Dynamic]` paragraph if `setuptools-scm` is present. Write exactly one, never both.
- **`## Important Notes` section:** include when there is something critical to flag. Always include when `release.yml: PRESENT` (flag that OIDC trusted publisher must be configured on PyPI before merge). Also use for: omitted items (`release.yml` not added because no PyPI workflow existed; `src/` layout not adopted because repo doesn't publish to PyPI), unusual constraint pins, branch-protection check names reviewers must verify, or any other non-obvious decision.

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
Add this section only if there is something critical to flag (e.g. OIDC trusted publisher must be configured before merge, a branch-protection check name that must match, a retained workflow that reviewers should scrutinise). Omit entirely if nothing warrants it.

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
- `## Important Notes` is conditional — include it only when there is something genuinely critical. Do not add it just to have a section. When included, each bullet must be unique and not repeat facts already stated elsewhere.
- **No repeated content:** every claim must appear in exactly one section. Before writing any bullet, verify it is not already conveyed elsewhere in the description.
- **Accuracy over completeness:** every claim in the description must be true of this specific PR. Never write a conditional item (bracketed or conditional section) unless its condition was confirmed true in Mode 2 Step 1. When in doubt, omit rather than guess.
- **Never mention ruff** as part of this migration — it is out of scope.

---

## Mode 3 — Test/Verify

Verify an existing migration PR against the full Test suite. **Report only — do not fix, commit, or modify anything.** Fixes belong to Mode 1.

### Step 1 — Identify the PR

If a PR (or branch) isn't specified and the working tree isn't already on the migration branch, ask which PR to verify. Check it out with `gh pr checkout <number>`.

### Step 2 — Run every test

Run **all** tests from the [Test suite](#test-suite--tests-10390), in order, Test 10 through Test 390.

**Test 10 is a hard gate.** If ruff is present, Test 10 fails: **stop running the remaining tests**, report only Test 10's failure, and follow its instructions (ask the user to revert the ruff changes, then re-run). Do not report the other tests as passed or failed when Test 10 halts — record them as `⏭️ Skipped (halted at Test 10 — ruff present)`.

Otherwise, do not stop at the first failure and do not skip a test without recording why (e.g. `make docs` with no `docs/` directory, Test 80 when the repo is in the hardcoded non-PyPI list, Test 110 always (gated — only runs on explicit user request), Test 180 when the repo is in the hardcoded non-PyPI list, Test 210 always (gated — only runs on explicit user request), Test 220 when the user opted out of the src/ move, Test 230 when master did not use mypy, Test 360 when master had no isort config in any config file). Record the outcome of every single test.

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
| Test#360 | isort style unchanged | ✅ Pass | — OR — ⏭️ Skipped (no isort config on master) |
| Test#370 | No source-tracing comments in dependency-groups | ✅ Pass | |
| Test#380 | Required tox environments present | ✅ Pass | py, quality, docs all present |
| Test#390 | No manual venv GITHUB_PATH echo in CI | ✅ Pass | |

## Failure details

### Test#40 — Lockfile consistency
<evidence + what would fix it>
```

If Test 10 halts, the table lists Test#10 as `🛑 Halt` and every other row as `⏭️ Skipped (halted at Test 10 — ruff present)`, followed by the halt instructions.

---

## Test suite — Tests 10–390

All tests must be run as part of a verification report (Test/Verify mode). **Test 10 is a hard gate — if it fails, halt.**

**Test groups** (tests are numbered in order of execution, not by group):

| Group | Tests | What they check |
|---|---|---|
| Entry gate (run first) | 10 | Ruff absent everywhere |
| Python version | 260 | Python < 3.12 removed from tox, CI, classifiers |
| Package structure and files | 90, 130, 220, 310 | Stale files deleted; `__version__` removed; src/ layout correct; no empty codecov.yml introduced |
| Package build | 30, 70, 80 | Build output complete; package imports; setuptools-scm runtime (PyPI) |
| Dependency management | 40, 50, 160, 170, 270, 340 | Lockfile in sync; groups resolve; all packages migrated; constraints; static deps; `-r` refs use include-group |
| Migration parity | 155 | Every field from master's setup.py/setup.cfg (metadata, entry points, tool configs) present in pyproject.toml |
| Versioning | 240, 245, 246 | Versioning strategy: setuptools-scm (PyPI) or static version (no-PyPI), including 0.x guard; PSR `tag_format` matches existing release tags (245, offline) and a matching baseline tag exists for the latest PyPI release (246, ground-truth) — else manual baseline tag required |
| Quality tooling | 230, 280, 360, 370 | Mypy retained (if used); quality group has original linters; isort style unchanged; no source-tracing comments in dependency groups |
| Tox configuration | 60, 320, 330, 380 | tox.ini parses; all envs resolve; no env renamed; commands invoke make targets; required envs present |
| Makefile | 20, 140, 350 | Targets exit 0; no target dropped without reason; targets run tools directly (not via tox) |
| GitHub Actions and CI | 100, 150, 180, 250, 290, 300, 305, 390 | YAML valid; branch protection preserved; CI-first + OIDC in release.yml; `uv run tox`; no action version downgrades vs main; toxenv uses `py` not `py312`; `fail-fast` not set + strategy parity with master; no manual venv PATH echo |
| Code review audit | 120, 190 | Logic changes noted; no invented thresholds |
| PR documentation (gated) | 210 | PR body complete and accurate (explicit request only) |
| SHA pinning audit (gated) | 110 | Actions SHA-pinned in PR-modified workflows (explicit request only) |

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
- Deleted files (`setup.py`, `setup.cfg`) appear in the tarball — they should not be included after deletion. `CHANGELOG.rst` (if present) is deprecated and must not be packaged either.
- The source package directory is missing or empty.
- Static assets that existed before the migration are absent — their absence will break installs.

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

**Pass:** PR tarball contains all required files; no deleted file reappears; PR wheel contains the full package with static assets, `METADATA` present, no `.pyc` files; no regressions vs main in either tarball or wheel; Step 3b reports OK or SKIP (SKIP for any non-PyPI repo, or a repo with no coverage artifacts).

**Fail:** Any deleted file reappears in the tarball; source package directory missing or empty; static assets absent from tarball or wheel; any file present in main missing from PR (regression); Step 3b FAILs (a PyPI repo whose `MANIFEST.in` omits prune rules for generated artifacts).

### Test 40 — Lockfile consistency

```bash
uv lock --check
```

Must exit 0. If it fails, run `uv lock` to regenerate and commit the updated lockfile.

### Test 50 — Dependency group resolution

```bash
uv sync --group dev
uv sync --group ci
uv sync --group quality
uv sync --group test
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

### Test 130 — `__version__` uses `importlib.metadata` pattern

```bash
grep -rn '__version__' --include='*.py' . | grep -v '\.tox' | grep -v '/test'
```

**Pass criteria — both must hold:**
1. No hardcoded `__version__ = "x.y.z"` string remains in package source.
2. The `importlib.metadata` pattern is present in the package `__init__.py`, with `# pragma: no cover` on the `except PackageNotFoundError` line:

```python
from importlib.metadata import PackageNotFoundError, version
try:
    __version__ = version("<package-name>")
except PackageNotFoundError:  # pragma: no cover
    __version__ = "unknown"
```

`__version__` should always be kept as a norm — do not remove it entirely. The `# pragma: no cover` is required because the except branch is unreachable during tests (the package is always installed) and will cause codecov failures without it.


### Test 90 — No stale files on disk

```bash
for f in setup.py setup.cfg .coveragerc; do
  [ -f "$f" ] && echo "STALE: $f still exists" || echo "OK: $f absent"
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

For each changed workflow file, check for un-pinned references — **excluding org-internal reusable workflow calls and PSR actions** (which intentionally use floating version tags):

```bash
git diff master...HEAD --name-only -- '.github/workflows/*.yml' '.github/workflows/*.yaml' \
  | xargs grep -E 'uses:\s+\S+@' \
  | grep -v '@[0-9a-f]\{40\}' \
  | grep -v '^#' \
  | grep -v 'uses:\s\+openedx/\.github/' \
  | grep -v 'python-semantic-release/'
```

**Exemptions from SHA pinning:**
- `python-semantic-release/python-semantic-release` and `python-semantic-release/publish-action` — these run only on push to the default branch (never in PR CI), so floating version tags (e.g. `@v10.6.1`) are correct and intentional. The `openedx/XBlock` reference implementation uses this pattern.
- `pypa/gh-action-pypi-publish` — **must be SHA-pinned** with a verified commit SHA (not a tag-object SHA). A floating ref on this action caused a real production incident; verify the SHA resolves via `gh api repos/pypa/gh-action-pypi-publish/commits/<sha>` before accepting.

**Pass:** No un-pinned third-party action references in any workflow file added or modified by the PR (PSR actions with floating version tags are exempt; `gh-action-pypi-publish` must be SHA-pinned).

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
if master_license and not project.get("license"):
    add(WARN, f"[project].license missing (master had: {master_license!r})")
elif project.get("license"):
    print(f"  ok  license = {project['license']!r}")

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

# Packages legitimately added to specific groups by this migration that were not
# in the original .in files. Keyed by group name → set of normalized package names.
# tox-uv: the migration template always adds tox-uv to the ci group even when
# ci.in only had tox, because uv-venv-lock-runner requires it.
ADDED_BY_MIGRATION = {
    'ci': {'tox-uv'},
}

def normalize(name):
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

in_files = ['base.in', 'test.in', 'dev.in', 'doc.in']
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

# Split missing into hard failures (gone from the resolved env too) and soft warnings
# (still transitively present in uv.lock — declaration lost but environment intact).
missing_gone       = {p for p in missing if p not in LOCKED}
missing_transitive = {p for p in missing if p in LOCKED}

print("Step 1 — Overall parity:")
print("  MISSING & GONE (in master .in files, not in pyproject.toml, not in uv.lock):")
for p in sorted(missing_gone): print(f"    FAIL: {p}")
if not missing_gone: print("    (none)")

print("  MISSING but TRANSITIVELY AVAILABLE (dropped explicit declaration, still in uv.lock):")
for p in sorted(missing_transitive): print(f"    WARN: {p}  — re-declare explicitly for reproducibility, or confirm the drop is intentional")
if not missing_transitive: print("    (none)")

print("  ADDED in PR (not in any master .in file):")
for p in sorted(added): print(f"    ADDED: {p}")
if not added: print("    (none)")

print(f"\n  Master total: {len(master_pkgs)} | PR total: {len(pr_pkgs)}")
if missing_gone:
    raise SystemExit(f"\nFAIL: {len(missing_gone)} package(s) missing from pyproject.toml AND absent from uv.lock")

# ── Step 2 — Group-level exact parity: each .in file maps to its named group ──

group_checks = {'dev': 'dev.in', 'test': 'test.in', 'doc': 'doc.in', 'ci': 'ci.in', 'quality': 'quality.in'}
step2_failures = []

dep_groups = data.get('dependency-groups', {})
for group_name, in_filename in group_checks.items():
    r = subprocess.run(['git', 'show', f'master:requirements/{in_filename}'], capture_output=True, text=True)
    if r.returncode != 0:
        print(f"\nStep 2 [{group_name}]: master:requirements/{in_filename} not found — skipping")
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

**Pass:** No `FAIL:` or `EXTRA:` lines, exit code 0. `WARN:` lines (a master direct-dep dropped from explicit declaration but still resolvable in `uv.lock`) do not fail the test — surface them so the author can re-declare for reproducibility or confirm the drop was intentional.

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

### Test 180 — release.yml structure: CI first, then OIDC publish only

Skip (with reason) if the repo is in the hardcoded non-PyPI list — in that case `release.yml` is not added. Otherwise verify that `release.yml` (a) runs the CI workflow first via a reusable-workflow call, and (b) publishes to PyPI using **OIDC trusted publishing only** — no token auth anywhere.

```bash
echo "=== run_tests / run_ci job calling CI workflow ==="
grep -n "uses:.*ci\.yml\|uses:.*python-tests\.yml" .github/workflows/release.yml \
  || echo "(none — FAIL: release.yml must call the CI workflow as a reusable workflow)"

echo "=== id-token permission (must be present on publish_to_pypi) ==="
grep -n "id-token" .github/workflows/release.yml || echo "(none — FAIL)"
echo "=== password / PYPI_UPLOAD_TOKEN (must be absent) ==="
grep -nE "password:|PYPI_UPLOAD_TOKEN" .github/workflows/release.yml || echo "(none — OK)"
echo "=== workflow filename ==="
[ -f .github/workflows/release.yml ] && echo "OK: named release.yml" || echo "FAIL: release workflow is not named release.yml"
```

**Pass:** A `run_tests` or `run_ci` job calls the CI workflow via `uses:`; `release` and `publish_to_pypi` declare `needs:`; `id-token: write` present in `publish_to_pypi`; **no** `password:` input and **no** `PYPI_UPLOAD_TOKEN`; the workflow is named `release.yml`; the PR description flags the trusted-publisher config as an out-of-band merge blocker.

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

### Test 250 — uv run tox in CI (not bare tox)

```bash
for workflow in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ ! -f "$workflow" ] && continue
  if grep -E '^\s*-\s+run:\s+tox\s' "$workflow" > /dev/null; then
    echo "FAIL: bare tox in $(basename $workflow) — use 'uv run tox'"
  fi
done
echo "OK: all tox invocations use uv run"
```

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

Feanil's rule (mockprock #66): "The make targets should just run the tests in the environment they exist in. `uv run pytest`." Delegating from Makefile to tox makes local iteration painful — developers must spin up a full tox environment just to run a quick test. The Makefile is the direct interface; tox is the CI wrapper.

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

**Pass:** Core Makefile targets (`test`, `lint`/`quality`, `test-with-coverage`, `docs`) invoke tools directly via `uv run <tool>`, not by calling tox.

**Fail:** A core Makefile target delegates to tox (`uv run tox -e ...`) — this forces tox for local dev and defeats the purpose of having Makefile targets.

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
