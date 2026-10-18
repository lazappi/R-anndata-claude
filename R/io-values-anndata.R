#' AnnData and Raw
#'
#' Reads and writes the Elements `anndata` and `raw`, both version 0.1.0.
#' Both are groups holding one Element per Slot.
#'
#' An `anndata` group has `X`, `obs`, `var`, `obsm`, `varm`, `obsp`, `varp`,
#' `layers`, `uns` and `raw`.
#' The `NA` layer (X, ADR 0004) is written to `X` and never inside `layers`.
#' `obsm`, `varm`, `obsp`, `varp`, `layers` and `uns` are always written as
#' `dict` groups, even when empty, as Python does.
#' A missing `X` is not written, and a group without `X` reads as `NULL`.
#' A `raw` group has `X`, `var` and `varm`, and is read as an `AnnData` that
#' the `raw` argument of [AnnData()] accepts.
#'
#' `X` and every layer must have at most 2 dimensions to be written, otherwise
#' `anndata_non_2d_error` is raised (`_check_x_and_layers_are_2d_on_write`).
#'
#' @param store An open rhdf5 file or group handle.
#' @param key Name of the Element within `store`, `"/"` writes into the root.
#' @param value An `AnnData` or `Raw`.
#' @param dataset_kwargs A list of dataset creation options.
#' @param path Path of the Element.
#' @param adata An `AnnData`.
#' @param call The call reported by errors.
#'
#' @name io-anndata
#' @keywords internal
NULL

# Python's `_non_2d_message`
non_2d_message <- function(value, name) {
  dims <- dim(value)
  if (length(dims) <= 2L) {
    return(NULL)
  }
  paste0(
    name,
    " must be 2-dimensional, but got an array with shape (",
    paste(dims, collapse = ", "),
    ") (ndim=",
    length(dims),
    "). Storing higher-dimensional arrays in `X` or `layers` violates the ",
    "AnnData specification, and cannot be written to disk."
  )
}

#' @rdname io-anndata
check_x_and_layers_are_2d <- function(adata, call = rlang::caller_env()) {
  layers <- as.list(adata$layers)
  keys <- names(layers) %||% character()
  messages <- list(non_2d_message(adata$X, "X"))
  for (i in which(!is.na(keys))) {
    name <- paste0("Layer ", encodeString(keys[[i]], quote = "'"))
    messages <- c(messages, list(non_2d_message(layers[[i]], name)))
  }
  messages <- Filter(Negate(is.null), messages)
  if (length(messages) > 0L) {
    anndata_abort(
      # Braces can only come from user keys, so they are escaped for cli
      gsub("([{}])", "\\1\\1", messages[[1L]]),
      "anndata_non_2d_error",
      call = call
    )
  }
  invisible(NULL)
}

# The layers without X, which is stored under the `NA` key
layers_without_x <- function(adata) {
  layers <- as.list(adata$layers)
  layers[!is.na(names(layers) %||% character())]
}

# Python's `write_sparse_as_dense`, which keeps the dtype of the data
densify <- function(x) {
  dense <- as.matrix(x)
  dtype <- get_dtype(x)[["data"]]
  if (!is.null(dtype) && !is.logical(dense)) {
    dense <- set_dtype(dense, dtype)
  }
  dense
}

# Writes X or raw X, dense when `name` is in `as_dense` and the matrix is sparse
write_x_elem <- function(group, x, name, dataset_kwargs, call) {
  if (inherits(x, "backed_dense") && methods::is(group, "H5IdComponent")) {
    return(write_backed_dense(group, x, dataset_kwargs, call))
  }
  x <- backed_in_memory(x)
  if (name %in% dataset_kwargs$as_dense && methods::is(x, "sparseMatrix")) {
    x <- densify(x)
  }
  # `chunks` applies to a dense X only, as in Python's `write_zarr`
  if (!identical(name, "X") || methods::is(x, "sparseMatrix")) {
    dataset_kwargs$chunks <- NULL
  }
  write_elem(group, "X", x, dataset_kwargs, call)
}

#' @rdname io-anndata
write_anndata <- function(store, key, value, dataset_kwargs, path) {
  call <- rlang::caller_env()
  check_x_and_layers_are_2d(value, call)
  group <- if (identical(key, "/")) {
    group_root(store)
  } else {
    group_create(store, key)
  }
  on.exit(node_close(group), add = TRUE)
  set_elem_attr(group, "encoding-type", "anndata")
  set_elem_attr(group, "encoding-version", "0.1.0")
  write_anndata_members(group, value, dataset_kwargs, call)
  invisible(NULL)
}

# Writes the members of an `anndata` group. `write_x = FALSE` leaves X as it is
# on disk, which is how a backed object is updated in place.
write_anndata_members <- function(
  group,
  value,
  dataset_kwargs,
  call,
  write_x = TRUE
) {
  if (write_x && !is.null(value$X)) {
    write_x_elem(group, value$X, "X", dataset_kwargs, call)
  }
  # Only X takes the `chunks` argument
  dataset_kwargs$chunks <- NULL
  slots <- list(
    obs = value$obs,
    var = value$var,
    uns = value$uns,
    obsm = as.list(value$obsm),
    varm = as.list(value$varm),
    obsp = as.list(value$obsp),
    varp = as.list(value$varp),
    layers = layers_without_x(value)
  )
  for (name in names(slots)) {
    write_elem(group, name, slots[[name]], dataset_kwargs, call)
  }
  if (!is.null(value$raw)) {
    write_elem(group, "raw", value$raw, dataset_kwargs, call)
  } else if (inherits(group, "zarr_node")) {
    # Python writes a missing raw as a null Element in zarr, not in h5ad
    write_elem(group, "raw", NULL, dataset_kwargs, call)
  }
  invisible(NULL)
}

