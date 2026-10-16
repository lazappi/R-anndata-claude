#' zarr backend of the store layer (reading)
#'
#' The read operations of [io-store] for a local zarr directory store, version 2
#' or 3, sharded or not, consolidated or not, through Rarr.
#' The write operations are in [io-store-zarr-write].
#'
#' A handle is a `zarr_node`: the store directory, the absolute path of the
#' node within the store and the zarr format.
#' Metadata is always read from the node's own files, so consolidated metadata
#' is neither needed nor trusted.
#' Rarr cannot read complex values, and turns 64-bit integers (and uint32)
#' beyond the R integer range into `NA`.
#' Those arrays are read again as 16-bit integers or float64 from a temporary
#' copy of the array with a trailing dimension, which holds the same bytes, and
#' the values are put together in R.
#'
#' @param path Path of the store directory.
#' @param call The call reported by errors.
#'
#' @name io-store-zarr
#' @keywords internal
NULL

# Built by a function so that the operations are looked up at call time
zarr_backend <- function() {
  list(
    node_path = function(node) node$path,
    is_file = function(store) identical(store$path, "/"),
    node_open = zarr_node_open,
    node_close = function(node) invisible(NULL),
    group_create = zarr_group_create,
    group_root = function(store) zarr_node(store$root, "/", store$version),
    group_members = zarr_group_members,
    member_exists = zarr_member_exists,
    member_delete = zarr_member_delete,
    attr_exists = function(node, name) name %in% names(zarr_attrs(node)),
    attr_read = zarr_attr_read,
    attr_write = zarr_attr_write,
    array_info = zarr_info,
    array_read = zarr_array_read,
    dataset_read = zarr_dataset_read,
    dataset_write = zarr_dataset_write,
    bool_write = zarr_bool_write,
    complex_write = zarr_complex_write,
    string_write = zarr_string_write,
    string_read = zarr_string_read,
    null_write = zarr_null_write
  )
}

zarr_node <- function(root, path, version) {
  structure(
    list(root = root, path = path, version = version),
    class = "zarr_node"
  )
}

#' @rdname io-store-zarr
zarr_open <- function(path, call = rlang::caller_env()) {
  if (grepl("\\.zip$", path, ignore.case = TRUE)) {
    abort_not_supported(
      c(
        "Cannot read {.path {path}}, zip stores are not supported.",
        i = "Unzip it and read the directory."
      ),
      class = "anndata_zarr_zip_error",
      path = path,
      call = call
    )
  }
  if (!dir.exists(path)) {
    anndata_abort(
      "Cannot open {.path {path}}, it is not a directory.",
      "anndata_invalid_value_error",
      path = path,
      call = call
    )
  }
  for (version in c(3L, 2L)) {
    meta <- zarr_meta(path, version)
    if (identical(meta$kind, "group")) {
      return(zarr_node(path, "/", version))
    }
  }
  anndata_abort(
    "Cannot open {.path {path}}, it is not a zarr group.",
    "anndata_invalid_value_error",
    path = path,
    call = call
  )
}

zarr_dir <- function(node) {
  relative <- substring(node$path, 2L)
  if (nzchar(relative)) file.path(node$root, relative) else node$root
}

# The kind (`group` or `array`), metadata and attributes of the node in `dir`,
# `NULL` when it holds none
zarr_meta <- function(dir, version) {
  if (version == 3L) {
    file <- file.path(dir, "zarr.json")
    if (!file.exists(file)) {
      return(NULL)
    }
    meta <- jsonlite::fromJSON(file, simplifyVector = FALSE)
    return(list(
      kind = meta$node_type,
      meta = meta,
      attrs = meta$attributes %||% list()
    ))
  }
  files <- c(array = ".zarray", group = ".zgroup")
  found <- file.exists(file.path(dir, files))
  if (!any(found)) {
    return(NULL)
  }
  kind <- names(files)[found][[1L]]
  meta <- jsonlite::fromJSON(
    file.path(dir, files[[kind]]),
    simplifyVector = FALSE
  )
  attrs_file <- file.path(dir, ".zattrs")
  attrs <- if (file.exists(attrs_file)) {
    jsonlite::fromJSON(attrs_file, simplifyVector = FALSE)
  } else {
    list()
  }
  list(kind = kind, meta = meta, attrs = attrs)
}

zarr_attrs <- function(node) zarr_meta(zarr_dir(node), node$version)$attrs

