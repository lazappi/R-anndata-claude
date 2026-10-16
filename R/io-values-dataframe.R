#' Data frames
#'
#' Reads and writes the Element `dataframe`, version 0.2.0, a group with the
#' attributes `_index` and `column-order`, one member per column and one for
#' the index.
#' Its R values are `S4Vectors::DataFrame` (read and written) and `data.frame`
#' (written).
#'
#' The index is the row names, with the index name in `metadata()` under
#' `index_name` (the `index_name` attribute of a `data.frame`).
#' The member is called `_index` when there is no index name.
#' Row names that are `NULL` (or automatic for a `data.frame`) are written as
#' Python writes a `RangeIndex`, an int64 `array` of `0` to `n - 1`.
#' An index that is not a plain string vector (integer, categorical or a
#' string-array) is kept in `metadata()` under `index_source` and written back
#' as it was, as long as the row names still match it.
#'
#' Columns follow the rules of the Elements they are written as.
#' A `character` column is a `nullable-string-array` as pandas 3 writes a `str`
#' column, unless it was read from a plain `string-array` or the setting
#' `allow_write_nullable_strings` is `FALSE` (see [io-nullable]).
#' A column must be a vector without a `dim` of more than one dimension, and
#' column names must be unique and not `_index`.
#'
#' @inheritParams io-registry
#'
#' @name io-dataframe
#' @keywords internal
NULL

# Marks a string vector read from a plain `string-array`, which Python only
# writes for object columns and with `allow_write_nullable_strings` off
plain_string <- function(x) {
  if (is.character(x) && is.null(get_nullable(x))) set_nullable(x, FALSE) else x
}

frame_parts <- function(df) {
  if (is.data.frame(df)) {
    index_name <- attr(df, "index_name", exact = TRUE)
    names <- if (automatic_row_names(df)) NULL else rownames(df)
    columns <- as.list(df)
    source <- NULL
  } else {
    index_name <- frame_index_name(df)
    names <- rownames(df)
    columns <- as.list(df)
    source <- S4Vectors::metadata(df)[["index_source"]]
  }
  list(
    index_name = index_name,
    names = names,
    n = nrow(df),
    columns = columns,
    source = source
  )
}

# The value written as the index
frame_index <- function(parts) {
  names <- parts$names
  if (is.null(names)) {
    return(as_array(set_dtype(as.double(seq_len(parts$n) - 1L), "int64")))
  }
  source <- parts$source
  if (!is.null(source) && identical(categories_as_levels(source), names)) {
    index <- source
  } else {
    index <- names
  }
  if (is.character(index) && is.null(get_nullable(index))) {
    index <- set_nullable(index, "NaN")
  }
  if (is.factor(index)) index else as_array(index)
}

frame_column <- function(column, name, path, call) {
  if (is.data.frame(column) || methods::is(column, "DataFrame")) {
    abort_unwritable(
      path,
      paste0("column ", encodeString(name, quote = "\""), " is a data frame"),
      call
    )
  }
  if (!is.atomic(column) || is.factor(column)) {
    return(column)
  }
  if (length(dim(column)) > 1L) {
    abort_unwritable(
      path,
      paste0("column ", encodeString(name, quote = "\""), " is a matrix"),
      call
    )
  }
  if (is.character(column) && is.null(get_nullable(column))) {
    column <- set_nullable(column, "NaN")
  }
  as_array(column)
}

set_string_array_attr <- function(group, name, values) {
  if (length(values) > 0L) {
    rhdf5::h5writeAttribute(
      values,
      group,
      name,
      encoding = "UTF-8",
      variableLengthString = TRUE,
      asScalar = FALSE
    )
    return(invisible(NULL))
  }
  # h5py writes an empty list as an empty float64 array
  space <- rhdf5::H5Screate_simple(0L)
  on.exit(rhdf5::H5Sclose(space), add = TRUE)
  attr <- rhdf5::H5Acreate(group, name, "H5T_IEEE_F64LE", space)
  rhdf5::H5Aclose(attr)
  invisible(NULL)
}

#' @rdname io-dataframe
write_dataframe <- function(store, key, value, dataset_kwargs, path) {
  call <- rlang::caller_env()
  parts <- frame_parts(value)
  col_names <- names(parts$columns) %||% character()

  if ("_index" %in% col_names) {
    abort_unwritable(path, "\"_index\" is a reserved column name", call)
  }
  if (anyDuplicated(col_names) > 0L) {
    abort_unwritable(path, "column names must be unique", call)
  }
  index_key <- parts$index_name %||% "_index"
  index <- frame_index(parts)
  if (index_key %in% col_names) {
    column <- parts$columns[[index_key]]
    same <- !is.null(parts$names) &&
      identical(categories_as_levels(column), parts$names)
    if (!same) {
      abort_unwritable(
        path,
        "the index name is also the name of a column with different values",
        call
      )
    }
  }

  group <- rhdf5::H5Gcreate(store, key)
  on.exit(rhdf5::H5Gclose(group), add = TRUE)
  set_string_array_attr(group, "column-order", col_names)
  set_elem_attr(group, "_index", index_key)
  write_elem(group, index_key, index, dataset_kwargs, call)
  for (name in col_names) {
    column <- frame_column(
      parts$columns[[name]],
      name,
      paste0(path, "/", name),
      call
    )
    write_elem(group, name, column, dataset_kwargs, call)
  }
  invisible(NULL)
}

read_attr_strings <- function(elem, name, path, call) {
  if (!rhdf5::H5Aexists(elem, name)) {
    abort_io_registry(
      "Cannot read {.path {path}}, it has no attribute {.field {name}}.",
      path = path,
      call = call
    )
  }
  attr <- rhdf5::H5Aopen(elem, name)
  on.exit(rhdf5::H5Aclose(attr), add = TRUE)
  space <- rhdf5::H5Aget_space(attr)
  on.exit(rhdf5::H5Sclose(space), add = TRUE, after = FALSE)
  if (any(rhdf5::H5Sget_simple_extent_dims(space)$size == 0L)) {
    return(character())
  }
  as.character(rhdf5::H5Aread(attr))
}

read_dataframe_elem <- function(elem, path, store) {
  call <- rlang::caller_env()
  col_names <- read_attr_strings(elem, "column-order", path, call)
  index_key <- read_attr_strings(elem, "_index", path, call)

  index <- read_elem(store, paste0(path, "/", index_key))
  dim(index) <- NULL
  n <- length(index)
  columns <- vector("list", length(col_names))
  for (i in seq_along(col_names)) {
    column <- read_elem(store, paste0(path, "/", col_names[[i]]))
    dim(column) <- NULL
    if (length(column) != n) {
      abort_io_registry(
        "Cannot read {.path {path}}, column {.val {col_names[[i]]}} has
         length {length(column)} and the index has length {n}.",
        path = path,
        call = call
      )
    }
    columns[[i]] <- plain_string(column)
  }
  names(columns) <- col_names

  index <- plain_string(index)
  names <- categories_as_levels(index)
  df <- methods::new(
    "DFrame",
    listData = columns,
    nrows = n,
    rownames = names
  )
  if (!identical(index_key, "_index")) {
    df <- with_index_name(df, index_key)
  }
  plain <- is.character(index) &&
    is.null(get_dtype(index)) &&
    identical(get_nullable(index), "NaN")
  if (!plain) {
    S4Vectors::metadata(df)[["index_source"]] <- index
  }
  df
}

register_writer("DataFrame", "dataframe", "0.2.0", write_dataframe)
register_writer("data.frame", "dataframe", "0.2.0", write_dataframe)
register_reader("dataframe", "0.2.0", read_dataframe_elem)
