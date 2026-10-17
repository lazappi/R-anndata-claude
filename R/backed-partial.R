#' Partial reads of Elements
#'
#' `read_elem_partial()` reads a part of an Element, as Python's function of
#' the same name does.
#' It is internal, as is `read_elem()`.
#' Arrays and sparse matrices read only the selected rows and columns, data
#' frames read the `items` (columns) and the selected rows, and categoricals and
#' string arrays the selected rows.
#' Other Elements (dicts, scalars, the root and so on) have no partial reader
#' and raise an `anndata_io_registry_error`.
#' Indices follow the R rules (1-based positions, negative and logical
#' vectors), and the result always has the dimensions of the selection (there
#' is no dropping to a vector).
#' As in Python, a dense array, data frame or categorical needs positions in
#' increasing order and a sparse matrix accepts any order.
#'
#' @param store An open file or group handle.
#' @param path The path of the Element in `store`.
#' @param items Names of the columns of a data frame to read, or `NULL` for all.
#' @param rows,cols R indices along the first and second dimension, or `NULL`
#'   for all.
#'
#' @name anndata-read-elem-partial
#' @keywords internal
NULL

# Python's error for dense data read out of order
require_increasing <- function(positions, call) {
  if (is.unsorted(positions, strictly = TRUE)) {
    abort_index("Indexing elements must be in increasing order.", call)
  }
  positions
}

#' @rdname anndata-read-elem-partial
read_elem_partial <- function(
  store,
  path,
  items = NULL,
  rows = NULL,
  cols = NULL
) {
  call <- rlang::caller_env()
  elem <- node_open(store, path)
  on.exit(node_close(elem), add = TRUE)
  type <- read_elem_attr(elem, "encoding-type")
  version <- read_elem_attr(elem, "encoding-version")
  matrix_like <- type %in% c("array", "csr_matrix", "csc_matrix")
  x <- if (matrix_like) {
    manager <- list(handle = function() store)
    backed_x_elem(manager, path, store, call)
  }
  if (!is.null(x)) {
    return(partial_matrix(x, rows, cols, call))
  }
  vectors <- c("array", "string-array", "nullable-string-array", "categorical")
  if (type %in% vectors) {
    values <- read_elem(store, path)
    return(partial_vector(values, rows, call))
  }
  if (type == "dataframe" && identical(version, "0.2.0")) {
    df <- read_dataframe_elem(elem, path, store, items = items)
    positions <- normalize_index(rows, rownames(df), "rows", call)
    return(subset_frame(df, require_increasing(positions, call)))
  }
  abort_io_registry(
    c(
      "No partial read method registered for {.path {path}} with encoding
       type {.val {type}} version {.val {version}}.",
      i = "You may need to update your installation of anndata.claude."
    ),
    path = path,
    encoding_type = type,
    encoding_version = version,
    call = call
  )
}

# A selection of a 2-D `backed_x`, which keeps its dimensions
partial_matrix <- function(x, rows, cols, call) {
  shape <- backed_shape(x)
  if (inherits(x, "backed_dense")) {
    rows <- require_increasing(
      backed_positions(rows %||% seq_len(shape[[1L]]), shape[[1L]], call),
      call
    )
    cols <- require_increasing(
      backed_positions(cols %||% seq_len(shape[[2L]]), shape[[2L]], call),
      call
    )
  }
  rows <- rows %||% seq_len(shape[[1L]])
  cols <- cols %||% seq_len(shape[[2L]])
  x[rows, cols, drop = FALSE]
}

# Rows of a vector-like Element (categorical, string array or 1-D array)
partial_vector <- function(values, rows, call) {
  if (length(dim(values)) > 1L) {
    abort_not_supported(
      "A partial read of an array with {length(dim(values))} dimensions is
       not supported.",
      class = "anndata_partial_read_error",
      call = call
    )
  }
  n <- length(values)
  positions <- normalize_index(rows, character(n), "rows", call)
  copy_dtype(values[require_increasing(positions, call)], values)
}
