#' HDF5 backend of the store layer (tables)
#'
#' The `table_read` and `table_write` operations of [io-store] for HDF5, which
#' hold the `rec-array` Element as a compound dataset.
#' rhdf5 cannot see or build the members of a compound type, so the field types
#' come from the compiled helper (ADR 0008, `R/io-compound.R`).
#'
#' Reading with `records = TRUE` records the dtype of each column that is not
#' the R type, as for plain arrays: the numeric name (`"uint8"`, `"float32"`,
#' ...) and for strings `"h5_fixed_ascii:<bytes>"` or `"h5_fixed_utf8:<bytes>"`
#' for a fixed-length string and `"h5_vlen_ascii"` for an ASCII variable-length
#' one.
#' Variable-length UTF-8 is what h5py writes for text, so it has no record.
#' Writing restores the records, and gives fields without one int32, float64,
#' bool and variable-length UTF-8 as h5py does.
#' A string record is overridden when the text does not fit (a fixed width is
#' widened).
#' Fixed-length UTF-8 records and non-ASCII text in a fixed-length field are
#' written as variable-length UTF-8, because anndata fails to read either.
#' Records of zarr are ignored.
#'
#' @param store An open rhdf5 file or group handle.
#' @param key,path Name or path of the dataset.
#' @param frame A `data.frame` of numeric, logical and character columns.
#' @param values The `data.frame` rhdf5 read.
#' @param column,name A column of `frame` and its name.
#' @param dataset_kwargs A list of dataset creation options.
#' @param call The call reported by errors.
#'
#' @name io-store-h5-table
#' @keywords internal
NULL

h5_string_kinds <- c("h5_fixed_ascii", "h5_fixed_utf8", "h5_vlen_ascii")

# The path of a dataset in its file, and the file's path
h5_table_location <- function(store, path) {
  base <- rhdf5::H5Iget_name(store)
  absolute <- if (startsWith(path, "/")) {
    path
  } else {
    paste0(if (identical(base, "/")) "" else base, "/", path)
  }
  list(file = rhdf5::H5Fget_name(store), dataset = absolute)
}

# The dtype name of an integer or float member
h5_member_dtype <- function(class, size, sign) {
  if (class == "float") {
    return(paste0("float", 8L * size))
  }
  paste0(if (identical(sign, "unsigned")) "u" else "", "int", 8L * size)
}

# Adds dtype records to the columns of `values` read by rhdf5
h5_table_records <- function(store, path, values) {
  where <- h5_table_location(store, path)
  # The helper reads the file by path, so rhdf5's writes must be on disk
  rhdf5::H5Fflush(store)
  members <- compound_members(where$file, where$dataset)
  for (i in seq_along(values)) {
    column <- values[[i]]
    if (is.raw(column)) {
      column <- as.integer(column)
    }
    class <- members$class[[i]]
    record <- if (class %in% c("integer", "float")) {
      h5_member_dtype(class, members$size[[i]], members$sign[[i]])
    } else if (class == "string") {
      ascii <- !members$utf8[[i]]
      if (members$variable[[i]]) {
        if (ascii) "h5_vlen_ascii"
      } else {
        paste0(
          if (ascii) "h5_fixed_ascii:" else "h5_fixed_utf8:",
          members$size[[i]]
        )
      }
    }
    values[[i]] <- if (is.null(record) || is.factor(column)) {
      column
    } else {
      record_dtype(column, record)
    }
  }
  values
}

# The `compound_field()` of a column
h5_table_field <- function(column, name, path, call) {
  record <- get_dtype(column)
  column <- drop_dtype(column)
  if (is.character(column)) {
    parts <- strsplit(record %||% "", ":", fixed = TRUE)[[1L]]
    kind <- if (length(parts) > 0L && parts[[1L]] %in% h5_string_kinds) {
      parts[[1L]]
    } else {
      "h5_vlen_utf8"
    }
    ascii <- !anyNA(iconv(column, "UTF-8", "ASCII"))
    # anndata cannot read a fixed-length UTF-8 field or fixed-length non-ASCII
    # text, so those are written as variable-length UTF-8
    if (!ascii || kind == "h5_fixed_utf8") {
      kind <- "h5_vlen_utf8"
    }
    utf8 <- kind %in% c("h5_vlen_utf8", "h5_fixed_utf8")
    variable <- kind %in% c("h5_vlen_utf8", "h5_vlen_ascii")
    size <- if (variable) {
      NA_integer_
    } else {
      # A recorded width is widened when the values no longer fit
      max(
        if (length(parts) == 2L) as.integer(parts[[2L]]) else 0L,
        1L,
        nchar(column, "bytes")
      )
    }
    return(compound_field(
      name,
      column,
      "string",
      size,
      variable = variable,
      utf8 = utf8
    ))
  }
  if (is.logical(column)) {
    return(compound_field(name, column, "bool", 1L))
  }
  dtype <- if (!is.null(record) && record %in% numeric_dtypes) {
    record
  } else {
    native_dtype(column)
  }
  check_dtype_fits(column, dtype, path, call)
  is_float <- startsWith(dtype, "float")
  bits <- as.integer(sub("^[a-z]+", "", dtype))
  compound_field(
    name,
    column,
    if (is_float) "float" else "integer",
    bits %/% 8L,
    signed = !startsWith(dtype, "u")
  )
}

h5_table_write <- function(store, key, frame, dataset_kwargs, call) {
  path <- paste0(rhdf5::H5Iget_name(store), "/", key)
  fields <- Map(
    h5_table_field,
    frame,
    names(frame),
    path,
    list(call)
  )
  # The helper only does gzip, so lzf is written uncompressed
  level <- if (identical(dataset_kwargs$compression, "gzip")) {
    dataset_kwargs$compression_opts %||% 4L
  } else {
    0L
  }
  tmp <- tempfile(fileext = ".h5")
  on.exit(unlink(tmp), add = TRUE)
  compound_write(tmp, "x", fields, level = level)
  compound_copy(tmp, "x", store, key)
  invisible(NULL)
}
