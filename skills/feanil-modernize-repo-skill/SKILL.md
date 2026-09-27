---
disable-model-invocation: true
name: feanil-modernize-repo-skill
description: >
  Reviewer's playbook for the Python-modernization class of Open edX PRs (uv + pyproject.toml
  + python-semantic-release, epic public-engineering#506). Encodes the standard, decisions already
  made (do not re-litigate), the "does the wheel that comes out match the one that went in" check,
  the full checklist, known failure modes, and Feanil's review voice. Use ONLY when explicitly
  invoked with /feanil-modernize-repo-skill — do not auto-trigger.
allowed-tools: Read Glob Grep Bash Write Edit
---

# Reviewing Python-modernization PRs (public-engineering#506)

One guide for a class of PRs that lands in many repos and has to be checked for the
same things every time. The epic is
[openedx/public-engineering#506](https://github.com/openedx/public-engineering/issues/506),
"Modernize Python repos: pyproject.toml + uv + semantic-release". The Axim
Aximprovements team (salman2013, farhan, irfanuddinahmad) opens the PRs;
Feanil reviews and merges. Read this before step 1 of the workflow on any PR whose
title says modernize / uv / pyproject / semantic-release, and extend it at the end of
each one. Per-PR evidence goes in `<repo>-<number>-python-modernization.md`.

## What the standard is

Three phases per repo, straight from the issue body:

1. **Metadata into `pyproject.toml`** (PEP 621): `[project]` with a static
   `dependencies` list, `setuptools-scm` for the version from git tags,
   `setup.py`/`setup.cfg` deleted.
2. **pip-compile to uv**: PEP 735 `[dependency-groups]` (`test-base`, `test`,
   `quality`, `doc`, `ci`, `dev`, plus version-matrix groups), one committed `uv.lock`,
   `requirements/` deleted, `tox.ini` on `tox-uv`'s `uv-venv-lock-runner` with
   `dependency_groups`, Makefile on `uv lock`/`uv sync`, CI on `astral-sh/setup-uv` +
   `uv sync --group ci` + `uv run tox`. Constraints come from
   `edx_lint write_uv_constraints` ([edx-lint#537](https://github.com/openedx/edx-lint/pull/537),
   merged 2026-04-27): `[tool.uv].constraint-dependencies` is machine-written, repo
   overrides go in `[tool.edx_lint].uv_constraints`.
3. **semantic-release**: `[tool.semantic_release]` with a `build_command` that sets
   `SETUPTOOLS_SCM_PRETEND_VERSION`, a `release.yml` that runs CI then publishes to
   PyPI via OIDC, a `commitlint.yml`, and the PyPI trusted publisher configured.

**References, in the order to trust them:**

- The reference implementation is `openedx/sample-plugin`, and the files live under
  **`backend-plugin-sample/`**, not `backend/` as the issue body says (it was renamed;
  the `backend/` paths 404). `backend-plugin-sample/{pyproject.toml,tox.ini,Makefile}`,
  `.github/workflows/{ci.yml,backend-ci.yml,release.yml,commitlint.yml}`. Two things
  in it are deliberately **not** for other repos: `[tool.setuptools_scm] root = ".."`
  (the package is in a subdirectory) and `minor_tags = ["feat", "docs"]` (it wants
  releases on docs changes). It also carries `exclude-newer = "7 days"` and
  Renovate-driven `>=0` floors, which the issue does not ask for; treat those as
  sample-plugin choices until Feanil says otherwise.
- `openedx/xblocks-extra` is the second reference the team cites (farhan on
  xblocks-core#251 for `[dependency-groups]` shape and tooling).
- Merged real repos to compare against: `openedx/XBlock` (#914), `openedx/xblocks-core`
  (#251), `openedx/event-tracking` (#425), `openedx/DoneXBlock` (#388),
  `openedx/xblock-sdk` (#519), `openedx/RecommenderXBlock` (#136). XBlock's
  `pyproject.toml`, `tox.ini`, `ci.yml` and `release.yml` are the cleanest single-package
  example.
- [OEP-67](https://github.com/openedx/openedx-proposals/pull/784) merged 2026-05-07:
  `oeps/best-practices/oep-0067-bp-tools-and-technology.rst` and the ADR
  `oeps/best-practices/oep-0067/decisions/backend/0001-uv.rst`. OEP-18 was archived by
  the same PR.
- sample-plugin's comments point at
  `https://docs.openedx.org/en/latest/developers/how-tos/manage-uv-dependency-matrix.html`
  for the multi-Django matrix pattern (`conflicts` in `[tool.uv]`). Not yet fetched here.

## Decisions already made (do not re-litigate in a review)

From the 2026-07-15 meeting, written up by farhan on the issue, plus later threads:

- **OIDC trusted publishing, not `PYPI_UPLOAD_TOKEN`.** The implementation side must
  name the workflow `release.yml` (publisher entries are keyed on the filename). A PR
  whose `release.yml` still uses a stored token is behind the standard, even though
  xblocks-core#251 merged that way before the decision. **The PyPI side is done for
  every org repo** (Feanil, 2026-09-23), so the review does not raise it;
  irfanuddinahmad's 2026-07-15 checklist on the issue predates that. Verification is
  the first release run after merge, see the `release.yml` section.
- **Ruff is out of scope.** Pylint stays. Any ruff config, dependency or formatting
  churn in a modernization PR should be reverted or split out.
- **Scope is any repo with a `setup.py`**, PyPI-published or not. Non-PyPI repos get
  phases 1 and 2; whether they get `release.yml` is per repo.
- **`src/` layout is in scope** for this cycle (precedent xblocks-core, xblocks-extra).
- **Add `tox.ini` where missing.**
- **Keep the Makefile targets** (`upgrade`, `requirements`, `quality`, `test`, ...) and
  point them at uv equivalents rather than deleting them (farhan on DoneXBlock#388).
- **Zero-version semver** (kdmccormick on the issue): on `0.x` repos `feat`/`feat!`
  bump minor and `fix`/`perf` bump patch; on `1.x+` the usual major/minor/patch. That
  is `allow_zero_version = true` + `major_on_zero = false`. **Feanil, 2026-09-23:
  required on every `0.x` repo; harmless and acceptable on a `1.x+` repo.** So: a
  finding when a `0.x` repo lacks them, not a finding when a `3.0.0` repo has them
  (farhan's DoneXBlock#388 comment asking for their removal was stricter than needed).
- **No `CHANGELOG.rst`, and PSR's changelog stays off** (`changelog: "false"` in
  `release.yml`, no `[tool.semantic_release.changelog]` block). **Feanil, 2026-09-23:
  a PR that merges with the changelog enabled usually breaks the release and has to be
  rolled back.** That happened on xblocks-extra: #70 enabled it 2026-08-20 and #71
  reverted it the same day. Catch it in review; anchor on the `changelog:` line or
  the new file.
- **`exclude-newer`** (sample-plugin's 7-day cooling-off window) is part of the
  standard going forward but **does not need to ship in the modernization PR**
  (Feanil, 2026-09-23). Not a finding either way.
- **No new `codecov.yml`** unless the repo already had one (Feanil on DoneXBlock#388;
  irfanuddinahmad reached the same conclusion on opaque-keys#461).
- **`__version__`** stays available for compatibility but comes from
  `importlib.metadata.version("<dist-name>")`, not a hardcoded string (Feanil on
  DoneXBlock#388). The `try/except PackageNotFoundError` wrapper was dropped on
  i18n-tools#288 to match sample-plugin.

## Where to look first

1. **`gh pr checks`** and the PR's own CI run. Every matrix leg, `quality`, `docs`,
   `commitlint`. A red `docs` env has been the most common miss (DoneXBlock#388:
   `docs` defined in `tox.ini` but not in `envlist` or the CI matrix; XBlock#914:
   `.readthedocs.yml` still pointed at the deleted `requirements/doc.txt`).
2. **What the repo published last.** `pip download --no-deps --no-binary :all:
   <dist>==<latest>` (or the wheel) gives the old metadata and file list; the review's
   strongest check is the diff of that against what the branch builds (below).
3. **The tags.** `git tag --list` on the primary clone: bare `X.Y.Z` or `vX.Y.Z`? PSR
   defaults `tag_format` to `v{version}`; a repo with bare tags either sets
   `tag_format = "{version}"` or plans a bridging release (opaque-keys#461 went the
   second way, and DoneXBlock has *both* `3.0.0` and a stray `v3.0.0` on a different
   commit). Whatever PSR would compute as the next version is what actually ships.
4. **The description against the checklist** in the issue body. The PR template the
   team uses mirrors the three phases; tick each box against the diff.

## The review question: does the package that comes out match the one that went in

Everything else is convention. The thing that breaks consumers is a wheel that no
longer carries a data file, an entry point, an extra, or a dependency that
`setup.py` used to declare. So, from the worktree with its own `.venv`:

```bash
uv lock --check                       # lockfile matches pyproject (nothing stale)
uv sync --group ci
uv run tox                            # the matrix as CI runs it
SETUPTOOLS_SCM_PRETEND_VERSION=9.9.9 uv run --with build python -m build
uv run --with twine twine check dist/*
unzip -l dist/*.whl | sort -k4 > new_files.txt
unzip -p dist/*.whl '*/METADATA' > new_metadata.txt
```

and against the last published release:

```bash
pip download --no-deps --dest old/ <dist-name>==<latest>
unzip -l old/*.whl | sort -k4 > old_files.txt
unzip -p old/*.whl '*/METADATA' > old_metadata.txt
diff old_files.txt new_files.txt      # dropped templates/static/locale/data files
diff <(grep -E '^(Requires-Dist|Provides-Extra|Requires-Python)' old_metadata.txt | sort) \
     <(grep -E '^(Requires-Dist|Provides-Extra|Requires-Python)' new_metadata.txt | sort)
unzip -p old/*.whl '*/entry_points.txt'; unzip -p dist/*.whl '*/entry_points.txt'
```

**Build the wheel first and treat a failure as the headline.** On edx-ora2#2423 the build
failed outright and CI was green on every leg, because the only env that builds a wheel
(`docs`) was not in the CI matrix. `python -m build --wheel` is the single highest-value
command in this whole checklist. If it fails, `release.yml` can never publish: PSR 10.6.2
runs `build_command` in `semantic_release/cli/commands/version.py` at line 666, *before*
`git_commit` (712) and `git_tag` (728), deliberately so a failed build commits nothing. So
the failure is clean but total, and it only shows up after merge.

**Two setuptools defaults change what "package data" means, and both bite on this class:**

1. **setuptools-scm registers a `setuptools.file_finders` entry point**
   (`vcs_versioning._file_finders:find_files`) that lists **every git-tracked path**.
2. **`include-package-data` defaults to `true`** under `pyproject.toml` (it defaulted to
   `False` in `setup.py` unless passed).

Together they mean the wheel gets every git-tracked file under a package directory, so
`MANIFEST.in`, `[tool.setuptools.package-data]` and `packages.find`'s `exclude` stop
bounding it. On ora2 that doubled the wheel (466 -> 957 files, 2.6 -> 4.9 MB) with test
fixtures, sass sources and a duplicate locale tree, and a **git-tracked symlink to a
directory** (`openassessment/locale -> conf/locale`) made `build_py` fail outright on
`copy_file`. Check both on any repo that commits data files or symlinks, and note that
`include-package-data = false` is not a safe blanket fix: on ora2 it built but dropped
`openassessment/locale/`, where Django looks for an app's translations.

**A third default compounds them, and the boilerplate `exclude` does not cover it.** The
team's template ships these two blocks together:

```toml
[tool.setuptools.packages.find]
exclude = ["*tests"]

[tool.setuptools.exclude-package-data]
"*" = ["tests*", "*.tests*", "spec*", "*.spec*"]
```

`packages.find` under `pyproject.toml` defaults to **`namespaces = true`**, so every
directory under the package is discovered as a package whether or not it has an
`__init__.py`. `exclude = ["*tests"]` is an fnmatch on the dotted name and only matches
names that *end* in `tests`, so `<pkg>.processors.tests.fixtures.current` survives it and
ships. The `exclude-package-data` block cannot clean up after it: setuptools joins those
patterns onto **each discovered package's own source dir**, so for a fixture package they
come out as `.../tests/fixtures/current/tests*` and match nothing. The block is not inert
(it does catch the test `.py` modules attributed to the real packages, and `*.spec*`
accidentally catches anything with `.spec` in the name, e.g. `edx.special_exam.*.json`),
which is why it looks like it is working.

On event-routing-backends#571 this put **182 test fixture JSON files** into the wheel:
100 files / 118,919 bytes published -> 261 / 261,698 on the branch. The fix is one line,
`exclude = ["*tests*"]`, which is what `openedx/xblocks-core` already merged; `DoneXBlock`'s
`["*.tests*", "tests*"]` works too. Both give byte-identical results. **So: on any repo in
this batch that commits fixture or data directories under the package, grep for
`exclude = ["*tests"]` and build the wheel.** It is not enough to read the config, because
the sibling `exclude-package-data` block makes it read as covered. `event-tracking` merged
with the same line and is fine only because it has no committed data under the package.

To see which packages setuptools actually attributed a file to, monkeypatch in-process
(`build`'s subprocess defeats a patch applied before `python -m build`):

```python
import fnmatch
from setuptools.command import build_py as bp
orig = bp.build_py.exclude_data_files
def patched(self, package, src_dir, files):
    files = list(files)
    pats = list(self._get_platform_patterns(self.exclude_package_data, package, src_dir))
    print(package, src_dir, len(files), pats, file=sys.stderr)
    return orig(self, package, src_dir, files)
bp.build_py.exclude_data_files = patched
import setuptools.build_meta as bm; bm.build_wheel('/tmp/dbgdist')
```

Things this has to answer, and where the answer lives:

- **Dependencies.** Every `install_requires` line from the old `setup.py` (often read
  from `requirements/base.in`) is in `[project].dependencies`, with the same floors
  and markers. Watch for `dynamic = ["dependencies"]` still pointing at a requirements
  file, which the issue calls out as not done.
- **Extras.** `extras_require` → `[project.optional-dependencies]` (XBlock kept its
  `django` extra).
- **Package data.** `MANIFEST.in`, `include_package_data`, `package_data` →
  `[tool.setuptools.package-data]` / `include-package-data`. Static, templates,
  `conf/locale`, `public/`. The wheel file-list diff is the proof.
- **Entry points.** `[project.entry-points."xblock.v1"]`, `lms.djangoapp`,
  `cms.djangoapp`, console scripts. Byte-for-byte against the old
  `entry_points.txt`.
- **`packages.find`.** With `src/` layout, `where = ["src"]`; without it, an `include`
  list that still matches every package (XBlock ships `xblock*` **and**
  `web_fragments*`).
- **Python floor and classifiers.** `requires-python` and the `Programming Language`
  / `Framework :: Django` classifiers match the tox envlist. The issue notes a new
  framework version may force a `requires-python` bump; then the old Python leaves the
  envlist too.
- **Version.** `dynamic = ["version"]`, `[tool.setuptools_scm]` with
  `version_scheme = "only-version"` and `local_scheme = "no-local-version"`,
  `fallback_version = "0.0.0"` (not `0.0.0.dev0`: openedx-events had 17 tests die on
  `tuple(map(int, __version__.split(".")))`). No `root = ".."`. Any hardcoded
  `__version__` replaced per the decision above.
- **License.** SPDX string in `[project].license`, `license-files` glob, and the old
  `License ::` classifier removed (setuptools rejects the pair). Deprecated
  identifiers (`AGPL-3.0` → `AGPL-3.0-only`) came up on DoneXBlock.

## The rest of the checklist

### uv and the lockfile

- `uv.lock` committed and `uv lock --check` clean on the head commit.
- `[dependency-groups]` uses the standard names; `test` includes `test-base`; matrix
  groups (`django42`, `django60`, ...) are listed pairwise in `[tool.uv].conflicts`.
- `default-groups = []` when a `dev` group exists, or `uv sync --group ci` drags the
  whole `dev` superset in (irfanuddinahmad on DoneXBlock#388). XBlock uses
  `package = true` instead; check what the repo needs, not that a line exists.
  **Check the Makefile before asking for this line.** `default-groups = []` makes a
  bare `uv run <tool>` fail, because `uv run` only syncs the default groups:
  ```
  $ uv run tox -e pii_check
  Installed 66 packages in 68ms
  error: Failed to spawn: `tox`
    cause: No such file or directory (os error 2)
  ```
  CI is unaffected because it runs `uv sync --group ci` first, but any Makefile target
  that calls `uv run <tool>` **without** a preceding `uv sync --group <g>` breaks. On
  event-routing-backends#571 that was five targets (`test-all`, `test`, `coverage`,
  `diff_cover`, `pii_check`) against 44 packages saved per CI job, so the comment was
  staged and then withdrawn. The mechanical fix is `uv run --group ci tox -e <env>`,
  verified working, but it makes every target noisier. **Grep the Makefile for
  `uv run` not preceded by `uv sync` before writing this one up**, and price the ask
  honestly: it is install time only, and it is not worth rebuilding a Makefile around.
- `[tool.uv].constraint-dependencies` matches what `edx_lint write_uv_constraints`
  writes today (run it into a scratch copy and diff, the way sample-plugin's
  `make check-constraints` does). Anything repo-specific is in
  `[tool.edx_lint].uv_constraints`, not hand-edited into the managed list.
- `requirements/` gone, and nothing still reads it: `.readthedocs.yaml`, `Makefile`,
  `tox.ini`, `.github/workflows/*.yml`, `docs/conf.py`, `Dockerfile`, `catalog-info.yaml`.
  `grep -rn 'requirements/' --exclude-dir=.git` from the worktree root.
- **`upgrade-python-requirements.yml`** still makes sense. The org's upgrade workflow
  ran `make upgrade` over pip-compile output; with uv it has to produce a `uv.lock`
  diff and the summary comment reviewers depend on (felipemontoya and farhan on the
  issue, 2026-09-17/18). enterprise-catalog#1144 lost the summary because its
  workflow crashed on a nonexistent `team_reviewers` entry, so a green PR is not proof
  the bot works. Check the workflow file and, if the repo is already on uv, its last
  scheduled run.

### tox, Makefile, CI

- `tox.ini`: `requires = tox-uv>=1`, every env on `runner = uv-venv-lock-runner` with
  `dependency_groups`, and `envlist` names every env the CI matrix runs, `docs`
  included.
- Makefile: targets kept, `upgrade` runs `edx_lint write_uv_constraints` then
  `uv lock --upgrade`, `requirements` is `uv sync --group dev`, nothing calls a bare
  `tox`/`pylint`/`twine` that `uv sync` did not put on PATH ("`uv sync` does not put
  tools on PATH. Use `uv run tox`" is in the issue's notes). **Run the targets, don't
  read them.** On event-routing-backends#571 every invocation moved to `uv run` except
  `clean`'s `coverage erase`, which sits above the patch's first changed line and so is
  not in the diff at all; `make clean`, `make test`, `make coverage` and `make
  diff_cover` all died at their first line. `make clean && make test && make quality`
  from a fresh `uv sync --group dev` and no activated venv costs a minute and catches
  exactly this class. Also watch for a target that **inlines a tox env's command list**
  instead of calling `uv run tox -e <env>`: same repo put 15 lines of `docs`/`quality`/
  `pii_check` commands in the Makefile that already exist in `tox.ini`, a second copy to
  keep in sync.
- `ci.yml`: `astral-sh/setup-uv` pinned to a SHA like every other action in the file
  (xblocks-core#251 shipped `@v6`; XBlock master still has `@v7`), `uv sync --group
  ci`, `uv run tox -e <env>` or `TOXENV`. **Static job names**: branch protection
  matches required checks by name, so `name: ${{ matrix.toxenv }}` breaks protection
  (staff-graded-xblock#394 discussion, reverted on openedx-filters#381). `fetch-depth:
  0` is **not** wanted on the test checkout (farhan on DoneXBlock#388: both references
  omit it, `fallback_version` covers it), but **is** wanted on the release checkout.
- `ci.yml` triggers: `pull_request` plus `workflow_call` so `release.yml` can reuse
  it. Whether to also keep `push:` (double-runs on the default branch) has gone both
  ways: opaque-keys#461 restored it at the code owners' request, openedx-filters#381
  left it off. Not worth a comment unless the repo's owners have a view.
- `commitlint.yml` present and calling
  `openedx/.github/.github/workflows/commitlint.yml@master`. Also **run it in your
  head on the PR's own commits**: the team's early PRs had non-conventional titles
  ("Modernize python tooling"), and a red commitlint on the modernization PR itself
  is a bad start for a repo that is about to version itself from commit messages.

### release.yml

Compare line by line with sample-plugin's; XBlock's is the single-package cut of it.

- `on: push: branches: [<default branch>]`; the repo's real default branch (`master`
  on most of these, `main` on newer ones).
- `run_ci` / `run_tests` job `uses: ./.github/workflows/ci.yml` so the release runs the
  same checks a PR does. Copilot flagged on xblocks-core#251 that a reusable workflow
  needing `CODECOV_TOKEN` has to be passed `secrets: inherit`; check whether `ci.yml`
  uses any.
- `release` job: `needs`, `if: github.ref_name == '<branch>'`, `concurrency` with
  `cancel-in-progress: false`, `permissions: contents: write`, checkout at
  `${{ github.ref_name }}` with `fetch-depth: 0`, then `git reset --hard ${{ github.sha }}`.
- PSR action pinned to a SHA (v10.6.2 = `9a026e93…` at time of writing), `changelog:
  "false"`, **`vcs_release: "false"`**, and then the **immutable-releases step**: `gh
  release create "$TAG" --verify-tag --notes-file ... dist/*` creates as draft,
  attaches, publishes. Without `vcs_release: "false"` PSR publishes a release with no
  assets and immutable releases then refuse the upload (farhan on DoneXBlock#388,
  2026-09-02).
- The PSR step gets **`secrets.GITHUB_TOKEN`** (Feanil, 2026-09-23: the org secret is
  not needed going forward). A `release.yml` handing it
  `secrets.OPENEDX_SEMANTIC_RELEASE_GITHUB_TOKEN` gets a comment asking for the
  default token. Two merged repos (XBlock, event-tracking) still use the org secret
  and release fine; that is a cleanup for them, not a reason to accept it in new PRs.
- `upload-artifact` with `if-no-files-found: error`, `download-artifact` in a
  **separate** `publish_to_pypi` job with `permissions: contents: read, id-token:
  write` and `pypa/gh-action-pypi-publish` pinned. No `password:` / token input.
- `[tool.semantic_release]` in `pyproject.toml`: `build_command` sets
  `SETUPTOOLS_SCM_PRETEND_VERSION=$NEW_VERSION`; `tag_format` matches the tag history
  (or a bridging release is planned and named); no `minor_tags` override unless
  justified (XBlock kept `["feat", "docs"]`, which the issue says other repos should
  not); zero-version flags per the open question above.
- **The publisher is done.** Feanil added the PyPI trusted publisher on all the org's
  repos (2026-09-23), so the review does not raise it. Verification is post-merge:
  the first `release.yml` run on the default branch has to publish. **After a
  modernization PR merges, check that run** (`gh api repos/openedx/<repo>/actions/runs
  --jq '.workflow_runs[] | select(.path | test("release.yml"))'`) and that the version
  it tagged is on PyPI, and note the result in the detail file.

### Things that should not be in the diff

- Ruff, black, or a reformatting sweep (out of scope).
- A new `codecov.yml` or `.pre-commit-config.yaml` (see decisions).
- A `CHANGELOG.rst` or `changelog: "true"` / a `[tool.semantic_release.changelog]`
  block. This one breaks the release after merge (xblocks-extra#70 → #71), so it is a
  blocker, not taste.
- Behaviour changes to the package. `git diff --stat origin/<base>...HEAD -- ':!*.lock'`
  should be build/CI/docs files plus the `src/` move. A `src/` move shows as renames;
  `git diff -M --stat` keeps it readable, and `git diff -M origin/<base>...HEAD --
  src/` should be empty apart from `__version__`.
- Django version support changes smuggled in (xblock-lti-consumer#685 dropped
  `django42` mid-PR). Fine if the repo already dropped it; a finding if the matrix
  shrank because the migration made the old version awkward.

## Failure modes seen so far

From the review threads on the PRs opened before this guide existed:

- `docs` env not in `envlist` / not in the CI matrix; `.readthedocs.yaml` pointing at
  a deleted requirements file (DoneXBlock#388, XBlock#914). On edx-ora2#2423 `docs` was in
  `envlist` but not in the CI matrix **and** red on its own first command (105 doc8
  errors), which hid a wheel that did not build. A green RTD check is not cover: RTD runs
  `.readthedocs.yaml`, not the tox env.
- `python -m build --wheel` fails and no CI leg builds a wheel (edx-ora2#2423). See the
  two setuptools defaults under "The review question".
- The wheel grows instead of shrinking. Diff the file lists in both directions; on
  edx-ora2#2423 nothing was dropped and 491 files were added.
- A now-stale release doc. `.github/release_process.md` on edx-ora2 still said to bump
  `openassessment/__init__.py` and hand-create a matching tag. `grep -rln 'setup.py\|
  __init__.py\|release' .github/*.md docs/` before finishing.
- `release.yml` lets PSR create the GitHub release, then the artifact upload fails on
  immutable releases (DoneXBlock#388).
- `id-token: write` removed to "match master" and a stored token kept, against the
  decision (xblocks-core#251, before the decision was made).
- `fallback_version = "0.0.0.dev0"` (openedx-events, DoneXBlock).
- Unpinned `astral-sh/setup-uv@vN` next to SHA-pinned everything else
  (xblocks-core#251; XBlock master still).
- `uv tool install tox` in the Makefile instead of `uv run tox` (xblocks-core#251).
- Ruff declared and configured but never run (DoneXBlock#388).
- `default-groups` left at uv's default with a `dev` group present (DoneXBlock#388).
- `tag_format` default on a repo with bare tags (DoneXBlock#388, opaque-keys#461).
- `fetch-depth: 0` on the CI checkout (DoneXBlock#388).
- `MANIFEST.in` still listing `LICENSE` after `license-files` took over (DoneXBlock#388).
- Matrix job named from `${{ matrix.toxenv }}` (staff-graded-xblock#394,
  openedx-filters#381).
- `authors` set to `edX / oscm@edx.org` vs sample-plugin's `Open edX Project /
  oscm@openedx.org` (opaque-keys#461). Taste; not a finding on its own.

## Delivery notes for this class

- Most anchors are in `pyproject.toml`, `tox.ini`, `Makefile`, `.github/workflows/*`.
  `pyproject.toml` is usually a rewrite (`status: modified` with one big hunk), so walk
  the patch for positions; the workflows are usually `added`, so position = line.
- The same finding recurs across repos. Write it once well in the detail file and
  reuse the wording, but re-verify it per repo: "matrix shrank" or "publisher missing"
  is a fact about that repo, not the class.
- Anchor the OIDC / publisher comment on the `publish_to_pypi` job's `permissions`
  block; the `tag_format` comment on `[tool.semantic_release]`; the wheel-contents
  comment on `[tool.setuptools.package-data]` or `MANIFEST.in`, whichever the diff
  touches.
- The review body should say what was built and diffed (old wheel version, head SHA)
  so the author can reproduce it.

## What Feanil kept and cut on this class

**From edx-ora2#2423 (2026-09-23), the first review through this guide.** He read the
draft summary and said: *"it's fine to drop E, keep the comments short and actionable but
go ahead and post the pending review."* So:

- **Cut the standards-only finding.** `fallback_version = "0.0.0.dev0"` instead of
  `"0.0.0"` went out. It is on the failure-modes list below, but nothing in the repo or in
  openedx-platform reads `__version__`, and the draft said so. **A deviation from the
  standard that changes nothing about what ships is not a finding here.** Check for a
  consumer before writing one up; if there is none, leave it in the detail file.
- **Trim the mechanism, keep the numbers.** The staged comments kept the error text, the
  file:line citations, the measured counts (466 -> 957 files, 2,601,590 -> 4,878,011 bytes)
  and the ask; the derivations went to the detail file. Draft at that length from the start.
- He did not ask to see the comment wording before posting, having read the findings in
  the walkthrough. That is not a general licence: the go-ahead was explicit and per-action.

**From event-routing-backends#571 (2026-09-23), the second review through this guide.** He read
the walkthrough and said *"add all 3 but re-check my voice file, I updated it"*, then *"stage it"*.
So:

- **The three "offered but not staged" items all went in.** On ora2 he cut a standards-only
  finding; here he took every one of the three marginal items. The difference is that all three
  were written as things he could act on and none of them was a standards deviation with no
  consumer: a license expression that changes published metadata, a `permissions` block that
  differs from the reference, and a Makefile carrying a second copy of the tox envs. **Offer the
  marginal ones in the walkthrough rather than dropping them silently**; he decides.
- **The voice file gets re-read every session, not recalled.** He had added five Part 0 rules
  since the ora2 review, three of which changed this draft: hedging stays on a *proposal* while
  findings stay flat, a non-reproduction or a disagreement with the author's analysis is reported
  in the first person and credits what they got right in the second, and the standalone
  "Verified against head X on DATE" stamp comes out when the comment already names the command.
- **Marginal items go out as proposals ending on a question.** "Do you want to change it here, or
  leave the batch consistent and sort it out across repos later?" and "Was there a reason to
  inline them?" That is the register for anything the author is free to decline.
- **He asks what a recommendation means in practice, and that question is worth pre-empting.**
  His follow-up on the Makefile comment was "what does that mean in practice for changes to the
  Makefile?" The comment had named a direction without showing the result. Answering it cost one
  `default-groups = []` comment, which turned out to break five Makefile targets and had to be
  withdrawn, and surfaced a real bug nobody had run into (`make clean`). **Before staging a
  comment that asks for a shape change rather than a one-line edit, write the replacement out and
  run it.** If it is short enough to paste, paste it; a fenced block is right where a
  `suggestion` cannot span the change.

**From openedx-atlas#78 (2026-09-23).** Staged with two comments; he **dropped the
release-workflow split** and submitted the rest. His reason: *"splitting the release
workflow is a bigger change and so it makes sense that they left it out of scope since
the job was already publishing this way previously."*

- **Ask whether the PR creates the condition or only changes its mechanism.** The comment
  argued that dropping `password:` turns on an OIDC token every step in the job can use,
  including an `npx`. True as far as it goes, but that job already held
  `secrets.PYPI_UPLOAD_TOKEN` in its environment, so the set of steps that could publish
  to PyPI did not change. Only the credential did. A property the previous state already
  had is pre-existing, and a modernization PR is not where it gets fixed.
- **Size the ask against the PR.** A restructure into a second job is out of scope for a
  packaging change even when the target shape is right. The retry argument (0.7.1 tagged,
  released and npm-published, then 400'd on upload with no way to re-run just the upload)
  was real and still was not enough on its own.
- The inverse of the "leftovers of the removal" rule under **Writing in Feanil's voice**:
  that rule promotes things *this change* orphaned, and this one demotes things *this
  change* merely inherited. Run both directions before deciding where a finding sits.
- What survived: the dead `[tool.coverage.run]` block, which the PR itself ported forward,
  and the whole review body, including the paragraph answering another reviewer's open
  `CHANGES_REQUESTED`.

**From ccx-keys#190 and enmerkar-underscore#249 (2026-09-23), both submitted with
edits.** He reworded four of the six staged comments and left two untouched. The
general lesson went into the voice file as Part 0 #13-16; what is specific to this
class:

- **`default-groups = []` is off the checklist.** It was staged on three PRs and he
  asked whether it was worth it. Measured on enmerkar-underscore with
  `astral-sh/setup-uv`'s `enable-cache: true`: `uv sync --group ci` takes **0.08s warm
  and 3.43s cold** against 0.07s either way without the dev group, and the cold cache
  is 173M vs 137M. So it is ~3.4s per leg on a lockfile change and nothing otherwise.
  The comment was dropped from opaque-keys#461, i18n-tools#288 and
  enmerkar-underscore#249. Only raise it on a repo whose `setup-uv` has no
  `enable-cache`, and price it before writing it.
- **The `AGPL-3.0` comment survives, but only as one sentence.** Cut the
  `License-Expression:` paste and the comparison against the last release; keep the
  deprecation fact, `LICENSE:<lines>` with the quoted "or any later version" text, and
  the ask.
- **The `changelog: "false"` comment survives without its history.** Drop the PSR
  `action.yml` mechanism and the xblocks-extra #70/#71 rollback; "otherwise the release
  will fail trying to write a changelog to the repo" is the whole justification.
- **The PSR-token comment went out unedited, list of precedent repos and all.** That
  is the shape to reuse verbatim.
- **`publish_to_pypi` missing `contents: read` is a `nit:`,** and argued from the job
  not needing write access, not from what sample-plugin does. Check first whether it
  is load-bearing: event-tracking publishes fine with only `id-token: write`.
- **A reproduction transcript is never the thing he cuts.** The
  `tox -e django42` -> `5.2.17` block came through untouched.

**Findings worth killing by measurement, not writing.** Two of this guide's own checklist
items were wrong for this repo and both took one command:

- `name: ${{ matrix.toxenv }}` breaking branch protection - `gh api
  repos/openedx/<repo>/branches/master/protection --jq .required_status_checks` showed
  ora2 requires only `openedx/cla`. Check protection before writing this one.
- `[tool.uv].constraint-dependencies` drifting from `edx_lint write_uv_constraints` - the
  three missing constraints were not in `uv.lock` at all, so they constrained nothing.
  Grep the lock for each package before calling drift a finding.

What he has written on the team's PRs elsewhere, all short and all imperative:

- "This should be replaced with a `get_version` call and the variable should still be
  set for convenience/compatibility." (DoneXBlock#388, `__init__.py`)
- "I thought we were not going to add changelogs since they can't be updated by
  python-semantic-release the way we have it setup." (DoneXBlock#388)
- "Is this file new or is this config being moved from somewhere else" → "codecov has
  default configuration which is fine in most cases." (DoneXBlock#388, `codecov.yml`)
- "You'll need to update the .readthedocs.yml now that the `doc.txt` file doesn't
  exist anymore." (XBlock#914)

So far: he comments on things that change what ships or what the docs build does, and
on files added without a reason. He has not commented on formatting, group naming or
Makefile wording.

## Open questions

None as of 2026-09-23. Six were raised when the guide was scaffolded and Feanil
settled all of them the same day; the answers are in "Decisions already made" and the
`release.yml` checklist. For the record, the two that were dropped rather than
decided: the `>=0` version-floor form and `exclude-newer` both belong to the later
Renovate project, so neither is a finding on a modernization PR.

## PRs under the epic

`gh search prs --owner openedx "public-engineering/issues/506"` on 2026-09-23. Reviews
done through this guide get a row in the main `CLAUDE.md` Status table and a detail
file; this table is the census.

**Open**

| Repo | PR | Author | Opened | Title |
|---|---|---|---|---|
| opaque-keys | [461](https://github.com/openedx/opaque-keys/pull/461) | irfanuddinahmad | 2026-07-27 | feat: modernize to uv + pyproject.toml + semantic-release |
| openedx-filters | [381](https://github.com/openedx/openedx-filters/pull/381) | irfanuddinahmad | 2026-07-27 | feat: modernize to uv + pyproject.toml + semantic-release |
| openedx-calc | [217](https://github.com/openedx/openedx-calc/pull/217) | irfanuddinahmad | 2026-07-27 | Modernize openedx-calc to uv + pyproject.toml + semantic-release |
| openedx-chem | [161](https://github.com/openedx/openedx-chem/pull/161) | irfanuddinahmad | 2026-07-27 | Modernize openedx-chem to uv + pyproject.toml + semantic-release |
| event-routing-backends | [571](https://github.com/openedx/event-routing-backends/pull/571) | irfanuddinahmad | 2026-07-28 | feat: modernize Python tooling - **reviewed, see below** |
| event-bus-kafka | [349](https://github.com/openedx/event-bus-kafka/pull/349) | irfanuddinahmad | 2026-07-28 | feat: modernize Python tooling |
| openedx-atlas | [78](https://github.com/openedx/openedx-atlas/pull/78) | farhan | 2026-07-28 | build: modernize Python packaging to uv + pyproject.toml |
| i18n-tools | [288](https://github.com/openedx/i18n-tools/pull/288) | farhan | 2026-09-02 | feat: modernize packaging with uv, pyproject.toml and semantic-release |
| codejail-includes | [28](https://github.com/openedx/codejail-includes/pull/28) | farhan | 2026-09-14 | chore: Modernize codejail-includes to use uv and pyproject.toml |
| tutor-contrib-aspects | [1330](https://github.com/openedx/tutor-contrib-aspects/pull/1330) | farhan | 2026-09-21 | build: modernize to uv + pyproject.toml (public-engineering#517) |
| platform-plugin-aspects | [253](https://github.com/openedx/platform-plugin-aspects/pull/253) | farhan | 2026-09-21 | build: migrate to uv + pyproject.toml + python-semantic-release |
| xblock-lti-consumer | [685](https://github.com/openedx/xblock-lti-consumer/pull/685) | salman2013 | 2026-07-14 | Modernize python tooling |
| acid-block | [282](https://github.com/openedx/acid-block/pull/282) | salman2013 | 2026-07-15 | Modernize python tooling |
| staff-graded-xblock | [394](https://github.com/openedx/staff-graded-xblock/pull/394) | salman2013 | 2026-07-15 | Modernize Python repo: pyproject.toml + uv + semantic-release |
| edx-ora2 | [2423](https://github.com/openedx/edx-ora2/pull/2423) | salman2013 | 2026-07-17 | Migrate to modern Python tooling (uv, pyproject.toml, semantic-release) - **reviewed, see below** |

None of these requested Feanil's review as of 2026-09-23 (`--review-requested=@me`
returns only the unrelated #39025, #499, #45, #38637, #1644).

**Merged**

| Repo | PR | Merged | Notes |
|---|---|---|---|
| xblocks-core | [251](https://github.com/openedx/xblocks-core/pull/251) | 2026-05 | first; pre-OIDC decision, ruff split to #267 |
| XBlock | [914](https://github.com/openedx/XBlock/pull/914) | 2026-06 | reference-quality; kept `minor_tags = ["feat","docs"]`, `setup-uv@v7` unpinned |
| DoneXBlock | [388](https://github.com/openedx/DoneXBlock/pull/388) | 2026-09 | longest thread; most of the failure-modes list |
| xblock-sdk | [519](https://github.com/openedx/xblock-sdk/pull/519) | | |
| RecommenderXBlock | [136](https://github.com/openedx/RecommenderXBlock/pull/136) | | |
| event-tracking | [425](https://github.com/openedx/event-tracking/pull/425) | | |
| mockprock | [66](https://github.com/openedx/mockprock/pull/66) | 2026-07 | non-PyPI; "pylint retained, no ruff" |
| openedx-webhooks | [440](https://github.com/openedx/openedx-webhooks/pull/440) | 2026-07 | non-PyPI |
| openedx-webhooks-data-schema | [42](https://github.com/openedx/openedx-webhooks-data-schema/pull/42) | 2026-07 | non-PyPI |
| forum | [283](https://github.com/openedx/forum/pull/283) | 2026-07 | Feanil cleared this one himself in the 2026-08 batch |
| xapi-db-load | [258](https://github.com/openedx/xapi-db-load/pull/258) | 2026-07 | same |
| xblocks-extra | [64](https://github.com/openedx/xblocks-extra/pull/64), [69](https://github.com/openedx/xblocks-extra/pull/69), [70](https://github.com/openedx/xblocks-extra/pull/70), [71](https://github.com/openedx/xblocks-extra/pull/71) | 2026-08 | OIDC + SHA pin follow-ups; #70 enabled the changelog and broke the release, #71 rolled it back the same day |

Many July PRs were closed and reopened (farhan's first pass, e.g. codejail#316,
codejail-service#88, credentials-themes#1082, forum#281, enmerkar-underscore#247,
edx-enterprise-data#692); the reopened ones are in the open table where they exist.

## Reviews so far

| Repo | PR | Detail |
|---|---|---|
| edx-ora2 | [2423](https://github.com/openedx/edx-ora2/pull/2423) | [edx-ora2-2423-python-modernization.md](edx-ora2-2423-python-modernization.md) - review `5292220027`, 4 comments, staged 2026-09-23 |
| event-routing-backends | [571](https://github.com/openedx/event-routing-backends/pull/571) | [event-routing-backends-571-python-modernization.md](event-routing-backends-571-python-modernization.md) - review `5292792598`, 6 comments, staged 2026-09-23 (rebuilt from `5292657291`) |
