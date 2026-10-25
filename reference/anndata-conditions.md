# Condition conventions

Developer notes for raising errors and warnings inside the package.

## Arguments

- message:

  Message in cli style, interpolated in `.envir`.

- class:

  Specific subclass, added after the generic one is prepended.

- ...:

  Further fields stored in the condition.

- call:

  The call reported by the condition, by default the function that
  called the wrapper.

- .envir:

  Environment used to interpolate `message`.

## Details

All conditions go through
[`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html) and
[`cli::cli_warn()`](https://cli.r-lib.org/reference/cli_abort.html) via
the internal wrappers `anndata_abort()` and `anndata_warn()`. Every
condition has class `anndata_error` or `anndata_warning`, a specific
subclass named for the situation, and the `rlang_error` or
`rlang_warning` class added by cli. Tests check classes rather than
message text.

Python's categories map to these classes:

|  |  |
|----|----|
| Python | R class |
| `ImplicitModificationWarning` | `anndata_implicit_modification_warning` |
| `FutureWarning` | `anndata_future_warning` |
| `IORegistryError` | `anndata_io_registry_error` |
| shape mismatch | `anndata_dimension_error` |
| feature in a later sub-project | `anndata_not_supported_error` |
| values do not fit an On-disk dtype | `anndata_dtype_overflow_error` |
| dataset is not an integer or float | `anndata_dtype_error` |

A Python `logger.warning` call becomes an `anndata_warning` subclass
named for the situation too, and `logger.info` is signalled as the
(silent unless handled) condition `anndata_info_message`. A Python
`UserWarning` becomes an `anndata_warning` subclass named for the
situation (e.g. `anndata_names_not_unique_warning`), and any other
Python error becomes an `anndata_error` subclass named likewise. Use the
named constructors (`abort_dimension()`, `abort_io_registry()`,
`abort_not_supported()`, `warn_implicit_modification()`,
`warn_future()`) for the classes above and `anndata_abort()` or
`anndata_warn()` for new ones.
