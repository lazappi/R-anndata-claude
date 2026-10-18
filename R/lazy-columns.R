#' Lazy data frame columns
#'
#' The columns of a lazy `obs` or `var` (see [lazy-dataframe]):
#' - plain numeric, bool and string columns are 1-d `DelayedArray`s over a
#'   `StoreDenseSeed` (see [lazy-dense])
#' - a `LazyCategorical` holds a 1-d `DelayedArray` of codes and the categories
#'   (read at once, as they are small)
#' - a `LazyNullable` holds 1-d `DelayedArray`s of `values` and `mask`
#'
#' The two classes define `length()`, `[`, `show()`, `as.vector()` and
#' `as.data.frame()`, so they subset, print and realise inside a `DataFrame`.
#' `[` stays lazy and realising gives exactly what `read_h5ad()`/`read_zarr()`
#' give for the same Element: the `factor` with its categories attribute, the
#' value with `NA` and the nullable record, the On-disk dtype record.
#'
#' @param x A lazy column.
#' @param i Positions to keep.
#' @param j,drop,... Not used.
#' @param mode Not used.
#' @param store An open store handle, see [io-store].
#' @param path Absolute path of the Element of the column.
#' @param call The call reported by errors.
#' @param object A lazy column.
#'
#' @name lazy-columns
#' @keywords internal
NULL

#' @noRd
setClass(
  "LazyCategorical",
  slots = c(
    codes = "ANY",
    categories = "ANY",
    ordered = "logical",
    path = "character"
  )
)

#' @noRd
setClass(
  "LazyNullable",
  slots = c(
    values = "ANY",
    mask = "ANY",
    na_value = "character",
    path = "character"
  )
)

# The StoreDenseSeed under a (possibly subset) DelayedArray, `NULL` if none
lazy_leaf_seed <- function(x) {
  seed <- DelayedArray::seed(x)
  while (
    !methods::is(seed, "StoreDenseSeed") && methods::.hasSlot(seed, "seed")
  ) {
    seed <- methods::slot(seed, "seed")
  }
  if (methods::is(seed, "StoreDenseSeed")) seed else NULL
}

# The values of a 1-d lazy array with the On-disk dtype record that
# `read_elem()` gives
realise_lazy_array <- function(x) {
  values <- as.vector(x)
  seed <- lazy_leaf_seed(x)
  if (is.null(seed) || seed@dtype %in% c("bool", "string")) {
    return(values)
  }
  record_dtype(values, seed@dtype)
}

realise_lazy_categorical <- function(x, call = rlang::caller_env()) {
  categorical_from_parts(
    realise_lazy_array(x@codes),
    x@categories,
    x@ordered,
    x@path,
    call
  )
}

realise_lazy_nullable <- function(x, call = rlang::caller_env()) {
  values <- nullable_from_parts(
    realise_lazy_array(x@values),
    realise_lazy_array(x@mask),
    x@path,
    call
  )
  if (is.character(values)) {
    set_nullable(values, x@na_value)
  } else {
    set_nullable(values)
  }
}

# Realises any column of a lazy frame, a column that is already in memory (for
# example a newly assigned one) is returned as it is
realise_lazy_column <- function(x, call = rlang::caller_env()) {
  if (methods::is(x, "LazyCategorical")) {
    realise_lazy_categorical(x, call)
  } else if (methods::is(x, "LazyNullable")) {
    realise_lazy_nullable(x, call)
  } else if (methods::is(x, "DelayedArray")) {
    values <- realise_lazy_array(x)
    if (is.character(values)) plain_string(values) else values
  } else {
    x
  }
}

#' @rdname lazy-columns
setMethod("length", "LazyCategorical", function(x) length(x@codes))

#' @rdname lazy-columns
setMethod("length", "LazyNullable", function(x) length(x@values))

#' @rdname lazy-columns
setMethod("[", "LazyCategorical", function(x, i, j, ..., drop = TRUE) {
  if (!missing(i)) {
    x@codes <- x@codes[i, drop = FALSE]
  }
  x
})

