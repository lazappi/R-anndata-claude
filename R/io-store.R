#' Store layer
#'
#' The backend-neutral layer between the encodings and a storage format.
#' Encodings (`R/io-*.R`) never call rhdf5 directly, they call the functions
#' here, which dispatch on the class of the handle they are given to a backend
#' (`store_backend()`).
#' HDF5 (`h5_backend()`) and zarr (`zarr_backend()`, which writes v3 only so
#' far) each have a list of the same operations.
#'
#' A `store` is an open file or group, and a `node` is an open group or array.
#' Both are handles of the backend, and paths are absolute within the store.
#'
#' A `selection` is `NULL` (the whole array) or a list with one entry per
#' dimension, each `NULL` (every index) or a strictly increasing vector of
#' 1-based indices.
#' Dimensions are in Python's order, so `selection = list(1:2, NULL)` is numpy's
#' `x[0:2, :]`.
#'
#' The array information from `array_info()` is a one-row data frame, as
#' `h5ls()` gives, with `name`, `dclass` (`INTEGER`, `FLOAT`, `ENUM`,
#' `COMPOUND` or `STRING`), `dtype` and `rank`, and the list columns `shape`
#' and `chunks` (numeric vectors in Python's order).
#' `chunks` is `NULL` for a contiguous HDF5 dataset and for a 0-d array, and
#' the inner chunk shape for a sharded zarr array.
#'
#' @param store,node An open file or group handle.
#' @param key,name Name of a member of `store`, or of an attribute.
#' @param path Absolute path of an Element or array.
#' @param value The value to write.
#' @param dtype The On-disk dtype of an attribute, `NULL` for the type of
#'   `value`.
#' @param selection A selection, see the description.
#' @param call The call reported by errors.
#' @param dataset_kwargs A list of dataset creation options.
#' @param frame A data frame of numeric, logical and character columns.
#'
#' @name io-store
#' @keywords internal
NULL

# The backend of a handle, a list of the operations the wrappers below call.
# Built by a function so that the operations are looked up at call time.
store_backend <- function(store) {
  if (methods::is(store, "H5IdComponent")) {
    return(h5_backend())
  }
  if (inherits(store, "zarr_node")) {
    return(zarr_backend())
  }
  class <- class(store)
  anndata_abort(
    "{.arg store} must be an open store, not {.cls {class}}.",
    "anndata_invalid_value_error"
  )
}

#' @rdname io-store
node_path <- function(node) store_backend(node)$node_path(node)

#' @rdname io-store
elem_path <- function(store, key) {
  parent <- node_path(store)
  if (identical(parent, "/")) paste0("/", key) else paste0(parent, "/", key)
}

#' @rdname io-store
is_store_file <- function(store) store_backend(store)$is_file(store)

#' @rdname io-store
node_open <- function(store, path) store_backend(store)$node_open(store, path)

#' @rdname io-store
node_close <- function(node) store_backend(node)$node_close(node)

#' @rdname io-store
group_create <- function(store, key) {
  store_backend(store)$group_create(store, key)
}

# The root group of a store, which may be a file
group_root <- function(store) store_backend(store)$group_root(store)

#' @rdname io-store
group_members <- function(node) store_backend(node)$group_members(node)

#' @rdname io-store
member_exists <- function(store, key) {
  store_backend(store)$member_exists(store, key)
}

#' @rdname io-store
member_delete <- function(store, key) {
  store_backend(store)$member_delete(store, key)
}

#' @rdname io-store
attr_exists <- function(node, name) store_backend(node)$attr_exists(node, name)

# Values of an attribute, 64-bit integers as doubles and an empty array as an
# empty character vector
attr_read <- function(node, name) store_backend(node)$attr_read(node, name)

#' @rdname io-store
#' @param scalar Whether a character vector is written as a scalar.
#'   Character vectors are written as variable-length UTF-8, logicals as
#'   scalars and `dtype = "int64"` writes an int64 array.
attr_write <- function(node, name, value, dtype = NULL, scalar = TRUE) {
  store_backend(node)$attr_write(node, name, value, dtype, scalar)
}

#' @rdname io-store
array_info <- function(store, path) store_backend(store)$array_info(store, path)

#' @rdname io-store
array_read <- function(
  store,
  path,
  selection = NULL,
  call = rlang::caller_env()
) {
  store_backend(store)$array_read(store, path, selection, call)
}

# Reads a dataset as strings whatever its class (used by `bytes`)
string_read <- function(store, path, call = rlang::caller_env()) {
  store_backend(store)$string_read(store, path, call)
}

#' @rdname io-store
null_write <- function(store, key) store_backend(store)$null_write(store, key)

#' @rdname io-store
table_write <- function(
  store,
  key,
  frame,
  dataset_kwargs = list(),
  call = rlang::caller_env()
) {
  store_backend(store)$table_write(store, key, frame, dataset_kwargs, call)
}

#' @rdname io-store
table_read <- function(store, path, call = rlang::caller_env()) {
  store_backend(store)$table_read(store, path, call)
}

#' @rdname io-store
read_elem_attr <- function(elem, name) {
  if (!attr_exists(elem, name)) {
    return("")
  }
  as.character(attr_read(elem, name))
}

#' @rdname io-store
set_elem_attr <- function(elem, name, value) attr_write(elem, name, value)
