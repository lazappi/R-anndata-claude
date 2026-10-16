#' Arrays, scalars, strings, null and bytes
#'
#' Reads and writes the Elements `array`, `string-array`, `numeric-scalar`,
#' `string`, `null` and `bytes` (read only), all version 0.2.0 except `null`
#' (0.1.0).
#'
#' R has no scalars, so Python's rule is kept with the `dim` attribute:
#' - a length-1 atomic vector with no `dim` is written as a `numeric-scalar` or
#'   `string`
#' - a length-1 vector with a `dim` (or wrapped in [as_array()]) is written as a
#'   1-element `array` or `string-array`
#' - an Element read from disk remembers its Encoding type the same way, a
#'   scalar has no `dim` and a 1-element array has `dim` 1
#'
#' Scalars are never compressed.
#' Arrays have `dim()` equal to the shape Python sees, and a `logical` array
#' without `NA` is written as h5py's boolean.
#' `NA_real_` and `NaN` are both written as NaN and read as `NaN`.
#' Only complex128 is written, and reading complex64 raises
#' `anndata_dtype_error` because rhdf5 reads it incorrectly.
#' `bytes` is read as a `raw` vector.
#' Integer, logical and character values with `NA` are written as the nullable
#' Elements, see [io-nullable].
#' Complex values with `NA` cannot be written and raise
#' `anndata_io_registry_error`.
#'
#' @param x An atomic vector, matrix or array.
#' @param loc An open rhdf5 file or group handle.
#' @param name Name or path of a dataset below `loc`.
#' @param dims Dimensions of the array as Python sees them.
#' @param scalar Whether to use a scalar dataspace.
#' @param call The call reported by errors.
#'
#' @name io-values
#' @keywords internal
NULL

#' Mark a vector as an array
#'
#' R has no scalars, so a length-1 vector is written to an h5ad file as a scalar
#' unless it has a `dim`.
#' `as_array()` gives a vector a `dim` so that it is written as a 1-element
#' array, as Python writes a 1-element `numpy` array.
#' A value that already has a `dim` is returned unchanged.
#'
#' @param x An atomic vector, matrix or array.
#'
#' @return `x` with a `dim`.
#'
#' @examples
#' as_array(1.5)
#' @export
as_array <- function(x) {
  if (!is.atomic(x) || is.null(x)) {
    class <- class(x)
    anndata_abort(
      "{.arg x} must be an atomic vector, not {.cls {class}}.",
      "anndata_invalid_value_error"
    )
  }
  if (is.null(dim(x))) {
    dim(x) <- length(x)
  }
  x
}

#' @rdname io-values
h5_space <- function(dims, scalar) {
  if (scalar) {
    rhdf5::H5Screate("H5S_SCALAR")
  } else {
    rhdf5::H5Screate_simple(rev(dims))
  }
}

# h5py's boolean, an int8 enum of FALSE and TRUE
bool_type <- function() {
  type <- rhdf5::H5Tenum_create(dtype_id = "H5T_STD_I8LE")
  rhdf5::H5Tenum_insert(type, "FALSE", 0L)
  rhdf5::H5Tenum_insert(type, "TRUE", 1L)
  type
}

# h5py's variable-length UTF-8 string
string_type <- function() {
  type <- rhdf5::H5Tcopy("H5T_C_S1")
  rhdf5::H5Tset_size(type, -1L)
  rhdf5::H5Tset_cset(type, "UTF8")
  type
}

# h5py's complex128, a compound of float64 `r` and `i`.
# rhdf5 only builds it internally, so take it from a throwaway dataset.
complex_type <- function() {
  file <- tempfile(fileext = ".h5")
  on.exit(unlink(file), add = TRUE)
  rhdf5::h5createFile(file)
  rhdf5::h5createDataset(
    file,
    "x",
    dims = 1L,
    storage.mode = "complex",
    level = 0L
  )
  store <- rhdf5::H5Fopen(file)
  on.exit(rhdf5::H5Fclose(store), add = TRUE, after = FALSE)
  dset <- rhdf5::H5Dopen(store, "x")
  on.exit(rhdf5::H5Dclose(dset), add = TRUE, after = FALSE)
  rhdf5::H5Dget_type(dset)
}

# The values in HDF5's row-major order
row_major <- function(values, dims) {
  if (length(dims) > 1L) aperm(array(values, dims)) else values
}

# Python's shape to R: the dims are reversed by rhdf5, so they are swapped back,
# and 1-d datasets have no `dim`
from_row_major <- function(values) {
  dims <- dim(values)
  if (length(dims) == 1L) {
    dim(values) <- NULL
  } else if (length(dims) > 1L) {
    values <- aperm(values)
  }
  values
}

