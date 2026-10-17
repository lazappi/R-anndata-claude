#' Backed dense X
#'
#' A `backed_dense` is a `backed_x` for a dense array on disk.
#' `[` accepts every R index form of a base matrix (positive, negative and
#' logical vectors, repeated and unsorted positions, `drop`) and reads only the
#' needed part of the file into memory.
#' Python's dense handle rejects unsorted and repeated indices, here they are
#' read as a sorted selection and then rearranged in memory.
#' Values carry the On-disk dtype record, as for `read_h5ad()`.
#' A vector index such as `x[i]` (or `x[]`) has no rows and columns to select,
#' so it reads the whole array.
#'
#' @param x A `backed_dense`.
#' @param i,j Row and column indices, as for a base matrix.
#' @param drop Whether a single row or column becomes a vector.
#' @param ... Ignored.
#'
#' @name anndata-backed-dense
#' @keywords internal
NULL

# Positions (1-based) selected by `index` on a dimension of length `n`, with the
# rules of a base matrix. Names do not exist, so a character index is an error.
backed_positions <- function(index, n, call) {
  if (is.character(index) || is.factor(index)) {
    abort_index(
      "A backed array has no names, so it cannot be indexed by name.",
      call
    )
  }
  if (is.logical(index) && length(index) > n) {
    abort_index("A logical index is longer than the dimension.", call)
  }
  if (is.numeric(index) && any(index > n, na.rm = TRUE)) {
    abort_index("Subscript out of bounds.", call)
  }
  positions <- tryCatch(
    seq_len(n)[index],
    error = function(e) abort_index(conditionMessage(e), call)
  )
  if (anyNA(positions)) {
    abort_index("Missing values are not allowed in an index.", call)
  }
  positions
}

# Reads the rows `rows` and columns `cols` (sorted, unique positions) of the
# array on disk
backed_dense_block <- function(x, rows, cols, call) {
  manager <- .subset2(x, "manager")
  selection <- if (is.null(rows) && is.null(cols)) NULL else list(rows, cols)
  array_read(manager$handle(), .subset2(x, "path"), selection, call)
}

# Reads everything (`rows` and `cols` of `NULL`) or a selection, returning
# values arranged as the positions are given
backed_dense_read <- function(x, rows, cols, call) {
  shape <- .subset2(x, "shape")
  rows <- rows %||% seq_len(shape[[1L]])
  cols <- cols %||% seq_len(shape[[2L]])
  if (length(rows) == 0L || length(cols) == 0L) {
    # HDF5 cannot select nothing, so take the empty part of a single value
    if (any(shape == 0L)) {
      block <- backed_dense_block(x, NULL, NULL, call)
    } else {
      block <- backed_dense_block(x, 1L, 1L, call)
    }
    return(copy_dtype(
      block[rep(1L, length(rows)), rep(1L, length(cols)), drop = FALSE],
      block
    ))
  }
  unique_rows <- sort(unique(rows))
  unique_cols <- sort(unique(cols))
  block <- backed_dense_block(x, unique_rows, unique_cols, call)
  if (identical(unique_rows, rows) && identical(unique_cols, cols)) {
    return(block)
  }
  copy_dtype(
    block[match(rows, unique_rows), match(cols, unique_cols), drop = FALSE],
    block
  )
}

#' @export
#' @noRd
`[.backed_dense` <- function(x, i, j, ..., drop = TRUE) {
  call <- rlang::caller_env()
  shape <- .subset2(x, "shape")
  if (...length() > 0L) {
    abort_index("A backed array is indexed by rows and columns only.", call)
  }
  n_index <- nargs() - as.integer(!missing(drop))
  if (n_index < 3L) {
    # `x[]` and `x[i]` index the values as a vector
    values <- backed_dense_read(x, NULL, NULL, call)
    if (missing(i)) {
      return(values)
    }
    return(copy_dtype(values[i], values))
  }
  rows <- if (missing(i)) NULL else backed_positions(i, shape[[1L]], call)
  cols <- if (missing(j)) NULL else backed_positions(j, shape[[2L]], call)
  values <- backed_dense_read(x, rows, cols, call)
  if (isTRUE(drop) && any(dim(values) == 1L)) {
    return(copy_dtype(drop(values), values))
  }
  values
}

#' @export
#' @noRd
as.matrix.backed_dense <- function(x, ...) {
  backed_dense_read(x, NULL, NULL, rlang::caller_env())
}

#' @export
#' @noRd
as.array.backed_dense <- function(x, ...) {
  backed_dense_read(x, NULL, NULL, rlang::caller_env())
}
