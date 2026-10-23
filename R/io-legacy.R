#' Unencoded Elements
#'
#' Reads Elements written without `encoding-type` and `encoding-version`
#' attributes (`read_basic`), as old anndata releases did.
#' Each one raises `anndata_old_format_warning`, as Python's `OldFormatWarning`.
#' A group is read as a dict and a dataset as an array or scalar, and a group
#' with the h5sparse attributes `h5sparse_format` and `h5sparse_shape` is read
#' as a CSR or CSC matrix.
#' Writing always uses the current encodings.
#'
#' @param elem An open group or dataset handle.
#' @param path Path of the Element.
#' @param store The store `elem` was opened from.
#' @param call The call reported by conditions.
#'
#' @name io-legacy
#' @keywords internal
NULL

# Whether a group is a matrix in the h5sparse layout
has_h5sparse_attrs <- function(elem) {
  attr_exists(elem, "h5sparse_format")
}

# The CSR or CSC encoding type of an h5sparse group
h5sparse_encoding <- function(elem) {
  paste0(read_elem_attr(elem, "h5sparse_format"), "_matrix")
}

# Python's `shape` property prefers `shape` and falls back to `h5sparse_shape`
read_h5sparse_shape <- function(elem, path, call) {
  if (attr_exists(elem, "shape")) {
    return(read_shape_attr(elem, path, call))
  }
  if (!attr_exists(elem, "h5sparse_shape")) {
    abort_io_registry(
      "Cannot read {.path {path}}, it has no {.field h5sparse_shape}
       attribute.",
      path = path,
      call = call
    )
  }
  as.vector(attr_read(elem, "h5sparse_shape"))
}

#' @rdname io-legacy
read_unencoded_elem <- function(elem, path, store, call) {
  anndata_warn(
    "Element {.path {path}} was written without encoding metadata.",
    "anndata_old_format_warning",
    path = path,
    call = call
  )
  if (!is_group(elem)) {
    return(read_values_with_shape(store, path, scalar = FALSE))
  }
  if (has_h5sparse_attrs(elem)) {
    csr <- identical(h5sparse_encoding(elem), "csr_matrix")
    shape <- read_h5sparse_shape(elem, path, call)
    return(read_sparse_parts(csr, shape, path, store, call))
  }
  read_mapping_elem(elem, path, store)
}
