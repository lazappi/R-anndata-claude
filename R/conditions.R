#' Condition conventions
#'
#' Developer notes for raising errors and warnings inside the package.
#'
#' All conditions go through [cli::cli_abort()] and [cli::cli_warn()] via the
#' internal wrappers `anndata_abort()` and `anndata_warn()`.
#' Every condition has class `anndata_error` or `anndata_warning`, a specific
#' subclass named for the situation, and the `rlang_error` or `rlang_warning`
#' class added by cli.
#' Tests check classes rather than message text.
#'
#' Python's categories map to these classes:
#'
#' | Python | R class |
#' | ------ | ------- |
#' | `ImplicitModificationWarning` | `anndata_implicit_modification_warning` |
#' | `FutureWarning` | `anndata_future_warning` |
#' | `IORegistryError` | `anndata_io_registry_error` |
#' | shape mismatch | `anndata_dimension_error` |
#' | feature in a later sub-project | `anndata_not_supported_error` |
#' | values do not fit an On-disk dtype | `anndata_dtype_overflow_error` |
#' | dataset is not an integer or float | `anndata_dtype_error` |
#'
#' A Python `logger.warning` call becomes an `anndata_warning` subclass named
#' for the situation too, and `logger.info` is signalled as the (silent unless
#' handled) condition `anndata_info_message`.
#' A Python `UserWarning` becomes an `anndata_warning` subclass named for the
#' situation (e.g. `anndata_names_not_unique_warning`), and any other Python
#' error becomes an `anndata_error` subclass named likewise.
#' Use the named constructors (`abort_dimension()`, `abort_io_registry()`,
#' `abort_not_supported()`, `warn_implicit_modification()`, `warn_future()`) for
#' the classes above and `anndata_abort()` or `anndata_warn()` for new ones.
#'
#' @param message Message in cli style, interpolated in `.envir`.
#' @param class Specific subclass, added after the generic one is prepended.
#' @param ... Further fields stored in the condition.
#' @param call The call reported by the condition, by default the function that
#'   called the wrapper.
#' @param .envir Environment used to interpolate `message`.
#'
#' @name anndata-conditions
#' @keywords internal
NULL

anndata_abort <- function(
  message,
  class,
  ...,
  call = rlang::caller_env(),
  .envir = parent.frame()
) {
  cli::cli_abort(
    message,
    class = c(class, "anndata_error"),
    ...,
    call = call,
    .envir = .envir
  )
}

anndata_warn <- function(
  message,
  class,
  ...,
  call = rlang::caller_env(),
  .envir = parent.frame()
) {
  cli::cli_warn(
    message,
    class = c(class, "anndata_warning"),
    ...,
    call = call,
    .envir = .envir
  )
}

abort_dimension <- function(
  message,
  ...,
  call = rlang::caller_env(),
  .envir = parent.frame()
) {
  anndata_abort(
    message,
    "anndata_dimension_error",
    ...,
    call = call,
    .envir = .envir
  )
}

abort_io_registry <- function(
  message,
  ...,
  class = NULL,
  call = rlang::caller_env(),
  .envir = parent.frame()
) {
  anndata_abort(
    message,
    c(class, "anndata_io_registry_error"),
    ...,
    call = call,
    .envir = .envir
  )
}

abort_not_supported <- function(
  message,
  ...,
  class = NULL,
  call = rlang::caller_env(),
  .envir = parent.frame()
) {
  anndata_abort(
    message,
    c(class, "anndata_not_supported_error"),
    ...,
    call = call,
    .envir = .envir
  )
}

warn_implicit_modification <- function(
  message,
  ...,
  call = rlang::caller_env(),
  .envir = parent.frame()
) {
  anndata_warn(
    message,
    "anndata_implicit_modification_warning",
    ...,
    call = call,
    .envir = .envir
  )
}

#' Warn that a method is deprecated, as Python's `@deprecated` does
#' (a `FutureWarning`, so the class also has `anndata_future_warning`).
#' @noRd
warn_deprecated <- function(method, advice, call = rlang::caller_env()) {
  anndata_warn(
    # Braces in the Python advice must not be interpolated by cli
    gsub(
      "([{}])",
      "\\1\\1",
      paste0(
        "The method `",
        method,
        "` is deprecated and will be removed in the future. ",
        advice
      )
    ),
    c("anndata_deprecated_warning", "anndata_future_warning"),
    method = method,
    call = call
  )
}

warn_future <- function(
  message,
  ...,
  call = rlang::caller_env(),
  .envir = parent.frame()
) {
  anndata_warn(
    message,
    "anndata_future_warning",
    ...,
    call = call,
    .envir = .envir
  )
}
