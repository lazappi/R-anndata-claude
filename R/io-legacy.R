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

# Python's `read_dataframe_legacy`: a dataframe stored as a compound dataset
# whose first field is the index
read_dataframe_legacy <- function(store, path, call) {
  anndata_warn(
    "{.path {path}} was written with a very old version of AnnData.
     Consider rewriting it.",
    "anndata_old_format_warning",
    path = path,
    call = call
  )
  fields <- lapply(table_read(store, path, call), rec_array_read_field)
  for (name in intersect(table_int64_fields(store, path), names(fields))) {
    fields[[name]] <- set_dtype(fields[[name]], "int64")
  }
  frame_from_parts(
    fields[-1L],
    plain_string(fields[[1L]]),
    names(fields)[[1L]]
  )
}

# Whether `path` is the legacy compound layout (a dataset) and not a dataframe
# Element (a group), as in Python's `read_dataframe`
is_legacy_frame <- function(store, path) {
  node <- node_open(store, path)
  on.exit(node_close(node), add = TRUE)
  !is_group(node)
}

# Python's `_clean_uns`: categories kept in `uns[["<col>_categories"]]` become
# the levels of the `obs` and `var` column of that name, and the key is removed
clean_legacy_uns <- function(obs, var, uns, call) {
  drop <- character()
  for (key in names(uns) %||% character()) {
    if (!endsWith(key, "_categories")) {
      next
    }
    name <- gsub("_categories", "", key, fixed = TRUE)
    categories <- as.vector(drop_dtype(uns[[key]]))
    for (frame in c("obs", "var")) {
      ann <- if (frame == "obs") obs else var
      if (!name %in% names(ann)) {
        next
      }
      codes <- drop_dtype(ann[[name]])
      # Python's hack to find the axis the categories were stored for
      if (!is.numeric(codes) || !isTRUE(all(codes < length(categories)))) {
        next
      }
      ann[[name]] <- categorical_from_parts(
        codes,
        categories,
        FALSE,
        paste0("/", frame, "/", name),
        call
      )
      if (frame == "obs") {
        obs <- ann
      } else {
        var <- ann
      }
      drop <- c(drop, key)
    }
  }
  uns[unique(drop)] <- NULL
  list(obs = obs, var = var, uns = uns)
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
