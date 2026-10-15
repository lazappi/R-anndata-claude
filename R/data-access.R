abort_key <- function(message, class, call, .envir = parent.frame()) {
  anndata_abort(message, class, call = call, .envir = .envir)
}

# The matrix of layer `layer`, or X when `layer` is `NULL`
layer_matrix <- function(
  adata,
  layer,
  call,
  x_class = "anndata_missing_x_error"
) {
  value <- .subset2(adata, "layers")$get(layer %||% NA_character_)
  if (is.null(value) && is.null(layer)) {
    abort_key("{.field X} is {.code NULL}.", x_class, call)
  }
  if (is.null(value)) {
    abort_key("Layer {.val {layer}} not found.", "anndata_key_error", call)
  }
  value
}

# Mirrors `to_df`: a dense data frame with the names as dimnames
adata_to_df <- function(adata, layer, call) {
  x <- layer_matrix(adata, layer, call)
  if (is_sparse(x)) {
    x <- as.matrix(x)
  }
  dimnames(x) <- NULL
  obs_names <- .subset2(adata, "obs_names")
  if (anyNA(obs_names) || anyDuplicated(obs_names)) {
    abort_key(
      "{.field obs_names} must be unique and not missing to make a data
       frame, because R row names are unique.",
      "anndata_names_not_unique_error",
      call
    )
  }
  df <- as.data.frame(x, stringsAsFactors = FALSE)
  names(df) <- .subset2(adata, "var_names")
  rownames(df) <- obs_names
  df
}

# Mirrors `_get_vector_ambiguous`. `axis` is the axis of the returned vector.
adata_vector <- function(adata, k, axis, layer, call) {
  if (!rlang::is_string(k)) {
    abort_invalid_argument("{.arg k} must be a single string.", call)
  }
  other <- if (axis == "obs") "var" else "obs"
  frame <- .subset2(adata, axis)
  in_frame <- k %in% colnames(frame)
  position <- match(k, .subset2(adata, paste0(other, "_names")))
  if (in_frame && !is.na(position)) {
    abort_key(
      "Key {.val {k}} could be found in both {.field {other}_names} and the
       columns of {.field {axis}}.",
      "anndata_ambiguous_key_error",
      call
    )
  }
  if (!in_frame && is.na(position)) {
    abort_key(
      "Could not find key {.val {k}} in {.field {other}_names} or the
       columns of {.field {axis}}.",
      "anndata_key_error",
      call
    )
  }
  if (in_frame) {
    return(frame[[k]])
  }
  value <- layer_matrix(adata, layer, call, "anndata_key_error")
  as.vector(if (axis == "obs") value[, position] else value[position, ])
}
