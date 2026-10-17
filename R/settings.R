#' Package settings
#'
#' `anndata_settings` mirrors Python's `anndata.settings`.
#' Each setting is a field that is read with `anndata_settings$name` and set
#' with `anndata_settings$name <- value`.
#' Values are stored as R options named `anndata.claude.<setting>`, so
#' [options()] and [withr::local_options()] work too, and an unset option means
#' the default.
#' Invalid values (and unknown setting names) raise an error of class
#' `anndata_invalid_setting_error`.
#'
#' `anndata_settings$reset()` restores every default.
#' `with_anndata_settings()` and `local_anndata_settings()` override settings
#' temporarily, equivalent to `settings.override` in Python, and restore the
#' previous values on exit even when an error occurs.
#' Printing `anndata_settings` lists each setting, its value and a description.
#'
#' @section Settings:
#' * `remove_unused_categories` (default `TRUE`): Whether or not to remove
#'   unused categories with factors.
#' * `check_uniqueness` (default `TRUE`): Whether or not to check uniqueness of
#'   the `obs` indices on creation of an `AnnData`.
#' * `allow_write_nullable_strings` (default `NULL`): Whether or not to allow
#'   writing of nullable string arrays.
#'   When `NULL` it behaves as Python with pandas 3 (`infer_string` is true).
#'   When `FALSE` explicitly, string arrays are written in the old,
#'   non-nullable format.
#' * `disallow_forward_slash_in_h5ad` (default `TRUE`): Whether or not to
#'   disallow the `/` character in keys for h5ad files.
#' * `write_csr_csc_indices_with_min_possible_dtype` (default `FALSE`): Write a
#'   csr or csc matrix with the minimum possible data type for `indices`, always
#'   unsigned integer.
#' * `restrict_index_types` (default `TRUE`): Whether to force coercion to a
#'   string index upon creation of an `AnnData` or setting `obs`/`var`.
#'   Setting this to `FALSE` allows other index types, but integer indices are
#'   always converted to strings.
#' * `zarr_write_format` (default `3`): The zarr format version that
#'   [write_zarr()] writes.
#'   Writing version 2 is not yet supported and raises
#'   `anndata_not_supported_error`.
#' * `auto_shard_zarr_v3` (default `TRUE`): Whether zarr v3 arrays are sharded
#'   automatically, with a target of 1 GB uncompressed per shard.
#'   An explicit `shards` dataset argument overrides it and it is ignored for
#'   version 2.
#'   Shard shapes can differ from Python's, and rec-arrays are not sharded.
#' * `min_rows_for_chunked_h5_copy` (default `1000`): The least number of rows
#'   read at once when a dense X on disk is copied to a new h5ad file (a
#'   chunked source dataset raises it to its chunk length).
#'   Writing to a compressed dataset copies it chunk by chunk instead.
#'
#' @section Omitted settings:
#' Python's `copy_on_write_X` is deprecated and always on upstream, so it is
#' omitted (copy-on-write is the only behaviour).
#' `use_sparse_array_on_read` is omitted because R has no distinction between
#' scipy sparse matrices and sparse arrays.
#'
#' @param new A named list of settings to override.
#' @param code Code to run with the overridden settings.
#' @param .local_envir The environment whose exit restores the settings.
#'
#' @return `with_anndata_settings()` returns the value of `code`.
#'   `local_anndata_settings()` returns the previous values invisibly.
#'
#' @examples
#' anndata_settings$check_uniqueness
#'
#' with_anndata_settings(list(check_uniqueness = FALSE), {
#'   anndata_settings$check_uniqueness
#' })
#'
#' anndata_settings$check_uniqueness <- FALSE
#' anndata_settings$reset()
#' anndata_settings
#'
#' @name anndata_settings
NULL

setting_flag <- function(x) is.logical(x) && length(x) == 1L && !is.na(x)

