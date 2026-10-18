#' On-disk dtype records
#'
#' Internal mechanism that keeps the On-disk dtype of numeric Elements that R
#' cannot represent natively (float32, int8, int16, the unsigned integers,
#' int64 and the sparse index dtypes).
#'
#' The record is the `anndata_dtype` attribute (see [anndata-matrix-values]).
#' Dense values hold a single dtype name such as `"float32"`.
#' Sparse matrices hold a named character vector with the names `data`,
#' `indices` and `indptr`.
#' Plain vectors and arrays that carry a record also get the S3 class
#' `anndata_typed`, whose print method hides the attribute, so they print and
#' compute like ordinary R values.
#' Subsetting, copy and transpose copy the record with `copy_dtype()`.
#'
#' The nullable record is the `anndata_nullable` attribute, set by the readers
#' of `nullable-integer`, `nullable-boolean` and `nullable-string-array`.
#' It makes the value write back as a nullable Element even when it holds no
#' `NA`, as Python writes any pandas nullable array.
#' For strings it holds the `na-value` attribute (`"NaN"` or `"NA"`), and it is
#' `TRUE` for the other types.
#'
#' Reading with `read_dataset()` records the dtype only where it differs from
#' the R type returned, which is `float64` for double and `int32` for integer.
#' Writing with `write_dataset()` restores the recorded dtype, or the R type
#' when there is no record, and raises `anndata_dtype_overflow_error` when the
#' values no longer fit.
#' It never truncates or wraps.
#'
#' int64 and uint64 are read as double when every value has magnitude below
#' 2^53 and otherwise raise `anndata_dtype_overflow_error`.
#' An int32 dataset holding -2147483648, the bit pattern of `NA_integer_`, is
#' read as double with an `int32` record.
#'
#' @param x A numeric value.
#' @param dtype A dtype name from `numeric_dtypes`.
#' @param path Path of the Element, used in errors.
#' @param loc An open rhdf5 file or group handle.
#' @param name Name or path of a dataset below `loc`.
#' @param scalar Whether to write a scalar dataspace.
#' @param dataset_kwargs A list of dataset creation options, see
#'   [io-compression].
#' @param selection A selection of the array to read, see [io-store].
#' @param call The call reported by errors.
#'
#' @name dtype-records
#' @keywords internal
NULL

numeric_dtypes <- c(
  "int8",
  "int16",
  "int32",
  "int64",
  "uint8",
  "uint16",
  "uint32",
  "uint64",
  "float32",
  "float64"
)

typed_class <- "anndata_typed"

# The first value outside each integer dtype on either side
dtype_limits <- list(
  int8 = c(-2^7, 2^7),
  int16 = c(-2^15, 2^15),
  int32 = c(-2^31, 2^31),
  int64 = c(-2^63, 2^63),
  uint8 = c(0, 2^8),
  uint16 = c(0, 2^16),
  uint32 = c(0, 2^32),
  uint64 = c(0, 2^64)
)

float32_max <- 3.4028234663852886e38

h5_numeric_types <- c(
  int8 = "H5T_STD_I8LE",
  int16 = "H5T_STD_I16LE",
  int32 = "H5T_STD_I32LE",
  int64 = "H5T_STD_I64LE",
  uint8 = "H5T_STD_U8LE",
  uint16 = "H5T_STD_U16LE",
  uint32 = "H5T_STD_U32LE",
  uint64 = "H5T_STD_U64LE",
  float32 = "H5T_IEEE_F32LE",
  float64 = "H5T_IEEE_F64LE"
)

#' @rdname dtype-records
get_dtype <- function(x) {
  attr(x, dtype_attr, exact = TRUE)
}

#' @rdname dtype-records
set_dtype <- function(x, dtype) {
  attr(x, dtype_attr) <- dtype
  if (is.null(oldClass(x)) && !isS4(x)) {
    oldClass(x) <- c(typed_class, class(x))
  }
  x
}

#' @rdname dtype-records
drop_dtype <- function(x) {
  attr(x, dtype_attr) <- NULL
  attr(x, nullable_attr) <- NULL
  if (identical(oldClass(x)[1L], typed_class)) {
    oldClass(x) <- NULL
  }
  x
}

#' @rdname dtype-records
get_nullable <- function(x) {
  attr(x, nullable_attr, exact = TRUE)
}

#' @rdname dtype-records
set_nullable <- function(x, na_value = TRUE) {
  attr(x, nullable_attr) <- na_value
  if (is.null(oldClass(x)) && !isS4(x)) {
    oldClass(x) <- c(typed_class, class(x))
  }
  x
}

#' @export
print.anndata_typed <- function(x, ...) {
  print(drop_dtype(x), ...)
  invisible(x)
}

# The dtype R would write for `x` without a record
native_dtype <- function(x) {
  if (is.integer(x)) "int32" else "float64"
}

