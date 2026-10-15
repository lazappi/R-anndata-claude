#' Annotated data matrix
#'
#' `AnnData()` creates an annotated data matrix of `n_obs` observations by
#' `n_vars` variables, following Python anndata 0.13.4.
#' It wraps the `AnnData` R6 class (ADR 0002), so objects have reference
#' semantics: `b <- a` aliases and does not copy.
#'
#' `X` is stored in the layers storage under the `NA` key (ADR 0004) and
#' `adata$X` aliases it.
#' The shape comes from `X`, from `shape` or is inferred from `obs` and `var`.
#' Giving both `shape` and `X` is an error.
#' Without names, observations and variables are named `"0"`, `"1"`, ...,
#' `"n-1"` as in Python.
#'
#' @section Fields:
#' * `X`: the data matrix, or `NULL`
#' * `uns`: unstructured annotation, a named list
#' * `obs`, `var`: annotation `S4Vectors::DataFrame`s
#' * `obs_names`, `var_names`: character names
#' * `n_obs`, `n_vars`, `shape`: dimensions
#' * `is_view` (always `FALSE`), `isbacked` (always `FALSE`) and `filename`
#'   (always `NULL`)
#'
#' The dimension and backing fields are read-only and assigning to them raises
#' an `anndata_read_only_error`.
#'
#' @param X A numeric or logical matrix, or a `Matrix` sparse matrix, or `NULL`.
#' @param obs,var Annotations of observations and variables as `NULL`, a named
#'   list, a `data.frame` or a `DataFrame`.
#' @param uns Unstructured annotation, a named list or `NULL`.
#' @param ... Must be empty, so that the arguments after `uns` are named.
#' @param obsm,varm,obsp,varp,layers Aligned mappings as named lists or `NULL`.
#'   An `NA` name in `layers` addresses X.
#' @param raw Further Slot (not yet supported).
#' @param shape Integer vector `c(n_obs, n_vars)` used when `X` is `NULL`.
#' @param filename,filemode Backed mode (not yet supported).
#'
#' @return An `AnnData` object.
#'
#' @examples
#' adata <- AnnData(matrix(as.numeric(1:6), nrow = 3))
#' adata$shape
#' adata$obs_names
#'
#' @export
AnnData <- function(
  X = NULL,
  obs = NULL,
  var = NULL,
  uns = NULL,
  ...,
  obsm = NULL,
  varm = NULL,
  layers = NULL,
  raw = NULL,
  shape = NULL,
  obsp = NULL,
  varp = NULL,
  filename = NULL,
  filemode = NULL
) {
  rlang::check_dots_empty()
  AnnDataClass$new(
    X = X,
    obs = obs,
    var = var,
    uns = uns,
    obsm = obsm,
    varm = varm,
    layers = layers,
    raw = raw,
    shape = shape,
    obsp = obsp,
    varp = varp,
    filename = filename,
    filemode = filemode
  )
}

abort_read_only <- function(field, call = rlang::caller_env()) {
  anndata_abort(
    "{.field {field}} is read-only.",
    "anndata_read_only_error",
    call = call
  )
}

abort_invalid_argument <- function(message, call, .envir = parent.frame()) {
  anndata_abort(
    message,
    "anndata_invalid_argument_error",
    call = call,
    .envir = .envir
  )
}

# Slot arguments whose assignment is implemented by later tickets, so that
# values are never silently dropped
abort_slot_not_supported <- function(slot, call) {
  abort_not_supported(
    "Constructing with {.arg {slot}} is not yet supported.",
    call = call
  )
}

check_shape <- function(shape, call) {
  valid <- is.numeric(shape) &&
    length(shape) == 2L &&
    !anyNA(shape) &&
    all(shape >= 0) &&
    all(shape == round(shape))
  if (!valid) {
    abort_invalid_argument(
      "{.arg shape} must be two non-negative whole numbers.",
      call
    )
  }
  as.integer(shape)
}

