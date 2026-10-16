#' Nullable arrays
#'
#' Reads and writes the Elements `nullable-integer`, `nullable-boolean` and
#' `nullable-string-array` (all version 0.1.0), groups holding `values` and a
#' boolean `mask`.
#'
#' R writes the nullable Element for the values Python writes it for:
#' - an `integer`, `logical` or `character` vector with `NA`
#' - a value read from a nullable Element, which keeps the `anndata_nullable`
#'   record (see [dtype-records]) so that it is written back as the same
#'   Element when it holds no `NA`
#'
#' A plain `character` vector without `NA` is a `string-array` and a `double`
#' vector is never nullable, because Python has no nullable float encoding.
#' Integer values keep their On-disk dtype, so `nullable-integer` of `int64` is
#' read as `double` with an `int64` record.
#' The `na-value` attribute of `nullable-string-array` is `"NaN"` for new
#' values and is restored from the record otherwise.
#'
#' With the setting `allow_write_nullable_strings` set to `FALSE`, a `character`
#' vector without `NA` is written as a `string-array` and one with `NA` raises
#' `anndata_nullable_strings_error`, as Python raises a `ValueError`.
#'
#' @param value The R value, with its records.
#' @param kind The Encoding type to write.
#' @inheritParams io-registry
#'
#' @name io-nullable
#' @keywords internal
NULL

int_dtypes <- grep("^u?int", numeric_dtypes, value = TRUE)

# The nullable Encoding type `value` is written as, or NULL when it is not
nullable_kind <- function(value, plain) {
  record <- get_nullable(value)
  if (length(dim(plain)) > 1L) {
    return(NULL)
  }
  switch(
    typeof(plain),
    # A `FALSE` record marks a string read from a plain `string-array`
    character = if (anyNA(plain) || !is.null(record) && !isFALSE(record)) {
      "nullable-string-array"
    },
    logical = if (anyNA(plain) || !is.null(record)) "nullable-boolean",
    integer = if (anyNA(plain) || !is.null(record)) "nullable-integer",
    # Only an int64 or other integer dtype record makes a double an integer
    double = if (
      !is.null(record) && isTRUE(get_dtype(value)[[1L]] %in% int_dtypes)
    ) {
      "nullable-integer"
    }
  )
}

abort_nullable_strings <- function(path, call) {
  anndata_abort(
    c(
      "Cannot write {.path {path}}, it is a character vector with missing
       values.",
      "x" = "The setting {.field allow_write_nullable_strings} is
             {.val FALSE}.",
      i = "Set it to {.val TRUE} or remove the missing values."
    ),
    "anndata_nullable_strings_error",
    path = path,
    call = call
  )
}

#' @rdname io-nullable
write_nullable <- function(
  store,
  key,
  value,
  kind,
  dataset_kwargs,
  path,
  call
) {
  plain <- drop_dtype(value)
  na <- is.na(plain)
  na_value <- "NaN"
  if (kind == "nullable-string-array") {
    if (isFALSE(anndata_settings$allow_write_nullable_strings)) {
      if (any(na)) {
        abort_nullable_strings(path, call)
      }
      write_elem(store, key, as_array(plain), dataset_kwargs, call)
      return(invisible(NULL))
    }
    if (identical(get_nullable(value), "NA")) {
      na_value <- "NA"
    }
  }

  group <- group_create(store, key)
  on.exit(node_close(group), add = TRUE)
  filler <- switch(
    kind,
    "nullable-string-array" = "",
    "nullable-boolean" = FALSE,
    0L
  )
  # Python writes the filler under the mask, and a record must survive it
  # without the nullable record, which would make the write recurse
  values <- copy_dtype(plain, value)
  values[na] <- filler
  write_elem(group, "values", as_array(values), dataset_kwargs, call)
  write_elem(group, "mask", as_array(as.vector(na)), dataset_kwargs, call)
  set_elem_attr(group, "encoding-type", kind)
  set_elem_attr(group, "encoding-version", "0.1.0")
  if (kind == "nullable-string-array") {
    set_elem_attr(group, "na-value", na_value)
  }
  invisible(NULL)
}

# Reads `values` and `mask` of a nullable group, with `NA` where the mask is set
read_nullable_parts <- function(path, store, call) {
  values <- read_elem(store, paste0(path, "/values"))
  mask <- as.vector(read_elem(store, paste0(path, "/mask")))
  if (length(values) != length(mask)) {
    abort_io_registry(
      "Cannot read {.path {path}}, {.field values} has length
       {length(values)} and {.field mask} has length {length(mask)}.",
      path = path,
      call = call
    )
  }
  dim(values) <- NULL
  values[mask] <- NA
  values
}

read_nullable_elem <- function(elem, path, store) {
  values <- read_nullable_parts(path, store, rlang::caller_env())
  set_nullable(values)
}

read_nullable_string_elem <- function(elem, path, store) {
  values <- read_nullable_parts(path, store, rlang::caller_env())
  # Python defaults to `NA`, and anything but `NaN` means `pd.NA`
  na_value <- if (identical(read_elem_attr(elem, "na-value"), "NaN")) {
    "NaN"
  } else {
    "NA"
  }
  set_nullable(values, na_value)
}

register_reader("nullable-integer", "0.1.0", read_nullable_elem)
register_reader("nullable-boolean", "0.1.0", read_nullable_elem)
register_reader("nullable-string-array", "0.1.0", read_nullable_string_elem)
