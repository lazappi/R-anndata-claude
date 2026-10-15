# Condition helpers

Status: done
Type: task
Blocked by: 03

## What

Implement the internal condition conventions from the "Conditions" section of `.scratch/foundations/spec.md`.

- Internal wrappers around `cli::cli_abort()` and `cli::cli_warn()` that always add `anndata_error` or `anndata_warning` plus a specific subclass, and pass `call` through correctly
- Named constructors or documented class names for the Python categories needed early:
  - `anndata_implicit_modification_warning` (`ImplicitModificationWarning`)
  - `anndata_future_warning` (`FutureWarning`)
  - `anndata_io_registry_error` (`IORegistryError`)
  - `anndata_dimension_error`
  - `anndata_not_supported_error`, for features in later sub-projects ("not yet supported")
- A test helper (e.g. `expect_anndata_condition(expr, class)`) that asserts a condition's class
- A short developer note in the package documentation (e.g. an internal roxygen page) listing the class conventions so later tickets use them consistently

## Acceptance criteria

- Unit tests cover each wrapper, class inheritance (`anndata_error` and `rlang_error`), and correct call reporting
- `scripts/check.sh` passes

## References

- Python `src/anndata/_warnings.py` for the warning categories

## Comments

2026-10-15: Added `R/conditions.R` with `anndata_abort()`/`anndata_warn()` and named constructors (`abort_dimension`, `abort_io_registry`, `abort_not_supported`, `warn_implicit_modification`, `warn_future`), plus an internal Rd page `anndata-conditions` listing the class conventions.
All take `call = rlang::caller_env()` and `.envir = parent.frame()`, so the reported call and cli interpolation are the caller's.
`expect_anndata_condition(expr, class)` in `tests/testthat/helper-conditions.R` catches the condition itself, because `expect_condition()` lets a condition of another class propagate instead of failing.
Gotcha: single-file lintr (quick mode) flags internal functions used inside top-level helper functions in test files as undefined, so define such helpers inside `test_that()`.
Reviewer flagged an unrelated uncommitted edit to `CLAUDE.md` ("allowed to acknowledge" to "should acknowledge") that this run did not make, so it was left uncommitted for the human.