# Mirrors `_infer_shape_for_axis`: a frame wins, then the first element of the
# layers and the aligned mappings that has dimensions.
# `axis` is 1 for observations and 2 for variables.
infer_axis_shape <- function(frame, mapping, layers, pairwise, axis) {
  for (elem in list(frame, mapping, pairwise)) {
    if (!is.null(dim(elem))) {
      return(dim(elem)[[1L]])
    }
  }
  sources <- list(
    list(layers, axis),
    list(mapping, 1L),
    list(pairwise, 1L)
  )
  for (source in sources) {
    for (value in source[[1L]]) {
      if (!is.null(dim(value))) {
        return(dim(value)[[source[[2L]]]])
      }
    }
  }
  NA_integer_
}

infer_shape <- function(
  obs = NULL,
  var = NULL,
  obsm = NULL,
  varm = NULL,
  layers = NULL,
  obsp = NULL,
  varp = NULL
) {
  as.integer(c(
    infer_axis_shape(obs, obsm, layers, obsp, 1L),
    infer_axis_shape(var, varm, layers, varp, 2L)
  ))
}

is_plain_vector <- function(x) {
  is.null(dim(x)) &&
    is.atomic(x) &&
    !is.object(x) &&
    (is.numeric(x) || is.logical(x))
}

# Mirrors the Python `X` setter: scalars fill, other shapes are reshaped in C
# (row-major) order with a warning, and only 2-D values can be reshaped.
# `shape` is `c(n_obs, n_vars)`.
coerce_x_shape <- function(value, shape, call) {
  if (is_plain_vector(value)) {
    if (length(value) == 1L) {
      warn_future(
        "The ability to set {.field X} with a scalar value will be removed in
         the future.",
        call = call
      )
      return(matrix(value, shape[[1L]], shape[[2L]]))
    }
    dims <- length(value)
  } else {
    value <- as_anndata_matrix(
      value,
      allow_array = TRUE,
      what = "X",
      call = call
    )
    dims <- dim(value)
  }
  if (!identical(as.integer(dims[1:2]), shape)) {
    if (length(dims) > 2L) {
      abort_dimension(
        "Cannot set {.field X} from an array of shape ({dims}): its leading
         two dimensions do not match the shape ({shape}). Automatic reshaping
         is only supported for 2-D inputs.",
        what = "X",
        call = call
      )
    }
    warn_future(
      "Automatic reshaping when setting {.field X} will be removed in the
       future.",
      call = call
    )
    value <- reshape_x(value, shape, call)
  } else if (length(dims) > 2L) {
    anndata_warn(
      "{.field X} must be 2-dimensional, but got an array with shape ({dims}).
       Higher-dimensional arrays violate the AnnData specification and cannot
       be written to disk.",
      "anndata_non_2d_warning",
      call = call
    )
  }
  value
}

reshape_x <- function(value, shape, call) {
  if (is_sparse(value)) {
    abort_dimension(
      "Cannot reshape a sparse {.field X} to ({shape}).",
      what = "X",
      call = call
    )
  }
  if (length(value) != prod(shape)) {
    abort_dimension(
      "Cannot reshape {.field X} of size {length(value)} into shape
       ({shape}).",
      what = "X",
      call = call
    )
  }
  flat <- if (is.null(dim(value))) value else as.vector(t(value))
  copy_dtype(matrix(flat, shape[[1L]], shape[[2L]], byrow = TRUE), value)
}