setting_specs <- list(
  remove_unused_categories = list(
    default = TRUE,
    valid = setting_flag,
    expected = "`TRUE` or `FALSE`",
    description = "Remove unused categories from factors"
  ),
  check_uniqueness = list(
    default = TRUE,
    valid = setting_flag,
    expected = "`TRUE` or `FALSE`",
    description = "Check uniqueness of obs names on creation"
  ),
  allow_write_nullable_strings = list(
    default = NULL,
    valid = function(x) is.null(x) || setting_flag(x),
    expected = "`TRUE`, `FALSE` or `NULL`",
    description = "Allow writing nullable string arrays (NULL infers it)"
  ),
  disallow_forward_slash_in_h5ad = list(
    default = TRUE,
    valid = setting_flag,
    expected = "`TRUE` or `FALSE`",
    description = "Disallow `/` in keys for h5ad files"
  ),
  write_csr_csc_indices_with_min_possible_dtype = list(
    default = FALSE,
    valid = setting_flag,
    expected = "`TRUE` or `FALSE`",
    description = "Write sparse indices with the minimum unsigned dtype"
  ),
  restrict_index_types = list(
    default = TRUE,
    valid = setting_flag,
    expected = "`TRUE` or `FALSE`",
    description = "Force string indices on creation and when setting obs/var"
  ),
  zarr_write_format = list(
    default = 3L,
    valid = function(x) {
      is.numeric(x) && length(x) == 1L && !is.na(x) && x %in% c(2, 3)
    },
    expected = "`2` or `3`",
    description = "Zarr format version written (2 is not yet supported)"
  ),
  auto_shard_zarr_v3 = list(
    default = TRUE,
    valid = setting_flag,
    expected = "`TRUE` or `FALSE`",
    description = "Shard zarr v3 arrays automatically (not yet written)"
  ),
  min_rows_for_chunked_h5_copy = list(
    default = 1000L,
    valid = function(x) {
      is.numeric(x) && length(x) == 1L && !is.na(x) && x >= 1 && x == trunc(x)
    },
    expected = "a positive whole number",
    description = "Rows copied at once from a backed dense X"
  )
)

setting_option <- function(name) paste0("anndata.claude.", name)

get_setting <- function(name) {
  getOption(setting_option(name), setting_specs[[name]]$default)
}

# Validates before storing so that an invalid value never reaches options()
check_setting <- function(name, value, call = rlang::caller_env()) {
  spec <- setting_specs[[name]]
  if (is.null(spec)) {
    anndata_abort(
      c(
        "Unknown setting {.val {name}}.",
        i = "Settings are {.val {names(setting_specs)}}."
      ),
      "anndata_invalid_setting_error",
      call = call
    )
  }
  if (!spec$valid(value)) {
    anndata_abort(
      paste(
        "Setting {.field {name}} must be {spec$expected},",
        "not {.cls {class(value)}}."
      ),
      "anndata_invalid_setting_error",
      call = call
    )
  }
  invisible(value)
}

set_setting <- function(name, value, call = rlang::caller_env()) {
  check_setting(name, value, call = call)
  opts <- list(value)
  names(opts) <- setting_option(name)
  options(opts)
  invisible(value)
}

# Active bindings do not survive installation (they are saved as plain values),
# so the fields are added when the package loads
populate_settings <- function(env) {
  for (name in names(setting_specs)) {
    local({
      name <- name
      makeActiveBinding(
        name,
        function(value) {
          if (missing(value)) {
            get_setting(name)
          } else {
            set_setting(name, value)
          }
        },
        env
      )
    })
  }
  reset <- function() {
    options(structure(
      vector("list", length(setting_specs)),
      names = setting_option(names(setting_specs))
    ))
    invisible(NULL)
  }
  assign("reset", reset, envir = env)
  lockEnvironment(env, bindings = TRUE)
  invisible(env)
}

#' @rdname anndata_settings
#' @format `anndata_settings` is an environment of class `anndata_settings`.
#' @export
anndata_settings <- structure(
  new.env(parent = emptyenv()),
  class = "anndata_settings"
)

.onLoad <- function(libname, pkgname) {
  populate_settings(anndata_settings)
}

# Environments cannot gain fields, so unknown names must be caught here for a
# classed error rather than the base "locked environment" one
#' @export
`$<-.anndata_settings` <- function(x, name, value) {
  set_setting(name, value)
  x
}

#' @export
`[[<-.anndata_settings` <- function(x, i, value) {
  set_setting(i, value)
  x
}

#' @export
print.anndata_settings <- function(x, ...) {
  cli::cat_line("<anndata_settings>")
  for (name in names(setting_specs)) {
    value <- get_setting(name)
    shown <- if (is.null(value)) "NULL" else format(value)
    cli::cat_line(
      "  ",
      format(name, width = 47L),
      format(shown, width = 6L),
      " ",
      setting_specs[[name]]$description
    )
  }
  invisible(x)
}

#' @rdname anndata_settings
#' @export
local_anndata_settings <- function(new, .local_envir = parent.frame()) {
  if (!is.list(new) || (length(new) > 0L && !rlang::is_named(new))) {
    anndata_abort(
      "{.arg new} must be a named list of settings.",
      "anndata_invalid_setting_error"
    )
  }
  for (name in names(new)) {
    check_setting(name, new[[name]])
  }
  # Read all previous values first, with NULL kept as an unset option
  old <- structure(
    lapply(names(new), function(name) getOption(setting_option(name))),
    names = setting_option(names(new))
  )
  do.call(
    on.exit,
    list(bquote(options(.(old))), add = TRUE),
    envir = .local_envir
  )
  options(structure(new, names = setting_option(names(new))))
  invisible(old)
}

#' @rdname anndata_settings
#' @export
with_anndata_settings <- function(new, code) {
  local_anndata_settings(new)
  code
}
