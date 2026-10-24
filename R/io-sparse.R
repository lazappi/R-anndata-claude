#' Sparse matrices
#'
#' Reads and writes the Elements `csr_matrix` and `csc_matrix`, both version
#' 0.1.0.
#' `dgRMatrix` and `lgRMatrix` are written as `csr_matrix`, and `dgCMatrix` and
#' `lgCMatrix` as `csc_matrix`.
#'
#' The Element is a group holding the datasets `data`, `indices` and `indptr`
#' and the `shape` attribute (an int64 pair, rows then columns).
#' A logical matrix has boolean `data`, and a double matrix has `data` of the
#' dtype in its On-disk dtype record (float64 without one).
#' `indices` and `indptr` are int32 unless the record says otherwise, and
#' `indices` shrink to the smallest unsigned dtype that holds the minor axis
#' size when the setting `write_csr_csc_indices_with_min_possible_dtype` is on.
#' Reading records every dtype that differs from those defaults (see
#' [dtype-records]).
#' Values that no longer fit a recorded dtype raise
#' `anndata_dtype_overflow_error`, and logical `NA` raises
#' `anndata_io_registry_error` because Python's bool has no missing value.
#' Complex `data` has no `Matrix` class, so it is not supported.
#'
#' @param store An open rhdf5 file or group handle.
#' @param key Name of the Element within `store`.
#' @param value A `dgRMatrix`, `lgRMatrix`, `dgCMatrix` or `lgCMatrix`.
#' @param dataset_kwargs A list of dataset creation options.
#' @param path Path of the Element.
#' @param group An open group handle.
#' @param shape The `shape` attribute, rows then columns.
#'
#' @name io-sparse
#' @keywords internal
NULL

#' @rdname io-sparse
write_shape_attr <- function(group, shape) {
  attr_write(group, "shape", as.double(shape), dtype = "int64")
}

#' @rdname io-sparse
write_sparse <- function(store, key, value, dataset_kwargs, path) {
  call <- rlang::caller_env()
  parts <- sparse_parts(value)
  if (is.logical(parts$data) && anyNA(parts$data)) {
    abort_unwritable(
      path,
      "it contains missing values, which a boolean sparse matrix cannot hold",
      call
    )
  }
  dtypes <- sparse_write_dtypes(value, path, call)

  group <- group_create(store, key)
  on.exit(node_close(group), add = TRUE)
  type <- if (is_csr(value)) "csr_matrix" else "csc_matrix"
  set_elem_attr(group, "encoding-type", type)
  set_elem_attr(group, "encoding-version", "0.1.0")
  write_shape_attr(group, dim(value))

  # Python writes the components as plain datasets with no Encoding attributes,
  # resizable in HDF5 so that `append()` can grow them
  dataset_kwargs$resizable <- TRUE
  for (part in names(parts)) {
    values <- parts[[part]]
    if (identical(dtypes[[part]], "bool")) {
      write_bool_dataset(group, part, values, FALSE, call, dataset_kwargs)
    } else {
      write_dataset(
        group,
        part,
        set_dtype(values, dtypes[[part]]),
        dataset_kwargs = dataset_kwargs,
        call = call
      )
    }
  }
  invisible(NULL)
}

read_sparse_part <- function(store, path, call) {
  array_read(store, path, call = call)
}

read_shape_attr <- function(elem, path, call) {
  # nocov start: defensive, a malformed file is not worth building a fixture
  if (!attr_exists(elem, "shape")) {
    abort_io_registry(
      "Cannot read {.path {path}}, it has no {.field shape} attribute.",
      path = path,
      call = call
    )
  }
  # nocov end
  as.vector(attr_read(elem, "shape"))
}

# Indices and pointers are R integers, so the values must fit in int32
as_sparse_index <- function(x, path, call) {
  dtype <- get_dtype(x) %||% native_dtype(x)
  values <- as.vector(drop_dtype(x))
  # nocov start: defensive, needs a matrix with more than 2^31 stored values
  if (
    !is.integer(values) &&
      length(values) > 0L &&
      max(values) > .Machine$integer.max
  ) {
    abort_dtype_overflow(
      path,
      dtype,
      "Matrix cannot index values above the largest R integer",
      max(values),
      call
    )
  }
  # nocov end
  list(values = as.integer(values), dtype = dtype)
}