#' @noRd
AnnDataClass <- R6Class(
  "AnnData",
  cloneable = FALSE,
  public = list(
    #' @description Create an `AnnData`, see [AnnData()].
    #' @param X,obs,var,uns,obsm,varm,layers,raw,shape,obsp,varp See
    #'   [AnnData()].
    #' @param filename,filemode See [AnnData()].
    initialize = function(
      X = NULL,
      obs = NULL,
      var = NULL,
      uns = NULL,
      obsm = NULL,
      varm = NULL,
      layers = NULL,
      raw = NULL,
      shape = NULL,
      obsp = NULL,
      varp = NULL,
      filename = NULL,
      filemode = NULL
    ) {
      call <- rlang::caller_env(2L)
      if (!is.null(filename) || !is.null(filemode)) {
        abort_not_supported(
          "Backed mode ({.arg filename} and {.arg filemode}) is not yet
           supported.",
          call = call
        )
      }
      if (!is.null(raw)) {
        abort_slot_not_supported("raw", call)
      }
      # Python takes X from layers[None] when X is not given
      layers_x <- if (is.list(layers)) layers[is.na(names(layers))] else list()
      if (length(layers_x) && !is.null(layers_x[[1L]])) {
        if (is.null(X)) {
          X <- layers_x[[1L]]
        } else if (!identical(X, layers_x[[1L]])) {
          abort_invalid_argument(
            "If you provide {.code layers[[NA]]} and {.arg X}, they must be
             identical.",
            call
          )
        }
      }
      if (!is.null(X)) {
        X <- as_anndata_matrix(X, what = "X", call = call)
        if (!is.null(shape)) {
          abort_invalid_argument(
            "{.arg shape} must be {.code NULL} if {.arg X} is not
             {.code NULL}.",
            call
          )
        }
        dims <- dim(X)[1:2]
        source <- "X"
      } else {
        dims <- if (!is.null(shape)) {
          check_shape(shape, call)
        } else {
          infer_shape(obs, var, obsm, varm, layers, obsp, varp)
        }
        source <- "shape"
      }
      private$.obs <- as_annotation_frame(
        obs,
        "obs",
        if (is.na(dims[[1L]])) NULL else dims[[1L]],
        source,
        call
      )
      private$.var <- as_annotation_frame(
        var,
        "var",
        if (is.na(dims[[2L]])) NULL else dims[[2L]],
        source,
        call
      )
      private$set_uns(uns %||% list(), call)
      private$.layers <- aligned_mapping_class$new(self, "layers")
      private$.layers$replace(layers, call = call)
      if (!is.null(X)) {
        private$set_x(X, call)
      }
      initial <- list(obsm = obsm, varm = varm, obsp = obsp, varp = varp)
      for (attr in names(initial)) {
        mapping <- aligned_mapping_class$new(self, attr)
        mapping$replace(initial[[attr]], call = call)
        private[[paste0(".", attr)]] <- mapping
      }
      if (get_setting("check_uniqueness")) {
        check_names_unique(rownames(private$.obs), "obs", call = call)
        check_names_unique(rownames(private$.var), "var", call = call)
      }
      invisible(self)
    }
  ),
  active = list(
    #' @field X The data matrix, stored in the layers storage under the `NA`
    #'   key. Assigning `NULL` removes it.
    X = function(value) {
      if (missing(value)) {
        return(private$.layers$get(NA_character_))
      }
      private$set_x(value, rlang::caller_env())
    },
    #' @field layers Aligned mapping of arrays with the shape of the data, see
    #'   `anndata-aligned-mappings`. X is stored under the `NA` key (ADR 0004).
    #'   Assigning a named list replaces the layers and keeps X (with a
    #'   warning) unless the list has an `NA` entry.
    layers = function(value) {
      private$aligned("layers", value, missing(value), rlang::caller_env())
    },
    #' @field obs Annotation of observations, a `DataFrame`.
    obs = function(value) {
      if (missing(value)) {
        return(private$.obs)
      }
      private$set_frame("obs", value, rlang::caller_env())
    },
    #' @field var Annotation of variables, a `DataFrame`.
    var = function(value) {
      if (missing(value)) {
        return(private$.var)
      }
      private$set_frame("var", value, rlang::caller_env())
    },
    #' @field obsm,varm Aligned mappings of axis arrays, see
    #'   `anndata-aligned-mappings`. Assigning a named list replaces them.
    obsm = function(value) {
      private$aligned("obsm", value, missing(value), rlang::caller_env())
    },
    varm = function(value) {
      private$aligned("varm", value, missing(value), rlang::caller_env())
    },
    #' @field obsp,varp Aligned mappings of pairwise arrays.
    obsp = function(value) {
      private$aligned("obsp", value, missing(value), rlang::caller_env())
    },
    varp = function(value) {
      private$aligned("varp", value, missing(value), rlang::caller_env())
    },
    #' @field obs_names Names of observations.
    obs_names = function(value) {
      if (missing(value)) {
        return(rownames(private$.obs))
      }
      private$set_names("obs", value, rlang::caller_env())
    },
    #' @field var_names Names of variables.
    var_names = function(value) {
      if (missing(value)) {
        return(rownames(private$.var))
      }
      private$set_names("var", value, rlang::caller_env())
    },
    #' @field uns Unstructured annotation, a named list. Assigning replaces it
    #'   and `adata$uns[["k"]] <- v` sets one entry.
    uns = function(value) {
      if (missing(value)) {
        return(private$.uns)
      }
      private$set_uns(value, rlang::caller_env())
    },
    #' @field n_obs Number of observations.
    n_obs = function(value) {
      if (!missing(value)) {
        abort_read_only("n_obs")
      }
      nrow(private$.obs)
    },
    #' @field n_vars Number of variables.
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
      c(nrow(private$.obs), nrow(private$.var))
    },
    #' @field is_view Always `FALSE` until views are supported.
    is_view = function(value) {
      if (!missing(value)) {
        abort_read_only("is_view")
      }
      FALSE
    },
    #' @field isbacked Always `FALSE` until backed mode is supported.
    isbacked = function(value) {
      if (!missing(value)) {
        abort_read_only("isbacked")
      }
      FALSE
    },
    #' @field filename Always `NULL` until backed mode is supported.
    filename = function(value) {
      if (!missing(value)) {
        abort_read_only("filename")
      }
      NULL
    }
  ),
  private = list(
    .obs = NULL,
    .var = NULL,
    .layers = NULL,
    .uns = NULL,
    .obsm = NULL,
    .varm = NULL,
    .obsp = NULL,
    .varp = NULL,
    # Gets an aligned mapping, or replaces its contents. Assigning the mapping
    # itself is what `adata$obsm[["k"]] <- v` does after the mapping changed.
    aligned = function(attr, value, get, call) {
      mapping <- private[[paste0(".", attr)]]
      if (get) {
        return(mapping)
      }
      if (!identical(value, mapping)) {
        mapping$replace(value, call = call)
      }
      invisible(NULL)
    },
    # Replaces obs or var, which takes its names from the value (Python resets
    # them to "0", "1", ... when the value has none) and passes them on
    set_frame = function(attr, value, call) {
      field <- paste0(".", attr)
      n <- nrow(private[[field]])
      private[[field]] <- as_annotation_frame(value, attr, n, "shape", call)
      private$rename_mapped_frames(attr)
    },
    # Sets obs_names or var_names, and a plain vector has no index name
    set_names = function(attr, value, call) {
      field <- paste0(".", attr)
      frame <- private[[field]]
      if (is.factor(value)) {
        value <- as.character(value)
      }
      if (!is.atomic(value) || is.null(value) || is.object(value)) {
        abort_invalid_argument(
          "{.field {attr}_names} must be a vector of names.",
          call
        )
      }
      if (length(value) != nrow(frame)) {
        abort_dimension(
          "Length of passed value for {.field {attr}_names} is
           {length(value)}, but this AnnData has shape ({self$shape}).",
          what = paste0(attr, "_names"),
          call = call
        )
      }
      frame <- with_frame_names(frame, as.character(unname(value)))
      private[[field]] <- with_index_name(frame, NULL)
      private$rename_mapped_frames(attr)
    },
    # Data frames in obsm and varm share the names of their axis
    rename_mapped_frames = function(attr) {
      frame <- private[[paste0(".", attr)]]
      mapping <- private[[paste0(".", attr, "m")]]
      mapping$rename_frames(rownames(frame), frame_index_name(frame))
      invisible(NULL)
    },
    set_uns = function(value, call) {
      keys <- names(value)
      named <- !is.null(keys) && !anyNA(keys) && all(nzchar(keys))
      valid <- is.list(value) && !is.object(value) && (named || !length(value))
      if (!valid) {
        abort_invalid_argument("{.field uns} must be a named list.", call)
      }
      private$.uns <- value
      invisible(NULL)
    },
    # Validates X and stores it first in the layers storage under the `NA` key
    set_x = function(value, call) {
      if (is.null(value)) {
        private$.layers$remove(NA_character_)
        return(invisible(NULL))
      }
      value <- coerce_x_shape(value, self$shape, call)
      private$.layers$set(NA_character_, value, call = call)
      invisible(NULL)
    }
  )
)
