#' Matrix value helpers
#'
#' Internal helpers for the array values held in X, layers, obsm, varm, obsp
#' and varp.
#' Accepted values are base `matrix` or `array` (double, integer or logical),
#' `dgCMatrix`/`lgCMatrix` (CSC) and `dgRMatrix`/`lgRMatrix` (CSR).
#' Other `Matrix` classes are coerced, sparse to CSC and dense to base `matrix`.
#'
#' The On-disk dtype record is the `anndata_dtype` attribute.
#' The helpers copy it onto every result that keeps the values.
#'
#' @param x A matrix-like value.
#' @param i,j Integer positions (1-based) on the first and second dimension, or
#'   `NULL` to keep that dimension whole.
#' @param allow_array Whether arrays with more than 2 dimensions are accepted.
#' @param what Description of the value used in error messages.
#' @param call The call reported by errors.
#'
#' @name anndata-matrix-values
#' @keywords internal
NULL

dtype_attr <- "anndata_dtype"

# Copies the On-disk dtype record (if any) from `from` to `to`
copy_dtype <- function(to, from) {
  dtype <- attr(from, dtype_attr, exact = TRUE)
  if (!is.null(dtype)) {
    attr(to, dtype_attr) <- dtype
  }
  to
}

is_csr <- function(x) {
  methods::is(x, "RsparseMatrix")
}

is_sparse <- function(x) {
  methods::is(x, "sparseMatrix")
}

accepted_sparse <- c("dgCMatrix", "lgCMatrix", "dgRMatrix", "lgRMatrix")

abort_unsupported_value <- function(what, x, call) {
  anndata_abort(
    c(
      "{.arg {what}} must be a numeric or logical matrix, array or sparse
       matrix.",
      "x" = "Got {.cls {class(x)}}."
    ),
    "anndata_unsupported_value_error",
    call = call
  )
}

#' @rdname anndata-matrix-values
as_anndata_matrix <- function(
  x,
  allow_array = FALSE,
  what = "value",
  call = rlang::caller_env()
) {
  if (methods::is(x, "Matrix")) {
    return(coerce_matrix_class(x, what, call))
  }
  if (is.array(x) && (is.numeric(x) || is.logical(x)) && !is.object(x)) {
    n_dim <- length(dim(x))
    if (n_dim == 2L || (allow_array && n_dim > 2L)) {
      return(x)
    }
  }
  abort_unsupported_value(what, x, call)
}

coerce_matrix_class <- function(x, what, call) {
  if (class(x)[[1]] %in% accepted_sparse) {
    return(x)
  }
  if (is_sparse(x)) {
    csc <- methods::as(
      methods::as(x, "generalMatrix"),
      "CsparseMatrix"
    )
    # Pattern and other value types become double or logical
    if (methods::is(csc, "nMatrix")) {
      csc <- methods::as(csc, "lMatrix")
    } else if (!methods::is(csc, "lMatrix") && !methods::is(csc, "dMatrix")) {
      abort_unsupported_value(what, x, call)
    }
    return(copy_dtype(csc, x))
  }
  # Dense Matrix classes, including symmetric and triangular, become base
  dense <- as.matrix(x)
  if (!is.numeric(dense) && !is.logical(dense)) {
    abort_unsupported_value(what, x, call)
  }
  copy_dtype(dense, x)
}

#' @rdname anndata-matrix-values
matrix_dim <- function(x) {
  dim(x)
}

#' @rdname anndata-matrix-values
matrix_subset <- function(x, i = NULL, j = NULL) {
  n_dim <- length(dim(x))
  if (is_sparse(x) || n_dim == 2L) {
    i <- i %||% seq_len(nrow(x))
    j <- j %||% seq_len(ncol(x))
    out <- x[i, j, drop = FALSE]
  } else {
    args <- c(
      list(x, i %||% TRUE, j %||% TRUE),
      rep(list(TRUE), n_dim - 2L),
      list(drop = FALSE)
    )
    out <- do.call(`[`, args)
  }
  copy_dtype(out, x)
}

#' @rdname anndata-matrix-values
matrix_transpose <- function(x) {
  n_dim <- length(dim(x))
  out <- if (is_sparse(x)) {
    Matrix::t(x)
  } else if (n_dim == 2L) {
    t(x)
  } else {
    aperm(x, c(2L, 1L, seq_len(n_dim)[-(1:2)]))
  }
  if (is_csr(x) && !is_csr(out)) {
    out <- methods::as(out, "RsparseMatrix")
  }
  copy_dtype(out, x)
}
