#' Lazy data frames
#'
#' A lazy `obs` or `var` is a `LazyDFrame`, an `S4Vectors::DataFrame` whose
#' columns are lazy (see [lazy-columns]).
#' Reading it reads metadata, the categories and (with
#' `load_annotation_index`) the index.
#' Row subsetting, column subsetting and printing work as for any `DataFrame`
#' and stay lazy, and `lazy_dataframe_realise()` gives the `DataFrame` that
#' `read_h5ad()`/`read_zarr()` give for the same Element.
#'
#' With `load_annotation_index = FALSE` the row names are `NULL` (Python's
#' dummy range index) and the index stays a lazy column in the `lazy_index`
#' slot, which row subsetting follows and realising loads.
#'
#' @param store An open store handle, see [io-store].
#' @param path Absolute path of the `dataframe` Element.
#' @param load_annotation_index Whether the index is read into memory.
#' @param call The call reported by errors.
#' @param df A `LazyDFrame`.
#' @param x A `LazyDFrame`.
#' @param i Row positions, already normalised by `S4Vectors`.
#'
#' @name lazy-dataframe
#' @keywords internal
NULL

#' @importClassesFrom S4Vectors DFrame
#' @noRd
setClass("LazyDFrame", contains = "DFrame", slots = c(lazy_index = "ANY"))

#' @rdname lazy-dataframe
lazy_dataframe <- function(
  store,
  path,
  load_annotation_index = TRUE,
  call = rlang::caller_env()
) {
  elem <- node_open(store, path)
  on.exit(node_close(elem), add = TRUE)
  col_names <- read_attr_strings(elem, "column-order", path, call)
  index_key <- read_attr_strings(elem, "_index", path, call)
  index_path <- paste0(path, "/", index_key)

  if (load_annotation_index) {
    index <- read_elem(store, index_path)
    dim(index) <- NULL
    lazy_index <- NULL
    n <- length(index)
  } else {
    lazy_index <- lazy_column(store, index_path, call)
    n <- length(lazy_index)
  }
  columns <- vector("list", length(col_names))
  for (i in seq_along(col_names)) {
    columns[[i]] <- lazy_column(store, paste0(path, "/", col_names[[i]]), call)
    if (length(columns[[i]]) != n) {
      abort_io_registry(
        "Cannot read {.path {path}}, column {.val {col_names[[i]]}} has
         length {length(columns[[i]])} and the index has length {n}.",
        path = path,
        call = call
      )
    }
  }
  names(columns) <- col_names

  if (load_annotation_index) {
    df <- frame_from_parts(columns, index, index_key)
  } else {
    df <- methods::new("DFrame", listData = columns, nrows = n)
    if (!identical(index_key, "_index")) {
      df <- with_index_name(df, index_key)
    }
  }
  methods::new("LazyDFrame", df, lazy_index = lazy_index)
}

#' @importFrom S4Vectors extractROWS
#' @rdname lazy-dataframe
setMethod("extractROWS", c("LazyDFrame", "ANY"), function(x, i) {
  out <- methods::callNextMethod()
  if (!is.null(x@lazy_index)) {
    out@lazy_index <- x@lazy_index[as.integer(i), drop = FALSE]
  }
  out
})

#' @importFrom BiocGenerics as.data.frame
#' @rdname lazy-dataframe
setMethod("as.data.frame", "LazyDFrame", function(x, ...) {
  as.data.frame(lazy_dataframe_realise(x), ...)
})

#' @rdname lazy-dataframe
lazy_dataframe_realise <- function(df, call = rlang::caller_env()) {
  columns <- lapply(as.list(df), realise_lazy_column, call = call)
  if (is.null(df@lazy_index)) {
    return(methods::new(
      "DFrame",
      listData = columns,
      nrows = nrow(df),
      rownames = df@rownames,
      metadata = S4Vectors::metadata(df)
    ))
  }
  index_key <- frame_index_name(df) %||% "_index"
  frame_from_parts(columns, realise_lazy_column(df@lazy_index, call), index_key)
}