# min() and max() are much faster than comparing every value
indices_in_range <- function(values, bound) {
  length(values) == 0L || (min(values) >= 0L && max(values) < bound)
}

read_sparse_elem <- function(elem, path, store) {
  call <- rlang::caller_env()
  csr <- identical(read_elem_attr(elem, "encoding-type"), "csr_matrix")
  shape <- read_shape_attr(elem, path, call)
  read_sparse_parts(csr, shape, path, store, call)
}

# Reads `data`, `indices` and `indptr` below `path` as a matrix of `shape`
read_sparse_parts <- function(csr, shape, path, store, call) {
  # nocov start: defensive, a malformed file is not worth building a fixture
  if (length(shape) != 2L) {
    abort_io_registry(
      "Cannot read {.path {path}}, its {.field shape} must have length 2.",
      path = path,
      call = call
    )
  }
  # nocov end
  data <- read_sparse_part(store, paste0(path, "/data"), call)
  indices <- as_sparse_index(
    read_sparse_part(store, paste0(path, "/indices"), call),
    paste0(path, "/indices"),
    call
  )
  indptr <- as_sparse_index(
    read_sparse_part(store, paste0(path, "/indptr"), call),
    paste0(path, "/indptr"),
    call
  )

  major <- if (csr) shape[[1L]] else shape[[2L]]
  minor <- if (csr) shape[[2L]] else shape[[1L]]
  valid <- length(indptr$values) == major + 1L &&
    length(indices$values) == length(data) &&
    identical(indptr$values[[length(indptr$values)]], length(data)) &&
    !is.unsorted(indptr$values) &&
    indices_in_range(indices$values, minor)
  if (!valid) {
    abort_io_registry(
      "Cannot read {.path {path}}, its {.field data}, {.field indices} and
       {.field indptr} do not describe a {shape[[1L]]} x {shape[[2L]]} matrix.",
      path = path,
      call = call
    )
  }

  data_dtype <- get_dtype(data) %||%
    if (is.logical(data)) "bool" else native_dtype(data)
  new_sparse_matrix(csr, drop_dtype(data), indices, indptr, shape, data_dtype)
}

# The Matrix class for parts read from disk: `data`, and `indices` and `indptr`
# as lists of `values` and `dtype`. Records every dtype that is not a default.
new_sparse_matrix <- function(csr, data, indices, indptr, shape, data_dtype) {
  if (!is.logical(data)) {
    data <- as.double(data)
  }
  class <- paste0(
    if (is.logical(data)) "l" else "d",
    "g",
    if (csr) "R" else "C",
    "Matrix"
  )
  args <- list(
    class,
    x = data,
    p = indptr$values,
    Dim = as.integer(shape)
  )
  # scipy allows unsorted indices within a major slice but Matrix does not.
  # A non-increasing step is fine when it crosses a slice boundary, which is
  # the case when the position is an `indptr` value (the slice ends there)
  n_values <- length(indices$values)
  steps <- which(indices$values[-1L] <= indices$values[-n_values])
  if (length(steps) > 0L && !all(steps %in% indptr$values)) {
    slice <- rep.int(seq_along(indptr$values[-1L]), diff(indptr$values))
    ord <- order(slice, indices$values)
    indices$values <- indices$values[ord]
    args$x <- args$x[ord]
  }
  args[[if (csr) "j" else "i"]] <- indices$values
  matrix <- do.call(methods::new, args)

  dtypes <- c(
    data = data_dtype,
    indices = indices$dtype,
    indptr = indptr$dtype
  )
  defaults <- c(
    data = if (is.logical(data)) "bool" else "float64",
    indices = "int32",
    indptr = "int32"
  )
  differs <- dtypes != defaults
  if (any(differs)) {
    matrix <- set_dtype(matrix, dtypes[differs])
  }
  matrix
}

for (r_class in c("dgCMatrix", "lgCMatrix")) {
  register_writer(r_class, "csc_matrix", "0.1.0", write_sparse)
}
for (r_class in c("dgRMatrix", "lgRMatrix")) {
  register_writer(r_class, "csr_matrix", "0.1.0", write_sparse)
}
rm(r_class)

register_reader("csr_matrix", "0.1.0", read_sparse_elem)
register_reader("csc_matrix", "0.1.0", read_sparse_elem)
