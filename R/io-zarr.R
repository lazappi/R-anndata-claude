#' Read and write zarr stores
#'
#' `read_zarr()` reads a zarr store into an [AnnData()], and `write_zarr()`
#' (also `adata$write_zarr()`) writes one, following Python anndata 0.13.4
#' (`zarr.py`).
#' Stores round trip between R and Python.
#'
#' `read_zarr()` reads zarr version 3 stores, sharded or not, with or without
#' consolidated metadata, from a directory store.
#' Version 2 is not yet supported.
#' Zip stores are not supported, unzip them first.
#' Stores in a legacy layout (such as one with `raw.X`) raise
#' `anndata_legacy_format_error`.
#'
#' `write_zarr()` writes zarr version 3 and replaces an existing store.
#' To protect other data it refuses a directory that is neither empty nor a
#' zarr group.
#' The version is the `zarr_write_format` setting ([anndata_settings]), and
#' version 2 is not yet supported.
#' With `convert_strings_to_categoricals`, character columns of `obs`, `var` and
#' `raw$var` with fewer distinct values than rows are converted to factors in
#' `adata` first, **in place**, as Python does.
#' `X` and every layer must have at most 2 dimensions.
#' Like Python, a missing `raw` is written as a `null` Element.
#'
#' @param store Path of the zarr directory store.
#' @param adata An [AnnData()].
#' @param chunks The chunk shape of a dense `X`, one whole number for each
#'   dimension (it does not apply to sparse matrices, layers or other
#'   Elements), or `NULL` for the default.
#'   A chunk larger than the array is cut to the shape of the array.
#' @param convert_strings_to_categoricals Whether to convert character columns
#'   to factors before writing.
#' @param consolidate_metadata Whether to write consolidated metadata, inline
#'   in the root `zarr.json`, after all Elements.
#' @param ... Dataset arguments for every array.
#'   `compressors` is `NULL` for no compression, a name (`"zstd"`, `"gzip"`,
#'   `"blosc"`) or a list with a `name` and the options of that compressor
#'   (`level` for zstd and gzip, `cname`, `clevel` and `shuffle` for blosc),
#'   for example `list(name = "gzip", level = 5)`.
#'   The default is zstd.
#'   Scalars take the same compressor and the `null` Element is always zstd,
#'   as in Python.
#'   `compressor` is accepted as Python's older name for `compressors`, but
#'   scalars ignore it, as in Python.
#'   `shards` must be `NULL` until sharded writing is supported (any other
#'   value raises `anndata_not_supported_error`), and other arguments raise
#'   `anndata_invalid_argument_error`.
#'
#' @return `read_zarr()` returns an [AnnData()] and `write_zarr()` returns
#'   `NULL` invisibly.
#'
#' @examplesIf requireNamespace("Rarr", quietly = TRUE)
#' adata <- AnnData(matrix(as.numeric(1:6), nrow = 3))
#' path <- tempfile(fileext = ".zarr")
#' write_zarr(adata, path)
#' read_zarr(path)$shape
#'
#' @name zarr
NULL

check_store_path <- function(store, call) {
  valid <- is.character(store) &&
    length(store) == 1L &&
    !is.na(store) &&
    nzchar(store)
  if (!valid) {
    abort_invalid_argument(
      "{.arg store} must be a single directory path.",
      call
    )
  }
  path.expand(store)
}

#' @rdname zarr
#' @export
read_zarr <- function(store) {
  call <- rlang::current_env()
  path <- check_store_path(store, call)
  if (!file.exists(path)) {
    anndata_abort(
      "Cannot read {.path {path}}, the store does not exist.",
      "anndata_file_not_found_error",
      call = call
    )
  }
  root <- zarr_open(path, call)
  if (member_exists(root, "raw.X")) {
    abort_legacy("/raw.X", "a legacy raw layout", call = call)
  }
  read_elem(root, "/")
}

# The directory is cleared by the write, so only an empty directory or an
# existing zarr group is accepted
check_store_replaceable <- function(path, call) {
  if (
    !file.exists(path) ||
      length(list.files(path, all.files = TRUE, no.. = TRUE)) == 0L
  ) {
    return(invisible(NULL))
  }
  is_group <- dir.exists(path) &&
    any(file.exists(file.path(path, c("zarr.json", ".zgroup"))))
  if (!is_group) {
    anndata_abort(
      "Cannot write to {.path {path}}, it exists and is not a zarr store.",
      "anndata_invalid_value_error",
      path = path,
      call = call
    )
  }
  invisible(NULL)
}

#' @rdname zarr
#' @export
write_zarr <- function(
  adata,
  store,
  chunks = NULL,
  convert_strings_to_categoricals = TRUE, # nolint: object_length_linter.
  consolidate_metadata = TRUE,
  ...
) {
  call <- rlang::current_env()
  if (!inherits(adata, "AnnData")) {
    abort_invalid_argument(
      "{.arg adata} must be an {.cls AnnData}, not
       {.obj_type_friendly {adata}}.",
      call
    )
  }
  path <- check_store_path(store, call)
  check_x_and_layers_are_2d(adata, call)
  if (!is.null(chunks)) {
    check_chunks(chunks, call)
  }
  dataset_kwargs <- check_zarr_dataset_args(list(...), call)
  if (anndata_settings$zarr_write_format != 3) {
    abort_not_supported(
      "Writing zarr version 2 is not yet supported, set the
       {.field zarr_write_format} setting to 3.",
      call = call
    )
  }
  check_store_replaceable(path, call)
  if (convert_strings_to_categoricals) {
    adata$strings_to_categoricals()
    raw <- adata$raw
    if (!is.null(raw)) {
      raw$var <- categorise_frame(raw$var, call)
    }
  }
  unlink(path, recursive = TRUE)
  root <- zarr_create(path)
  dataset_kwargs$chunks <- chunks
  write_elem(root, "/", adata, dataset_kwargs, call = call)
  if (consolidate_metadata) {
    zarr_consolidate(path)
  }
  invisible(NULL)
}

# The dataset arguments `...` of `write_zarr()`: `compressors` (or Python's
# older name `compressor`) and `shards`. Python raises a `TypeError` for any
# other argument, such as the h5py `compression`.
check_zarr_dataset_args <- function(args, call) {
  if (length(args) == 0L) {
    return(list())
  }
  known <- c("compressors", "compressor", "shards")
  if (is.null(names(args)) || !all(names(args) %in% known)) {
    abort_invalid_argument(
      "Dataset arguments of a zarr store must be named {.arg compressors} or
       {.arg shards}.",
      call
    )
  }
  if ("compressor" %in% names(args)) {
    # As Python, `compressor` replaces `compressors` when both are given
    args <- args[names(args) != "compressors"]
    names(args)[names(args) == "compressor"] <- "compressors"
    args[["legacy_compressor"]] <- TRUE
  }
  if ("shards" %in% names(args)) {
    if (!is.null(args[["shards"]])) {
      abort_not_supported(
        "Writing sharded zarr arrays is not yet supported, use
         {.code shards = NULL}.",
        call = call
      )
    }
    args[["shards"]] <- NULL
  }
  args
}

check_chunks <- function(chunks, call) {
  valid <- is.numeric(chunks) &&
    length(chunks) > 0L &&
    !anyNA(chunks) &&
    all(chunks >= 1) &&
    all(chunks == round(chunks))
  if (!valid) {
    abort_invalid_argument(
      "{.arg chunks} must be a vector of positive whole numbers.",
      call
    )
  }
}
