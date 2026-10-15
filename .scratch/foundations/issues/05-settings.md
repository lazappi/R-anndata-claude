# Settings

Status: done
Type: task
Blocked by: 04

## What

Implement `anndata_settings`, `with_anndata_settings()` and `local_anndata_settings()` as specified in the "Settings" section of `.scratch/foundations/spec.md`, with the six MVP settings and their Python defaults.

- Values are stored as options named `anndata.claude.<setting>`
- Reading a setting whose option is unset returns the default
- Assignment validates types and allowed values and raises a classed error on invalid values (including unknown setting names)
- `reset()` restores every default
- Scoped overrides restore previous values on exit, even on error
- `print(anndata_settings)` lists the settings, their values and descriptions
- The help page documents each setting (with the Python description) and why `copy_on_write_X` and `use_sparse_array_on_read` are omitted

## Acceptance criteria

- Tests for get, set, validation errors by class, reset, scoped override (including nesting and error exit), interaction with `options()`, and printing (snapshot test)
- Exported functions are fully documented with runnable examples
- `scripts/check.sh` passes

## Comments

- 2026-10-15: Implemented `R/settings.R` with tests and a print snapshot. `anndata_settings` is an S3 environment whose active bindings are added in `.onLoad()`, because active bindings do not survive installation. `$<-` and `[[<-` methods give classed errors (`anndata_invalid_setting_error`) for unknown names. Scoped overrides use `on.exit` via `do.call` (withr is only in Suggests and `rlang::defer` is not exported). `scripts/check.sh` now runs `pkgload::load_all()` before linting so `object_usage_linter` sees internals from other files.

## References

- Python `src/anndata/_settings.py:9-73`
