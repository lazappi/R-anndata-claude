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

#' @rdname io-anndata
write_anndata <- function(store, key, value, dataset_kwargs, path) {
  call <- rlang::caller_env()
  check_x_and_layers_are_2d(value, call)
  group <- if (identical(key, "/")) {
    rhdf5::H5Gopen(store, "/")
  } else {
    rhdf5::H5Gcreate(store, key)
  }
  on.exit(rhdf5::H5Gclose(group), add = TRUE)
  set_elem_attr(group, "encoding-type", "anndata")
  set_elem_attr(group, "encoding-version", "0.1.0")

  if (!is.null(value$X)) {
    write_elem(group, "X", value$X, dataset_kwargs, call)
  }
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
  }
  invisible(NULL)
}

#' @rdname io-anndata
write_raw <- function(store, key, value, dataset_kwargs, path) {
  call <- rlang::caller_env()
  group <- rhdf5::H5Gcreate(store, key)
  on.exit(rhdf5::H5Gclose(group), add = TRUE)
  set_elem_attr(group, "encoding-type", "raw")
  set_elem_attr(group, "encoding-version", "0.1.0")
  write_elem(group, "X", value$X, dataset_kwargs, call)
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

read_anndata_elem <- function(elem, path, store) {
  members <- rhdf5::h5ls(elem, recursive = FALSE)$name
  prefix <- if (identical(path, "/")) "/" else paste0(path, "/")
  slots <- list()
  for (key in intersect(anndata_slot_keys, members)) {
    slots[key] <- list(read_elem(store, paste0(prefix, key)))
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
  adata
}

register_writer("AnnData", "anndata", "0.1.0", write_anndata)
register_writer("Raw", "raw", "0.1.0", write_raw)
register_reader("anndata", "0.1.0", read_anndata_elem)
register_reader("raw", "0.1.0", read_anndata_elem)