#' @rdname io-anndata
write_raw <- function(store, key, value, dataset_kwargs, path) {
  call <- rlang::caller_env()
  group <- group_create(store, key)
  on.exit(node_close(group), add = TRUE)
  set_elem_attr(group, "encoding-type", "raw")
  set_elem_attr(group, "encoding-version", "0.1.0")
  write_x_elem(group, value$X, "raw/X", dataset_kwargs, call)
  write_elem(group, "var", value$var, dataset_kwargs, call)
  write_elem(group, "varm", as.list(value$varm), dataset_kwargs, call)
  invisible(NULL)
}

anndata_slot_keys <- c(
  "X",
  "obs",
  "var",
  "obsm",
  "varm",
  "obsp",
  "varp",
  "layers",
  "uns",
  "raw"
)

# The options of `read_h5ad()` that reach the readers, set for one read
read_state <- new.env(parent = emptyenv())
read_state$as_sparse <- character()
# The file manager while `read_h5ad(backed = )` reads, otherwise `NULL`
read_state$backed <- NULL
# `list(load_annotation_index = )` while `read_lazy()` reads, otherwise `NULL`
read_state$lazy <- NULL

# Python's `read_dense_as_csr` and `read_dense_as_csc`, in chunks of
# `chunk_size` rows (CSR) or columns (CSC)
dense_as_sparse <- function(x, path, call) {
  if (methods::is(x, "sparseMatrix")) {
    anndata_abort(
      "Cannot read {.path {path}} as sparse, it is already stored as sparse.",
      "anndata_invalid_argument_error",
      call = call
    )
  }
  if (length(dim(x)) != 2L) {
    anndata_abort(
      "Cannot read {.path {path}} as sparse, it is not 2-dimensional.",
      "anndata_invalid_argument_error",
      call = call
    )
  }
  csr <- identical(read_state$fmt, "csr")
  dtype <- get_dtype(x) %||% if (is.logical(x)) "bool" else native_dtype(x)
  plain <- drop_dtype(x)
  size <- dim(plain)[if (csr) 1L else 2L]
  # A symmetric matrix would get a symmetric class, so ask for a general one
  as_csc <- function(m) {
    methods::as(methods::as(m, "generalMatrix"), "CsparseMatrix")
  }
  if (size == 0L) {
    combined <- as_csc(plain)
  } else {
    chunks <- lapply(
      seq(1L, size, by = read_state$chunk_size),
      function(start) {
        index <- seq(start, min(start + read_state$chunk_size - 1L, size))
        as_csc(
          if (csr) {
            plain[index, , drop = FALSE]
          } else {
            plain[, index, drop = FALSE]
          }
        )
      }
    )
    combined <- if (csr) do.call(rbind, chunks) else do.call(cbind, chunks)
  }
  if (csr) {
    combined <- methods::as(combined, "RsparseMatrix")
  }
  default <- if (is.logical(plain)) "bool" else "float64"
  if (!identical(dtype, default)) {
    combined <- set_dtype(combined, c(data = dtype))
  }
  combined
}

read_anndata_elem <- function(elem, path, store) {
  call <- rlang::caller_env()
  members <- group_members(elem)
  prefix <- if (identical(path, "/")) "/" else paste0(path, "/")
  slots <- list()
  for (key in intersect(anndata_slot_keys, members)) {
    key_path <- paste0(prefix, key)
    value <- NULL
    if (key == "X" && !is.null(read_state$backed)) {
      # In backed mode X and raw X stay on disk
      value <- backed_x_elem(read_state$backed, key_path, store, call)
    }
    if (is.null(value) && !is.null(read_state$lazy)) {
      value <- read_lazy_slot(store, key_path, key, read_state$lazy, call)
    }
    if (is.null(value)) {
      value <- read_elem(store, key_path)
    }
    if (
      key == "X" &&
        is.null(read_state$backed) &&
        substring(key_path, 2L) %in% read_state$as_sparse
    ) {
      value <- dense_as_sparse(value, key_path, call)
    }
    slots[key] <- list(value)
  }
  # Higher-dimensional X and layers violate the spec, so the constructor
  # refuses them and they are set afterwards, which only warns as Python does
  deferred_x <- length(dim(slots$X)) > 2L
  deferred_layers <- vapply(
    slots$layers,
    function(layer) length(dim(layer)) > 2L,
    logical(1)
  )
  tall <- slots$layers[deferred_layers]
  if (deferred_x) {
    x <- slots$X
    slots$X <- NULL
  }
  if (length(tall) > 0L) {
    slots$layers <- slots$layers[!deferred_layers]
  }
  adata <- do.call(AnnData, slots[!vapply(slots, is.null, logical(1))])
  if (deferred_x) {
    adata$X <- x
  }
  for (key in names(tall)) {
    adata$layers[[key]] <- tall[[key]]
  }
  if (identical(path, "/") && !is.null(read_state$backed)) {
    .subset2(adata, "attach_file")(read_state$backed)
  }
  adata
}

register_writer("AnnData", "anndata", "0.1.0", write_anndata)
register_writer("Raw", "raw", "0.1.0", write_raw)
register_reader("anndata", "0.1.0", read_anndata_elem)
register_reader("raw", "0.1.0", read_anndata_elem)
