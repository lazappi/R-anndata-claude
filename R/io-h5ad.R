#' Read and write h5ad files
#'
#' `read_h5ad()` reads an `.h5ad` file into an [AnnData()], and `write_h5ad()`
#' (also `adata$write_h5ad()`) writes one, following Python anndata 0.13.4
#' (`h5ad.py`).
#' Files round trip between R and Python.
#'
#' `write_h5ad()` replaces an existing file.
#' With `convert_strings_to_categoricals`, character columns of `obs`, `var` and
#' `raw$var` with fewer distinct values than rows are converted to factors in
#' `adata` first, **in place**, as Python does.
#' `X` and every layer must have at most 2 dimensions.
#'
#' `adata$unwriteable()` reports whether the object holds a value that cannot
#' be written, which is `TRUE` for a value without an encoding (a function, a
#' `Date`, a partly named list) and for `X` or a layer with more than 2
#' dimensions.
#' `store_type` is `NULL`, `"h5"` or `"zarr"` and does not change the result,
#' because every Element that can be written to one store can be written to
#' the other.
#'
#' @param filename Path of the `.h5ad` file.
#' @param backed Backed mode, not yet supported so it must be `NULL` or
#'   `FALSE`.
#' @param as_sparse Elements stored dense to read as sparse matrices, `"X"`
#'   and/or `"raw/X"` (`"raw.X"` is accepted too).
#'   An Element that is already sparse on disk is an error.
#' @param as_sparse_fmt Sparse format of `as_sparse`, `"csr"` or `"csc"`.
#' @param chunk_size Number of rows (CSR) or columns (CSC) converted to sparse
#'   at a time.
#' @param compression `NULL`, `"gzip"` or `"lzf"`, the HDF5 filter applied to
#'   every dataset except scalars.
#' @param compression_opts The gzip level from 0 to 9 (4 when `NULL`), which
#'   `"lzf"` does not accept.
#' @param as_dense Sparse matrices to write dense, `"X"` and/or `"raw/X"`
#'   (`"raw.X"` is accepted too), which keeps the On-disk dtype.
#'   Dense matrices are written as they are.
#'   Unlike Python the `/raw` group keeps its Encoding attributes.
#' @param adata An [AnnData()].
#' @param convert_strings_to_categoricals Whether to convert character columns
#'   to factors before writing.
#'
#' @return `read_h5ad()` returns an [AnnData()] and `write_h5ad()` returns
#'   `NULL` invisibly.
#'
#' @examples
#' adata <- AnnData(matrix(as.numeric(1:6), nrow = 3))
#' path <- tempfile(fileext = ".h5ad")
#' write_h5ad(adata, path)
#' read_h5ad(path)$shape
#'
#' @name h5ad
NULL

check_filename <- function(filename, call) {
  valid <- is.character(filename) &&
    length(filename) == 1L &&
    !is.na(filename) &&
    nzchar(filename)
  if (!valid) {
    abort_invalid_argument(
      "{.arg filename} must be a single file path.",
      call
    )
  }
  path.expand(filename)
}

#' @rdname h5ad
#' @export
read_h5ad <- function(
  filename,
  backed = NULL,
  as_sparse = character(),
  as_sparse_fmt = c("csr", "csc"),
  chunk_size = 6000L
) {
  call <- rlang::current_env()
  if (!is.null(backed) && !isFALSE(backed)) {
    abort_not_supported(
      "Backed mode ({.arg backed}) is not yet supported.",
      call = call
    )
  }
  if (
    !is.character(as_sparse_fmt) ||
      length(as_sparse_fmt) == 0L ||
      !all(as_sparse_fmt %in% c("csr", "csc"))
  ) {
    abort_not_supported(
      "Dense formats can only be read to CSR or CSC matrices at this time.",
      call = call
    )
  }
  as_sparse_fmt <- as_sparse_fmt[[1L]]
  if (!is.character(as_sparse) || anyNA(as_sparse)) {
    abort_invalid_argument("{.arg as_sparse} must be a character vector.", call)
  }
  as_sparse[as_sparse == "raw.X"] <- "raw/X"
  if (!all(as_sparse %in% c("X", "raw/X"))) {
    abort_not_supported(
      "Currently only {.val X} and {.val raw/X} can be read as sparse.",
      call = call
    )
  }
  valid_chunk <- is.numeric(chunk_size) &&
    length(chunk_size) == 1L &&
    !is.na(chunk_size) &&
    chunk_size >= 1 &&
    chunk_size == round(chunk_size)
  if (!valid_chunk) {
    abort_invalid_argument(
      "{.arg chunk_size} must be a positive whole number.",
      call
    )
  }
  read_state$as_sparse <- as_sparse
  read_state$fmt <- as_sparse_fmt
  read_state$chunk_size <- as.integer(chunk_size)
  on.exit(read_state$as_sparse <- character(), add = TRUE)
  filename <- check_filename(filename, call)
  if (!file.exists(filename)) {
    anndata_abort(
      "Cannot read {.path {filename}}, the file does not exist.",
      "anndata_file_not_found_error",
      call = call
    )
  }
  store <- rhdf5::H5Fopen(filename, flags = "H5F_ACC_RDONLY")
  on.exit(rhdf5::H5Fclose(store), add = TRUE)
  read_elem(store, "/")
}

