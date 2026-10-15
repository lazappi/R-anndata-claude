#' Aligned mappings: obsm, varm, obsp and varp
#'
#' Internal R6 class behind `adata$obsm`, `adata$varm`, `adata$obsp` and
#' `adata$varp`, following `src/anndata/_core/aligned_mapping.py`.
#' Axis arrays (obsm and varm) need a first dimension equal to n_obs or n_vars,
#' and accept a `data.frame` or `DataFrame` whose row names equal the obs_names
#' or var_names.
#' Pairwise arrays (obsp and varp) need both dimensions equal to n_obs or
#' n_vars.
#' A plain numeric or logical vector becomes a one column matrix, as a
#' 1-D numpy array does in Python.
#'
#' The mapping supports `[[`, `$`, `[[<-`, `$<-`, `names()`, `length()` and
#' `as.list()`, and assigning `NULL` removes a key.
#' `$` looks up keys first, so a key named like a method (`get`, `set`,
#' `remove`, `replace`, `keys`) hides it, and `[[` is always safe.
#'
#' @param key A single non-empty string.
#' @param value The value to store, or `NULL` to remove `key`.
#' @param call The call reported by conditions.
#'
#' @name anndata-aligned-mappings
#' @keywords internal
NULL

aligned_kinds <- list(
  obsm = list(axis = 1L, pairwise = FALSE, class = "AxisArrays"),
  varm = list(axis = 2L, pairwise = FALSE, class = "AxisArrays"),
  obsp = list(axis = 1L, pairwise = TRUE, class = "PairwiseArrays"),
  varp = list(axis = 2L, pairwise = TRUE, class = "PairwiseArrays"),
  layers = list(axis = 1:2, pairwise = FALSE, class = "Layers")
)

is_frame <- function(x) {
  is.data.frame(x) || methods::is(x, "DataFrame")
}

# The `NA` key addresses X in layers (ADR 0004), and `[[NA]]` gives a logical
check_key <- function(key, call, allow_na = FALSE) {
  if (allow_na && length(key) == 1L && is.na(key) && !is.object(key)) {
    return(NA_character_)
  }
  if (!is.character(key) || length(key) != 1L || is.na(key) || !nzchar(key)) {
    abort_invalid_argument(
      "A key must be a single non-empty string.",
      call
    )
  }
  key
}

# Python only reshapes 1-D numpy arrays, which are plain vectors in R
as_column <- function(value) {
  if (is_plain_vector(value)) {
    return(copy_dtype(matrix(value, ncol = 1L), value))
  }
  value
}