#' @rdname lazy-columns
setMethod("[", "LazyNullable", function(x, i, j, ..., drop = TRUE) {
  if (!missing(i)) {
    x@values <- x@values[i, drop = FALSE]
    x@mask <- x@mask[i, drop = FALSE]
  }
  x
})

#' @importFrom BiocGenerics as.vector as.data.frame
#' @rdname lazy-columns
setMethod("as.vector", "LazyCategorical", function(x, mode = "any") {
  realise_lazy_categorical(x)
})

#' @rdname lazy-columns
setMethod("as.vector", "LazyNullable", function(x, mode = "any") {
  realise_lazy_nullable(x)
})

#' @rdname lazy-columns
setMethod("as.data.frame", "LazyCategorical", function(x, ...) {
  data.frame(x = realise_lazy_categorical(x))
})

#' @rdname lazy-columns
setMethod("as.data.frame", "LazyNullable", function(x, ...) {
  data.frame(x = drop_dtype(realise_lazy_nullable(x)))
})

# The first values of a lazy column, for printing
lazy_head <- function(x, n = 6L) {
  as.vector(x[seq_len(min(length(x), n))])
}

show_lazy_column <- function(object, label) {
  cat("<", label, "> of length ", length(object), "\n", sep = "")
  print(drop_dtype(lazy_head(object)))
  if (length(object) > 6L) {
    cat("... (", length(object) - 6L, " more, not read)\n", sep = "")
  }
  invisible(NULL)
}

#' @rdname lazy-columns
setMethod("show", "LazyCategorical", function(object) {
  show_lazy_column(object, "LazyCategorical")
})

#' @rdname lazy-columns
setMethod("show", "LazyNullable", function(object) {
  show_lazy_column(object, "LazyNullable")
})

#' @importFrom S4Vectors showAsCell
#' @rdname lazy-columns
setMethod("showAsCell", "LazyCategorical", function(object) {
  as.character(drop_dtype(as.vector(object)))
})

#' @rdname lazy-columns
setMethod("showAsCell", "LazyNullable", function(object) {
  as.character(drop_dtype(as.vector(object)))
})

# One lazy 1-d array, `strings` allows a string array
lazy_array_column <- function(store, path, strings, call) {
  seed <- store_dense_seed(store, path, call = call, strings = strings)
  if (length(seed@dim) != 1L) {
    abort_io_registry(
      "Cannot read {.path {path}} lazily as a column, it has
       {length(seed@dim)} dimensions.",
      path = path,
      call = call
    )
  }
  DelayedArray::DelayedArray(seed)
}

#' @rdname lazy-columns
lazy_column <- function(store, path, call = rlang::caller_env()) {
  elem <- node_open(store, path)
  on.exit(node_close(elem), add = TRUE)
  type <- read_elem_attr(elem, "encoding-type")
  switch(
    type,
    array = ,
    "string-array" = lazy_array_column(store, path, TRUE, call),
    categorical = methods::new(
      "LazyCategorical",
      codes = lazy_array_column(store, paste0(path, "/codes"), FALSE, call),
      categories = read_elem(store, paste0(path, "/categories")),
      ordered = identical(read_elem_attr(elem, "ordered"), "TRUE"),
      path = path
    ),
    "nullable-integer" = ,
    "nullable-boolean" = ,
    "nullable-string-array" = {
      strings <- type == "nullable-string-array"
      methods::new(
        "LazyNullable",
        values = lazy_array_column(
          store,
          paste0(path, "/values"),
          strings,
          call
        ),
        mask = lazy_array_column(store, paste0(path, "/mask"), FALSE, call),
        na_value = if (identical(read_elem_attr(elem, "na-value"), "NaN")) {
          "NaN"
        } else {
          "NA"
        },
        path = path
      )
    },
    abort_io_registry(
      "Cannot read {.path {path}} lazily as a column, its encoding type
       {.val {type}} is not a column.",
      path = path,
      call = call
    )
  )
}