abort_unwritable <- function(path, what, call) {
  abort_io_registry(
    "Cannot write {.path {path}}, {what}.",
    path = path,
    call = call
  )
}

# Python has no NA in these dtypes, R's `NA` needs a nullable encoding
check_no_missing <- function(x, path, call) {
  if (!is.double(x) && anyNA(x)) {
    abort_unwritable(
      path,
      "it contains missing values, which need a nullable encoding",
      call
    )
  }
}

#' @rdname io-values
write_bool_dataset <- function(
  loc,
  name,
  x,
  scalar,
  call,
  dataset_kwargs = list()
) {
  store_backend(loc)$bool_write(loc, name, x, scalar, call, dataset_kwargs)
}

#' @rdname io-values
write_complex_dataset <- function(
  loc,
  name,
  x,
  scalar,
  call,
  dataset_kwargs = list()
) {
  store_backend(loc)$complex_write(loc, name, x, scalar, call, dataset_kwargs)
}

#' @rdname io-values
write_string_dataset <- function(
  loc,
  name,
  x,
  scalar,
  call,
  dataset_kwargs = list()
) {
  store_backend(loc)$string_write(loc, name, x, scalar, call, dataset_kwargs)
}

h5_write_bool <- function(loc, name, x, scalar, call, dataset_kwargs) {
  dims <- dim(x) %||% length(x)
  space <- h5_space(dims, scalar)
  on.exit(rhdf5::H5Sclose(space), add = TRUE)
  type <- bool_type()
  dcpl <- if (!scalar) make_dcpl(dataset_kwargs, rev(dims), type)
  on.exit(close_dcpl(dcpl), add = TRUE)
  dset <- rhdf5::H5Dcreate(loc, name, type, space, dcpl = dcpl)
  on.exit(rhdf5::H5Dclose(dset), add = TRUE, after = FALSE)
  if (length(x) > 0L) {
    rhdf5::H5Dwrite(
      dset,
      as.raw(row_major(as.vector(x), dims)),
      h5type = type
    )
  }
  invisible(NULL)
}

h5_write_complex <- function(loc, name, x, scalar, call, dataset_kwargs) {
  dims <- dim(x) %||% length(x)
  space <- h5_space(dims, scalar)
  on.exit(rhdf5::H5Sclose(space), add = TRUE)
  type <- complex_type()
  dcpl <- if (!scalar) make_dcpl(dataset_kwargs, rev(dims), type)
  on.exit(close_dcpl(dcpl), add = TRUE)
  dset <- rhdf5::H5Dcreate(loc, name, type, space, dcpl = dcpl)
  on.exit(rhdf5::H5Dclose(dset), add = TRUE, after = FALSE)
  if (length(x) > 0L) {
    rhdf5::H5Dwrite(dset, as.vector(row_major(as.vector(x), dims)))
  }
  invisible(NULL)
}

h5_write_string <- function(loc, name, x, scalar, call, dataset_kwargs) {
  dims <- dim(x) %||% length(x)
  space <- h5_space(dims, scalar)
  on.exit(rhdf5::H5Sclose(space), add = TRUE)
  type <- string_type()
  dcpl <- if (!scalar) make_dcpl(dataset_kwargs, rev(dims), type)
  on.exit(close_dcpl(dcpl), add = TRUE)
  dset <- rhdf5::H5Dcreate(loc, name, type, space, dcpl = dcpl)
  on.exit(rhdf5::H5Dclose(dset), add = TRUE, after = FALSE)
  if (length(x) > 0L) {
    rhdf5::H5Dwrite(dset, as.vector(row_major(as.vector(x), dims)))
  }
  invisible(NULL)
}

# Python writes `string-array` and `array` for 1-element arrays, and the scalar
# encodings for scalars
value_encoding <- function(x, scalar) {
  if (is.character(x)) {
    if (scalar) "string" else "string-array"
  } else if (scalar) {
    "numeric-scalar"
  } else {
    "array"
  }
}

