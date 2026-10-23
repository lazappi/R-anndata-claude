#' Read a Matrix Market file
#'
#' `read_mtx()` reads a `.mtx` file (Matrix Market, coordinate or array
#' format, with the `integer`, `real` or `pattern` field) into an [AnnData()]
#' object with a CSR X, as Python's `read_mtx()`.
#' The `obs` and `var` names are `"0"`, `"1"` and so on.
#' Symmetric and skew-symmetric matrices are expanded to the full matrix.
#'
#' @param filename A path (a `.gz` or `.bz2` suffix is decompressed).
#' @param dtype A numpy dtype string for X, such as `"float32"` (the default),
#'   `"float64"` or `"int32"`.
#'   The values are R doubles that carry the On-disk dtype.
#' @return An [AnnData()] object with a sparse (CSR) X.
#' @examples
#' path <- tempfile(fileext = ".mtx")
#' writeLines(
#'   c(
#'     "%%MatrixMarket matrix coordinate integer general",
#'     "2 3 2",
#'     "1 1 5",
#'     "2 3 7"
#'   ),
#'   path
#' )
#' read_mtx(path)
#' @export
read_mtx <- function(filename, dtype = "float32") {
  call <- rlang::current_env()
  if (!rlang::is_string(dtype) || !dtype %in% numeric_dtypes) {
    abort_invalid_argument(
      "{.arg dtype} must be one of {.val {numeric_dtypes}}.",
      call
    )
  }
  if (!rlang::is_string(filename)) {
    abort_invalid_argument("{.arg filename} must be a path.", call)
  }
  if (!file.exists(path.expand(filename))) {
    anndata_abort(
      "The source file does not exist: {.path {filename}}",
      "anndata_file_not_found_error",
      call = call
    )
  }
  lines <- text_lines(filename, call)
  mtx <- mtx_parse(lines, call)
  X <- mtx_sparse(mtx, dtype)
  AnnData(X)
}

mtx_error <- function(message, call) {
  anndata_abort(
    gsub("}", "}}", gsub("{", "{{", message, fixed = TRUE), fixed = TRUE),
    "anndata_invalid_value_error",
    call = call
  )
}

# The numbers on `lines` as a matrix with `ncol` columns (one row per line)
mtx_numbers <- function(lines, ncol, call) {
  fields <- strsplit(trimws(lines), "[ \t]+")
  if (any(lengths(fields) != ncol)) {
    mtx_error("Malformed Matrix Market data line.", call)
  }
  values <- suppressWarnings(as.double(unlist(fields)))
  if (anyNA(values)) {
    mtx_error("Malformed Matrix Market data line.", call)
  }
  matrix(values, ncol = ncol, byrow = TRUE)
}

# Port of scipy's `mmread` for the real, integer and pattern fields, returning
# zero-based triplets and the shape
mtx_parse <- function(lines, call) {
  if (!length(lines) || !startsWith(lines[[1L]], "%%MatrixMarket")) {
    mtx_error("source is not in Matrix Market format", call)
  }
  header <- strsplit(tolower(lines[[1L]]), "[ \t]+")[[1L]]
  if (length(header) != 5L || header[[2L]] != "matrix") {
    mtx_error("source is not in Matrix Market format", call)
  }
  format <- header[[3L]]
  field <- header[[4L]]
  symmetry <- header[[5L]]
  if (!format %in% c("coordinate", "array")) {
    mtx_error(paste0("Unknown format: ", format), call)
  }
  if (field == "complex") {
    mtx_error("Complex Matrix Market fields are not supported.", call)
  }
  if (!field %in% c("real", "integer", "pattern", "unsigned-integer")) {
    mtx_error(paste0("Unknown field: ", field), call)
  }
  if (!symmetry %in% c("general", "symmetric", "skew-symmetric", "hermitian")) {
    mtx_error(paste0("Unknown symmetry: ", symmetry), call)
  }
  lines <- lines[-1L]
  lines <- lines[!startsWith(lines, "%")]
  if (!length(lines)) {
    mtx_error("Matrix Market size line is missing.", call)
  }
  size <- mtx_numbers(lines[[1L]], if (format == "array") 2L else 3L, call)
  data <- lines[-1L]
  shape <- as.integer(size[1L, 1:2])
  if (format == "coordinate") {
    entries <- mtx_numbers(data, if (field == "pattern") 2L else 3L, call)
    if (nrow(entries) != size[[3L]]) {
      mtx_error("Matrix Market entry count does not match the header.", call)
    }
    i <- entries[, 1L] - 1
    j <- entries[, 2L] - 1
    x <- if (field == "pattern") rep(1, length(i)) else entries[, 3L]
  } else {
    if (field == "pattern") {
      mtx_error("Unknown field: pattern", call)
    }
    values <- mtx_numbers(data, 1L, call)[, 1L]
    nr <- shape[[1L]]
    nc <- shape[[2L]]
    grid <- expand.grid(i = seq_len(nr) - 1, j = seq_len(nc) - 1)
    if (symmetry != "general") {
      # only the lower triangle is stored, by column
      offset <- if (symmetry == "skew-symmetric") 1 else 0
      grid <- grid[grid$i >= grid$j + offset, ]
    }
    if (length(values) != nrow(grid)) {
      mtx_error("Matrix Market entry count does not match the header.", call)
    }
    keep <- values != 0
    i <- grid$i[keep]
    j <- grid$j[keep]
    x <- values[keep]
  }
  if (symmetry != "general") {
    off <- i != j
    sign <- if (symmetry == "skew-symmetric") -1 else 1
    x <- c(x, sign * x[off])
    mirrored <- list(i = c(i, j[off]), j = c(j, i[off]))
    i <- mirrored$i
    j <- mirrored$j
  }
  list(i = i, j = j, x = x, shape = shape)
}

# A CSR matrix of `dtype` from the triplets (duplicates are summed)
mtx_sparse <- function(mtx, dtype) {
  m <- Matrix::sparseMatrix(
    i = mtx$i,
    j = mtx$j,
    x = mtx$x,
    dims = mtx$shape,
    index1 = FALSE
  )
  m <- methods::as(m, "generalMatrix")
  # scipy sums duplicates, then casts
  if (grepl("^u?int", dtype)) {
    m@x <- trunc(m@x)
  } else if (dtype == "float32") {
    m@x <- to_float32(m@x)
  }
  m <- methods::as(m, "RsparseMatrix")
  record_dtype(m, dtype)
}