# Absolute path of `name`, a path below the store node or already absolute
zarr_abs_path <- function(store, name) {
  parts <- if (startsWith(name, "/")) {
    name
  } else {
    paste(store$path, name, sep = "/")
  }
  parts <- strsplit(parts, "/", fixed = TRUE)[[1L]]
  paste0("/", paste(parts[nzchar(parts)], collapse = "/"))
}

zarr_node_open <- function(store, path) {
  node <- zarr_node(store$root, zarr_abs_path(store, path), store$version)
  if (is.null(zarr_meta(zarr_dir(node), node$version))) {
    anndata_abort(
      "There is no zarr group or array at {.path {node$path}}.",
      "anndata_invalid_value_error",
      path = node$path
    )
  }
  node
}

zarr_member_exists <- function(store, key) {
  node <- zarr_node(store$root, zarr_abs_path(store, key), store$version)
  !is.null(zarr_meta(zarr_dir(node), node$version))
}

# Alphabetical, as `h5ls()` lists a group
zarr_group_members <- function(node) {
  dir <- zarr_dir(node)
  members <- list.files(dir, include.dirs = TRUE)
  members <- members[dir.exists(file.path(dir, members))]
  has_meta <- vapply(
    members,
    function(member) {
      !is.null(zarr_meta(file.path(dir, member), node$version))
    },
    logical(1)
  )
  sort(members[has_meta], method = "radix")
}

# JSON lists of scalars become vectors and an empty list an empty character
# vector, as for HDF5 attributes
zarr_attr_read <- function(node, name) {
  value <- zarr_attrs(node)[[name]]
  if (!is.list(value)) {
    return(value)
  }
  if (length(value) == 0L) {
    return(character())
  }
  scalar <- vapply(
    value,
    function(item) is.atomic(item) && length(item) == 1L,
    logical(1)
  )
  if (all(scalar) && is.null(names(value))) unlist(value) else value
}

# The numpy-style dtype of a v2 array as the name v3 uses
zarr_v2_dtype <- function(meta) {
  dtype <- meta$dtype
  if (!is.character(dtype)) {
    return("struct")
  }
  kind <- substr(dtype, 2L, 2L)
  size <- suppressWarnings(as.integer(substring(dtype, 3L)))
  names <- c(i = "int", u = "uint", f = "float", c = "complex")
  if (kind %in% c("i", "u", "f")) {
    return(paste0(names[[kind]], 8L * size))
  }
  if (kind == "c") {
    return(paste0("complex", 8L * size))
  }
  if (kind == "b") {
    return("bool")
  }
  if (kind %in% c("U", "S")) {
    return("string")
  }
  filters <- vapply(
    meta$filters %||% list(),
    function(filter) filter$id %||% "",
    character(1)
  )
  if (kind == "O" && "vlen-utf8" %in% filters) "string" else "object"
}

zarr_dtype_class <- function(dtype) {
  if (grepl("^u?int[0-9]+$", dtype)) {
    "INTEGER"
  } else if (grepl("^(b?float)[0-9]+$", dtype)) {
    "FLOAT"
  } else if (dtype == "bool") {
    "ENUM"
  } else if (dtype == "string") {
    "STRING"
  } else if (grepl("^complex[0-9]+$", dtype) || dtype == "struct") {
    "COMPOUND"
  } else {
    "OTHER"
  }
}

# The metadata of an array: its shape (from the metadata, because Rarr cannot
# tell a 0-d array from a 1-element one), dtype and path
zarr_array_meta <- function(store, path) {
  node <- zarr_node_open(store, path)
  found <- zarr_meta(zarr_dir(node), node$version)
  if (!identical(found$kind, "array")) {
    anndata_abort(
      "{.path {node$path}} is a zarr group, not an array.",
      "anndata_invalid_value_error",
      path = node$path
    )
  }
  meta <- found$meta
  dtype <- if (node$version == 3L) {
    if (is.character(meta$data_type)) meta$data_type else "struct"
  } else {
    zarr_v2_dtype(meta)
  }
  list(
    node = node,
    meta = meta,
    dtype = dtype,
    shape = as.numeric(unlist(meta$shape))
  )
}

# The row of an array in the shape `h5ls()` gives
zarr_info <- function(store, path) {
  array <- zarr_array_meta(store, path)
  data.frame(
    name = basename(array$node$path),
    dclass = zarr_dtype_class(array$dtype),
    dtype = array$dtype,
    rank = length(array$shape),
    stringsAsFactors = FALSE
  )
}

