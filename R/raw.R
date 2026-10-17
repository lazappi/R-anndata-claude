#' Raw
#'
#' Internal R6 class behind `adata$raw`, following
#' `src/anndata/_core/raw.py`.
#' A Raw holds `X`, `var` and `varm` and shares its observations with the parent
#' `AnnData`, so `obs_names` and `n_obs` come from the parent.
#'
#' Without `X` the Raw is built from the parent's own `X`, `var` and `varm`,
#' which is also what Python does when `adata$raw <- other` is given an
#' `other` whose `X` is `NULL`.
#'
#' `raw[i, j]` subsets with R indices (see `anndata-index`) and never drops
#' dimensions.
#' The result belongs to a copy of the parent restricted to the observations in
#' `i`, and keeps `varm` rows in step with `j`.
#' `raw[i]` subsets observations only.
#'
#' `var` and `X` may be assigned, which is what `raw$var$col <- v` needs, and
#' an assigned value is validated against the other Slots of the Raw.
#' In Python they are read-only properties that are modified in place.
#'
#' @param parent The `AnnData` the Raw belongs to.
#' @param X The raw data matrix with `n_obs` rows, or `NULL` to take X, var and
#'   varm from `parent`.
#' @param var Variable annotation, as for [AnnData()].
#' @param varm Aligned mapping or named list of arrays with a row per variable.
#' @param from_parent Whether to take X, var and varm from `parent`.
#' @param call The call reported by conditions.
#'
#' @name anndata-raw
#' @keywords internal
NULL

