#' Rec-arrays
#'
#' Reads and writes the Element `rec-array`, version 0.2.0, a structured
#' (compound) dataset such as scanpy's `rank_genes_groups` results in `uns`.
#'
#' The R value is a `data.frame` with the extra class `anndata_rec_array`
#' (made by `new_rec_array()`), which keeps the field names, field order and
#' field values.
#'
#' Field dtypes are kept (ADR 0008, the field types come from a compiled
#' helper because rhdf5 cannot see or build compound types).
#' A field read from HDF5 or zarr carries an On-disk dtype record, unless it
#' has the R type, and writing restores it.
#' Integer fields are read as `integer` (or `double` when they do not fit)
#' with the record `"uint8"`, `"int64"` and so on, `f4` fields as `double`
#' with the record `"float32"`, and booleans as `logical`.
#' Strings are `character`, with the record `"h5_fixed_ascii:<bytes>"`,
#' `"h5_fixed_utf8:<bytes>"` or `"h5_vlen_ascii"` unless they are
#' variable-length UTF-8 as h5py writes text (zarr records
#' `"<type>:<length_bytes>"`).
#' Fields without a record are written as int32, float64, bool and
#' variable-length UTF-8 strings, which Python reads with any text.
#' A recorded string width is widened when the text no longer fits, and a
#' fixed-length or ASCII record becomes variable-length UTF-8 for non-ASCII
#' text, as does a fixed-length UTF-8 record, because anndata cannot read
#' either as a fixed-length field.
#' Integer and string fields cannot hold `NA`, so writing one raises
#' `anndata_io_registry_error`.
#' A rec-array with no rows is written, and `compression = "gzip"` in
#' `dataset_kwargs` compresses an HDF5 rec-array (zarr uses `compressors`).
#' **Deviation from Python:** `"lzf"` is not available to the helper, so an
#' HDF5 rec-array is written uncompressed under it.
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

# The field as an integer, double, logical or character vector, keeping its
# On-disk dtype record
rec_array_field <- function(field, name, path, call) {
  record <- get_dtype(field)
  field <- drop_dtype(field)
  if (is.factor(field)) {
    field <- as.character(field)
  } else if (is.raw(field)) {
    field <- as.integer(field)
  }
  supported <- is.integer(field) ||
    is.double(field) ||
    is.character(field) ||
    is.logical(field)
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
  if (is.double(field)) {
    # `NA_real_` and `NaN` are both written as a plain NaN
    field[is.na(field)] <- NaN
  }
  field <- as.vector(field)
  if (is.null(record)) field else set_dtype(field, record)
}

#' @rdname io-rec-array
write_rec_array <- function(store, key, value, dataset_kwargs, path) {
  call <- rlang::caller_env()
  fields <- names(value)
  if (anyDuplicated(fields) > 0L || anyNA(fields) || any(fields == "")) {
    abort_unwritable(path, "its field names must be unique and not empty", call)
  }
  if (length(fields) == 0L) {
    abort_unwritable(path, "it has no fields", call)
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
  table_write(store, key, frame, dataset_kwargs, call)
  invisible(NULL)
}

# Fields rhdf5 reads into R types that Python treats differently
rec_array_read_field <- function(field) {
  if (is.factor(field)) {
    as.character(field) == "TRUE"
  } else if (is.raw(field)) {
    as.integer(field)
  } else {
    record <- get_dtype(field)
    field <- as.vector(field)
    if (is.null(record)) field else set_dtype(field, record)
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
  values <- table_read(store, path, call, records = TRUE)
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