#' @noRd
aligned_mapping_class <- R6Class(
  "AnnDataAlignedMapping",
  cloneable = FALSE,
  public = list(
    #' @description Create an empty mapping aligned to `parent`.
    #' @param parent The `AnnData` the mapping belongs to.
    #' @param attrname One of `"obsm"`, `"varm"`, `"obsp"` and `"varp"`.
    initialize = function(parent, attrname) {
      private$parent <- parent
      private$attrname <- attrname
      private$is_layers <- identical(attrname, "layers")
      private$store <- list()
    },
    #' @description The value stored under `key`, or `NULL`.
    get = function(key) {
      key <- check_key(key, rlang::caller_env(), private$is_layers)
      position <- match(key, names(private$store))
      if (is.na(position)) NULL else private$store[[position]]
    },
    #' @description Validate `value` and store it under `key`.
    set = function(key, value, call = rlang::caller_env()) {
      key <- check_key(key, call, private$is_layers)
      if (is.null(value)) {
        private$drop(key)
        return(invisible(self))
      }
      private$put(key, private$validate(value, key, call))
      invisible(self)
    },
    #' @description Remove `key`, if present.
    remove = function(key) {
      key <- check_key(key, rlang::caller_env(), private$is_layers)
      private$drop(key)
      invisible(self)
    },
    #' @description Remove every key. In layers `keep_x` decides whether X
    #'   stays, and `NULL` keeps it with a warning, as Python does.
    #' @param keep_x `TRUE`, `FALSE` or `NULL`.
    clear = function(keep_x = NULL, call = rlang::caller_env()) {
      if (!private$is_layers) {
        private$store <- list()
        return(invisible(self))
      }
      if (is.null(keep_x)) {
        warn_future(
          "{.code layers$clear()} currently keeps {.field X} (stored under the
           {.code NA} key), but a future release may drop it. Pass
           {.code keep_x = TRUE} to keep it or {.code keep_x = FALSE} to drop
           it and silence this warning.",
          call = call
        )
        keep_x <- TRUE
      }
      if (!is.logical(keep_x) || length(keep_x) != 1L || is.na(keep_x)) {
        abort_invalid_argument(
          "{.arg keep_x} must be {.code TRUE}, {.code FALSE} or {.code NULL}.",
          call
        )
      }
      x <- private$store[is.na(names(private$store))]
      private$store <- if (keep_x) x else list()
      invisible(self)
    },
    #' @description Replace the whole contents with a named list.
    replace = function(value, call = rlang::caller_env()) {
      if (is_aligned_mapping(value)) {
        value <- as.list(value)
      }
      value <- value %||% list()
      keys <- names(value)
      layers <- private$is_layers
      if (!is.list(value) || is_frame(value)) {
        abort_invalid_argument(
          "{.field {private$attrname}} must be a named list or {.code NULL}.",
          call
        )
      }
      if (length(value)) {
        named <- !is.null(keys) && (layers || !anyNA(keys))
        if (!named || !all(nzchar(keys) | is.na(keys))) {
          abort_invalid_argument(
            "{.field {private$attrname}} must be a fully named list.",
            call
          )
        }
        if (anyDuplicated(keys)) {
          abort_invalid_argument(
            "{.field {private$attrname}} has duplicated keys.",
            call
          )
        }
      }
      # Validate everything before replacing anything
      store <- value[!vapply(value, is.null, logical(1))]
      for (i in seq_along(store)) {
        store[[i]] <- private$validate(store[[i]], names(store)[[i]], call)
      }
      if (layers && anyNA(names(private$store)) && !anyNA(keys)) {
        warn_future(
          "Assigning to {.field layers} without an {.code NA} key currently
           preserves {.field X}, but a future release may drop it. Include
           {.code NA = adata$X} to keep it, or {.code NA = NULL} to drop it and
           silence this warning.",
          call = call
        )
        store <- c(store, private$store[is.na(names(private$store))])
      }
      private$store <- store
      invisible(self)
    },
    #' @description Give every data frame the names of the parent axis.
    #' @param new_names,index_name The names and their index name.
    rename_frames = function(new_names, index_name) {
      for (key in names(private$store)) {
        value <- private$store[[key]]
        if (is_frame(value)) {
          value <- with_frame_names(value, new_names)
          private$store[[key]] <- with_index_name(value, index_name)
        }
      }
      invisible(self)
    },
    #' @description The keys in insertion order.
    keys = function() {
      names(private$store) %||% character()
    },
    #' @description The stored values as a named list.
    to_list = function() {
      private$store
    },
    #' @description Print like Python's `repr`.
    print = function(...) {
      keys <- paste0("'", names(private$store), "'", collapse = ", ")
      cat(
        aligned_kinds[[private$attrname]]$class,
        " with keys: ",
        keys,
        "\n",
        sep = ""
      )
      invisible(self)
    }
  ),
  private = list(
    parent = NULL,
    attrname = NULL,
    store = NULL,
    is_layers = FALSE,
    # Keys are matched with `match()` because `NA` (X) is not a valid `[[` name
    put = function(key, value) {
      position <- match(key, names(private$store))
      if (is.na(position)) {
        private$store <- c(private$store, list(value))
        names(private$store)[[length(private$store)]] <- key
      } else {
        private$store[[position]] <- value
      }
    },
    drop = function(key) {
      position <- match(key, names(private$store))
      if (!is.na(position)) {
        private$store <- private$store[-position]
      }
    },
    validate = function(value, key, call) {
      kind <- aligned_kinds[[private$attrname]]
      parent <- private$parent
      what <- paste0(
        private$attrname,
        "[[",
        if (is.na(key)) "NA" else encodeString(key, quote = "'"),
        "]]"
      )
      if (private$is_layers && is_frame(value)) {
        value <- as.matrix(value)
      }
      if (is_frame(value)) {
        if (kind$pairwise) {
          anndata_abort(
            "{.field {what}} cannot be a data frame, use a matrix.",
            "anndata_unsupported_value_error",
            call = call
          )
        }
        return(private$validate_frame(value, what, call))
      }
      value <- as_column(value)
      value <- as_anndata_matrix(
        value,
        allow_array = TRUE,
        what = what,
        call = call
      )
      right_shape <- if (private$is_layers) {
        parent$shape
      } else {
        rep(parent$shape[[kind$axis]], if (kind$pairwise) 2L else 1L)
      }
      actual_shape <- dim(value)[seq_along(right_shape)]
      if (!identical(as.integer(actual_shape), as.integer(right_shape))) {
        abort_dimension(
          "Value passed for key {.val {key}} is of incorrect shape.
           Values of {.field {private$attrname}} must match the dimensions
           of the parent. Value had shape ({actual_shape}) while it should
           have had ({right_shape}).",
          what = private$attrname,
          call = call
        )
      }
      # The X setter reports its own non-2-D warning
      if (private$is_layers && !is.na(key) && length(dim(value)) > 2L) {
        anndata_warn(
          "Layer {.val {key}} must be 2-dimensional, but got an array with
           shape ({dim(value)}). Higher-dimensional arrays violate the AnnData
           specification and cannot be written to disk.",
          "anndata_non_2d_warning",
          call = call
        )
      }
      value
    },
    # Row names must equal the names of the aligned axis, as Python's index
    validate_frame = function(value, what, call) {
      kind <- aligned_kinds[[private$attrname]]
      frame <- if (kind$axis == 1L) private$parent$obs else private$parent$var
      names <- rownames(frame)
      automatic <- is.data.frame(value) && automatic_row_names(value)
      actual <- if (automatic) NULL else rownames(value)
      if (!identical(as.character(actual), as.character(names))) {
        anndata_abort(
          "The row names of {.field {what}} do not match the
           {if (kind$axis == 1L) 'observation' else 'variable'} names of the
           parent.",
          "anndata_names_mismatch_error",
          call = call
        )
      }
      if (is.data.frame(value)) {
        value <- S4Vectors::DataFrame(value, check.names = FALSE)
      }
      value <- with_frame_names(value, names)
      S4Vectors::metadata(value) <- list()
      # Python gives the value the index name of the parent
      with_index_name(value, frame_index_name(frame))
    }
  )
)

is_aligned_mapping <- function(x) {
  inherits(x, "AnnDataAlignedMapping")
}

#' @export
#' @noRd
`$.AnnDataAlignedMapping` <- function(x, name) {
  value <- .subset2(x, "get")(name)
  if (!is.null(value)) {
    return(value)
  }
  .subset2(x, name)
}

#' @export
#' @noRd
`[[.AnnDataAlignedMapping` <- function(x, i, ...) {
  .subset2(x, "get")(i)
}

#' @export
#' @noRd
`[[<-.AnnDataAlignedMapping` <- function(x, i, value) {
  .subset2(x, "set")(i, value, call = rlang::caller_env())
  x
}

#' @export
#' @noRd
`$<-.AnnDataAlignedMapping` <- function(x, name, value) {
  .subset2(x, "set")(name, value, call = rlang::caller_env())
  x
}

#' @export
#' @noRd
names.AnnDataAlignedMapping <- function(x) {
  .subset2(x, "keys")()
}

#' @export
#' @noRd
length.AnnDataAlignedMapping <- function(x) {
  length(.subset2(x, "keys")())
}

#' @export
#' @noRd
as.list.AnnDataAlignedMapping <- function(x, ...) {
  .subset2(x, "to_list")()
}