# The selection checked against the shape, with every `NULL` entry filled in
zarr_selection_index <- function(shape, selection) {
  if (length(selection) != length(shape)) {
    anndata_abort(
      "{.arg selection} must have one entry per dimension, {length(shape)}
       here.",
      "anndata_invalid_value_error"
    )
  }
  for (i in seq_along(selection)) {
    selection[i] <- list(selection[[i]] %||% seq_len(shape[[i]]))
    bad <- is.unsorted(selection[[i]], strictly = TRUE) ||
      any(selection[[i]] < 1L | selection[[i]] > shape[[i]])
    if (bad) {
      anndata_abort(
        "{.arg selection} indices must be strictly increasing and within the
         array.",
        "anndata_invalid_value_error"
      )
    }
  }
  selection
}

# Reads the array in `dir` (the whole array or the selection) with Rarr and puts
# the dims right: none for 0-d and 1-d arrays, as for HDF5
zarr_rarr_read <- function(dir, shape, selection) {
  values <- if (is.null(selection) || length(shape) == 0L) {
    suppressMessages(Rarr::read_zarr_array(dir))
  } else {
    index <- zarr_selection_index(shape, selection)
    suppressMessages(Rarr::read_zarr_array(dir, index = index))
  }
  if (length(shape) <= 1L) {
    dim(values) <- NULL
  }
  values
}

zarr_array_read <- function(store, path, selection, call) {
  array <- zarr_array_meta(store, path)
  switch(
    zarr_dtype_class(array$dtype),
    INTEGER = ,
    FLOAT = zarr_numeric_read(array, selection, call),
    ENUM = ,
    STRING = zarr_rarr_read(zarr_dir(array$node), array$shape, selection),
    COMPOUND = zarr_complex_read(array, selection, call),
    abort_dataset_type(array$node$path, "its class is not supported", call)
  )
}

zarr_dataset_read <- function(store, path, selection, call) {
  zarr_numeric_read(zarr_array_meta(store, path), selection, call)
}

zarr_string_read <- function(store, path, call) {
  values <- zarr_array_read(store, path, NULL, call)
  as.character(values)[[1L]]
}

zarr_numeric_read <- function(array, selection, call) {
  path <- array$node$path
  dtype <- array$dtype
  if (!dtype %in% numeric_dtypes) {
    anndata_abort(
      "Cannot read {.path {path}}, it is not an integer or float dataset.",
      "anndata_dtype_error",
      path = path,
      call = call
    )
  }
  if (dtype %in% c("int64", "uint64", "uint32")) {
    # Always from 16-bit parts (read as double like HDF5), because Rarr warns
    # once per value beyond the integer range, which takes minutes when big
    return(record_dtype(zarr_wide_read(array, selection, path, call), dtype))
  }
  dir <- zarr_dir(array$node)
  values <- zarr_rarr_read(dir, array$shape, selection)
  if (identical(dtype, "int32") && anyNA(values)) {
    # R reads -2^31 as NA
    missing <- is.na(values)
    values <- structure(as.double(values), dim = dim(values))
    values[missing] <- -2^31
  }
  record_dtype(values, dtype)
}

# int64, uint64 and uint32 values Rarr could not hold, put together from 16-bit
# parts, least significant first
zarr_wide_read <- function(array, selection, path, call) {
  dtype <- array$dtype
  count <- if (identical(dtype, "uint32")) 2L else 4L
  parts <- zarr_split_read(array, "uint16", count, selection)
  columns <- matrix(as.double(parts), ncol = count)
  weights <- 2^(16 * (seq_len(count) - 1L))
  negative <- identical(dtype, "int64") & columns[, count] >= 2^15
  # Two's complement: a negative value is minus the complement plus one
  columns[negative, ] <- 65535 - columns[negative, , drop = FALSE]
  values <- as.vector(columns %*% weights)
  values[negative] <- values[negative] + 1
  # A sum that is not exact is at least 2^53, so it is caught here too
  if (any(values >= 2^53)) {
    abort_dtype_precision(path, dtype, call)
  }
  values[negative] <- -values[negative]
  zarr_unsplit_dims(values, parts)
}

# The dims of `parts`, which has a trailing split dimension, without it and
# with none for 0-d and 1-d arrays
zarr_unsplit_dims <- function(values, parts) {
  dims <- dim(parts)
  dims <- dims[-length(dims)]
  dim(values) <- if (length(dims) > 1L) dims else NULL
  values
}

