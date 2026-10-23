#' zarr backend of the store layer (tables)
#'
#' The `table_read` and `table_write` operations of [io-store] for zarr v3,
#' which hold the `rec-array` Element as a one-dimensional array of the `struct`
#' data type.
#' Rarr cannot read or write these, so the records are packed and unpacked in R
#' and only the zstd and blosc steps go through Rarr (see `zarr_compress()`
#' and `zarr_decompress()`, gzip is done in R).
#'
#' Python writes the fields in order, one record after another with no padding,
#' little-endian, with strings as `fixed_length_utf32` (zero padded) or
#' `null_terminated_bytes`, and compresses each chunk as `compressors` says
#' (zstd by default).
#' Reading handles those codecs with zstd, gzip, blosc or no compression, and
#' the chunk grid of any size.
#' zarr keeps the field dtypes (zarr-io/14), as HDF5 does (see
#' [io-store-h5-table]), and ignores the string records of HDF5.
#' Reading records the dtype of each column that is not the R type, as for plain
#' arrays: the numeric name (`"uint8"`, `"float32"`, ...) and for strings
#' `"<type>:<length_bytes>"` unless it is the `fixed_length_utf32` width that
#' writing would choose.
#' Writing restores the records, and sizes fields without one as Python does
#' (int32, float64, bool, and `fixed_length_utf32` of four times the longest
#' UTF-8 byte length).
#' Records are one chunk, sharded only when `shards` is given because Python's
#' automatic sharding of rec-arrays is disabled.
#'
#' @param store A zarr group node.
#' @param key,path Name or path of the array.
#' @param frame A `data.frame` of numeric, logical and character columns.
#' @param call The call reported by errors.
#' @param dataset_kwargs A list of dataset creation options.
#' @param column,name A column of `frame` and its name.
#' @param values,type,size Strings of a field, its data type and its width in
#'   bytes.
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

zarr_string_kinds <- c("fixed_length_utf32", "null_terminated_bytes")

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

# The compressor codecs a struct array may use (besides `bytes`)
zarr_struct_compressors <- c("zstd", "gzip", "blosc")

# The compressor codec among the `codecs` metadata, or `NULL` for none
zarr_struct_codec <- function(codecs) {
  for (codec in codecs) {
    if (codec$name %in% zarr_struct_compressors) {
      return(codec)
    }
  }
  NULL
}

# The bytes of a chunk compressed as `codec` says (`NULL` is uncompressed),
# the inverse of `zarr_compress()`: gzip is read in R, and zstd and blosc by
# reading the chunk back as a 1-d uint8 array of `size` values
zarr_decompress <- function(file, size, codec) {
  if (is.null(codec)) {
    return(readBin(file, "raw", file.size(file)))
  }
  if (identical(codec$name, "gzip")) {
    con <- gzfile(file, "rb")
    on.exit(close(con), add = TRUE)
    return(readBin(con, "raw", size))
  }
  config <- codec$configuration
  compressor <- if (identical(codec$name, "blosc")) {
    list(
      name = "blosc",
      cname = config$cname,
      clevel = config$clevel,
      shuffle = config$shuffle
    )
  } else {
    list(name = "zstd", level = config$level %||% 0L)
  }
  tmp <- tempfile("zarr-decompress")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  dir.create(file.path(tmp, "c"), recursive = TRUE)
  zarr_write_array_meta(tmp, "uint8", size, size, compressor)
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
  if (identical(codecs, "sharding_indexed")) {
    return(zarr_sharded_struct_bytes(array, itemsize, path, call))
  }
  if (!all(codecs %in% c("bytes", zarr_struct_compressors))) {
    abort_not_supported(
      "Cannot read {.path {path}}, it uses the codecs {codecs}.",
      path = path
    )
  }
  codec <- zarr_struct_codec(meta$codecs)
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
    zarr_decompress(file, count, codec)
  })
  as.raw(unlist(chunks))[seq_len(rows * itemsize)]
}

