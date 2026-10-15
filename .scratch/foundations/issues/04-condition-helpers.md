# Condition helpers

Status: ready-for-agent
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
