#' zarr backend of the store layer (tables)
#'
#' The `table_read` and `table_write` operations of [io-store] for zarr v3,
#' which hold the `rec-array` Element as a one-dimensional array of the `struct`
#' data type.
#' Rarr cannot read or write these, so the records are packed and unpacked in R
#' and only the zstd step goes through Rarr (see `zarr_zstd()`).
#'
#' Python writes the fields in order, one record after another with no padding,
#' little-endian, with strings as `fixed_length_utf32` (zero padded) or
#' `null_terminated_bytes`, and compresses each chunk with zstd.
#' Reading handles those codecs, and the chunk grid of any size.
#' Writing follows ADR 0005: int32, float64 and `fixed_length_utf32` fields in
#' one chunk, which Python reads with the same field names, order and values.
#'
#' @param store A zarr group node.
#' @param key,path Name or path of the array.
#' @param frame A `data.frame` of integer, double and character columns.
#' @param call The call reported by errors.
#'
#' @name io-store-zarr-table
#' @keywords internal
NULL

# Bytes and R type of the numeric field data types
zarr_field_kinds <- c(
  int8 = "integer",
  int16 = "integer",
  int32 = "integer",
  uint8 = "integer",
  uint16 = "integer",
  uint32 = "double",
  int64 = "double",
  uint64 = "double",
  float32 = "float",
  float64 = "float",
  bool = "bool"
)

# The name and byte width of each field of a `struct` data type
zarr_struct_fields <- function(meta, path, call, version = 3L) {
  if (version == 2L) {
    return(zarr_v2_struct_fields(meta, path, call))
  }
  fields <- meta$data_type$configuration$fields
  lapply(fields, function(field) {
    type <- field$data_type
    name <- if (is.character(type)) type else type$name
    size <- if (name %in% names(zarr_field_kinds)) {
      zarr_value_sizes[[name]]
    } else if (name %in% c("fixed_length_utf32", "null_terminated_bytes")) {
      as.integer(type$configuration$length_bytes)
    } else {
      abort_dataset_type(
        path,
        paste0("field \"", field$name, "\" has the unsupported type ", name),
        call
      )
    }
    list(name = field$name, type = name, size = size)
  })
}

# The fields of a v2 structured dtype (a list of `[name, typestr]` pairs), in
# the form `zarr_struct_fields()` gives for v3
zarr_v2_struct_fields <- function(meta, path, call) {
  kinds <- c(
    "|u1" = "uint8",
    "|i1" = "int8",
    "<i2" = "int16",
    "<u2" = "uint16",
    "<i4" = "int32",
    "<u4" = "uint32",
    "<i8" = "int64",
    "<u8" = "uint64",
    "<f4" = "float32",
    "<f8" = "float64",
    "|b1" = "bool"
  )
  lapply(meta$dtype, function(field) {
    name <- field[[1L]]
    typestr <- field[[2L]]
    width <- suppressWarnings(as.integer(substring(typestr, 3L)))
    if (startsWith(typestr, ">")) {
      abort_not_supported(
        "Cannot read {.path {path}}, it is big-endian.",
        path = path
      )
    }
    if (typestr %in% names(kinds)) {
      type <- kinds[[typestr]]
      size <- zarr_value_sizes[[type]]
    } else if (grepl("^<U[0-9]+$", typestr)) {
      type <- "fixed_length_utf32"
      size <- 4L * width
    } else if (grepl("^\\|S[0-9]+$", typestr)) {
      type <- "null_terminated_bytes"
      size <- width
    } else {
      abort_dataset_type(
        path,
        paste0("field \"", name, "\" has the unsupported type ", typestr),
        call
      )
    }
    list(name = name, type = type, size = size)
  })
}

# The bytes of one v2 chunk file (decoded by the array's compressor), by
# reading it back as a 1-d uint8 array of `size` values
zarr_v2_unpack <- function(file, size, meta) {
  tmp <- tempfile("zarr-v2-bytes")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  dir.create(tmp)
  jsonlite::write_json(
    list(
      zarr_format = 2L,
      shape = list(size),
      chunks = list(size),
      dtype = "|u1",
      compressor = meta$compressor,
      filters = NULL,
      fill_value = 0L,
      order = "C"
    ),
    file.path(tmp, ".zarray"),
    auto_unbox = TRUE,
    null = "null"
  )
  file.copy(file, file.path(tmp, "0"))
  values <- suppressMessages(Rarr::read_zarr_array(tmp))
  as.raw(as.vector(values))
}

