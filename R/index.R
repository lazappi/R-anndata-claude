#' Index helpers
#'
#' Internal helpers that turn an R index into positions along one axis.
#' Indices use R semantics, a deliberate deviation from Python:
#' positive integers are 1-based positions (repeats and reordering allowed),
#' negative integers exclude positions, logical vectors must have the length of
#' the axis and character vectors match names, taking the first match.
#' Zero, `NA`, unknown names, out-of-range positions and mixed signs raise an
#' `anndata_index_error`.
#'
#' @param i An index, or `NULL` to keep the whole axis.
#' @param names The names along the axis.
#' @param what Description of the axis used in error messages.
#' @param call The call reported by errors.
#' @param df A `DataFrame` or `data.frame`.
#' @param idx Integer positions, or `NULL` to keep every row.
#'
#' @name anndata-index
#' @keywords internal
NULL

abort_index <- function(message, call, .envir = parent.frame()) {
  anndata_abort(message, "anndata_index_error", call = call, .envir = .envir)
}

#' @rdname anndata-index
normalize_index <- function(i, names, what, call = rlang::caller_env()) {
  n <- length(names)
  if (is.null(i)) {
    return(seq_len(n))
  }
  if (is.factor(i)) {
    i <- as.character(i)
  }
  if (!(is.numeric(i) || is.logical(i) || is.character(i)) || is.object(i)) {
    abort_index(
      "The index for {.field {what}} must be numeric, logical or character,
       not {.cls {class(i)}}.",
      call
    )
  }
  if (anyNA(i)) {
    abort_index(
      "The index for {.field {what}} must not contain {.code NA}.",
      call
    )
  }
  if (is.logical(i)) {
    if (length(i) != n) {
      abort_index(
        "A logical index for {.field {what}} must have length {n}, not
         {length(i)}.",
        call
      )
    }
    return(which(i))
  }
  if (is.character(i)) {
    positions <- match(i, names)
    if (anyNA(positions)) {
      abort_index(
        "Names not found in {.field {what}}: {.val {i[is.na(positions)]}}.",
        call
      )
    }
    return(positions)
  }
  if (any(i != round(i))) {
    abort_index(
      "A numeric index for {.field {what}} must contain whole numbers.",
      call
    )
  }
  i <- as.integer(i)
  if (any(i == 0L)) {
    abort_index("An index for {.field {what}} must not contain zero.", call)
  }
  if (any(i < 0L) && any(i > 0L)) {
    abort_index(
      "An index for {.field {what}} cannot mix positive and negative
       positions.",
      call
    )
  }
  if (any(abs(i) > n)) {
    abort_index(
      "Positions out of range for {.field {what}}, which has {n} entries.",
      call
    )
  }
  if (all(i < 0L)) {
    i <- seq_len(n)[i]
  }
  i
}

# Row subset that keeps names (which may be `NA` or duplicated) and the index
# name, none of which `[` is guaranteed to keep
#' @rdname anndata-index
subset_frame <- function(df, idx = NULL) {
  if (is.null(idx)) {
    return(df)
  }
  if (is.data.frame(df)) {
    df <- S4Vectors::DataFrame(df, check.names = FALSE)
  }
  names <- rownames(df)[idx]
  index_name <- frame_index_name(df)
  out <- with_frame_names(df, NULL)[idx, , drop = FALSE]
  out <- with_frame_names(out, names)
  with_index_name(out, index_name)
}

# Subsets an aligned value on its first dimension, or both when pairwise
subset_value <- function(x, idx, pairwise = FALSE) {
  if (is.null(idx)) {
    return(x)
  }
  if (is_frame(x)) {
    return(subset_frame(x, idx))
  }
  matrix_subset(x, idx, if (pairwise) idx)
}

# Independent copy of `adata` restricted to observations `oidx` and variables
# `vidx` (`NULL` keeps an axis), with `raw` as given to `AnnData()`
subset_slots <- function(adata, oidx = NULL, vidx = NULL, raw = NULL) {
  by_axis <- function(mapping, idx, pairwise = FALSE) {
    lapply(as.list(mapping), subset_value, idx = idx, pairwise = pairwise)
  }
  layers <- lapply(
    as.list(adata$layers),
    function(x) matrix_subset(x, oidx, vidx)
  )
  # Repeated names are expected when indices repeat
  suppressWarnings(
    AnnData(
      obs = subset_frame(adata$obs, oidx),
      var = subset_frame(adata$var, vidx),
      uns = adata$uns,
      obsm = by_axis(adata$obsm, oidx),
      varm = by_axis(adata$varm, vidx),
      obsp = by_axis(adata$obsp, oidx, TRUE),
      varp = by_axis(adata$varp, vidx, TRUE),
      layers = layers,
      raw = raw,
      shape = if (!length(layers)) {
        c(
          length(oidx %||% seq_len(adata$n_obs)),
          length(vidx %||% seq_len(adata$n_vars))
        )
      }
    ),
    classes = "anndata_names_not_unique_warning"
  )
}

# Drops the unused levels of the factor columns of `sub`, a row subset of
# `full`, and subsets the matching `<col>_colors` entry of `uns` (Python
# `_remove_unused_categories`). Returns the new frame and `uns`.
drop_unused_categories <- function(full, sub, uns) {
  for (key in colnames(full)) {
    column <- full[[key]]
    if (!is.factor(column)) {
      next
    }
    kept <- droplevels(sub[[key]])
    sub[[key]] <- kept
    color_key <- paste0(key, "_colors")
    colors <- uns[[color_key]]
    if (is.null(colors)) {
      next
    }
    if (length(colors) != nlevels(column)) {
      uns[[color_key]] <- NULL
    } else {
      uns[[color_key]] <- colors[levels(column) %in% levels(kept)]
    }
  }
  list(frame = sub, uns = uns)
}

# Independent copy of `adata` restricted to observations `oidx` and variables
# `vidx` (`NULL` keeps an axis), with raw subset on observations only
subset_anndata <- function(adata, oidx = NULL, vidx = NULL) {
  raw <- adata$raw
  new <- subset_slots(
    adata,
    oidx,
    vidx,
    raw = if (!is.null(raw)) {
      list(
        X = matrix_subset(raw$X, oidx, NULL),
        var = raw$var,
        varm = as.list(raw$varm)
      )
    }
  )
  if (get_setting("remove_unused_categories")) {
    obs <- drop_unused_categories(adata$obs, new$obs, new$uns)
    var <- drop_unused_categories(adata$var, new$var, obs$uns)
    new$obs <- obs$frame
    new$var <- var$frame
    new$uns <- var$uns
  }
  new
}

#' @export
#' @noRd
`[.AnnData` <- function(x, i, j) {
  call <- rlang::caller_env()
  rows <- if (missing(i)) NULL else i
  cols <- if (missing(j) || nargs() < 3L) NULL else j
  oidx <- normalize_index(rows, .subset2(x, "obs_names"), "obs", call)
  vidx <- normalize_index(cols, .subset2(x, "var_names"), "var", call)
  subset_anndata(x, oidx, vidx)
}
