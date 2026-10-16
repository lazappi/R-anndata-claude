#' Rec-arrays
#'
#' Reads and writes the Element `rec-array`, version 0.2.0, a structured
#' (compound) dataset such as scanpy's `rank_genes_groups` results in `uns`.
#'
#' The R value is a `data.frame` with the extra class `anndata_rec_array`
#' (made by `new_rec_array()`), which keeps the field names, field order and
#' field values.
#'
#' **Deviation from Python:** rhdf5 cannot inspect or build the fields of a
#' compound type, so field dtypes are not preserved (ADR 0005).
#' Reading turns integer fields of any width into `integer` (or `double` when
#' they do not fit, read through `bit64conversion = "double"`), floats into
#' `double`, `u1` fields into `integer`, booleans into `logical` and fixed or
#' variable-length strings into `character`.
#' Writing produces int32, float64 and fixed-length string fields, the only
#' ones rhdf5's compound writer supports.
#' String fields are sized to the longest value in bytes, and logical and `raw`
#' fields are written as int32.
#' Python reads the result with the same field names, order and values, but
#' not the same field dtypes.
#' Integer and string fields cannot hold `NA`, so writing one raises
#' `anndata_io_registry_error`, as does a rec-array with no rows.
#' Python's `anndata` decodes fixed-length strings as ASCII and fails to read
#' any other text, so a string field with non-ASCII text also raises
#' `anndata_io_registry_error` rather than write a file Python cannot read.
#' Non-ASCII text is read without problems.
#' Rec-arrays are never compressed, so `dataset_kwargs` has no effect on them.
#' Integers of 2^53 or more raise `anndata_dtype_overflow_error` on read.
#'
#' @param x A `data.frame`.
#' @param store An open rhdf5 file or group handle.
#' @param key Name of the Element within `store`.
#' @param value A rec-array made by `new_rec_array()`.
#' @param dataset_kwargs A list of dataset creation options.
#' @param path Path of the Element.
#'
#' @name io-rec-array
#' @keywords internal
NULL

rec_array_class <- "anndata_rec_array"

#' @rdname io-rec-array
new_rec_array <- function(x) {
  if (!is.data.frame(x)) {
    class <- class(x)
    anndata_abort(
      "{.arg x} must be a {.cls data.frame}, not {.cls {class}}.",
      "anndata_invalid_value_error"
    )
  }
  class(x) <- c(rec_array_class, "data.frame")
  x
}

# The field as an int32, float64 or character vector, the types rhdf5 writes
rec_array_field <- function(field, name, path, call) {
  field <- drop_dtype(field)
  if (is.factor(field)) {
    field <- as.character(field)
  } else if (is.raw(field) || is.logical(field)) {
    field <- as.integer(field)
  }
  supported <- is.integer(field) || is.double(field) || is.character(field)
  if (!supported) {
    abort_unwritable(
      path,
      paste0(
        "field \"",
        name,
        "\" has the unsupported class ",
        class(field)[[1L]]
      ),
      call
    )
  }
  if (!is.double(field) && anyNA(field)) {
    abort_unwritable(
      path,
      paste0("field \"", name, "\" contains missing values"),
      call
    )
  }
  # anndata decodes fixed-length strings as ASCII, so it cannot read others
  if (is.character(field) && anyNA(iconv(field, "UTF-8", "ASCII"))) {
    abort_unwritable(
      path,
      paste0(
        "field \"",
        name,
        "\" has non-ASCII text, which anndata cannot read from a ",
        "fixed-length string field"
      ),
      call
    )
  }
  if (is.double(field)) {
    # `NA_real_` and `NaN` are both written as a plain NaN
    field[is.na(field)] <- NaN
  }
  as.vector(field)
}

#' @rdname io-rec-array
write_rec_array <- function(store, key, value, dataset_kwargs, path) {
  call <- rlang::caller_env()
  fields <- names(value)
  if (anyDuplicated(fields) > 0L || anyNA(fields) || any(fields == "")) {
    abort_unwritable(path, "its field names must be unique and not empty", call)
  }
  if (length(fields) == 0L || nrow(value) == 0L) {
    abort_unwritable(path, "it has no fields or no rows", call)
  }
  columns <- lapply(seq_along(fields), function(i) {
    rec_array_field(.subset2(value, i), fields[[i]], path, call)
  })
  names(columns) <- fields
  frame <- structure(
    columns,
    class = "data.frame",
    row.names = seq_len(nrow(value))
  )
  table_write(store, key, frame)
  invisible(NULL)
}

# Fields rhdf5 reads into R types that Python treats differently
rec_array_read_field <- function(field) {
  if (is.factor(field)) {
    as.character(field) == "TRUE"
  } else if (is.raw(field)) {
    as.integer(field)
  } else {
    as.vector(field)
  }
}

read_rec_array_elem <- function(elem, path, store) {
  call <- rlang::caller_env()
  info <- array_info(store, path)
  if (as.integer(info$rank) != 1L) {
    abort_io_registry(
      "Cannot read {.path {path}}, a rec-array must be one-dimensional.",
      path = path,
      call = call
    )
  }
  values <- table_read(store, path, call)
  fields <- lapply(values, rec_array_read_field)
  frame <- structure(
    fields,
    class = c(rec_array_class, "data.frame"),
    row.names = seq_len(nrow(values))
  )
  frame
}

register_writer(rec_array_class, "rec-array", "0.2.0", write_rec_array)
register_reader("rec-array", "0.2.0", read_rec_array_elem)
