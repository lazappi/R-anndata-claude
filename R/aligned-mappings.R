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
  varp = list(axis = 2L, pairwise = TRUE, class = "PairwiseArrays")
)

is_frame <- function(x) {
  is.data.frame(x) || methods::is(x, "DataFrame")
}

check_key <- function(key, call) {
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
      private$store <- list()
    },
    #' @description The value stored under `key`, or `NULL`.
    get = function(key) {
      check_key(key, rlang::caller_env())
      private$store[[key]]
    },
    #' @description Validate `value` and store it under `key`.
    set = function(key, value, call = rlang::caller_env()) {
      check_key(key, call)
      if (is.null(value)) {
        private$store[[key]] <- NULL
        return(invisible(self))
      }
      private$store[[key]] <- private$validate(value, key, call)
      invisible(self)
    },
    #' @description Remove `key`, if present.
    remove = function(key) {
      check_key(key, rlang::caller_env())
      private$store[[key]] <- NULL
      invisible(self)
    },
    #' @description Replace the whole contents with a named list.
    replace = function(value, call = rlang::caller_env()) {
      if (is_aligned_mapping(value)) {
        value <- as.list(value)
      }
      value <- value %||% list()
      keys <- names(value)
      if (!is.list(value) || is_frame(value)) {
        abort_invalid_argument(
          "{.field {private$attrname}} must be a named list or {.code NULL}.",
          call
        )
      }
      if (length(value)) {
        if (is.null(keys) || anyNA(keys) || !all(nzchar(keys))) {
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
      for (key in names(store)) {
        store[[key]] <- private$validate(store[[key]], key, call)
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
    validate = function(value, key, call) {
      kind <- aligned_kinds[[private$attrname]]
      parent <- private$parent
      what <- paste0(
        private$attrname,
        "[[",
        encodeString(key, quote = "'"),
        "]]"
      )
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
      right_shape <- rep(
        parent$shape[[kind$axis]],
        if (kind$pairwise) 2L else 1L
      )
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
