#' Chunks of X
#'
#' Internal helpers behind `AnnData$chunked_X()` and `AnnData$chunk_X()`.
#' Chunks are read through `[` on X, so a backed X reads only the rows it
#' needs.
#'
#' @param adata An `AnnData`.
#' @param chunk_size,select,replace As the methods' arguments.
#' @param call The call reported by errors.
#'
#' @name anndata-chunks
#' @keywords internal
NULL

# X, or an error as Python's `TypeError` for a missing X
chunk_source <- function(adata, call) {
  x <- adata$X
  if (is.null(x)) {
    abort_invalid_argument("{.field X} is {.code NULL}, it has no rows.", call)
  }
  x
}

#' @rdname anndata-chunks
chunked_x <- function(adata, chunk_size, call) {
  if (is.null(chunk_size)) {
    chunk_size <- 6000L
  }
  valid <- is.numeric(chunk_size) &&
    length(chunk_size) == 1L &&
    !is.na(chunk_size) &&
    chunk_size == round(chunk_size)
  if (!valid) {
    abort_invalid_argument(
      "{.arg chunk_size} must be a single whole number.",
      call
    )
  }
  if (chunk_size == 0) {
    abort_invalid_argument("{.arg chunk_size} must not be zero.", call)
  }
  x <- chunk_source(adata, call)
  n <- adata$n_obs
  # A negative size gives one chunk of every row, as in Python
  size <- if (chunk_size < 0) n else as.integer(chunk_size)
  starts <- if (n > 0L) seq(1L, n, by = max(size, 1L)) else integer()
  lapply(starts, function(start) {
    end <- min(start + size - 1L, n)
    list(
      chunk = x[start:end, , drop = FALSE],
      start = start,
      end = end
    )
  })
}

#' @rdname anndata-chunks
chunk_x <- function(adata, select, replace, call) {
  x <- chunk_source(adata, call)
  n <- adata$n_obs
  if (is.null(select)) {
    abort_invalid_argument(
      "{.arg select} must be a number of rows or an index of rows.",
      call
    )
  }
  if (!inherits(select, "AsIs") && is.numeric(select) && length(select) == 1L) {
    if (is.na(select) || select < 0 || select != round(select)) {
      abort_invalid_argument(
        "{.arg select} must be a non-negative whole number of rows.",
        call
      )
    }
    size <- min(select, n)
    if (!isTRUE(replace) && !isFALSE(replace)) {
      abort_invalid_argument("{.arg replace} must be `TRUE` or `FALSE`.", call)
    }
    rows <- if (size == 0) {
      integer()
    } else {
      sample.int(n, size, replace = replace)
    }
  } else {
    if (inherits(select, "AsIs")) {
      select <- unclass(select)
    }
    rows <- normalize_index(select, rownames(adata$obs), "obs", call)
  }
  values <- x[rows, , drop = FALSE]
  if (inherits(values, "Matrix")) {
    values <- as.matrix(values)
  }
  values
}