# Attaches the record only when the dtype differs from the R type of `x`
record_dtype <- function(x, dtype) {
  if (identical(dtype, native_dtype(x))) x else set_dtype(x, dtype)
}

abort_dtype_overflow <- function(path, dtype, reason, example, call) {
  anndata_abort(
    c(
      "Cannot represent the values of {.path {path}} as {.val {dtype}}.",
      "x" = "{reason}, for example {.val {example}}."
    ),
    "anndata_dtype_overflow_error",
    path = path,
    dtype = dtype,
    call = call
  )
}

#' @rdname dtype-records
check_dtype_fits <- function(
  x,
  dtype,
  path,
  call = rlang::caller_env()
) {
  if (identical(dtype, "float64")) {
    return(invisible(x))
  }
  values <- as.double(as.vector(x))
  if (identical(dtype, "float32")) {
    bad <- is.finite(values) & abs(values) > float32_max
    if (any(bad)) {
      abort_dtype_overflow(
        path,
        dtype,
        "Values are outside the float32 range",
        values[bad][[1L]],
        call
      )
    }
    return(invisible(x))
  }
  limits <- dtype_limits[[dtype]]
  missing <- !is.finite(values)
  if (any(missing)) {
    abort_dtype_overflow(
      path,
      dtype,
      "Integers cannot hold missing or infinite values",
      values[missing][[1L]],
      call
    )
  }
  fractional <- values != trunc(values)
  if (any(fractional)) {
    abort_dtype_overflow(
      path,
      dtype,
      "Integers cannot hold fractional values",
      values[fractional][[1L]],
      call
    )
  }
  outside <- values < limits[[1L]] | values >= limits[[2L]]
  if (any(outside)) {
    abort_dtype_overflow(
      path,
      dtype,
      "Values are outside the range of the dtype",
      values[outside][[1L]],
      call
    )
  }
  invisible(x)
}

#' @rdname dtype-records
write_dtype <- function(x, path, call = rlang::caller_env()) {
  record <- get_dtype(x)
  dtype <- if (is.null(record)) native_dtype(x) else record[[1L]]
  check_dtype_fits(x, dtype, path, call)
  dtype
}

# The CSC and CSR slots as the Python attributes data, indices and indptr
sparse_parts <- function(x) {
  list(
    data = x@x,
    indices = if (is_csr(x)) x@j else x@i,
    indptr = x@p
  )
}

# Smallest unsigned dtype that holds the minor axis size (`methods.py:806-815`)
min_index_dtype <- function(minor_axis_size) {
  if (minor_axis_size <= 2^8 - 1) {
    "uint8"
  } else if (minor_axis_size <= 2^16 - 1) {
    "uint16"
  } else if (minor_axis_size <= 2^32 - 1) {
    "uint32"
  } else {
    "uint64"
  }
}

#' @rdname dtype-records
sparse_write_dtypes <- function(x, path, call = rlang::caller_env()) {
  record <- get_dtype(x)
  parts <- sparse_parts(x)
  dtypes <- c(
    data = if (is.logical(parts$data)) "bool" else "float64",
    indices = "int32",
    indptr = "int32"
  )
  recorded <- intersect(names(record), names(dtypes))
  dtypes[recorded] <- record[recorded]
  if (anndata_settings$write_csr_csc_indices_with_min_possible_dtype) {
    minor_axis_size <- dim(x)[if (is_csr(x)) 2L else 1L]
    dtypes[["indices"]] <- min_index_dtype(minor_axis_size)
  }
  for (part in names(parts)) {
    if (!identical(dtypes[[part]], "bool")) {
      check_dtype_fits(
        parts[[part]],
        dtypes[[part]],
        paste0(path, "/", part),
        call
      )
    }
  }
  dtypes
}

# The `h5ls()` row of a dataset: class, dtype, dataspace type and rank.
# `h5ls()` is the only way to see the sign and width (no `H5Tget_sign`).
h5_info <- function(loc, path) {
  parent <- rhdf5::H5Gopen(loc, dirname(path))
  on.exit(rhdf5::H5Gclose(parent), add = TRUE)
  listing <- rhdf5::h5ls(parent, recursive = FALSE, all = TRUE)
  info <- listing[listing$name == basename(path), , drop = FALSE]
  shape <- h5_shape_chunks(loc, path)
  info$shape <- list(shape$shape)
  info$chunks <- list(shape$chunks)
  info
}