# The bytes of a chunk compressed with zstd, by reading them back as a 1-d
# uint8 array of `size` values (the inverse of `zarr_zstd()`)
zarr_unzstd <- function(file, size) {
  tmp <- tempfile("zarr-unzstd")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  dir.create(file.path(tmp, "c"), recursive = TRUE)
  zarr_write_array_meta(tmp, "uint8", size, size)
  file.copy(file, file.path(tmp, "c", "0"))
  values <- suppressMessages(Rarr::read_zarr_array(tmp))
  as.raw(as.vector(values))
}

# The bytes of the whole array, `chunk_rows` records per chunk (a missing chunk
# is all zero)
zarr_struct_bytes <- function(array, itemsize, path, call) {
  meta <- array$meta
  if (array$node$version == 2L) {
    if (!identical(meta$order, "C") || length(meta$filters) > 0L) {
      abort_not_supported(
        "Cannot read {.path {path}}, it is not C order or it has filters.",
        path = path
      )
    }
    dir <- zarr_dir(array$node)
    chunk_rows <- meta$chunks[[1L]]
    count <- chunk_rows * itemsize
    chunks <- lapply(
      seq_len(ceiling(array$shape / chunk_rows)) - 1L,
      function(i) {
        file <- file.path(dir, i)
        if (!file.exists(file)) {
          raw(count)
        } else if (is.null(meta$compressor)) {
          readBin(file, "raw", file.size(file))
        } else {
          zarr_v2_unpack(file, count, meta)
        }
      }
    )
    return(as.raw(unlist(chunks))[seq_len(array$shape * itemsize)])
  }
  codecs <- vapply(meta$codecs, function(codec) codec$name, character(1))
  if (!all(codecs %in% c("bytes", "zstd"))) {
    abort_not_supported(
      "Cannot read {.path {path}}, it uses the codecs {codecs}.",
      path = path
    )
  }
  endian <- meta$codecs[[1L]]$configuration$endian %||% "little"
  if (!identical(endian, "little")) {
    abort_not_supported(
      "Cannot read {.path {path}}, it is big-endian.",
      path = path
    )
  }
  rows <- array$shape
  chunk_rows <- meta$chunk_grid$configuration$chunk_shape[[1L]]
  dir <- zarr_dir(array$node)
  chunks <- lapply(seq_len(ceiling(rows / chunk_rows)) - 1L, function(i) {
    file <- file.path(dir, "c", i)
    count <- chunk_rows * itemsize
    if (!file.exists(file)) {
      return(raw(count))
    }
    if ("zstd" %in% codecs) {
      zarr_unzstd(file, count)
    } else {
      readBin(file, "raw", file.size(file))
    }
  })
  as.raw(unlist(chunks))[seq_len(rows * itemsize)]
}

# One field from its bytes, a matrix with a column per record
zarr_field_values <- function(bytes, field, path, call) {
  type <- field$type
  size <- field$size
  rows <- ncol(bytes)
  if (type == "fixed_length_utf32") {
    points <- matrix(
      readBin(as.vector(bytes), "integer", rows * size %/% 4L, size = 4L),
      ncol = rows
    )
    return(vapply(
      seq_len(rows),
      function(i) intToUtf8(points[points[, i] != 0L, i]),
      character(1)
    ))
  }
  if (type == "null_terminated_bytes") {
    return(vapply(
      seq_len(rows),
      function(i) {
        text <- bytes[, i]
        zeros <- which(text == as.raw(0))
        if (length(zeros) > 0L) {
          text <- text[seq_len(zeros[[1L]] - 1L)]
        }
        out <- rawToChar(text)
        Encoding(out) <- "UTF-8"
        out
      },
      character(1)
    ))
  }
  kind <- zarr_field_kinds[[type]]
  if (kind == "bool") {
    return(bytes[1L, ] != as.raw(0))
  }
  if (kind == "float") {
    return(readBin(as.vector(bytes), "double", rows, size = size))
  }
  weights <- 256^(seq_len(size) - 1L)
  values <- colSums(matrix(as.double(bytes), nrow = size) * weights)
  if (startsWith(type, "int")) {
    # Two's complement: minus the complement plus one, which stays exact for
    # 64-bit values (2^64 - 9 is not a double)
    negative <- bytes[size, ] >= as.raw(128)
    complement <- colSums(
      matrix(255 - as.double(bytes[, negative, drop = FALSE]), nrow = size) *
        weights
    )
    values[negative] <- -(complement + 1)
  }
  if (any(abs(values) >= 2^53)) {
    abort_dtype_precision(path, type, call)
  }
  if (kind == "integer" && !any(values <= -2^31)) {
    values <- as.integer(values)
  }
  values
}