#' @noRd
raw_class <- R6Class(
  "Raw",
  cloneable = FALSE,
  public = list(
    #' @description Create a Raw for `parent`.
    initialize = function(
      parent,
      X = NULL,
      var = NULL,
      varm = NULL,
      from_parent = is.null(X),
      call = rlang::caller_env()
    ) {
      if (!is.null(X) && !from_parent) {
        X <- as_anndata_matrix(X, what = "raw$X", call = call)
        if (nrow(X) != parent$n_obs) {
          abort_dimension(
            "{.field X} has {nrow(X)} rows, but n_obs is {parent$n_obs}.",
            what = "raw$X",
            call = call
          )
        }
      }
      private$parent <- parent
      if (from_parent) {
        private$.X <- parent$X
        private$.var <- parent$var
        varm <- parent$varm
      } else {
        private$.X <- X
        private$.var <- as_annotation_frame(
          var,
          "var",
          if (is.null(X)) NULL else ncol(X),
          "X",
          call
        )
      }
      private$.varm <- aligned_mapping_class$new(self, "varm")
      private$.varm$replace(varm, call = call)
      invisible(self)
    },
    #' @description The Raw restricted to the observations `i` and variables
    #'   `j`, see [anndata-index].
    #' @param i,j Indices, or `NULL` to keep an axis whole.
    subset = function(i = NULL, j = NULL, call = rlang::caller_env()) {
      parent <- private$parent
      oidx <- normalize_index(i, parent$obs_names, "obs", call)
      vidx <- normalize_index(j, self$var_names, "var", call)
      new_parent <- subset_slots(parent, oidx)
      varm <- lapply(
        as.list(private$.varm),
        subset_value,
        idx = vidx
      )
      raw_class$new(
        new_parent,
        X = if (!is.null(private$.X)) {
          matrix_subset(private$.X, oidx, vidx)
        },
        var = subset_frame(private$.var, vidx),
        varm = varm,
        from_parent = FALSE,
        call = call
      )
    },
    #' @description Reads a backed `X` into memory (used when the parent
    #'   leaves backed mode).
    load_x = function() {
      private$.X <- backed_in_memory(private$.X)
      invisible(self)
    },
    #' @description A Raw with independent contents and the same parent.
    copy = function() {
      raw_class$new(
        private$parent,
        X = private$.X,
        var = private$.var,
        varm = as.list(private$.varm),
        from_parent = FALSE
      )
    },
    #' @description An `AnnData` made from the Raw and the parent's `obs`,
    #'   `obsm`, `obsp` and `uns`.
    to_adata = function() {
      parent <- private$parent
      AnnData(
        X = private$.X,
        var = private$.var,
        varm = as.list(private$.varm),
        obs = parent$obs,
        obsm = as.list(parent$obsm),
        obsp = as.list(parent$obsp),
        uns = parent$uns
      )
    }
  ),
  active = list(
    #' @field X The raw data matrix, or `NULL`.
    X = function(value) {
      if (missing(value)) {
        return(reopen_backed(private$.X))
      }
      private$set_x(value, rlang::caller_env())
    },
    #' @field var Annotation of the raw variables, a `DataFrame`.
    var = function(value) {
      if (missing(value)) {
        return(private$.var)
      }
      private$set_var(value, rlang::caller_env())
    },
    #' @field varm Aligned mapping of arrays with a row per raw variable.
    varm = function(value) {
      mapping <- private$.varm
      if (missing(value)) {
        return(mapping)
      }
      if (!identical(value, mapping)) {
        mapping$replace(value, call = rlang::caller_env())
      }
      invisible(NULL)
    },
    #' @field var_names Names of the raw variables.
    var_names = function(value) {
      if (!missing(value)) {
        abort_read_only("var_names")
      }
      rownames(private$.var)
    },
    #' @field obs_names Names of the observations, shared with the parent.
    obs_names = function(value) {
      if (!missing(value)) {
        abort_read_only("obs_names")
      }
      private$parent$obs_names
    },
    #' @field n_obs Number of observations.
    n_obs = function(value) {
      if (!missing(value)) {
        abort_read_only("n_obs")
      }
      private$parent$n_obs
    },
    #' @field n_vars Number of raw variables.
    n_vars = function(value) {
      if (!missing(value)) {
        abort_read_only("n_vars")
      }
      nrow(private$.var)
    },
    #' @field shape `c(n_obs, n_vars)`.
    shape = function(value) {
      if (!missing(value)) {
        abort_read_only("shape")
      }
      c(private$parent$n_obs, nrow(private$.var))
    }
  ),
  private = list(
    parent = NULL,
    .X = NULL,
    .var = NULL,
    .varm = NULL,
    set_x = function(value, call) {
      if (is.null(value)) {
        abort_invalid_argument("{.field raw$X} cannot be {.code NULL}.", call)
      }
      # Python's `Raw.X` has no setter, and R only needs one for nested
      # assignment, which hands back the same placeholder
      if (inherits(private$.X, "backed_x")) {
        if (!identical(value, private$.X)) {
          abort_not_supported(
            "{.field raw$X} of a backed {.cls AnnData} cannot be replaced.",
            call = call
          )
        }
        return(invisible(NULL))
      }
      value <- as_anndata_matrix(value, what = "raw$X", call = call)
      if (!identical(as.integer(dim(value)), self$shape)) {
        abort_dimension(
          "{.field raw$X} has shape ({dim(value)}) but the Raw has shape
           ({self$shape}).",
          what = "raw$X",
          call = call
        )
      }
      private$.X <- value
      invisible(NULL)
    },
    # Keeps the names unless the value brings its own, as for `adata$var`
    set_var = function(value, call) {
      value <- as_annotation_frame(value, "var", nrow(private$.var), "X", call)
      private$.var <- value
      private$.varm$rename_frames(rownames(value), frame_index_name(value))
      invisible(NULL)
    }
  )
)

# Builds the Raw of `parent` from the `raw` argument of `AnnData()`, which is a
# Raw, an `AnnData` or a named list with `X`, `var` and `varm`
make_raw <- function(parent, raw, call) {
  if (is.null(raw) || (is.list(raw) && !length(raw))) {
    return(NULL)
  }
  if (inherits(raw, c("Raw", "AnnData"))) {
    return(raw_class$new(parent, raw$X, raw$var, raw$varm, call = call))
  }
  keys <- names(raw)
  valid <- is.list(raw) &&
    !is.object(raw) &&
    !is.null(keys) &&
    all(keys %in% c("X", "var", "varm")) &&
    !anyDuplicated(keys)
  if (!valid) {
    abort_invalid_argument(
      "{.arg raw} must be an {.cls AnnData} or a list with the named elements
       {.field X}, {.field var} and {.field varm}.",
      call
    )
  }
  # `[[` because `$` on a list partially matches `var` to `varm`
  raw_class$new(parent, raw[["X"]], raw[["var"]], raw[["varm"]], call = call)
}

#' @export
#' @noRd
`[.Raw` <- function(x, i, j) {
  rows <- if (missing(i)) NULL else i
  cols <- if (missing(j) || nargs() < 3L) NULL else j
  .subset2(x, "subset")(rows, cols, call = rlang::caller_env())
}
