#' Read an Element lazily
#'
#' `read_elem_lazy()` reads the metadata of an Element and leaves its data on
#' disk, so values are read only when they are realised or processed by block.
#' It matches Python's `read_elem_lazy()`.
#'
#' `r lifecycle::badge("experimental")`
#'
#' What is returned depends on the encoding of the Element:
#' - dense and sparse (CSR and CSC) arrays are `DelayedArray`s, sparse ones stay
#'   sparse (SparseArray) when processed by block
#' - string arrays are 1-d `DelayedArray`s of `character`
#' - categorical and nullable arrays are lazy columns, and a `dataframe` is a
#'   lazy data frame whose columns are lazy
#' - other encodings (such as `dict` and scalars) raise
#'   `anndata_io_registry_error`, as in Python
#'
#' Realising a lazy value gives what [read_h5ad()] and [read_zarr()] give for
#' the same Element, including `NA` and the On-disk dtype records.
#' The store stays open while any lazy object that uses it exists.
#'
#' @param store An h5ad file or a zarr directory (v3 or v2), given as a path or
#'   as an open store handle.
#' @param path Path of the Element within the store.
#' @param chunks Chunk shape of the `DelayedArray` grid, one entry per
#'   dimension, where `NA` or `-1` is the whole axis.
#'   The default is the on-disk chunking (1000 where an HDF5 array is
#'   contiguous) and for sparse arrays the major axis is cut every 1000
#'   positions.
#'   Sparse arrays can only be chunked along the major axis.
#'   Ignored for string, categorical, nullable and `dataframe` Elements.
#'
#' @return A `DelayedArray`, or a lazy column or data frame.
#'
#' @examplesIf requireNamespace("Rarr", quietly = TRUE)
#' adata <- AnnData(matrix(as.numeric(1:6), nrow = 3))
#' path <- tempfile(fileext = ".zarr")
#' write_zarr(adata, path)
#' read_elem_lazy(path, "X")
#'
#' @export
read_elem_lazy <- function(store, path = "/", chunks = NULL) {
  call <- rlang::current_env()
  store <- lazy_open_store(store, call)
  check_lazy_path(path, call)
  if (!is.null(chunks)) {
    valid <- is.numeric(chunks) && length(chunks) > 0L
    if (!valid) {
      abort_invalid_argument("{.arg chunks} must be a numeric vector.", call)
    }
  }
  lazy_elem(store, absolute_path(path), chunks, call)
}

check_lazy_path <- function(path, call) {
  valid <- is.character(path) && length(path) == 1L && !is.na(path)
  if (!valid) {
    abort_invalid_argument("{.arg path} must be a single string.", call)
  }
  invisible(path)
}

absolute_path <- function(path) {
  if (startsWith(path, "/")) path else paste0("/", path)
}

# Opens `store` when it is a path. An h5ad file is held open for as long as
# any object that holds the handle is alive.
lazy_open_store <- function(store, call) {
  if (!is.character(store)) {
    store_backend(store)
    return(store)
  }
  path <- check_store_path(store, call)
  if (!file.exists(path)) {
    anndata_abort(
      "Cannot read {.path {path}}, it does not exist.",
      "anndata_file_not_found_error",
      call = call
    )
  }
  if (dir.exists(path)) {
    return(zarr_open(path, call))
  }
  handle <- rhdf5::H5Fopen(path, flags = "H5F_ACC_RDONLY")
  closer <- new.env(parent = emptyenv())
  closer$handle <- handle
  reg.finalizer(
    closer,
    function(e) try(rhdf5::H5Fclose(e$handle), silent = TRUE),
    onexit = TRUE
  )
  attr(handle, "closer") <- closer
  handle
}

# The lazy value of the Element at `path`
lazy_elem <- function(store, path, chunks, call) {
  elem <- node_open(store, path)
  on.exit(node_close(elem), add = TRUE)
  type <- read_elem_attr(elem, "encoding-type")
  version <- read_elem_attr(elem, "encoding-version")
  switch(
    type,
    array = store_dense_seed_array(store, path, chunks, call),
    csr_matrix = ,
    csc_matrix = delayed_seed(store_sparse_seed(store, path, chunks, call)),
    "string-array" = ,
    categorical = ,
    "nullable-integer" = ,
    "nullable-boolean" = ,
    "nullable-string-array" = lazy_column(store, path, call),
    dataframe = lazy_dataframe(store, path, call = call),
    abort_io_registry(
      c(
        "No lazy read method registered for {.path {path}} with encoding type
         {.val {type}} version {.val {version}}.",
        i = "You may need to update your installation of anndata.claude."
      ),
      path = path,
      encoding_type = type,
      encoding_version = version,
      call = call
    )
  )
}

store_dense_seed_array <- function(store, path, chunks, call) {
  delayed_seed(store_dense_seed(store, path, chunks, call))
}

# The seed is a function argument, so errors raised while building it are
# wrapped by S4 dispatch unless it is built first
delayed_seed <- function(seed) {
  force(seed)
  DelayedArray::DelayedArray(seed)
}
