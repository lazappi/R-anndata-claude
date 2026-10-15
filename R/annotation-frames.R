#' Annotation frame helpers
#'
#' Internal helpers that turn user input into the `S4Vectors::DataFrame` held
#' in obs and var (ADR 0003).
#' Accepted input is `NULL`, a named list, a `data.frame` or a `DataFrame`.
#' A list may give the index in an `obs_names`/`row_names` (or
#' `var_names`/`col_names`) element.
#'
#' The row names of the result are the obs_names or var_names.
#' They are character and may contain duplicates and `NA`.
#' The index name is kept in `S4Vectors::metadata()` under `index_name`, and is
#' read from the same place on a `DataFrame` or from the `index_name` attribute
#' of a `data.frame`.
#'
#' @param anno The input value.
#' @param attr Either `"obs"` or `"var"`.
#' @param expected The number of rows required, or `NULL` to take it from the
#'   input.
#' @param source What fixed the length, `"X"` or `"shape"`, used in the error
#'   message.
#' @param names Names of observations or variables.
#' @param call The call reported by conditions.
#'
#' @name anndata-annotation-frames
#' @keywords internal
NULL

index_elements <- list(
  obs = c("obs_names", "row_names"),
  var = c("var_names", "col_names")
)

frame_index_name <- function(df) {
  S4Vectors::metadata(df)[["index_name"]]
}

with_index_name <- function(df, name) {
  S4Vectors::metadata(df)[["index_name"]] <- name
  df
}

# Sets row names without the checks that reject `NA` and duplicates
with_frame_names <- function(df, names) {
  df@rownames <- names
  df
}

# Default names are "0" ... "n-1", as Python's `RangeIndex(0, n).astype(str)`
default_names <- function(n) {
  as.character(seq_len(n) - 1L)
}

# Python warns for any non-string index, which includes the default integer
# index of a data frame
as_names <- function(x, call) {
  if (is.character(x)) {
    return(unname(x))
  }
  warn_implicit_modification("Transforming to str index.", call = call)
  unname(as.character(x))
}

abort_frame_length <- function(source, attr, expected, actual, call) {
  what <- paste0(if (attr == "obs") "row" else "column", "s")
  if (source == "X") {
    message <- c(
      "Observations annot. {.field {attr}} must have as many rows as
       {.field X} has {.val {what}} ({expected}), but has {actual} rows."
    )
  } else {
    message <- c(
      "{.arg shape} is inconsistent with {.field {attr}} ({actual}
       {.val {what}} instead of {expected})"
    )
  }
  abort_dimension(message, what = what, call = call)
}

#' @rdname anndata-annotation-frames
as_annotation_frame <- function(
  anno,
  attr = c("obs", "var"),
  expected = NULL,
  source = c("X", "shape"),
  call = rlang::caller_env()
) {
  attr <- rlang::arg_match(attr)
  source <- rlang::arg_match(source)
  if (is.null(anno)) {
    anno <- list()
  }
  if (methods::is(anno, "DataFrame") || is.data.frame(anno)) {
    return(frame_from_frame(anno, attr, expected, source, call))
  }
  if (is.list(anno)) {
    return(frame_from_list(anno, attr, expected, source, call))
  }
  anndata_abort(
    c(
      "Cannot convert {.cls {class(anno)}} to {.field {attr}} data frame.",
      "i" = "Use {.code NULL}, a named list, a {.cls data.frame} or a
        {.cls DataFrame}."
    ),
    "anndata_unsupported_value_error",
    call = call
  )
}

frame_from_list <- function(anno, attr, expected, source, call) {
  candidates <- index_elements[[attr]]
  index_name <- candidates[candidates %in% names(anno)][1L]
  if (length(anno) > 0L && !all(nzchar(names(anno) %||% ""))) {
    anndata_abort(
      "{.field {attr}} given as a list must be fully named.",
      "anndata_unsupported_value_error",
      call = call
    )
  }
  has_index <- !is.na(index_name)
  columns <- anno[setdiff(names(anno), index_name)]
  if (has_index) {
    names <- as_names(anno[[index_name]], call)
    n <- length(names)
  } else {
    n <- expected %||% (if (length(columns)) NROW(columns[[1L]]) else 0L)
  }
  actual <- vapply(columns, NROW, integer(1))
  if (any(actual != n)) {
    abort_frame_length(source, attr, n, actual[actual != n][[1L]], call)
  }
  if (!is.null(expected) && expected != n) {
    abort_frame_length(source, attr, expected, n, call)
  }
  # Python replaces the index with default names when the length is open
  if (is.null(expected) || !has_index) {
    names <- default_names(n)
  }
  df <- methods::new(
    "DFrame",
    listData = if (length(columns)) {
      columns
    } else {
      structure(list(), names = character())
    },
    nrows = as.integer(n),
    rownames = names
  )
  df
}

frame_from_frame <- function(anno, attr, expected, source, call) {
  n <- nrow(anno)
  if (!is.null(expected) && expected != n) {
    abort_frame_length(source, attr, expected, n, call)
  }
  index_name <- if (is.data.frame(anno)) {
    attr(anno, "index_name", exact = TRUE)
  } else {
    frame_index_name(anno)
  }
  names <- rownames(anno)
  if (is.null(names) || (is.data.frame(anno) && automatic_row_names(anno))) {
    names <- seq_len(n) - 1L
  }
  names <- as_names(names, call)
  # A DataFrame may already hold `NA` row names, which `DataFrame()` rejects
  df <- if (is.data.frame(anno)) {
    S4Vectors::DataFrame(anno, check.names = FALSE)
  } else {
    anno
  }
  df <- with_frame_names(df, names)
  S4Vectors::metadata(df) <- list()
  with_index_name(df, index_name)
}

automatic_row_names <- function(df) {
  .row_names_info(df) < 0L
}

#' @rdname anndata-annotation-frames
warn_names_not_unique <- function(attr, call = rlang::caller_env()) {
  anndata_warn(
    c(
      "{if (attr == 'obs') 'Observation' else 'Variable'} names are not unique.
       To make them unique, call {.code {attr}_names_make_unique()}."
    ),
    "anndata_names_not_unique_warning",
    attr = attr,
    call = call
  )
}

#' @rdname anndata-annotation-frames
check_names_unique <- function(names, attr, call = rlang::caller_env()) {
  names <- names[!is.na(names)]
  if (anyDuplicated(names) > 0L) {
    warn_names_not_unique(attr, call = call)
  }
  invisible(names)
}