zarr_table_read <- function(store, path, call) {
  array <- zarr_array_meta(store, path)
  node_path <- array$node$path
  if (!identical(array$dtype, "struct")) {
    abort_dataset_type(node_path, "it is not a zarr struct array", call)
  }
  fields <- zarr_struct_fields(array$meta, node_path, call, array$node$version)
  sizes <- vapply(fields, function(field) field$size, integer(1))
  itemsize <- sum(sizes)
  bytes <- matrix(
    zarr_struct_bytes(array, itemsize, node_path, call),
    nrow = itemsize
  )
  ends <- cumsum(sizes)
  columns <- lapply(seq_along(fields), function(i) {
    rows <- seq_len(sizes[[i]]) + ends[[i]] - sizes[[i]]
    zarr_field_values(
      bytes[rows, , drop = FALSE],
      fields[[i]],
      node_path,
      call
    )
  })
  names(columns) <- vapply(fields, function(field) field$name, character(1))
  structure(
    columns,
    class = "data.frame",
    row.names = seq_len(array$shape)
  )
}

# The bytes of a column as a matrix with a column per record, and its struct
# field description
zarr_field_bytes <- function(column, name) {
  if (is.character(column)) {
    width <- max(1L, nchar(column, "chars"))
    points <- matrix(0L, width, length(column))
    for (i in seq_along(column)) {
      codes <- utf8ToInt(enc2utf8(column[[i]]))
      points[seq_along(codes), i] <- codes
    }
    bytes <- writeBin(as.vector(points), raw(), size = 4L, endian = "little")
    size <- 4L * width
    type <- list(
      name = "fixed_length_utf32",
      configuration = list(length_bytes = size)
    )
    fill <- "0"
  } else if (is.integer(column)) {
    bytes <- zarr_encode_values(column, "int32")
    size <- 4L
    type <- "int32"
    fill <- 0L
  } else {
    bytes <- zarr_encode_values(column, "float64")
    size <- 8L
    type <- "float64"
    fill <- 0
  }
  list(
    bytes = matrix(bytes, nrow = size),
    field = list(name = name, data_type = type),
    fill = fill
  )
}

zarr_table_write <- function(store, key, frame) {
  zarr_require_v3(store)
  dir <- zarr_key_dir(store, key)
  rows <- nrow(frame)
  parts <- Map(zarr_field_bytes, frame, names(frame))
  payload <- as.vector(do.call(rbind, lapply(parts, function(p) p$bytes)))
  fill <- lapply(parts, function(p) p$fill)
  names(fill) <- names(frame)
  meta <- list(
    shape = list(rows),
    data_type = list(
      name = "struct",
      configuration = list(fields = unname(lapply(parts, function(p) p$field)))
    ),
    chunk_grid = list(
      name = "regular",
      configuration = list(chunk_shape = list(rows))
    ),
    chunk_key_encoding = list(
      name = "default",
      configuration = list(separator = "/")
    ),
    fill_value = fill,
    codecs = zarr_codecs("int32"),
    attributes = empty_object(),
    zarr_format = 3L,
    node_type = "array",
    storage_transformers = list()
  )
  dir.create(file.path(dir, "c"), recursive = TRUE, showWarnings = FALSE)
  zarr_write_json(meta, file.path(dir, "zarr.json"))
  writeBin(zarr_zstd(payload), file.path(dir, "c", "0"))
  invisible(NULL)
}
