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
  shape <- backed_shape(x)
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
  shape <- backed_shape(x)
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
  shape <- backed_shape(x)
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
    shape = backed_shape(x),
    to_memory = function() backed_sparse_to_memory(x),
    append = function(sparse_matrix) {
      backed_sparse_append(x, sparse_matrix, rlang::caller_env())
    },
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

# The scipy format name of a Matrix sparse matrix
sparse_format_name <- function(value) {
  if (methods::is(value, "RsparseMatrix")) {
    "csr"
  } else if (methods::is(value, "CsparseMatrix")) {
    "csc"
  } else if (methods::is(value, "TsparseMatrix")) {
    "coo"
  } else {
    class(value)[[1L]]
  }
}

# Grows the 1-d dataset `name` of `handle` by the length of `values` and writes
# them at the end, as h5py's `resize()` and slice assignment do
backed_sparse_extend <- function(handle, name, values, call) {
  if (length(values) == 0L) {
    return(invisible(NULL))
  }
  dset <- rhdf5::H5Dopen(handle, name)
  on.exit(rhdf5::H5Dclose(dset), add = TRUE)
  space <- rhdf5::H5Dget_space(dset)
  old <- rhdf5::H5Sget_simple_extent_dims(space)$size
  rhdf5::H5Sclose(space)
  resized <- tryCatch(
    {
      rhdf5::H5Dset_extent(dset, old + length(values))
      TRUE
    },
    error = function(e) FALSE
  )
  if (!resized) {
    anndata_abort(
      "Cannot append to {.path {name}}, the dataset cannot be resized.",
      "anndata_invalid_value_error",
      call = call
    )
  }
  space <- rhdf5::H5Dget_space(dset)
  on.exit(rhdf5::H5Sclose(space), add = TRUE)
  rhdf5::H5Sselect_index(space, list(old + seq_along(values)))
  mem <- rhdf5::H5Screate_simple(length(values))
  on.exit(rhdf5::H5Sclose(mem), add = TRUE, after = FALSE)
  if (is.logical(values)) {
    rhdf5::H5Dwrite(
      dset,
      as.raw(values),
      h5type = bool_type(),
      h5spaceFile = space,
      h5spaceMem = mem
    )
  } else {
    rhdf5::H5Dwrite(dset, values, h5spaceFile = space, h5spaceMem = mem)
  }
  invisible(NULL)
}

# `sparse_dataset(...)$append(value)`: Python's checks in the same order, then
# the shape attribute, `data`, `indptr` and `indices`
backed_sparse_append <- function(x, value, call) {
  if (inherits(value, "backed_sparse")) {
    value <- backed_sparse_to_memory(value)
  }
  if (!is_sparse(value)) {
    abort_invalid_argument(
      "Only sparse matrices of equivalent format can be appended to a
       sparse dataset, not {.cls {class(value)}}.",
      call
    )
  }
  csr <- backed_is_csr(x)
  format <- if (csr) "csr" else "csc"
  if (!identical(sparse_format_name(value), format)) {
    anndata_abort(
      "Matrices must have same format. Currently are {.val {format}} and
       {.val {sparse_format_name(value)}}.",
      "anndata_invalid_value_error",
      call = call
    )
  }
  handle <- .subset2(x, "manager")$handle()
  path <- .subset2(x, "path")
  shape <- backed_shape(x)
  parts <- sparse_parts(value)
  indptr_path <- part_path(path, "indptr")
  # `h5ls()` gives a resizable dataset's dim as "size / maximum"
  offset <- as.numeric(sub(
    " .*",
    "",
    array_info(handle, part_path(path, "indices"))$dim
  ))
  if (identical(h5_dtype(handle, indptr_path), "int32")) {
    if (offset + length(parts$indices) >= .Machine$integer.max) {
      anndata_abort(
        "This array was written with a 32 bit indptr, but is now large enough
         to require 64 bit values. Please recreate the array with a 64 bit
         indptr.",
        "anndata_invalid_value_error",
        call = call
      )
    }
  }
  axis <- if (csr) 2L else 1L
  if (shape[[axis]] != dim(value)[[axis]]) {
    anndata_abort(
      "{toupper(format)} matrices must have same size of dimension
       {axis - 1L} to be appended.",
      "anndata_invalid_value_error",
      call = call
    )
  }
  new_shape <- shape
  new_shape[[3L - axis]] <- shape[[3L - axis]] + dim(value)[[3L - axis]]

  elem <- rhdf5::H5Oopen(handle, path)
  on.exit(rhdf5::H5Oclose(elem), add = TRUE)
  # rhdf5 cannot ask a group handle for its file's intent, so probe with a
  # temporary attribute (Python fails at its first write too)
  probe <- ".anndata_write_probe"
  try(
    suppressWarnings(rhdf5::h5writeAttribute(1L, elem, probe)),
    silent = TRUE
  )
  if (!attr_exists(elem, probe)) {
    anndata_abort(
      "Cannot append, the file has no write intent.",
      "anndata_read_only_error",
      call = call
    )
  }
  rhdf5::H5Adelete(elem, probe)
  for (part in c("data", "indices", "indptr")) {
    dset <- rhdf5::H5Dopen(handle, part_path(path, part))
    space <- rhdf5::H5Dget_space(dset)
    maximum <- rhdf5::H5Sget_simple_extent_dims(space)$maxsize
    rhdf5::H5Sclose(space)
    rhdf5::H5Dclose(dset)
    if (!all(maximum == rhdf5::H5Sunlimited())) {
      anndata_abort(
        "Cannot append to {.path {part_path(path, part)}}, the dataset cannot
         be resized.",
        "anndata_invalid_value_error",
        call = call
      )
    }
  }
  if (attr_exists(elem, "h5sparse_shape")) {
    rhdf5::H5Adelete(elem, "h5sparse_shape")
  }
  rhdf5::H5Adelete(elem, "shape")
  write_shape_attr(elem, new_shape)

  backed_sparse_extend(handle, part_path(path, "data"), parts$data, call)
  backed_sparse_extend(
    handle,
    indptr_path,
    as.double(parts$indptr[-1L]) + offset,
    call
  )
  backed_sparse_extend(
    handle,
    part_path(path, "indices"),
    parts$indices,
    call
  )
  assign("shape", as.integer(new_shape), envir = .subset2(x, "state"))
  cache <- .subset2(x, "cache")
  if (!is.null(cache)) {
    rm(list = intersect("indptr", names(cache)), envir = cache)
  }
  invisible(NULL)
}

# Python's sparse handles have no item assignment (`TypeError`)
#' @export
#' @noRd
`[<-.backed_sparse` <- function(x, i, j, ..., value) {
  abort_not_supported(
    "A backed sparse matrix does not support item assignment."
  )
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
#' `handle$append(value)` adds the rows (CSR) or columns (CSC) of a sparse
#' matrix in the same format to the file, which must be open read-write and
#' hold resizable `data`, `indices` and `indptr` (as files written by Python
#' do), and the handle's shape grows with it.
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