write_values <- function(store, key, value, dataset_kwargs, path) {
  call <- rlang::caller_env()
  plain <- drop_dtype(value)
  if (is.object(plain)) {
    r_class <- class(plain)
    abort_io_registry(
      "No method registered for writing {.cls {r_class}} to {.path {path}}.",
      path = path,
      r_class = r_class,
      call = call
    )
  }
  kind <- nullable_kind(value, plain)
  if (!is.null(kind)) {
    return(write_nullable(store, key, value, kind, dataset_kwargs, path, call))
  }
  check_no_missing(plain, path, call)
  scalar <- length(value) == 1L && is.null(dim(value))
  switch(
    typeof(plain),
    character = write_string_dataset(
      store,
      key,
      plain,
      scalar,
      call,
      dataset_kwargs
    ),
    logical = write_bool_dataset(
      store,
      key,
      plain,
      scalar,
      call,
      dataset_kwargs
    ),
    complex = write_complex_dataset(
      store,
      key,
      plain,
      scalar,
      call,
      dataset_kwargs
    ),
    integer = ,
    double = write_dataset(
      store,
      key,
      value,
      scalar = scalar,
      dataset_kwargs = dataset_kwargs,
      call = call
    ),
    {
      r_class <- class(plain)
      abort_io_registry(
        "No method registered for writing {.cls {r_class}} to {.path {path}}.",
        path = path,
        r_class = r_class,
        call = call
      )
    }
  )
  elem <- node_open(store, key)
  on.exit(node_close(elem), add = TRUE)
  set_elem_attr(elem, "encoding-type", value_encoding(plain, scalar))
  set_elem_attr(elem, "encoding-version", "0.2.0")
  invisible(NULL)
}

write_null <- function(store, key, value, dataset_kwargs, path) {
  null_write(store, key)
  invisible(NULL)
}

abort_dataset_type <- function(path, what, call) {
  anndata_abort(
    "Cannot read {.path {path}}, {what}.",
    "anndata_dtype_error",
    path = path,
    call = call
  )
}

h5_read_bool <- function(loc, name, selection, call) {
  dset <- rhdf5::H5Dopen(loc, name)
  on.exit(rhdf5::H5Dclose(dset), add = TRUE)
  if (rhdf5::H5Tget_nmembers(rhdf5::H5Dget_type(dset)) != 2L) {
    abort_dataset_type(name, "it is an enum that is not a boolean", call)
  }
  values <- h5_dread(dset, selection)
  # `as.logical()` drops the dims that rhdf5 gives the factor
  logical <- array(
    as.character(values) == "TRUE",
    dim(values) %||% length(values)
  )
  from_row_major(logical)
}

h5_read_complex <- function(loc, name, selection, call) {
  dset <- rhdf5::H5Dopen(loc, name)
  on.exit(rhdf5::H5Dclose(dset), add = TRUE)
  if (!identical(rhdf5::H5Tget_size(rhdf5::H5Dget_type(dset)), 16L)) {
    abort_dataset_type(
      name,
      "it is complex64 and only complex128 can be read",
      call
    )
  }
  from_row_major(h5_dread(dset, selection, in_r = TRUE))
}

h5_read_string <- function(loc, name, selection, call) {
  dset <- rhdf5::H5Dopen(loc, name)
  on.exit(rhdf5::H5Dclose(dset), add = TRUE)
  from_row_major(h5_dread(dset, selection, in_r = TRUE))
}

# A 1-element 1-d array keeps `dim` 1 so it is written back as an array, a
# scalar dataspace has no `dim`
read_values_with_shape <- function(loc, path, scalar) {
  call <- rlang::caller_env()
  info <- array_info(loc, path)
  values <- array_read(loc, path, call = call)
  one_element <- length(values) == 1L && as.integer(info$rank) == 1L
  if (one_element && !scalar) {
    dim(values) <- 1L
  }
  values
}

read_array_elem <- function(elem, path, store) {
  read_values_with_shape(store, path, scalar = FALSE)
}

read_scalar_elem <- function(elem, path, store) {
  read_values_with_shape(store, path, scalar = TRUE)
}

read_null_elem <- function(elem, path, store) {
  NULL
}

# Python reads bytes as `bytes`, which R holds as `raw`
read_bytes_elem <- function(elem, path, store) {
  charToRaw(string_read(store, path, rlang::caller_env()))
}

for (r_class in c(
  "numeric",
  "integer",
  "logical",
  "complex",
  "matrix",
  "array"
)) {
  register_writer(r_class, "array", "0.2.0", write_values)
}
rm(r_class)
register_writer("character", "string-array", "0.2.0", write_values)
register_writer("NULL", "null", "0.1.0", write_null)

register_reader("array", "0.2.0", read_array_elem)
register_reader("string-array", "0.2.0", read_array_elem)
register_reader("numeric-scalar", "0.2.0", read_scalar_elem)
register_reader("string", "0.2.0", read_scalar_elem)
register_reader("null", "0.1.0", read_null_elem)
register_reader("bytes", "0.2.0", read_bytes_elem)