# The bytes of a struct array under the `sharding_indexed` codec: each shard
# file holds its inner chunks and an index of their offsets and sizes (8-byte
# little-endian integers, all 255 for a missing chunk) and a CRC-32C
zarr_sharded_struct_bytes <- function(array, itemsize, path, call) {
  config <- array$meta$codecs[[1L]]$configuration
  inner_codecs <- vapply(
    config$codecs,
    function(codec) codec$name,
    character(1)
  )
  if (!all(inner_codecs %in% c("bytes", zarr_struct_compressors))) {
    abort_not_supported(
      "Cannot read {.path {path}}, it uses the codecs {inner_codecs}.",
      path = path
    )
  }
  codec <- zarr_struct_codec(config$codecs)
  rows <- array$shape
  shard_rows <- array$meta$chunk_grid$configuration$chunk_shape[[1L]]
  inner_rows <- config$chunk_shape[[1L]]
  per_shard <- shard_rows %/% inner_rows
  inner_size <- inner_rows * itemsize
  if (identical(config$index_location, "start")) {
    abort_not_supported(
      "Cannot read {.path {path}}, its shard index is at the start.",
      path = path
    )
  }
  dir <- zarr_dir(array$node)
  decode <- function(blob) {
    if (is.null(codec)) {
      return(blob)
    }
    file <- tempfile("zarr-inner")
    on.exit(unlink(file), add = TRUE)
    writeBin(blob, file)
    zarr_decompress(file, inner_size, codec)
  }
  shards <- lapply(seq_len(ceiling(rows / shard_rows)) - 1L, function(i) {
    file <- file.path(dir, "c", i)
    if (!file.exists(file)) {
      return(raw(per_shard * inner_size))
    }
    bytes <- readBin(file, "raw", file.size(file))
    index_size <- 16L * per_shard
    index <- bytes[length(bytes) - 4L - rev(seq_len(index_size)) + 1L]
    entries <- matrix(index, nrow = 8L)
    values <- colSums(matrix(as.double(entries), nrow = 8L) * 256^(0:7))
    missing <- colSums(entries == as.raw(255)) == 8L
    offsets <- values[seq(1L, 2L * per_shard, by = 2L)]
    sizes <- values[seq(2L, 2L * per_shard, by = 2L)]
    lost <- missing[seq(1L, 2L * per_shard, by = 2L)]
    unlist(lapply(seq_len(per_shard), function(j) {
      if (lost[[j]]) {
        raw(inner_size)
      } else {
        decode(bytes[offsets[[j]] + seq_len(sizes[[j]])])
      }
    }))
  })
  as.raw(unlist(shards))[seq_len(rows * itemsize)]
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
    return(zarr_string_record(
      vapply(
        seq_len(rows),
        function(i) intToUtf8(points[points[, i] != 0L, i]),
        character(1)
      ),
      type,
      size
    ))
  }
  if (type == "null_terminated_bytes") {
    return(zarr_string_record(
      vapply(
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
      ),
      type,
      size
    ))
  }
  kind <- zarr_field_kinds[[type]]
  if (kind == "bool") {
    return(bytes[1L, ] != as.raw(0))
  }
  if (kind == "float") {
    return(record_dtype(
      readBin(as.vector(bytes), "double", rows, size = size),
      type
    ))
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
  record_dtype(values, type)
}

# The bytes a string field needs per record when written without a record:
# Python sizes it by the longest UTF-8 byte length, counted in characters for
# `fixed_length_utf32`
zarr_string_length <- function(values, type) {
  longest <- max(1L, nchar(values, "bytes"))
  if (type == "fixed_length_utf32") 4L * longest else longest
}

# The string field `values` of the given type and width, recorded as
# `"<type>:<width>"` when that is not what writing would choose (zarr-io/14)
zarr_string_record <- function(values, type, size) {
  if (
    identical(type, "fixed_length_utf32") &&
      identical(size, zarr_string_length(values, type))
  ) {
    return(values)
  }
  set_dtype(values, paste0(type, ":", size))
}

