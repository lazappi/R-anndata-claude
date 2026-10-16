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
read_h5ad <- function(filename, backed = NULL) {
  call <- rlang::current_env()
  if (!is.null(backed) && !isFALSE(backed)) {
    abort_not_supported(
      "Backed mode ({.arg backed}) is not yet supported.",
      call = call
    )
  }
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
  if (convert_strings_to_categoricals) {
    adata$strings_to_categoricals()
    raw <- adata$raw
    if (!is.null(raw)) {
      raw$var <- categorise_frame(raw$var, call)
    }
  }
  store <- rhdf5::H5Fcreate(filename, flags = "H5F_ACC_TRUNC")
  on.exit(rhdf5::H5Fclose(store), add = TRUE)
  write_elem(store, "/", adata, call = call)
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
