## Committing

- You are allowed to commit as needed in this project
- You should acknowledge yourself on commits. When working as an autonomous agents, always do this.
- Each commit should be an atomic unit of work
- This project uses gitmoji commits, do not use conventional commits
- Keep commit messages clear and brief

## Agent skills

### Issue tracker

Issues are tracked as local markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` plus `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Specifications

- Start at `.scratch/roadmap/spec.md`, which lists the sub-projects and their order
- Python anndata 0.13.4 is the only reference, fetch it with `scripts/fetch-reference.sh` (to `.reference/anndata/`)

## Ralph loop

- Development runs as a Ralph loop: `scripts/ralph.sh` feeds `PROMPT.md` to a fresh `claude -p` run per item in `fix_plan.md`
- Loop runs use `ralph/settings.json` (Sonnet, no plugins, project subagents only, no edits to specs, ADRs or loop config)
- Project subagents are defined in `.claude/agents/`: `searcher` and `checker` (Haiku), and `python-oracle` and `reviewer` (Sonnet)
- Create a `STOP` file at the root to stop the loop after the current run
- Versions use tidyverse-style development numbers (`0.0.0.9000`), bumped by one and tagged `v<version>` only when a ticket is done

## Build, test and learnings

Kept brief and current by the loop.

- `scripts/fetch-reference.sh` fetches the Python reference to `.reference/anndata/`
- `scripts/check.sh` is the full check that must pass before every commit, and `scripts/check.sh --quick <test files>` is for use during development (`--quick` takes test file paths and lints only changed R files)
- The full check fails on any NOTE (`error_on = "note"`) and sets `_R_CHECK_SYSTEM_CLOCK_=false` itself
- `LICENSE` needs `ORGANIZATION` as well as `COPYRIGHT HOLDER`, otherwise check gives a note
- Placeholder `@importFrom` lines in `R/anndata.claude-package.R` silence the unused-Imports note, remove each once real code uses that package
- `air.toml` and `.lintr` exist, check with `air format --check .` and `lintr::lint_package()`
- `R CMD check` gives a NOTE "unable to verify current time" unless `_R_CHECK_SYSTEM_CLOCK_=false` is set, so always set it.
  Never treat a NOTE as acceptable.
- The full check's document step fails if `man/` is new or changed, so run it once (it writes the files) then rerun
- Matrix classes: use `Matrix::t()` (base `t()` misses the S4 method in tests) and `as(x, "lMatrix")` (`as(x, "lgCMatrix")` is deprecated)
- `DataFrame` rejects `NA` row names via `rownames<-` and `DataFrame(row.names=)`, so set them with `with_frame_names()` (slot assignment), and the index name is kept in `metadata(df)$index_name`
- Variables only used inside cli `{}` strings trip `object_usage_linter`, so compute values inline or pass them as condition fields
- `AnnData` is `AnnDataClass` (R6, `R/anndata.R`) wrapped by `AnnData()`: roxygen needs `@noRd` on the class, `@importFrom R6 R6Class` stays in the package file and `.lintr` allows the names `AnnData`, `AnnDataClass` and `X`
- S3 methods for `$`, `[[` and similar need a plain `@export` tag (`@exportS3Method` breaks roxygen), and `R CMD check` needs `devtools::document()` to have registered them in `NAMESPACE`
- Inside R6 classes with custom `$` methods use `.subset2()` and `private`, not `self$`, and `adata$obsm[["k"]] <- v` assigns the mapping back to the active binding, so it must ignore an identical value
- Active bindings in package-level objects are lost on install, so create them in `.onLoad()`
- Snapshots are only written by `scripts/check.sh --quick`, because `R CMD check` runs in a temp copy
- Lint runs after `pkgload::load_all()` so cross-file internals are visible to `object_usage_linter`
- Fixtures are regenerated with `scripts/regenerate-fixtures.sh` (cases registered in `tests/python/generate_fixtures.py`), and a test checks they match a fresh generation, so recommit them when a case changes
- rhdf5 gotchas are in `.scratch/h5ad-io/rhdf5-spike.md`: read with `native = TRUE`, and use the low-level `H5D`/`H5A` API because high-level writes add `rhdf5-NA.OK` attributes and gzip
- `.scratch/h5ad-io/encoding-table.md` has a generated block: after changing an encoding case, run `uv run --project tests/python python -I tests/python/encoding_table.py tests/testthat/fixtures .scratch/h5ad-io/encoding-table.md`, because a test checks it is current
- Python is only used through `uv run --project tests/python ...`, in tests via `run_python()` which sets a private `TMPDIR` (uv lock files left in the check temp dir cause a NOTE)