zarr_complex_read <- function(array, selection, call) {
  path <- array$node$path
  if (!identical(array$dtype, "complex128")) {
    abort_dataset_type(
      path,
      "it is complex64 and only complex128 can be read",
      call
    )
  }
  parts <- zarr_split_read(array, "float64", 2L, selection)
  columns <- matrix(parts, ncol = 2L)
  values <- complex(real = columns[, 1L], imaginary = columns[, 2L])
  zarr_unsplit_dims(values, parts)
}

# Reads the array as `part_type` values with a trailing dimension of `count`,
# from a temporary copy of the array whose metadata describes that layout.
# The bytes of a chunk do not change, only its key gains a trailing index.
# The result keeps the trailing dimension.
zarr_split_read <- function(array, part_type, count, selection) {
  path <- array$node$path
  meta <- array$meta
  version <- array$node$version
  dir <- zarr_dir(array$node)
  fill <- unlist(meta$fill_value)
  if (!is.null(fill) && !identical(fill, 0) && !identical(fill, 0L)) {
    if (!is.numeric(fill) || any(fill != 0)) {
      abort_not_supported(
        "Cannot read {.path {path}}, its fill value is not zero.",
        path = path
      )
    }
  }
  tmp <- tempfile("zarr-split")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  if (version == 3L) {
    separator <- meta$chunk_key_encoding$configuration$separator
    if (is.null(separator)) {
      separator <- if (identical(meta$chunk_key_encoding$name, "v2")) {
        "."
      } else {
        "/"
      }
    }
    meta$shape <- c(meta$shape, list(count))
    meta$chunk_grid$configuration$chunk_shape <- c(
      meta$chunk_grid$configuration$chunk_shape,
      list(count)
    )
    meta$dimension_names <- NULL
    meta$data_type <- part_type
    meta$fill_value <- 0L
    for (codec in meta$codecs) {
      if (codec$name == "transpose") {
        abort_not_supported(
          "Cannot read {.path {path}}, it uses the transpose codec.",
          path = path
        )
      }
      if (codec$name == "bytes") {
        endian <- codec$configuration$endian %||% "little"
        if (!identical(endian, "little")) {
          abort_not_supported(
            "Cannot read {.path {path}}, it is big-endian.",
            path = path
          )
        }
      }
    }
    meta$codecs <- lapply(meta$codecs, function(codec) {
      if (codec$name == "sharding_indexed") {
        codec$configuration$chunk_shape <- c(
          codec$configuration$chunk_shape,
          list(count)
        )
      }
      codec
    })
    meta_file <- "zarr.json"
    rename <- TRUE
  } else {
    separator <- meta$dimension_separator %||% "."
    if (!identical(meta$order, "C") || !startsWith(meta$dtype, "<")) {
      abort_not_supported(
        "Cannot read {.path {path}}, it is not little-endian C order.",
        path = path
      )
    }
    rank <- length(meta$shape)
    meta$shape <- c(meta$shape, list(count))
    meta$chunks <- c(meta$chunks, list(count))
    meta$dtype <- if (part_type == "uint16") "<u2" else "<f8"
    meta$fill_value <- 0L
    meta_file <- ".zarray"
    # A 0-d array keeps its single chunk key
    rename <- rank > 0L
  }

  jsonlite::write_json(
    meta,
    file.path(tmp, meta_file),
    auto_unbox = TRUE,
    null = "null",
    digits = NA
  )
  metadata_files <- c("zarr.json", ".zarray", ".zattrs", ".zgroup")
  chunks <- setdiff(
    list.files(dir, recursive = TRUE, all.files = TRUE),
    metadata_files
  )
  for (chunk in chunks) {
    target <- if (rename) paste0(chunk, separator, "0") else chunk
    dir.create(
      dirname(file.path(tmp, target)),
      showWarnings = FALSE,
      recursive = TRUE
    )
    file.copy(file.path(dir, chunk), file.path(tmp, target))
  }

  shape <- c(array$shape, count)
  split_selection <- if (!is.null(selection)) c(selection, list(NULL))
  values <- suppressMessages(
    if (is.null(split_selection)) {
      Rarr::read_zarr_array(tmp)
    } else {
      Rarr::read_zarr_array(
        tmp,
        index = zarr_selection_index(shape, split_selection)
      )
    }
  )
  values
}