zarr_table_read <- function(store, path, call, records = FALSE) {
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
zarr_field_bytes <- function(column, name, path, call) {
  record <- get_dtype(column)
  column <- drop_dtype(column)
  if (is.character(column)) {
    parts <- strsplit(record %||% "", ":", fixed = TRUE)[[1L]]
    # A record of HDF5 (`"h5_fixed_ascii:3"`) is not a zarr string type
    if (length(parts) != 2L || !parts[[1L]] %in% zarr_string_kinds) {
      parts <- character()
    }
    kind <- if (length(parts) == 2L) parts[[1L]] else "fixed_length_utf32"
    # A recorded width is widened when the values no longer fit
    size <- max(
      if (length(parts) == 2L) as.integer(parts[[2L]]) else 0L,
      zarr_string_length(column, kind)
    )
    if (kind == "fixed_length_utf32") {
      points <- matrix(0L, size %/% 4L, length(column))
      for (i in seq_along(column)) {
        codes <- utf8ToInt(enc2utf8(column[[i]]))
        points[seq_along(codes), i] <- codes
      }
      bytes <- writeBin(as.vector(points), raw(), size = 4L, endian = "little")
      fill <- "0"
    } else {
      bytes <- as.raw(unlist(lapply(column, function(text) {
        text <- charToRaw(enc2utf8(text))
        c(text, raw(size - length(text)))
      })))
      fill <- "MA=="
    }
    type <- list(name = kind, configuration = list(length_bytes = size))
  } else {
    type <- if (is.logical(column)) {
      "bool"
    } else {
      record %||% native_dtype(column)
    }
    check_dtype_fits(column, type, path, call)
    bytes <- zarr_encode_values(column, type)
    size <- zarr_value_sizes[[type]]
    fill <- switch(
      zarr_field_kinds[[type]],
      bool = FALSE,
      float = 0,
      0L
    )
  }
  list(
    bytes = matrix(bytes, nrow = size),
    field = list(name = name, data_type = type),
    fill = fill
  )
}

zarr_table_write <- function(store, key, frame, dataset_kwargs, call) {
  zarr_require_v3(store)
  dir <- zarr_key_dir(store, key)
  rows <- nrow(frame)
  path <- paste0(store$path, "/", key)
  parts <- Map(zarr_field_bytes, frame, names(frame), path, list(call))
  payload <- as.vector(do.call(rbind, lapply(parts, function(p) p$bytes)))
  fill <- lapply(parts, function(p) p$fill)
  names(fill) <- names(frame)
  itemsize <- sum(vapply(parts, function(p) nrow(p$bytes), integer(1)))
  # Python writes one chunk of the whole array (or of one record when empty)
  # and does not shard rec-arrays unless asked (the automatic sharding is
  # commented out in `write_recarray_zarr`, so `auto_shard_zarr_v3` is ignored)
  chunk <- max(rows, 1L)
  shards <- if ("shards" %in% names(dataset_kwargs)) {
    zarr_shard_arg(dataset_kwargs, rows, call)
  }
  layout <- if (is.numeric(shards)) {
    list(chunk = chunk, shard = ceiling(shards / chunk) * chunk)
  } else {
    zarr_layout(rows, chunk, shards, "struct", itemsize)
  }
  compressor <- zarr_compressor_arg(dataset_kwargs, call)
  codecs <- zarr_codecs("int32", compressor)
  if (identical(compressor$name, "blosc")) {
    # The type size is that of a record, and the shuffle default follows it
    config <- codecs[[2L]]$configuration
    config$typesize <- itemsize
    config$shuffle <- compressor$shuffle %||%
      if (itemsize > 1L) "shuffle" else "bitshuffle"
    codecs[[2L]]$configuration <- config
    compressor$shuffle <- config$shuffle
  }
  if (!is.null(layout$shard)) {
    codecs <- zarr_shard_codecs(codecs, layout$chunk)
  }
  meta <- list(
    shape = list(rows),
    data_type = list(
      name = "struct",
      configuration = list(fields = unname(lapply(parts, function(p) p$field)))
    ),
    chunk_grid = list(
      name = "regular",
      configuration = list(chunk_shape = list(layout$shard %||% chunk))
    ),
    chunk_key_encoding = list(
      name = "default",
      configuration = list(separator = "/")
    ),
    fill_value = fill,
    codecs = codecs,
    attributes = empty_object(),
    zarr_format = 3L,
    node_type = "array",
    storage_transformers = list()
  )
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  zarr_write_json(meta, file.path(dir, "zarr.json"))
  if (rows > 0L) {
    dir.create(file.path(dir, "c"), showWarnings = FALSE)
    writeBin(
      zarr_compress(payload, compressor, "uint8"),
      file.path(dir, "c", "0")
    )
    if (!is.null(layout$shard)) {
      zarr_shard_files(dir, layout$chunk, layout$shard)
    }
  }
  invisible(NULL)
}