#' @rdname h5ad
#' @export
write_h5ad <- function(
  adata,
  filename,
  compression = NULL,
  compression_opts = NULL,
  as_dense = character(),
  convert_strings_to_categoricals = TRUE # nolint: object_length_linter.
) {
  call <- rlang::current_env()
  if (!inherits(adata, "AnnData")) {
    abort_invalid_argument(
      "{.arg adata} must be an {.cls AnnData}, not
       {.obj_type_friendly {adata}}.",
      call
    )
  }
  filename <- check_filename(filename, call)
  check_x_and_layers_are_2d(adata, call)
  if (!is.character(as_dense) || anyNA(as_dense)) {
    abort_invalid_argument("{.arg as_dense} must be a character vector.", call)
  }
  as_dense[as_dense == "raw.X"] <- "raw/X"
  if (!all(as_dense %in% c("X", "raw/X"))) {
    abort_not_supported(
      "Currently, only {.val X} and {.val raw/X} are supported values in
       {.arg as_dense}.",
      call = call
    )
  }
  if ("raw/X" %in% as_dense && is.null(adata$raw)) {
    abort_invalid_argument(
      "Cannot specify writing {.val raw/X} to dense if it doesn't exist.",
      call
    )
  }
  check_compression(compression, compression_opts, call)
  dataset_kwargs <- list(
    compression = compression,
    compression_opts = compression_opts,
    as_dense = as_dense
  )
  if (convert_strings_to_categoricals) {
    adata$strings_to_categoricals()
    raw <- adata$raw
    if (!is.null(raw)) {
      raw$var <- categorise_frame(raw$var, call)
    }
  }
  store <- rhdf5::H5Fcreate(filename, flags = "H5F_ACC_TRUNC")
  on.exit(rhdf5::H5Fclose(store), add = TRUE)
  write_elem(store, "/", adata, dataset_kwargs, call = call)
  invisible(NULL)
}

# Mirrors the `predicate` of `AnnData.unwriteable`, on the values of Slots
value_unwritable <- function(x) {
  if (is.null(x)) {
    return(FALSE)
  }
  if (inherits(x, "AnnData")) {
    return(adata_unwritable(x))
  }
  if (inherits(x, "Raw")) {
    return(
      any(vapply(as.list(x$varm), value_unwritable, logical(1))) ||
        value_unwritable(x$var) ||
        value_unwritable(x$X)
    )
  }
  if (is.factor(x)) {
    return(FALSE)
  }
  if (is.data.frame(x) || methods::is(x, "DataFrame")) {
    return(any(vapply(as.list(x), value_unwritable, logical(1))))
  }
  if (is.list(x) && !is.object(x)) {
    keys <- names(x)
    if (length(x) > 0L) {
      named <- !is.null(keys) && !anyNA(keys) && all(nzchar(keys))
      if (!named || anyDuplicated(keys) > 0L) {
        return(TRUE)
      }
    }
    return(any(vapply(x, value_unwritable, logical(1))))
  }
  is.null(lookup_writer(x))
}

adata_unwritable <- function(adata) {
  layers <- as.list(adata$layers)
  too_many_dims <- function(x) length(dim(x)) > 2L
  if (
    too_many_dims(adata$X) || any(vapply(layers, too_many_dims, logical(1)))
  ) {
    return(TRUE)
  }
  slots <- list(
    adata$obs,
    adata$var,
    adata$uns,
    as.list(adata$obsm),
    as.list(adata$varm),
    as.list(adata$obsp),
    as.list(adata$varp),
    # X is the `NA` layer, which is not a name a list can be written with
    layers_without_x(adata),
    list(X = adata$X),
    adata$raw
  )
  any(vapply(slots, value_unwritable, logical(1)))
}