# The shape and chunk shape of a dataset in numpy order, with `chunks` of
# `NULL` when the layout is not chunked and a shape of `numeric()` for scalar
# and null datasets
h5_shape_chunks <- function(loc, path) {
  dset <- rhdf5::H5Dopen(loc, path)
  on.exit(rhdf5::H5Dclose(dset), add = TRUE)
  space <- rhdf5::H5Dget_space(dset)
  on.exit(rhdf5::H5Sclose(space), add = TRUE, after = FALSE)
  # rhdf5 reverses the extent into R's order
  shape <- rev(as.numeric(rhdf5::H5Sget_simple_extent_dims(space)$size))
  plist <- rhdf5::H5Dget_create_plist(dset)
  on.exit(rhdf5::H5Pclose(plist), add = TRUE, after = FALSE)
  chunks <- NULL
  if (identical(rhdf5::H5Pget_layout(plist), "H5D_CHUNKED")) {
    chunks <- as.numeric(rhdf5::H5Pget_chunk(plist))
  }
  list(shape = shape, chunks = chunks)
}

# The dtype of a numeric dataset, or NA when it is not an integer or float
h5_dtype <- function(loc, path) {
  type <- h5_info(loc, path)$dtype
  match_type <- sub("BE$", "LE", type)
  names(h5_numeric_types)[match(match_type, h5_numeric_types)]
}

abort_dtype_precision <- function(path, dtype, call) {
  anndata_abort(
    c(
      "Cannot read {.path {path}}, it has dtype {.val {dtype}}.",
      "x" = "Values of magnitude {.val 2^53} or more cannot be represented
             exactly in R."
    ),
    "anndata_dtype_overflow_error",
    path = path,
    dtype = dtype,
    call = call
  )
}

read_h5_values <- function(dset, dtype, path, call, selection = NULL) {
  if (dtype %in% c("int64", "uint64", "uint32")) {
    lossy <- FALSE
    values <- withCallingHandlers(
      h5_dread(dset, selection, bit64conversion = "double"),
      warning = function(w) {
        lossy <<- TRUE
        rlang::cnd_muffle(w)
      }
    )
    if (lossy) {
      abort_dtype_precision(path, dtype, call)
    }
    return(values)
  }
  # rhdf5 reads -2^31 as NA and prints a message about it
  values <- suppressMessages(h5_dread(dset, selection))
  if (is.raw(values)) {
    # A scalar dataspace has no dim
    if (is.null(dim(values))) {
      return(as.integer(values))
    }
    return(array(as.integer(values), dim(values)))
  }
  if (identical(dtype, "int32") && anyNA(values)) {
    missing <- is.na(values)
    values <- structure(as.double(values), dim = dim(values))
    values[missing] <- -2^31
  }
  values
}

#' @rdname dtype-records
read_dataset <- function(
  loc,
  name,
  selection = NULL,
  call = rlang::caller_env()
) {
  store_backend(loc)$dataset_read(loc, name, selection, call)
}

#' @rdname dtype-records
write_dataset <- function(
  loc,
  name,
  x,
  scalar = FALSE,
  dataset_kwargs = list(),
  call = rlang::caller_env()
) {
  store_backend(loc)$dataset_write(loc, name, x, scalar, dataset_kwargs, call)
}

h5_read_dataset <- function(loc, name, selection, call) {
  dset <- rhdf5::H5Dopen(loc, name)
  on.exit(rhdf5::H5Dclose(dset), add = TRUE)
  path <- rhdf5::H5Iget_name(dset)
  dtype <- h5_dtype(loc, name)
  if (is.na(dtype)) {
    anndata_abort(
      "Cannot read {.path {path}}, it is not an integer or float dataset.",
      "anndata_dtype_error",
      path = path,
      call = call
    )
  }
  values <- read_h5_values(dset, dtype, path, call, selection)
  dims <- dim(values)
  if (length(dims) == 1L) {
    dim(values) <- NULL
  } else if (length(dims) > 1L && !dset@native) {
    values <- aperm(values)
  }
  record_dtype(values, dtype)
}

h5_write_dataset <- function(loc, name, x, scalar, dataset_kwargs, call) {
  path <- elem_path(loc, name)
  dtype <- write_dtype(x, path, call)
  values <- as.vector(drop_dtype(x))
  if (is.double(values)) {
    # `NA_real_` and `NaN` are both written as a plain NaN
    values[is.na(values)] <- NaN
  }
  dims <- dim(x) %||% length(x)
  space <- h5_space(dims, scalar, isTRUE(dataset_kwargs$resizable))
  on.exit(rhdf5::H5Sclose(space), add = TRUE)
  dcpl <- if (!scalar) {
    make_dcpl(dataset_kwargs, rev(dims), h5_numeric_types[[dtype]])
  }
  on.exit(close_dcpl(dcpl), add = TRUE)
  dset <- rhdf5::H5Dcreate(
    loc,
    name,
    h5_numeric_types[[dtype]],
    space,
    dcpl = dcpl
  )
  on.exit(rhdf5::H5Dclose(dset), add = TRUE)
  buffer <- if (length(dims) > 1L) {
    aperm(array(values, dims))
  } else {
    values
  }
  rhdf5::H5Dwrite(
    dset,
    if (identical(dtype, "uint8")) as.raw(buffer) else buffer
  )
  invisible(NULL)
}
