#' Backed sparse X and `sparse_dataset()`
#'
#' A `backed_sparse` is a `backed_x` for a CSR or CSC matrix on disk.
#' `[` accepts every R index form of a base matrix (positive, negative and
#' logical vectors, repeated and unsorted positions, `drop`) and reads only the
#' needed parts of `data` and `indices` into memory, using the cached `indptr`.
#' The result is a sparse matrix in the same format as the file (`dgRMatrix` or
#' `lgRMatrix` for CSR, `dgCMatrix` or `lgCMatrix` for CSC), or a plain vector
#' when `drop` removes a dimension, as for a `Matrix`.
#' Values carry the On-disk dtype record of `data`, as for `read_h5ad()`.
#' A vector index such as `x[i]` has no rows and columns to select, so it reads
#' the whole matrix.
#' `x[]` is the whole matrix, `as.matrix(x)` its dense form and
#' `x$to_memory()` the sparse matrix read as `read_h5ad()` reads it.
#' `x$format` is `"csr"` or `"csc"`, `x$backend` is `"hdf5"` and `x$shape` and
#' `x$dtype` describe the matrix.
#'
#' @param x A `backed_sparse`.
#' @param i,j Row and column indices, as for a base matrix.
#' @param drop Whether a single row or column becomes a vector.
#' @param ... Ignored.
#' @param name The name of a field or method.
#' @param rows,cols Sorted, unique row and column positions.
#' @param call The call reported by errors.
#'
#' @name anndata-backed-sparse
#' @keywords internal
NULL

part_path <- function(path, part) paste0(path, "/", part)

# Whether `x` is stored by rows
backed_is_csr <- function(x) identical(.subset2(x, "encoding"), "csr_matrix")

# Entries `positions` (1-based) of `indptr`, which is read once when cached
backed_sparse_indptr <- function(x, positions, call) {
  handle <- .subset2(x, "manager")$handle()
  path <- part_path(.subset2(x, "path"), "indptr")
  cache <- .subset2(x, "cache")
  if (is.null(cache)) {
    values <- array_read(handle, path, list(positions), call)
    return(as_sparse_index(values, path, call)$values)
  }
  if (is.null(cache$indptr)) {
    cache$indptr <- as_sparse_index(
      array_read(handle, path, NULL, call),
      path,
      call
    )$values
  }
  cache$indptr[positions]
}

# The sparse matrix of the sorted, unique `rows` and `cols`, reading only the
# slices of `data` and `indices` that belong to the selected major positions
backed_sparse_block <- function(x, rows, cols, call) {
  csr <- backed_is_csr(x)
  shape <- .subset2(x, "shape")
  dtype <- .subset2(x, "dtype")
  major <- if (csr) rows else cols
  minor <- if (csr) cols else rows
  n_minor <- shape[[if (csr) 2L else 1L]]
  handle <- .subset2(x, "manager")$handle()
  path <- .subset2(x, "path")

  first <- last <- integer()
  if (length(major) > 0L) {
    positions <- sort(unique(c(major, major + 1L)))
    pointers <- backed_sparse_indptr(x, positions, call)
    first <- pointers[match(major, positions)]
    last <- pointers[match(major + 1L, positions)]
  }
  counts <- last - first
  offsets <- sequence(counts, from = first + 1L)
  if (length(offsets) > 0L) {
    data <- array_read(handle, part_path(path, "data"), list(offsets), call)
    index_path <- part_path(path, "indices")
    indices <- as_sparse_index(
      array_read(handle, index_path, list(offsets), call),
      index_path,
      call
    )$values
    data <- drop_dtype(data)
  } else {
    data <- if (identical(dtype, "bool")) logical() else double()
    indices <- integer()
  }

  slice <- rep.int(seq_along(major), counts)
  if (length(minor) < n_minor) {
    keep <- (indices + 1L) %in% minor
    slice <- slice[keep]
    data <- data[keep]
    indices <- match(indices[keep] + 1L, minor) - 1L
  }
  pointers <- c(0L, cumsum(tabulate(slice, length(major))))
  new_sparse_matrix(
    csr,
    data,
    list(values = indices, dtype = "int32"),
    list(values = as.integer(pointers), dtype = "int32"),
    if (csr) {
      c(length(major), length(minor))
    } else {
      c(length(minor), length(major))
    },
    dtype
  )
}

# Reads everything (`rows` and `cols` of `NULL`) or a selection, returning a
# sparse matrix with the rows and columns arranged as the positions are given
backed_sparse_read <- function(x, rows, cols, call) {
  shape <- .subset2(x, "shape")
  rows <- rows %||% seq_len(shape[[1L]])
  cols <- cols %||% seq_len(shape[[2L]])
  unique_rows <- sort(unique(rows))
  unique_cols <- sort(unique(cols))
  block <- backed_sparse_block(x, unique_rows, unique_cols, call)
  if (identical(unique_rows, rows) && identical(unique_cols, cols)) {
    return(block)
  }
  copy_dtype(
    block[match(rows, unique_rows), match(cols, unique_cols), drop = FALSE],
    block
  )
}

