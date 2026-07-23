---
name: modernize-python-repos
description: >
  Modernize an Open edX Python repo to use uv, pyproject.toml (PEP 621/735), optional src/ layout
  (if publishing to PyPI), and python-semantic-release. Three modes: Implement/Re-implement (create or update
  the migration), PR creation (generate a formatted PR body for a completed migration), and
  Test/Verify (run the full test suite against a PR and report every result).
allowed-tools: Read Glob Grep Bash Write Edit
---

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
| **3. Test/Verify** | User asks to test or verify a migration PR | Run all 33 tests and report every result in one table — no fixes |

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
#      codejail-service, openedx-user-groups, cc2olx, pr_watcher_notifier
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
# Each group mirrors its requirements/*.in file exactly.
# Adapt groups to match the actual .in files present in the repo.
# "-r other.in" → {include-group = "other"}; "-c constraints.txt" → skip (handled via uv_constraints)
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
#  DO NOT EDIT constraint-dependencies DIRECTLY.
#  This list is managed by `edx_lint write_uv_constraints`
#  and will be overwritten the next time `make upgrade` is run.
#  - GLOBAL constraints: edit edx_lint/files/common_constraints.txt
#  - REPO-SPECIFIC constraints: edit [tool.edx_lint].uv_constraints in this file
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
version = ""                     # copy exactly from setup.cfg — bump manually at release
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

dynamic = ["readme"]
# readme = "README.rst"          # ← do NOT set this as static when "readme" is in dynamic above

dependencies = [
    # copy from requirements/base.in — static list
]

[project.urls]
Homepage = "https://github.com/openedx/<repo-name>"
Repository = "https://github.com/openedx/<repo-name>"

[tool.setuptools]
include-package-data = true

[tool.setuptools.dynamic]
readme = {file = ["README.rst"], content-type = "text/x-rst"}

[tool.setuptools.packages.find]
exclude = ["tests*", "*.tests", "*.tests.*"]
# No src/ layout for non-PyPI repos

[tool.setuptools.package-data]
"*" = [
    # Add non-.py asset glob patterns migrated from master's MANIFEST.in
]

[tool.uv]
package = true
#  DO NOT EDIT constraint-dependencies DIRECTLY.
#  This list is managed by `edx_lint write_uv_constraints`
#  and will be overwritten the next time `make upgrade` is run.
#  - GLOBAL constraints: edit edx_lint/files/common_constraints.txt
#  - REPO-SPECIFIC constraints: edit [tool.edx_lint].uv_constraints in this file
constraint-dependencies = []     # populated by `edx_lint write_uv_constraints`

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
| `include CHANGELOG.rst` | Drop — CHANGELOG.rst is deleted (PyPI) or kept but not packaged |
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

#### 1.4 — Remove hardcoded `__version__`

If master has `__version__ = "..."` hardcoded in a package `__init__.py`:

- **PyPI repo:** Remove it — version is now derived from git tags via setuptools-scm.
- **If genuinely needed at runtime** (other code imports it): replace with:
  ```python
  from importlib.metadata import version, PackageNotFoundError
  try:
      __version__ = version("<package-name>")
  except PackageNotFoundError:
      __version__ = "unknown"
  ```
- **Non-PyPI repo:** Either remove it and update `[project] version` to match, or keep it — but do NOT have two different versions in pyproject.toml and `__init__.py`.

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
# Each group mirrors its requirements/*.in file exactly.
# "-r other.in" in the .in file → {include-group = "other"} here.
# Direct packages → listed verbatim.

# From requirements/test.in (add Django matrix entries below if needed):
test = [
    # direct packages from test.in
    "coverage",
    "pytest",
    "pytest-cov",
    "pytest-django",
    # "-r base.in" → {include-group = "base"} (if present in test.in)
    # Django pinned to the highest version tested:
    "Django>=5.2,<6.0",
]

