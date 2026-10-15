# Foundations

Status: ready-for-agent

Sub-project 1 of the roadmap (`.scratch/roadmap/spec.md`).
It sets up everything that later sub-projects build on: the package skeleton, development tooling, settings, condition classes and the Python round-trip test harness.

## Scope

In:

- Package skeleton and metadata
- Development tooling and a single check script
- The settings system
- Condition (error and warning) helpers and class conventions
- The Python reference environment, fixture generation and round-trip test helpers

Out:

- Any `AnnData` behaviour (`core-object`)
- Any encoding logic (`h5ad-io`)
- CI configuration (added when the repository moves to GitHub)

## Package skeleton

- Package name `anndata.claude`, at the repository root
- Created and maintained with usethis conventions
- `DESCRIPTION`:
  - `Depends: R (>= 4.3)`
  - `License: BSD_3_clause + file LICENSE`, with the copyright holder as the package authors and an acknowledgement of the Python anndata authors in `LICENSE.md` and the README
  - `Config/testthat/edition: 3`, `Encoding: UTF-8`, `Roxygen: list(markdown = TRUE)`
  - Imports at least `R6`, `Matrix`, `S4Vectors`, `rhdf5`, `cli`, `rlang` and `lifecycle`.
    Add others only when a ticket needs them.
  - Suggests at least `testthat (>= 3.0.0)`, `withr`, `knitr`, `rmarkdown` and `covr`
- `.Rbuildignore` excludes `.scratch`, `.reference`, `.remember`, `docs`, `scripts`, `CONTEXT.md`, `CLAUDE.md` and other non-package files
- `README.md` (or `README.Rmd`) explains the package goal and its relationship to Python anndata 0.13.4
- One R file per concern, and internal helpers are not exported
- Every exported function has roxygen2 documentation with runnable `@examples`
- A vignette (in `h5ad-io`, once there is something to show) covers creating an object, h5ad I/O and Python round trips

## Tooling

- Formatting with `air` (`air.toml` at the root), with every file formatted
- Linting with `lintr` (`.lintr` at the root), using the default linters except where a documented reason applies
- Coverage measured with `covr`, with a target of at least 90% line coverage across the package
- `lifecycle` badges mark features that upstream marks experimental or deprecated
- `scripts/check.sh` runs these in order and fails on the first failure:
  1. `air format --check .`
  2. `lintr::lint_package()` (fails on any lint)
  3. `devtools::document()`, then fail if documentation files changed
  4. `devtools::check()` with no errors, warnings or notes
  5. Coverage report (printed, not enforced, until the MVP is complete)
- `scripts/fetch-reference.sh` already exists and fetches the reference implementation

## Settings

Mirror Python's `anndata.settings` (`src/anndata/_settings.py:9-73`).

- An exported `anndata_settings` object exposes each setting as a field: `anndata_settings$check_uniqueness` reads it and `anndata_settings$check_uniqueness <- FALSE` sets it
- Values are stored as R options named `anndata.claude.<setting>`, so `options()` and `withr::local_options()` also work
- Setting a value validates its type and allowed values, and invalid values raise a classed error
- `anndata_settings$reset()` restores the defaults (equivalent to `settings.reset`)
- `with_anndata_settings(new, code)` and `local_anndata_settings(new, .local_envir)` provide scoped overrides, equivalent to `settings.override` and following withr conventions
- Printing `anndata_settings` lists every setting with its current value and a one-line description

Settings in the MVP, with Python defaults:

| Setting | Default | Notes |
| ------- | ------- | ----- |
| `remove_unused_categories` | `TRUE` | |
| `check_uniqueness` | `TRUE` | |
| `allow_write_nullable_strings` | `NULL` | `NULL` behaves as Python with pandas 3 (`infer_string` is true) |
| `disallow_forward_slash_in_h5ad` | `TRUE` | |
| `write_csr_csc_indices_with_min_possible_dtype` | `FALSE` | |
| `restrict_index_types` | `TRUE` | |

Later sub-projects add their own settings (`zarr_write_format` and `auto_shard_zarr_v3` in `zarr-io`, and `min_rows_for_chunked_h5_copy` in `backed`).
`copy_on_write_X` (deprecated and always on upstream) and `use_sparse_array_on_read` (no scipy sparray distinction in R) are omitted, which is documented in the settings help page.
R-specific settings are only added when a ticket needs one.

## Conditions

- All errors and warnings raised by the package go through `cli::cli_abort()` and `cli::cli_warn()`, or a thin internal wrapper around them
- Every condition has the class `anndata_error` or `anndata_warning`, plus a specific subclass
- Python's named warning categories map to R classes:
  - `ImplicitModificationWarning` maps to `anndata_implicit_modification_warning`
  - `FutureWarning` maps to `anndata_future_warning`
  - A Python `UserWarning` maps to an `anndata_warning` subclass named for the situation (e.g. `anndata_names_not_unique_warning`)
- A Python error maps to an `anndata_error` subclass named for the situation (e.g. `anndata_io_registry_error` for `IORegistryError`, `anndata_dimension_error` for shape mismatches)
- Messages keep the meaning and key details of the Python message (names, shapes, keys) but are written in cli style
- A test helper asserts the class of a condition, and tests check classes rather than message text, except where the text is part of the spec

## Python reference environment

- A uv project at `tests/python/` (`pyproject.toml` and committed `uv.lock`) pins `anndata==0.13.4`, `pandas>=3`, and current `h5py`, `numpy` and `scipy`
- The environment is used only through `uv run --project tests/python <script>` subprocesses, never through reticulate
- Python scripts live in `tests/python/` and exchange data only through files and JSON on stdout

Scripts:

- `h5_tree.py <file>` prints a JSON description of every group and dataset in an HDF5 file: path, kind, attributes (with their stored types), dtype, shape and a value digest.
  This is the authority for Structural equivalence.
- `compare.py <a.h5ad> <b.h5ad>` reads both files with anndata and checks them with `anndata.tests.helpers.assert_equal` (`src/anndata/tests/helpers.py:620`), exiting non-zero with the difference on failure
- `generate_fixtures.py <outdir>` writes the committed fixture files (the set of cases is defined in `h5ad-io`)
- Further scripts are added by the sub-projects that need them

## R test helpers

In `tests/testthat/helper-*.R`:

- `skip_if_no_python()` skips when `uv` is not on the `PATH` or the environment variable `ANNDATA_SKIP_PYTHON` is `true`
- `run_python(script, ...)` runs a script in the reference environment and returns its stdout, failing the test with stderr on a non-zero exit
- `expect_structurally_equivalent(a, b)` compares the `h5_tree.py` output of two files and reports the differing paths
- `expect_python_equal(a, b)` runs `compare.py`
- `fixture_path(name)` returns the path to a committed fixture

Committed fixtures live in `tests/testthat/fixtures/` so that the main test suite runs offline.
Tests that need live Python are skipped cleanly when it is unavailable, and always run in `scripts/check.sh` when `uv` is present.
`scripts/regenerate-fixtures.sh` regenerates the fixtures from the reference environment.

## Acceptance criteria

- `scripts/check.sh` passes on a fresh clone after `scripts/fetch-reference.sh`, with the package containing only foundations code
- `anndata_settings` behaves as described, with tests for get, set, validation, reset and scoped override
- A smoke test writes a tiny HDF5 file from Python, then runs `h5_tree.py` and `compare.py` from R through the helpers
- The skip helpers are tested by running the suite with `ANNDATA_SKIP_PYTHON=true`, which must pass with skips and no failures
- README, LICENSE and DESCRIPTION are complete