# The whole matrix as `read_h5ad()` reads it, with every dtype record
backed_sparse_to_memory <- function(x) {
  read_elem(.subset2(x, "manager")$handle(), .subset2(x, "path"))
}

# A vector of the values of a one-row or one-column selection, with the dtype
backed_sparse_drop <- function(values, dtype) {
  record_dtype(drop(as.matrix(drop_dtype(values))), dtype)
}

#' @export
#' @noRd
`[.backed_sparse` <- function(x, i, j, ..., drop = TRUE) {
  call <- rlang::caller_env()
  shape <- .subset2(x, "shape")
  if (...length() > 0L) {
    abort_index("A backed array is indexed by rows and columns only.", call)
  }
  n_index <- nargs() - as.integer(!missing(drop))
  if (n_index < 3L) {
    # `x[]` and `x[i]` index the values as a vector
    values <- backed_sparse_read(x, NULL, NULL, call)
    if (missing(i)) {
      return(values)
    }
    return(record_dtype(as.vector(values[i]), .subset2(x, "dtype")))
  }
  rows <- if (missing(i)) NULL else backed_positions(i, shape[[1L]], call)
  cols <- if (missing(j)) NULL else backed_positions(j, shape[[2L]], call)
  values <- backed_sparse_read(x, rows, cols, call)
  if (isTRUE(drop) && any(dim(values) == 1L)) {
    return(backed_sparse_drop(values, .subset2(x, "dtype")))
  }
  values
}

#' @export
#' @noRd
`$.backed_sparse` <- function(x, name) {
  switch(
    name,
    format = if (backed_is_csr(x)) "csr" else "csc",
    backend = "hdf5",
    to_memory = function() backed_sparse_to_memory(x),
    .subset2(x, name)
  )
}

#' @export
#' @noRd
as.matrix.backed_sparse <- function(x, ...) {
  values <- backed_sparse_read(x, NULL, NULL, rlang::caller_env())
  record_dtype(as.matrix(drop_dtype(values)), .subset2(x, "dtype"))
}

#' @export
#' @noRd
as.array.backed_sparse <- function(x, ...) {
  as.matrix.backed_sparse(x)
}

#' Handle on a sparse matrix on disk
#'
#' Makes a handle on a `csr_matrix` or `csc_matrix` Element that is open in an
#' rhdf5 group, as Python's `anndata.io.sparse_dataset()` does.
#' The handle reads only the parts of `data` and `indices` that an index needs
#' (see `[`, `as.matrix()` and `$to_memory()`), and it is also what a backed
#' object holds as `X`.
#' It reads from the group while the group stays open, and the caller closes
#' the group.
#' Python's `append()` is not available yet.
#'
#' @param group An open rhdf5 group handle holding a `csr_matrix` or
#'   `csc_matrix` Element.
#' @param ... Must be empty, because Python takes `should_cache_indptr` by name
#'   only.
#' @param should_cache_indptr Whether to read `indptr` once and keep it.
#'
#' @return A `backed_sparse`, which has the fields `shape`, `dtype`, `format`
#'   (`"csr"` or `"csc"`) and `backend` (`"hdf5"`).
#'
#' @examples
#' path <- tempfile(fileext = ".h5ad")
#' x <- Matrix::sparseMatrix(i = c(1, 3), j = c(2, 3), x = c(5, 6))
#' write_h5ad(AnnData(methods::as(x, "RsparseMatrix")), path)
#' file <- rhdf5::H5Fopen(path, flags = "H5F_ACC_RDONLY")
#' group <- rhdf5::H5Gopen(file, "X")
#' handle <- sparse_dataset(group)
#' handle$format
#' handle[3, ]
#' rhdf5::H5Gclose(group)
#' rhdf5::H5Fclose(file)
#' @export
sparse_dataset <- function(group, ..., should_cache_indptr = TRUE) {
  call <- rlang::caller_env()
  if (...length() > 0L) {
    abort_invalid_argument(
      "{.arg should_cache_indptr} must be given by name.",
      call
    )
  }
  if (!inherits(group, "H5IdComponent")) {
    abort_invalid_argument(
      "{.arg group} must be an open rhdf5 group handle, not
       {.cls {class(group)}}.",
      call
    )
  }
  path <- node_path(group)
  encoding <- read_elem_attr(group, "encoding-type")
  if (!encoding %in% c("csr_matrix", "csc_matrix")) {
    abort_invalid_argument(
      "{.arg group} must be a {.val csr_matrix} or {.val csc_matrix} Element,
       not {.val {encoding}}.",
      call
    )
  }
  shape <- read_shape_attr(group, path, call)
  new_backed_x(
    list(handle = function() group),
    path,
    shape,
    encoding,
    backed_dtype(group, part_path(path, "data")),
    cache_indptr = isTRUE(should_cache_indptr)
  )
}