# If test.in has no Django pin and Django is added per-matrix (common pattern):
# Create a test-base group for the non-Django packages and one group per Django version:
# test-base = [<packages from test.in minus Django>]
# test       = [{include-group = "test-base"}, "Django>=5.2,<6.0"]
# django42   = [{include-group = "test-base"}, "Django>=4.2,<5.0"]
# Use this split ONLY when multiple Django versions are tested.

# From requirements/quality.in — retain master's linters EXACTLY (NO ruff):
quality = [
    # "-r test.in" → {include-group = "test"} (if quality.in includes test.in)
    {include-group = "test"},
    # direct packages from quality.in:
    "edx-lint",
    "isort",
    "pycodestyle",
    # add others only if they appear in quality.in
]

# From requirements/doc.in:
doc = [
    # "-r test.in" → {include-group = "test"} (if doc.in includes test.in)
    {include-group = "test"},
    # direct packages from doc.in:
    "Sphinx",
    "sphinx-book-theme",
]

# From requirements/ci.in (create with tox + tox-uv if ci.in does not exist):
ci = [
    # direct packages from ci.in — typically just:
    "tox",
    "tox-uv",
]

# From requirements/dev.in — exact mirror; "-r X.in" → {include-group = "X"}:
dev = [
    {include-group = "quality"},  # only if dev.in has "-r quality.in"
    {include-group = "ci"},       # only if dev.in has "-r ci.in"
    {include-group = "doc"},      # only if dev.in has "-r doc.in"
    # direct packages from dev.in (those not already included via "-r"):
]
```

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

Then populate `[tool.uv].constraint-dependencies` automatically — never edit it by hand:

```bash
uv run --with edx-lint edx_lint write_uv_constraints pyproject.toml
```

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
envlist = py312-django{42,52}, lint, docs
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

[testenv:lint]
runner = uv-venv-lock-runner
dependency_groups = quality
allowlist_externals = make
commands =
    make lint

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

#### 2.5 — Update Makefile

Only update the two targets the story changes. Everything else stays exactly as-is.

```makefile
requirements: ## install development environment requirements
	uv sync --group dev
	uv tool install tox --with tox-uv

upgrade: ## update python dependencies
	uv run --with edx-lint edx_lint write_uv_constraints pyproject.toml
	uv lock --upgrade
