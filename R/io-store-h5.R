#' HDF5 backend of the store layer
#'
#' The operations of [io-store] for open rhdf5 file and group handles.
#' The dataset readers and writers live with their encodings (`R/dtype.R`,
#' `R/io-values.R`) as `h5_*` functions.
#'
#' @param dset An open dataset handle.
#' @param selection A selection, see [io-store].
#' @param ... Further arguments of `rhdf5::H5Dread()`.
#' @param in_r Whether to read the whole dataset and subset it in R.
#'
#' @name io-store-h5
#' @keywords internal
NULL

# Built by a function so that the operations are looked up at call time
h5_backend <- function() {
  list(
    node_path = rhdf5::H5Iget_name,
    is_file = function(store) identical(rhdf5::H5Iget_type(store), "H5I_FILE"),
    node_open = rhdf5::H5Oopen,
    node_close = rhdf5::H5Oclose,
    group_create = rhdf5::H5Gcreate,
    group_root = function(store) rhdf5::H5Gopen(store, "/"),
    group_members = function(node) rhdf5::h5ls(node, recursive = FALSE)$name,
    member_exists = rhdf5::H5Lexists,
    member_delete = rhdf5::H5Ldelete,
    attr_exists = rhdf5::H5Aexists,
    attr_read = h5_attr_read,
    attr_write = h5_attr_write,
    array_info = h5_info,
    array_read = h5_array_read,
    dataset_read = h5_read_dataset,
    dataset_write = h5_write_dataset,
    bool_write = h5_write_bool,
    complex_write = h5_write_complex,
    string_write = h5_write_string,
    string_read = function(store, path, call) {
      h5_read_string(store, path, NULL, call)
    },
    null_write = h5_null_write,
    table_write = h5_table_write,
    table_read = h5_table_read
  )
}

h5_attr_read <- function(node, name) {
  attr <- rhdf5::H5Aopen(node, name)
  on.exit(rhdf5::H5Aclose(attr), add = TRUE)
  space <- rhdf5::H5Aget_space(attr)
  on.exit(rhdf5::H5Sclose(space), add = TRUE, after = FALSE)
  if (any(rhdf5::H5Sget_simple_extent_dims(space)$size == 0L)) {
    return(character())
  }
  rhdf5::H5Aread(attr, bit64conversion = "double")
}

h5_attr_write <- function(node, name, value, dtype, scalar) {
  if (is.character(value) && length(value) == 0L) {
    # h5py writes an empty list as an empty float64 array
    space <- rhdf5::H5Screate_simple(0L)
    on.exit(rhdf5::H5Sclose(space), add = TRUE)
    attr <- rhdf5::H5Acreate(node, name, "H5T_IEEE_F64LE", space)
    rhdf5::H5Aclose(attr)
  } else if (is.character(value)) {
    rhdf5::h5writeAttribute(
      value,
      node,
      name,
      encoding = "UTF-8",
      variableLengthString = TRUE,
      asScalar = scalar
    )
  } else if (identical(dtype, "int64")) {
    space <- rhdf5::H5Screate_simple(length(value))
    on.exit(rhdf5::H5Sclose(space), add = TRUE)
    attr <- rhdf5::H5Acreate(node, name, "H5T_STD_I64LE", space)
    on.exit(rhdf5::H5Aclose(attr), add = TRUE, after = FALSE)
    rhdf5::H5Awrite(attr, as.double(value))
  } else {
    rhdf5::h5writeAttribute(value, node, name, asScalar = scalar)
  }
  invisible(NULL)
}

# The selection checked and in the dims as rhdf5 returns them (reversed from
# Python's), with every `NULL` entry filled in
h5_selection_index <- function(dset, selection) {
  space <- rhdf5::H5Dget_space(dset)
  on.exit(rhdf5::H5Sclose(space), add = TRUE)
  sizes <- rhdf5::H5Sget_simple_extent_dims(space)$size
  index <- rev(selection)
  if (length(index) != length(sizes)) {
    anndata_abort(
      "{.arg selection} must have one entry per dimension, {length(sizes)}
       here.",
      "anndata_invalid_value_error"
    )
  }
  for (i in seq_along(index)) {
    index[i] <- list(index[[i]] %||% seq_len(sizes[[i]]))
    bad <- is.unsorted(index[[i]], strictly = TRUE) ||
      any(index[[i]] < 1L | index[[i]] > sizes[[i]])
    if (bad) {
      anndata_abort(
        "{.arg selection} indices must be strictly increasing and within the
         array.",
        "anndata_invalid_value_error"
      )
    }
  }
  index
}

# Reads a dataset, or the selected part of it.
# Variable-length strings and compounds crash HDF5 when read through a memory
# dataspace, so `in_r` reads them whole and subsets the values in R.
#' @rdname io-store-h5
h5_dread <- function(dset, selection = NULL, ..., in_r = FALSE) {
  if (is.null(selection)) {
    return(rhdf5::H5Dread(dset, ...))
  }
  index <- h5_selection_index(dset, selection)
  if (in_r) {
    values <- rhdf5::H5Dread(dset, ...)
    if (is.null(dim(values))) {
      return(values[index[[1]]])
    }
    return(do.call(`[`, c(list(values), index, list(drop = FALSE))))
  }
  space <- rhdf5::H5Dget_space(dset)
  on.exit(rhdf5::H5Sclose(space), add = TRUE)
  rhdf5::H5Sselect_index(space, index)
  mem <- rhdf5::H5Screate_simple(lengths(index))
  on.exit(rhdf5::H5Sclose(mem), add = TRUE, after = FALSE)
  rhdf5::H5Dread(dset, h5spaceFile = space, h5spaceMem = mem, ...)
}

h5_array_read <- function(store, path, selection, call) {
  info <- h5_info(store, path)
  switch(
    info$dclass,
    INTEGER = ,
    FLOAT = h5_read_dataset(store, path, selection, call),
    ENUM = h5_read_bool(store, path, selection, call),
    COMPOUND = h5_read_complex(store, path, selection, call),
    STRING = h5_read_string(store, path, selection, call),
    abort_dataset_type(path, "its class is not supported", call)
  )
}

h5_null_write <- function(store, key) {
  space <- rhdf5::H5Screate("H5S_NULL")
  on.exit(rhdf5::H5Sclose(space), add = TRUE)
  dset <- rhdf5::H5Dcreate(store, key, "H5T_IEEE_F32LE", space)
  on.exit(rhdf5::H5Dclose(dset), add = TRUE, after = FALSE)
  invisible(NULL)
}

h5_table_write <- function(store, key, frame) {
  # `level = 0` stops rhdf5 compressing, and a chunk is required to write
  rhdf5::h5writeDataset(frame, store, key, level = 0L, chunk = nrow(frame))
  invisible(NULL)
}

h5_table_read <- function(store, path, call) {
  dset <- rhdf5::H5Dopen(store, path)
  on.exit(rhdf5::H5Dclose(dset), add = TRUE)
  # rhdf5 only warns when a 64-bit value reaches 2^53 and is no longer exact
  withCallingHandlers(
    suppressMessages(rhdf5::H5Dread(dset, bit64conversion = "double")),
    warning = function(w) abort_dtype_precision(path, "int64", call)
  )
}
