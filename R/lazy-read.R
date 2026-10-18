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

#' Read an AnnData lazily
#'
#' `read_lazy()` reads an h5ad file or a zarr store (v3 or v2) into an
#' [AnnData()] whose `X`, `layers`, `obsm`, `varm`, `obsp`, `varp`, `obs`, `var`
#' and `raw` are lazy (see [read_elem_lazy()]) and whose `uns` is read into
#' memory.
#' It matches Python's `read_lazy()`.
#'
#' `r lifecycle::badge("experimental")`
#'
#' @param store An h5ad file or a zarr directory, given as a path or as an open
#'   store handle.
#' @param load_annotation_index Whether the `obs` and `var` indexes are read
#'   into memory.
#'   If `FALSE` the names are Python's dummy range (`"0"`, `"1"`, ...).
#'
#' @return An [AnnData()].
#'
#' @examplesIf requireNamespace("Rarr", quietly = TRUE)
#' adata <- AnnData(matrix(as.numeric(1:6), nrow = 3))
#' path <- tempfile(fileext = ".zarr")
#' write_zarr(adata, path)
#' read_lazy(path)
#'
#' @export
read_lazy <- function(store, load_annotation_index = TRUE) {
  call <- rlang::current_env()
  valid <- is.logical(load_annotation_index) &&
    length(load_annotation_index) == 1L &&
    !is.na(load_annotation_index)
  if (!valid) {
    abort_invalid_argument(
      "{.arg load_annotation_index} must be {.code TRUE} or {.code FALSE}.",
      call
    )
  }
  warn_unconsolidated_zarr(store, call)
  store <- lazy_open_store(store, call)
  read_state$lazy <- list(load_annotation_index = load_annotation_index)
  on.exit(read_state$lazy <- NULL, add = TRUE)
  read_elem(store, "/")
}

# Python's warning for a zarr v2 directory with no `.zmetadata`, which it reads
# group by group (this package never reads consolidated metadata, so only the
# warning is kept)
warn_unconsolidated_zarr <- function(store, call) {
  is_v2 <- is.character(store) &&
    length(store) == 1L &&
    file.exists(file.path(store, ".zgroup"))
  if (is_v2 && !file.exists(file.path(store, ".zmetadata"))) {
    anndata_warn(
      "Did not read zarr as consolidated. Consider consolidating your
       metadata.",
      "anndata_unconsolidated_zarr_warning",
      call = call
    )
  }
  invisible(store)
}

# Python cannot write an AnnData whose obs or var is a lazy frame (also for a
# View of one), it raises NotImplementedError and points to `to_memory()`
check_not_lazy <- function(adata, call) {
  if (
    methods::is(adata$obs, "LazyDFrame") || methods::is(adata$var, "LazyDFrame")
  ) {
    anndata_abort(
      "Writing an {.cls AnnData} with lazy {.field obs} or {.field var} is not
       supported yet, use {.code $to_memory()} to bring it into memory first.",
      "anndata_not_implemented_error",
      call = call
    )
  }
  invisible(adata)
}

# The lazy value of the slot `key` of an AnnData group, or `NULL` when the slot
# is read eagerly
read_lazy_slot <- function(store, path, key, lazy, call) {
  if (key == "X") {
    return(lazy_elem(store, path, NULL, call))
  }
  if (key %in% c("obs", "var")) {
    return(lazy_dataframe(store, path, lazy$load_annotation_index, call))
  }
  if (key %in% c("layers", "obsm", "varm", "obsp", "varp")) {
    group <- node_open(store, path)
    on.exit(node_close(group), add = TRUE)
    members <- group_members(group)
    values <- lapply(
      members,
      function(member) {
        lazy_elem(store, paste0(path, "/", member), NULL, call)
      }
    )
    names(values) <- members
    return(values)
  }
  NULL
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