```

**Drop** only these targets (they are directly replaced by the story):
- `compile-requirements` — replaced by `uv lock`
- Any other pip-compile or `requirements/*.txt` generation targets

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
      fail-fast: true
      matrix:
        python-version: ["3.12"]
        # If no Django matrix: use "py" (not "py312") — the python-version entry drives
        # the interpreter; using "py312" hardcodes the version in two places.
        # If Django matrix: use named envs like "django42", "django52".
        toxenv: [lint, docs, py]   # ← no Django: use "py"; with Django: [lint, docs, django42, django52]

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
        # Condition must reference the EXACT toxenv name used in the matrix above.
        # No Django matrix → "py". Django matrix → highest version, e.g. "django52".
        if: matrix.toxenv == 'py'
        uses: codecov/codecov-action@<SHA_FROM_MASTER_OR_LATEST> # vX.Y.Z
        with:
          token: ${{ secrets.CODECOV_TOKEN }}
          flags: unittests
          fail_ci_if_error: true
```

**Parity rules:**
- SHA-pin ALL actions — no mutable version tags (e.g. `@v4`)
- **Never downgrade a SHA** — for any action already on master, use its exact SHA or a newer one. Running with an older SHA than master is a regression.
- **`py` vs `py312` rule (hard rule, no exceptions):** For the bare Python test environment (no Django suffix), always use `toxenv: [py]` in the CI matrix — never `py312` or any version-specific name. The `python-version` matrix entry drives the interpreter; `py` lets tox resolve the right env automatically. Named envs like `django42`, `lint`, `docs` are unaffected — only the bare Python test env must be `py`.
- **Codecov `if:` condition must match the actual toxenv name** — if the matrix uses `py`, the condition is `matrix.toxenv == 'py'`; if it uses `django52`, it's `matrix.toxenv == 'django52'`. Never leave a stale `py312` or `django52` reference when the matrix uses a different name.
- Keep any `env:` variables or step conditions from master's CI (e.g. `DJANGO_SETTINGS_MODULE`)
- If master's CI checked branch protection under specific job names, the new `name:` field on the matrix job must match exactly — check with repo owner before changing
- If master had no Codecov step, do not add one
- Do not add an `actions/setup-python` step — `astral-sh/setup-uv` handles Python installation via `python-version`
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
        uses: python-semantic-release/python-semantic-release@SHA_VERSION # TODO: Update master version or latest version
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          git_committer_name: "github-actions"
          git_committer_email: "actions@users.noreply.github.com"
          changelog: "false"

      - name: Upload to GitHub Release Assets
        uses: python-semantic-release/publish-action@SHA_VERSION # TODO: Update master version or latest version
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
        uses: pypa/gh-action-pypi-publish@VERSION # TODO: Use Numeric or SHA whatever present on the master
        # No user/password — OIDC trusted publisher. Configure on PyPI before merging.
```

Get the current SHA for `pypa/gh-action-pypi-publish`:
```bash
gh api repos/pypa/gh-action-pypi-publish/git/ref/heads/release/v1 --jq '.object.sha'
```

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

#### 3.4 — Delete CHANGELOG.rst

python-semantic-release publishes via GitHub Releases (`changelog: "false"`), making CHANGELOG.rst redundant.

```bash
git rm CHANGELOG.rst
```

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

# Delete only for PyPI repos (Phase 3):
git rm CHANGELOG.rst 2>/dev/null || true

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

# --- Check 1: fail-fast must be true in CI ---
echo "--- Check 1: fail-fast ---"
if grep -q 'fail-fast: false' .github/workflows/ci.yml 2>/dev/null; then
  echo "FAIL: ci.yml has fail-fast: false — must be true"
else
  echo "OK: fail-fast is not false"
fi

# --- Check 2: toxenv must not use bare py3XX in CI matrix ---
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

# Find Codecov condition
codecov_match = re.search(r"if:\s*matrix\.toxenv\s*==\s*['\"]([^'\"]+)['\"]", content)
if codecov_match:
    condition_toxenv = codecov_match.group(1)
    if condition_toxenv not in toxenv_values:
        print(f"FAIL: Codecov condition references '{condition_toxenv}' but matrix has {toxenv_values}")
    else:
        print(f"OK: Codecov condition '{condition_toxenv}' matches matrix entry")
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

echo "======= END PRE-PR VALIDATION ======="
```

**All `FAIL:` lines must be resolved before creating the PR.** Do not proceed to Step 6 until the validation output contains only `OK:` and `SKIP:` lines.

---

### Checklist before opening the PR

- [ ] All metadata migrated from setup.cfg/setup.py to pyproject.toml
- [ ] `dependencies` is a static list in `[project]`
- [ ] MANIFEST.in asset patterns migrated to `[tool.setuptools.package-data]`
- [ ] Dependency groups created with exact parity to master's .in files
- [ ] `[tool.edx_lint].uv_constraints` set; `edx_lint write_uv_constraints` run; `[tool.uv].constraint-dependencies` populated
- [ ] `uv.lock` committed
- [ ] `requirements/` deleted
- [ ] `tox.ini` uses `tox-uv>=1`, `uv-venv-lock-runner`, tox envs call `make` targets
- [ ] Makefile `upgrade` → `edx_lint write_uv_constraints` + `uv lock --upgrade`
- [ ] Makefile `requirements` → `uv sync --group dev` + `uv tool install tox --with tox-uv`
- [ ] No Makefile targets dropped (except pip-compile targets) and none renamed; `*.py` glob change documented if removed
- [ ] CI uses `astral-sh/setup-uv`, `uv sync --group ci`, `uv run tox`, named `ci.yml`
- [ ] CI uses `fail-fast: true`
- [ ] CI toxenv matrix uses `py` (not `py312`) for the bare Python test env
- [ ] Codecov `if:` condition references the exact toxenv name used in the matrix
- [ ] All actions SHA-pinned; no SHA is older than what master used
- [ ] **pylint/isort/pycodestyle retained in quality group — no ruff introduced**
- [ ] `pylintrc`/`pylintrc_tweaks` still exist on disk
- [ ] `make lint` exits 0
- [ ] `make test` exits 0
- [ ] `uv lock --check` exits 0
- [ ] **Step 5a pre-PR validation: zero `FAIL:` lines**
- [ ] Coverage thresholds match master (no invented `fail_under`)
- [ ] `__version__` removed from package source (or replaced with importlib.metadata)
- [ ] **PyPI repos:** `release.yml` + `commitlint.yml` added; `CHANGELOG.rst` deleted; `[tool.semantic_release]` in pyproject.toml; zero-version guard only if 0.x; `## Important Notes` flags OIDC trusted publisher config required
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
- **Deleted files line:** list only entries marked `DELETED:` in Step 1 — not `KEPT:` and not `NOT ON MASTER:`. Include `.coveragerc` only if it existed on master. Include `CHANGELOG.rst` only if `release.yml: PRESENT`. Never list `pylintrc`/`pylintrc_tweaks` (they are kept this cycle).
- **Removed Makefile targets table:** populate from the `=== Targets removed ===` list only. Any target in `=== Targets kept ===` must not appear here, even if its implementation was rewritten. Include a specific reason per row.
- **Updated Makefile targets table:** include only if targets were updated (not removed). Omit the section entirely if no targets changed.
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

**Deleted files:** `setup.py`, `setup.cfg`, `requirements/`[, `.coveragerc` ← only if existed on master][, `CHANGELOG.rst` ← only if release gate passed]

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

Run **all** tests from the [Test suite](#test-suite--tests-10360), in order, Test 10 through Test 360.

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
| Test#210 | PR description completeness | ⏭️ Skipped (gated — run explicitly to check PR description) | |
| Test#220 | src/ layout | ✅ Pass | (PyPI repo) package under src/<pkg> — OR — (non-PyPI repo) flat layout retained, documented in PR |
| Test#290 | No action version downgrades | ✅ Pass | all PR-modified workflows use versions ≥ main |
| Test#300 | CI toxenv uses `py` not `py312` | ✅ Pass | no bare version-specific toxenv entries |
| Test#310 | No empty codecov.yml introduced | ✅ Pass | |
| Test#320 | Tox env names unchanged | ✅ Pass | all master tox env names preserved |
| Test#330 | tox commands invoke make targets | ✅ Pass | |
| Test#340 | Dependency groups use include-group | ✅ Pass | all -r references use include-group |
| Test#350 | Makefile targets run tools directly | ✅ Pass | |
| Test#360 | isort style unchanged | ✅ Pass | — OR — ⏭️ Skipped (no isort config on master) |

## Failure details

### Test#40 — Lockfile consistency
<evidence + what would fix it>
```

If Test 10 halts, the table lists Test#10 as `🛑 Halt` and every other row as `⏭️ Skipped (halted at Test 10 — ruff present)`, followed by the halt instructions.

---

## Test suite — Tests 10–360

All tests must be run as part of a verification report (Test/Verify mode). **Test 10 is a hard gate — if it fails, halt.**

**Test groups** (tests are numbered in order of execution, not by group):

| Group | Tests | What they check |
|---|---|---|
| Entry gate (run first) | 10 | Ruff absent everywhere |
| Python version | 260 | Python < 3.12 removed from tox, CI, classifiers |
| Package structure and files | 90, 130, 220, 310 | Stale files deleted; `__version__` removed; src/ layout correct; no empty codecov.yml introduced |
| Package build | 30, 70, 80 | Build output complete; package imports; setuptools-scm runtime (PyPI) |
| Dependency management | 40, 50, 160, 170, 270, 340 | Lockfile in sync; groups resolve; all packages migrated; constraints; static deps; `-r` refs use include-group |
| Versioning | 240 | Versioning strategy: setuptools-scm (PyPI) or static version (no-PyPI), including 0.x guard |
| Quality tooling | 230, 280, 360 | Mypy retained (if used); quality group has original linters; isort style unchanged |
| Tox configuration | 60, 320, 330 | tox.ini parses; all envs resolve; no env renamed; commands invoke make targets |
| Makefile | 20, 140, 350 | Targets exit 0; no target dropped without reason; targets run tools directly (not via tox) |
| GitHub Actions and CI | 100, 150, 180, 250, 290, 300 | YAML valid; branch protection preserved; CI-first + OIDC in release.yml; `uv run tox`; no action version downgrades vs main; toxenv uses `py` not `py312` |
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

```bash
uv run python -m build
ls dist/
```

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
- Deleted files (`setup.py`, `setup.cfg`, `CHANGELOG.rst`) appear in the tarball — they should not be included after deletion.
- The source package directory is missing or empty.
- Static assets that existed before the migration are absent — their absence will break installs.

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

**Pass:** PR tarball contains all required files; no deleted file reappears; PR wheel contains the full package with static assets, `METADATA` present, no `.pyc` files; no regressions vs main in either tarball or wheel.

**Fail:** Any deleted file reappears in the tarball; source package directory missing or empty; static assets absent from tarball or wheel; any file present in main missing from PR (regression).

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

### Test 130 — No `__version__` in package source

```bash
grep -rn '__version__' --include='*.py' .
```

Any match in the package source (not in tests or build tooling) is a failure. Remove it, or replace with the `importlib.metadata` pattern if genuinely needed at runtime.


### Test 90 — No stale files on disk

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

Any `STALE:` line or `REGRESSION:` line is a failure. Note: `CHANGELOG.rst` counts as `STALE` only on PyPI repos (release gate passed); for no-PyPI repos it must be kept.

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

For each changed workflow file, check for un-pinned references — **excluding org-internal reusable workflow calls**:

```bash
git diff master...HEAD --name-only -- '.github/workflows/*.yml' '.github/workflows/*.yaml' \
  | xargs grep -E 'uses:\s+\S+@' \
  | grep -v '@[0-9a-f]\{40\}' \
  | grep -v '^#' \
  | grep -v 'uses:\s\+openedx/\.github/'
```

**Pass:** No un-pinned third-party action references in any workflow file added or modified by the PR.

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
- Any target missing without a documented reason is a regression

**CI parity:**

```bash
grep -A5 'toxenv:' .github/workflows/ci.yml  # or python-tests.yml
```

Every tool that ran in the old CI must run in the new CI toxenv matrix.


### Test 160 — Dependency package parity

Run from the repo root (requires Python 3.11+ for `tomllib`):

```bash
python3 << 'PYEOF'
import re, subprocess, tomllib

# Tools legitimately removed by this migration (replaced by uv).
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

print("Step 1 — Overall parity:")
print("  MISSING from PR (in master .in files but not in pyproject.toml):")
for p in sorted(missing): print(f"    MISSING: {p}")
if not missing: print("    (none — all packages accounted for)")

print("  ADDED in PR (not in any master .in file):")
for p in sorted(added): print(f"    ADDED: {p}")
if not added: print("    (none)")

print(f"\n  Master total: {len(master_pkgs)} | PR total: {len(pr_pkgs)}")
if missing:
    raise SystemExit(f"\nFAIL: {len(missing)} package(s) missing from pyproject.toml")

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
    print(f"\nStep 2 — {in_filename} vs [dependency-groups.{group_name}]:")
    for p in sorted(missing_from_group):
        print(f"  MISSING: {p}  (in master {in_filename} but absent from {group_name} group)")
    for p in sorted(extra_in_group):
        print(f"  EXTRA:   {p}  (in {group_name} group but not in master {in_filename})")
    if not missing_from_group and not extra_in_group:
        print(f"  (ok — exact parity)")
    step2_failures.extend(missing_from_group)
    step2_failures.extend(extra_in_group)

if step2_failures:
    raise SystemExit(f"\nFAIL: {len(step2_failures)} package(s) with group parity violations")
PYEOF
```

**Pass:** No `MISSING:` or `EXTRA:` lines printed, exit code 0.

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
        print("FAIL: no-PyPI repo has setuptools-scm in build-system.requires — remove it")
    if has_scm_config:
        print("FAIL: no-PyPI repo has [tool.setuptools_scm] section — remove it")
    if not version:
        print("FAIL: no-PyPI repo missing static version in [project]")
    elif 'version' in dynamic:
        print("FAIL: no-PyPI repo should not have dynamic version")
    elif not has_scm and not has_scm_config:
        print(f"OK: no-PyPI repo has static version = {version!r}")
PYEOF
```

**Pass:** `setuptools` has no version specifier; PyPI repos use setuptools-scm with `dynamic = ["version"]`; 0.x repos have the zero-version guard; 1.x+ repos do not. No-PyPI repos use a static `version` field with no `setuptools-scm` present.

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

### Test 300 — CI toxenv uses `py` for test envs (not `py312` or other version-specific name)

Feanil's rule (mockprock #66): using `py` in the toxenv matrix is more resilient — when `python3.14` is added to `python-version` later, only the `python-version` row needs updating, not `toxenv` too. Bare `py3XX` entries cause a mismatch: the CI might try to run `py312` tests inside a `python3.14` environment.

Named envs like `lint`, `docs`, `quality`, `django42` are unaffected — only bare Python-version test envs (`py312`, `py311`, etc.) are wrong.

```bash
python3 << 'PYEOF'
import re, glob

failures = []
for wf_path in glob.glob('.github/workflows/*.yml') + glob.glob('.github/workflows/*.yaml'):
    try:
        content = open(wf_path).read()
    except FileNotFoundError:
        continue
    # Find bare py3XX entries (e.g., py312) NOT followed by a dash (py312-django42 is a legitimate matrix env name)
    for m in re.finditer(r'\bpy3\d{1,2}\b(?![-\w])', content):
        surrounding = content[max(0, m.start()-300):m.end()+50]
        if 'toxenv' in surrounding or 'matrix' in surrounding:
            failures.append(f"{wf_path}: bare toxenv entry '{m.group(0)}' found — use 'py' instead so python-version matrix drives the interpreter")
            break

if failures:
    for f in failures:
        print(f"FAIL: {f}")
else:
    print("OK: no bare version-specific toxenv entries (e.g. py312) in CI matrix")
PYEOF
```

**Pass:** CI toxenv matrix contains no bare `py3XX` entries for test runs. Named envs (`lint`, `django42`, etc.) are fine.

**Fail:** Any toxenv matrix entry matches `py3XX` without a framework suffix (e.g., `py312`, `py311`) — signals the Python version is hardcoded in two places and will break when the matrix is updated.

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

```bash
python3 << 'PYEOF'
import subprocess, re, tomllib

def parse_r_refs(content):
    refs = []
    for line in content.splitlines():
        m = re.match(r'^-r\s+(\S+?)\.in\s*(?:#.*)?$', line.strip())
        if m:
            refs.append(m.group(1))
    return refs

def get_include_groups(group_deps):
    includes = set()
    for dep in group_deps:
        if isinstance(dep, dict) and 'include-group' in dep:
            includes.add(dep['include-group'])
    return includes

with open('pyproject.toml', 'rb') as f:
    data = tomllib.load(f)

dep_groups = data.get('dependency-groups', {})
failures = []

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
    for ref in r_refs:
        if ref not in pr_includes:
            failures.append(
                f"[dependency-groups.{group_name}] missing {{include-group = \"{ref}\"}} "
                f"— master's {group_name}.in has '-r {ref}.in' which must become an include-group entry, not inlined packages"
            )

if failures:
    for f in failures:
        print(f"FAIL: {f}")
else:
    print("OK: all -r references in .in files are represented as include-group entries")
PYEOF
```

**Pass:** Every `-r X.in` in any master `.in` file is represented as `{include-group = "X"}` in the corresponding dependency group.

**Fail:** A `-r X.in` reference was flattened — the packages from `X.in` were inlined directly into the group rather than using `{include-group = "X"}`.

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
