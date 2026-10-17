#' zarr backend of the store layer (writing)
#'
#' The write operations of [io-store] for a local zarr v3 directory store.
#'
#' Rarr writes the chunks of numeric and bool arrays (compressed with zstd, the
#' codec Python uses), and the metadata (`zarr.json`) is always written by us so
#' that it matches what Python writes (the On-disk dtype given explicitly, no
#' identity `transpose` codec, the fill value and codecs of Python).
#' What Rarr cannot write is done here, following ADR 0007:
#'
#' - 0-d arrays (scalars and `null`) and variable-length UTF-8 strings: the
#'   chunk bytes are encoded in R and compressed by Rarr (as a `uint8` array,
#'   whose single chunk is exactly the compressed bytes)
#' - 64-bit integers from doubles, the int32 minimum and uint32 values beyond
#'   the R integer range, and complex values: the bytes of each value are split
#'   into 16-bit (or float64) parts along a trailing dimension that Rarr writes,
#'   and the chunk keys then lose that dimension, which is the inverse of
#'   `zarr_split_read()`
#'
#' The `compressors` dataset argument chooses the compressor (zstd by default,
#' see `zarr_compressor_arg()`), and nothing is sharded yet.
#'
#' @param path Path of the store directory.
#' @param dtype A dtype name: `numeric_dtypes`, `"bool"`, `"complex128"` or
#'   `"string"`.
#' @param values The values of an array, in R's order.
#' @param payload A raw vector of encoded chunk bytes.
#'
#' @name io-store-zarr-write
#' @keywords internal
NULL

zarr_numpy_types <- c(
  int8 = "|i1",
  int16 = "<i2",
  int32 = "<i4",
  int64 = "<i8",
  uint8 = "|u1",
  uint16 = "<u2",
  uint32 = "<u4",
  uint64 = "<u8",
  float32 = "<f4",
  float64 = "<f8",
  bool = "|b1"
)

# Bytes per value of the dtypes that are encoded by `zarr_encode_values()`
zarr_value_sizes <- c(
  int8 = 1L,
  int16 = 2L,
  int32 = 4L,
  int64 = 8L,
  uint8 = 1L,
  uint16 = 2L,
  uint32 = 4L,
  uint64 = 8L,
  float32 = 4L,
  float64 = 8L,
  bool = 1L,
  complex128 = 16L
)

# A JSON object with no members (an empty list would be written as `[]`)
empty_object <- function() structure(list(), names = character())

zarr_require_v3 <- function(node) {
  if (!identical(node$version, 3L)) {
    abort_not_supported(
      "Cannot write to a zarr v2 store, only zarr v3 can be written.",
      path = node$path
    )
  }
}

zarr_write_json <- function(x, file) {
  jsonlite::write_json(
    x,
    file,
    auto_unbox = TRUE,
    null = "null",
    digits = NA,
    pretty = FALSE
  )
}

# Creates (or replaces the metadata of) the root group of a v3 store
#' @rdname io-store-zarr-write
zarr_create <- function(path) {
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  zarr_write_group_meta(path)
  zarr_node(path, "/", 3L)
}

zarr_write_group_meta <- function(dir) {
  meta <- list(
    attributes = empty_object(),
    zarr_format = 3L,
    node_type = "group"
  )
  zarr_write_json(meta, file.path(dir, "zarr.json"))
}

# The directory of `key`, a path below the store node or already absolute
zarr_key_dir <- function(store, key) {
  zarr_dir(zarr_node(store$root, zarr_abs_path(store, key), store$version))
}

zarr_group_create <- function(store, key) {
  zarr_require_v3(store)
  path <- zarr_abs_path(store, key)
  node <- zarr_node(store$root, path, store$version)
  if (zarr_node_exists(node)) {
    anndata_abort(
      "There is already a zarr group or array at {.path {path}}.",
      "anndata_invalid_value_error",
      path = path
    )
  }
  dir.create(zarr_dir(node), recursive = TRUE, showWarnings = FALSE)
  zarr_write_group_meta(zarr_dir(node))
  node
}

zarr_member_delete <- function(store, key) {
  zarr_require_v3(store)
  unlink(zarr_key_dir(store, key), recursive = TRUE)
  invisible(NULL)
}

# An attribute value as JSON: character, logical and numeric vectors of length
# one are scalars when `scalar`, longer ones and empty ones are arrays, and a
# list is an array or an object
zarr_attr_json <- function(value, scalar) {
  if (is.list(value)) {
    return(value)
  }
  if (length(value) == 1L && scalar) {
    return(value)
  }
  as.list(value)
}

zarr_attr_write <- function(node, name, value, dtype, scalar) {
  zarr_require_v3(node)
  file <- file.path(zarr_dir(node), "zarr.json")
  meta <- jsonlite::fromJSON(file, simplifyVector = FALSE)
  attrs <- meta$attributes
  if (length(attrs) == 0L) {
    attrs <- empty_object()
  }
  attrs[[name]] <- zarr_attr_json(value, scalar)
  meta$attributes <- attrs
  zarr_write_json(meta, file)
  invisible(NULL)
}

# Chunks of at most 2^20 values, whole along the last dimensions, and of size 1
# along an empty dimension (the chunk shape need not match Python's)
zarr_chunk_shape <- function(dims) {
  # The option lets tests reach the multi-chunk paths with small arrays
  limit <- getOption("anndata.zarr_chunk_limit", 2^20)
  chunk <- pmax(dims, 1)
  for (i in seq_along(chunk)) {
    if (prod(chunk) > limit) {
      chunk[[i]] <- max(1, min(chunk[[i]], floor(limit / prod(chunk[-i]))))
    }
  }
  chunk
}

zarr_fill_value <- function(dtype) {
  switch(
    dtype,
    bool = FALSE,
    string = "",
    complex128 = list(0, 0),
    0
  )
}

is_one_of <- function(x, choices) {
  is.character(x) && length(x) == 1L && x %in% choices
}

is_whole_up_to <- function(x, max) {
  is.numeric(x) &&
    length(x) == 1L &&
    !is.na(x) &&
    x == round(x) &&
    x >= 0 &&
    x <= max
}

zarr_default_compressor <- list(name = "zstd", level = 0L)

zarr_blosc_names <- c("lz4", "lz4hc", "blosclz", "zstd", "zlib", "snappy")

# Bytes per value, which Python records as the blosc type size (1 for strings)
zarr_type_size <- function(dtype) {
  if (identical(dtype, "string")) 1L else zarr_value_sizes[[dtype]]
}

# The `compressors` dataset argument as a compressor: a list with a `name`
# (`"zstd"`, `"gzip"`, `"blosc"` or `"none"`) and its options. `NULL` is no
# compression, and a missing argument is Python's default (zstd).
# `write_zarr()` renames `compressor` and marks it `legacy_compressor`, which
# scalars ignore as Python's `_remove_scalar_compression_args` drops it.
zarr_compressor_arg <- function(dataset_kwargs, call, scalar = FALSE) {
  legacy <- isTRUE(dataset_kwargs[["legacy_compressor"]])
  if (!"compressors" %in% names(dataset_kwargs) || (scalar && legacy)) {
    return(zarr_default_compressor)
  }
  spec <- dataset_kwargs[["compressors"]]
  if (is.null(spec)) {
    return(list(name = "none"))
  }
  if (is.character(spec) && length(spec) == 1L) {
    spec <- list(name = spec)
  }
  options <- list(
    zstd = "level",
    gzip = "level",
    blosc = c("cname", "clevel", "shuffle"),
    none = character()
  )
  name <- if (is.list(spec)) spec[["name"]]
  valid <- is_one_of(name, names(options)) &&
    all(names(spec) %in% c("name", options[[name]]))
  if (!valid) {
    abort_invalid_argument(
      "{.arg compressors} must be {.code NULL}, a name or a list with a
       {.field name} ({.val zstd}, {.val gzip}, {.val blosc} or {.val none})
       and the options of that compressor.",
      call
    )
  }
  max_levels <- c(zstd = 22, gzip = 9, blosc = 9)
  level <- spec[["level"]] %||% spec[["clevel"]]
  if (!is.null(level) && !is_whole_up_to(level, max_levels[[name]])) {
    abort_invalid_argument(
      "The compression level of {.arg compressors} must be a whole number
       from 0 to {max_levels[[name]]}.",
      call
    )
  }
  cname <- spec[["cname"]]
  shuffle <- spec[["shuffle"]]
  shuffles <- c("noshuffle", "shuffle", "bitshuffle")
  blosc_ok <- (is.null(cname) || is_one_of(cname, zarr_blosc_names)) &&
    (is.null(shuffle) || is_one_of(shuffle, shuffles))
  if (!blosc_ok) {
    abort_invalid_argument(
      "{.field cname} and {.field shuffle} of a {.val blosc} compressor must be
       valid blosc options.",
      call
    )
  }
  compressor <- list(name = name)
  compressor$level <- switch(
    name,
    zstd = as.integer(level %||% 0L),
    gzip = as.integer(level %||% 5L),
    NULL
  )
  if (identical(name, "blosc")) {
    compressor$cname <- cname %||% "lz4"
    compressor$clevel <- as.integer(level %||% 5L)
    compressor$shuffle <- shuffle
  }
  compressor
}

# The compressor codec of the metadata, or `NULL` for no compression
zarr_compressor_codec <- function(compressor, dtype) {
  switch(
    compressor$name,
    zstd = list(
      name = "zstd",
      configuration = list(level = compressor$level, checksum = FALSE)
    ),
    gzip = list(
      name = "gzip",
      configuration = list(level = compressor$level)
    ),
    blosc = {
      size <- zarr_type_size(dtype)
      list(
        name = "blosc",
        configuration = list(
          typesize = size,
          cname = compressor$cname,
          clevel = compressor$clevel,
          shuffle = compressor$shuffle %||%
            if (size > 1L) "shuffle" else "bitshuffle",
          blocksize = 0L
        )
      )
    },
    NULL
  )
}

# Real gzip bytes (Rarr's gzip is zlib, which Python's gzip codec rejects)
zarr_gzip <- function(bytes, level) {
  file <- tempfile("zarr-gzip")
  on.exit(unlink(file), add = TRUE)
  con <- gzfile(file, "wb", compression = level)
  writeBin(bytes, con)
  close(con)
  readBin(file, "raw", file.size(file))
}

# Compresses the chunk files Rarr wrote without compression, in place
zarr_gzip_chunks <- function(dir, level) {
  for (file in list.files(file.path(dir, "c"), recursive = TRUE)) {
    file <- file.path(dir, "c", file)
    bytes <- readBin(file, "raw", file.size(file))
    writeBin(zarr_gzip(bytes, level), file)
  }
  invisible(NULL)
}

# The compressor as Rarr takes it, which ignores the level of zstd (it is only
# recorded in the metadata, and any level decodes). gzip is left to
# `zarr_gzip_chunks()`, so Rarr writes those chunks uncompressed.
zarr_rarr_compressor <- function(compressor, dtype) {
  switch(
    compressor$name,
    zstd = Rarr::use_zstd(0L),
    blosc = Rarr::use_blosc(
      compressor$cname,
      compressor$clevel,
      compressor$shuffle %||%
        if (zarr_type_size(dtype) > 1L) "shuffle" else "bitshuffle",
      typesize = zarr_type_size(dtype)
    ),
    NULL
  )
}

# The codecs Python writes: the array to bytes codec, then the compressor
zarr_codecs <- function(dtype, compressor = zarr_default_compressor) {
  array_bytes <- if (identical(dtype, "string")) {
    list(name = "vlen-utf8", configuration = empty_object())
  } else if (zarr_value_sizes[[dtype]] == 1L) {
    list(name = "bytes")
  } else {
    list(name = "bytes", configuration = list(endian = "little"))
  }
  codec <- zarr_compressor_codec(compressor, dtype)
  if (is.null(codec)) list(array_bytes) else list(array_bytes, codec)
}

# The shard layout of an array of shape `dims` (no shards for a 0-d array).
# `shards` is `NULL` (unsharded), `"auto"` or the shard shape, and the chunk
# shape is reduced where needed so that it divides an explicit shard shape.
# The shard shape is the whole array, or the largest block of chunks below the
# target of 1 GB uncompressed (Python's `array.target_shard_size_bytes`).
zarr_layout <- function(dims, chunk, shards, dtype, itemsize = NULL) {
  if (is.null(shards) || length(dims) == 0L) {
    return(list(chunk = chunk, shard = NULL))
  }
  if (identical(shards, "auto")) {
    shard <- ceiling(pmax(dims, 1) / chunk) * chunk
    # Strings are counted as 8 bytes, as for a Python object array
    target <- 1e9 /
      (itemsize %||%
        if (identical(dtype, "string")) {
          8
        } else {
          zarr_value_sizes[[dtype]]
        })
    for (i in seq_along(shard)) {
      if (prod(shard) > target) {
        room <- floor(target / prod(shard[-i]))
        shard[[i]] <- max(chunk[[i]], floor(room / chunk[[i]]) * chunk[[i]])
      }
    }
    return(list(chunk = chunk, shard = shard))
  }
  for (i in seq_along(chunk)) {
    candidates <- seq_len(min(chunk[[i]], shards[[i]]))
    chunk[[i]] <- max(candidates[shards[[i]] %% candidates == 0])
  }
  list(chunk = chunk, shard = shards)
}

# The `shards` dataset argument as `NULL`, `"auto"` or a shard shape.
# Python shards by default (`auto_shard_zarr_v3`), and `shards = NULL` given
# explicitly switches that off.
zarr_shard_arg <- function(dataset_kwargs, dims, call) {
  if (length(dims) == 0L) {
    return(NULL)
  }
  if (!"shards" %in% names(dataset_kwargs)) {
    return(if (isTRUE(anndata_settings$auto_shard_zarr_v3)) "auto")
  }
  shards <- dataset_kwargs[["shards"]]
  if (is.null(shards)) {
    return(NULL)
  }
  if (identical(shards, "auto")) {
    return("auto")
  }
  valid <- is.numeric(shards) &&
    length(shards) == length(dims) &&
    !anyNA(shards) &&
    all(shards >= 1) &&
    all(shards == round(shards))
  if (!valid) {
    abort_invalid_argument(
      "{.arg shards} must be {.code NULL} or have one positive whole number
       for each of the {length(dims)} dimension{?s} of the array.",
      call
    )
  }
  as.numeric(shards)
}

# The CRC-32C (Castagnoli) of `bytes` as four little-endian bytes. The CRC is
# held in two 16-bit halves, because R integers cannot hold 2^32.
zarr_crc32c <- function(bytes) {
  table_hi <- integer(256)
  table_lo <- integer(256)
  for (n in 0:255) {
    hi <- 0L
    lo <- n
    for (bit in 1:8) {
      carry <- bitwAnd(lo, 1L)
      lo <- bitwOr(lo %/% 2L, (hi %% 2L) * 32768L)
      hi <- hi %/% 2L
      if (carry == 1L) {
        hi <- bitwXor(hi, 0x82F6L)
        lo <- bitwXor(lo, 0x3B78L)
      }
    }
    table_hi[[n + 1L]] <- hi
    table_lo[[n + 1L]] <- lo
  }
  hi <- 0xFFFFL
  lo <- 0xFFFFL
  for (byte in as.integer(bytes)) {
    index <- bitwXor(bitwAnd(lo, 255L), byte) + 1L
    lo <- bitwXor(lo %/% 256L + (hi %% 256L) * 256L, table_lo[[index]])
    hi <- bitwXor(hi %/% 256L, table_hi[[index]])
  }
  lo <- bitwXor(lo, 0xFFFFL)
  hi <- bitwXor(hi, 0xFFFFL)
  as.raw(c(lo %% 256L, lo %/% 256L, hi %% 256L, hi %/% 256L))
}

# Packs the chunk files of an array into shard files (the `sharding_indexed`
# codec with the index at the end): the chunks one after another, then for each
# chunk of the shard its offset and size (both 2^64 - 1 for a missing chunk) as
# 8-byte little-endian integers, and the CRC-32C of that index. A shard with no
# chunks is not written.
zarr_shard_files <- function(dir, chunk, shard) {
  files <- list.files(file.path(dir, "c"), recursive = TRUE)
  if (length(files) == 0L) {
    return(invisible(NULL))
  }
  per_shard <- shard / chunk
  coords <- do.call(
    rbind,
    lapply(strsplit(files, "/", fixed = TRUE), as.numeric)
  )
  shard_coords <- sweep(coords, 2L, per_shard, function(x, y) x %/% y)
  inner <- sweep(coords, 2L, per_shard, function(x, y) x %% y)
  # C-order position of each chunk in its shard
  strides <- rev(cumprod(c(1, rev(per_shard)[-length(per_shard)])))
  position <- as.vector(inner %*% strides)
  keys <- apply(shard_coords, 1L, paste, collapse = "/")
  uint64 <- function(x) zarr_encode_values(x, "uint64")
  missing <- as.raw(rep(255L, 16L))
  shards <- list()
  for (key in unique(keys)) {
    members <- which(keys == key)
    members <- members[order(position[members])]
    blobs <- lapply(file.path(dir, "c", files[members]), function(file) {
      readBin(file, "raw", file.size(file))
    })
    sizes <- vapply(blobs, length, numeric(1))
    offsets <- c(0, cumsum(sizes))[seq_along(sizes)]
    index <- rep(list(missing), prod(per_shard))
    for (j in seq_along(members)) {
      index[[position[members[[j]]] + 1L]] <- c(
        uint64(offsets[[j]]),
        uint64(sizes[[j]])
      )
    }
    index <- unlist(index)
    shards[[key]] <- c(unlist(blobs), index, zarr_crc32c(index))
  }
  unlink(file.path(dir, "c"), recursive = TRUE)
  for (key in names(shards)) {
    target <- file.path(dir, "c", key)
    dir.create(dirname(target), recursive = TRUE, showWarnings = FALSE)
    writeBin(shards[[key]], target)
  }
  invisible(NULL)
}

# The `sharding_indexed` codec holding chunks of shape `chunk` coded by `codecs`
zarr_shard_codecs <- function(codecs, chunk) {
  list(list(
    name = "sharding_indexed",
    configuration = list(
      chunk_shape = as.list(chunk),
      codecs = codecs,
      index_codecs = list(
        list(name = "bytes", configuration = list(endian = "little")),
        list(name = "crc32c")
      ),
      index_location = "end"
    )
  ))
}

zarr_write_array_meta <- function(
  dir,
  dtype,
  dims,
  chunk,
  compressor = zarr_default_compressor,
  shard = NULL
) {
  codecs <- zarr_codecs(dtype, compressor)
  if (!is.null(shard)) {
    codecs <- zarr_shard_codecs(codecs, chunk)
    chunk <- shard
  }
  meta <- list(
    shape = as.list(dims),
    data_type = dtype,
    chunk_grid = list(
      name = "regular",
      configuration = list(chunk_shape = as.list(chunk))
    ),
    chunk_key_encoding = list(
      name = "default",
      configuration = list(separator = "/")
    ),
    fill_value = zarr_fill_value(dtype),
    codecs = codecs,
    attributes = empty_object(),
    zarr_format = 3L,
    node_type = "array",
    storage_transformers = list()
  )
  zarr_write_json(meta, file.path(dir, "zarr.json"))
}

# The little-endian bytes of `values` as `dtype`, one value after another
#' @rdname io-store-zarr-write
zarr_encode_values <- function(values, dtype) {
  size <- zarr_value_sizes[[dtype]]
  switch(
    dtype,
    bool = as.raw(as.integer(values)),
    float32 = ,
    float64 = {
      values[is.na(values)] <- NaN
      writeBin(as.double(values), raw(), size = size, endian = "little")
    },
    complex128 = {
      parts <- c(rbind(Re(values), Im(values)))
      parts[is.na(parts)] <- NaN
      writeBin(parts, raw(), size = 8L, endian = "little")
    },
    zarr_encode_integers(as.double(values), size)
  )
}

# Two's complement bytes of whole numbers, which are held exactly in doubles
# below 2^53 (the size is a byte count)
zarr_encode_integers <- function(values, size) {
  # One row of little-endian bytes per word (R integers cannot hold 2^31)
  word_bytes <- function(word, count) {
    divisors <- 256^(seq_len(count) - 1L)
    outer(word, divisors, function(w, d) floor(w / d) %% 256)
  }
  if (size <= 4L) {
    return(as.raw(t(word_bytes(values %% 2^(8 * size), size))))
  }
  low <- values %% 2^32
  high <- ((values - low) / 2^32) %% 2^32
  as.raw(t(cbind(word_bytes(low, 4L), word_bytes(high, 4L))))
}

# The variable-length UTF-8 chunk format: a count, then each value as a length
# and its bytes (all 4-byte little-endian integers)
#' @rdname io-store-zarr-write
zarr_vlen_encode <- function(values) {
  count <- length(values)
  header <- writeBin(as.integer(count), raw(), size = 4L, endian = "little")
  if (count == 0L) {
    return(header)
  }
  values <- enc2utf8(values)
  lengths <- nchar(values, "bytes")
  out <- raw(4 + sum(4 + lengths))
  out[1:4] <- header
  # 0-based offset of the length of each value
  starts <- 4 + c(0, cumsum(4 + lengths))[seq_len(count)]
  out[rep(starts, each = 4L) + 1:4] <- writeBin(
    as.integer(lengths),
    raw(),
    size = 4L,
    endian = "little"
  )
  if (sum(lengths) > 0) {
    out[rep(starts + 4, lengths) + sequence(lengths)] <- charToRaw(
      paste(values, collapse = "")
    )
  }
  out
}

# zstd-compressed `payload`, by writing it as a 1-d uint8 array with one chunk,
# whose chunk file is exactly the compressed bytes.
# The fill value must differ from the payload, because Rarr skips a chunk that
# only holds the fill value.
#' @rdname io-store-zarr-write
zarr_zstd <- function(payload) {
  zarr_compress(payload, zarr_default_compressor, "uint8")
}

# `payload` compressed as `compressor` says (as `zarr_zstd()` does), and left
# as it is without compression
zarr_compress <- function(payload, compressor, dtype) {
  if (identical(compressor$name, "none")) {
    return(payload)
  }
  if (identical(compressor$name, "gzip")) {
    return(zarr_gzip(payload, compressor$level))
  }
  tmp <- tempfile("zarr-zstd")
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  suppressMessages(Rarr::write_zarr_array(
    array(as.integer(payload), length(payload)),
    tmp,
    chunk_dim = length(payload),
    data_type = "|u1",
    order = "C",
    compressor = zarr_rarr_compressor(compressor, dtype),
    fill_value = if (any(payload != as.raw(0))) 0L else 1L,
    zarr_version = 3L
  ))
  file <- file.path(tmp, "c", "0")
  readBin(file, "raw", file.size(file))
}

# Writes an array held in one chunk, the whole array (or the only value of a 0-d
# array), from its encoded bytes.
# `write_chunk = FALSE` leaves the chunk out, as Python does for a value equal
# to the fill value.
zarr_write_single <- function(
  dir,
  dtype,
  dims,
  payload,
  write_chunk = TRUE,
  compressor = zarr_default_compressor,
  shards = NULL
) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  chunk <- pmax(dims, 1)
  layout <- if (is.numeric(shards)) {
    # The array is one chunk, so a shard is a multiple of it
    list(chunk = chunk, shard = ceiling(shards / chunk) * chunk)
  } else {
    zarr_layout(dims, chunk, shards, dtype)
  }
  zarr_write_array_meta(
    dir,
    dtype,
    dims,
    layout$chunk,
    compressor,
    layout$shard
  )
  if (!write_chunk || (length(dims) > 0L && prod(dims) == 0)) {
    return(invisible(NULL))
  }
  key <- if (length(dims) == 0L) "c" else c("c", rep("0", length(dims)))
  chunk_dir <- do.call(file.path, as.list(c(dir, key[-length(key)])))
  dir.create(chunk_dir, recursive = TRUE, showWarnings = FALSE)
  writeBin(
    zarr_compress(payload, compressor, dtype),
    file.path(chunk_dir, key[[length(key)]])
  )
  if (!is.null(layout$shard)) {
    zarr_shard_files(dir, layout$chunk, layout$shard)
  }
  invisible(NULL)
}

# The R values of a numeric array in the type Rarr needs, or `NULL` when Rarr
# cannot hold them: values beyond the R integer range (and the int32 minimum,
# which is `NA` for R) of the dtypes that must be integers in R
zarr_rarr_values <- function(values, dtype) {
  if (identical(dtype, "bool")) {
    return(as.logical(values))
  }
  if (dtype %in% c("float32", "float64")) {
    values[is.na(values)] <- NaN
    return(as.double(values))
  }
  if (dtype %in% c("int8", "int16", "uint8", "uint16")) {
    return(as.integer(values))
  }
  if (length(values) > 0L && any(abs(values) >= 2^31)) {
    return(NULL)
  }
  as.integer(values)
}

zarr_write_numeric <- function(
  dir,
  values,
  dtype,
  dims,
  chunk = NULL,
  compressor = zarr_default_compressor,
  shards = NULL
) {
  layout <- zarr_layout(dims, chunk %||% zarr_chunk_shape(dims), shards, dtype)
  chunk <- layout$chunk
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  if (length(values) == 0L) {
    zarr_write_array_meta(dir, dtype, dims, chunk, compressor, layout$shard)
    return(invisible(NULL))
  }
  held <- zarr_rarr_values(values, dtype)
  if (is.null(held)) {
    zarr_write_parts(dir, values, dtype, dims, chunk, compressor, shards)
    return(invisible(NULL))
  }
  suppressMessages(Rarr::write_zarr_array(
    array(held, dims),
    dir,
    chunk_dim = chunk,
    data_type = zarr_numpy_types[[dtype]],
    order = "C",
    compressor = zarr_rarr_compressor(compressor, dtype),
    fill_value = if (identical(dtype, "bool")) FALSE else 0,
    zarr_version = 3L
  ))
  if (identical(compressor$name, "gzip")) {
    zarr_gzip_chunks(dir, compressor$level)
  }
  zarr_write_array_meta(dir, dtype, dims, chunk, compressor, layout$shard)
  if (!is.null(layout$shard)) {
    zarr_shard_files(dir, chunk, layout$shard)
  }
  invisible(NULL)
}

# Writes the array as 16-bit integer parts (or float64 parts for complex) with a
# trailing dimension, and moves each chunk file to the key of the real array.
# Missing chunks are zero, which is the fill value of the real array too.
zarr_write_parts <- function(
  dir,
  values,
  dtype,
  dims,
  chunk,
  compressor = zarr_default_compressor,
  shards = NULL
) {
  layout <- zarr_layout(dims, chunk, shards, dtype)
  bytes <- zarr_encode_values(as.vector(values), dtype)
  if (identical(dtype, "complex128")) {
    count <- 2L
    parts <- readBin(bytes, "double", length(bytes) / 8, size = 8L)
    part_type <- "<f8"
  } else {
    count <- zarr_value_sizes[[dtype]] %/% 2L
    parts <- readBin(
      bytes,
      "integer",
      length(bytes) / 2,
      size = 2L,
      signed = FALSE
    )
    part_type <- "<u2"
  }
  # One column per part, so that R's order of the trailing dimension matches
  columns <- t(matrix(parts, nrow = count))
  suppressMessages(Rarr::write_zarr_array(
    array(as.vector(columns), c(dims, count)),
    dir,
    chunk_dim = c(chunk, count),
    data_type = part_type,
    order = "C",
    compressor = zarr_rarr_compressor(compressor, dtype),
    fill_value = 0,
    zarr_version = 3L
  ))
  for (file in list.files(file.path(dir, "c"), recursive = TRUE)) {
    file <- file.path(dir, "c", file)
    moved <- paste0(dirname(file), ".moved")
    file.rename(file, moved)
    unlink(dirname(file), recursive = TRUE)
    file.rename(moved, dirname(file))
  }
  if (identical(compressor$name, "gzip")) {
    zarr_gzip_chunks(dir, compressor$level)
  }
  zarr_write_array_meta(dir, dtype, dims, chunk, compressor, layout$shard)
  if (!is.null(layout$shard)) {
    zarr_shard_files(dir, chunk, layout$shard)
  }
  invisible(NULL)
}

# The on-disk shape of `x`, empty for a scalar
zarr_dims <- function(x, scalar) {
  if (scalar) numeric() else dim(x) %||% length(x)
}

# The chunk shape of the `chunks` dataset argument (Python's `chunks`), or
# `NULL` for the default. A chunk larger than the array is cut to its shape.
zarr_chunk_arg <- function(dataset_kwargs, dims, call) {
  chunks <- dataset_kwargs$chunks
  if (is.null(chunks) || length(dims) == 0L) {
    return(NULL)
  }
  valid <- is.numeric(chunks) &&
    length(chunks) == length(dims) &&
    !anyNA(chunks) &&
    all(chunks >= 1) &&
    all(chunks == round(chunks))
  if (!valid) {
    abort_invalid_argument(
      "{.arg chunks} must have one positive whole number for each of the
       {length(dims)} dimension{?s} of the array.",
      call
    )
  }
  pmax(pmin(chunks, dims), 1)
}

zarr_array_dir <- function(loc, name) {
  zarr_require_v3(loc)
  zarr_key_dir(loc, name)
}

zarr_dataset_write <- function(loc, name, x, scalar, dataset_kwargs, call) {
  dir <- zarr_array_dir(loc, name)
  dtype <- write_dtype(x, elem_path(loc, name), call)
  values <- as.vector(drop_dtype(x))
  dims <- zarr_dims(x, scalar)
  compressor <- zarr_compressor_arg(dataset_kwargs, call, scalar)
  if (scalar) {
    zarr_write_single(
      dir,
      dtype,
      dims,
      zarr_encode_values(values, dtype),
      compressor = compressor
    )
  } else {
    zarr_write_numeric(
      dir,
      values,
      dtype,
      dims,
      zarr_chunk_arg(dataset_kwargs, dims, call),
      compressor,
      zarr_shard_arg(dataset_kwargs, dims, call)
    )
  }
  invisible(NULL)
}

zarr_bool_write <- function(loc, name, x, scalar, call, dataset_kwargs) {
  dir <- zarr_array_dir(loc, name)
  values <- as.vector(x)
  dims <- zarr_dims(x, scalar)
  compressor <- zarr_compressor_arg(dataset_kwargs, call, scalar)
  if (scalar) {
    zarr_write_single(
      dir,
      "bool",
      dims,
      zarr_encode_values(values, "bool"),
      compressor = compressor
    )
  } else {
    zarr_write_numeric(
      dir,
      values,
      "bool",
      dims,
      zarr_chunk_arg(dataset_kwargs, dims, call),
      compressor,
      zarr_shard_arg(dataset_kwargs, dims, call)
    )
  }
  invisible(NULL)
}

zarr_complex_write <- function(loc, name, x, scalar, call, dataset_kwargs) {
  dir <- zarr_array_dir(loc, name)
  values <- as.vector(x)
  dims <- zarr_dims(x, scalar)
  compressor <- zarr_compressor_arg(dataset_kwargs, call, scalar)
  if (scalar) {
    zarr_write_single(
      dir,
      "complex128",
      dims,
      zarr_encode_values(values, "complex128"),
      compressor = compressor
    )
  } else if (length(values) == 0L) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    layout <- zarr_layout(
      dims,
      zarr_chunk_shape(dims),
      zarr_shard_arg(dataset_kwargs, dims, call),
      "complex128"
    )
    zarr_write_array_meta(
      dir,
      "complex128",
      dims,
      layout$chunk,
      compressor,
      layout$shard
    )
  } else {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
    zarr_write_parts(
      dir,
      values,
      "complex128",
      dims,
      zarr_chunk_shape(dims),
      compressor,
      zarr_shard_arg(dataset_kwargs, dims, call)
    )
  }
  invisible(NULL)
}

zarr_string_write <- function(loc, name, x, scalar, call, dataset_kwargs) {
  dir <- zarr_array_dir(loc, name)
  dims <- zarr_dims(x, scalar)
  payload <- zarr_vlen_encode(as.vector(row_major(as.vector(x), dims)))
  zarr_write_single(
    dir,
    "string",
    dims,
    payload,
    compressor = zarr_compressor_arg(dataset_kwargs, call, scalar),
    shards = zarr_shard_arg(dataset_kwargs, dims, call)
  )
  invisible(NULL)
}

# A `null` Element is a 0-d bool array holding `false`, which is the fill value
# so Python writes no chunk
zarr_null_write <- function(store, key) {
  zarr_require_v3(store)
  zarr_write_single(
    zarr_key_dir(store, key),
    "bool",
    numeric(),
    as.raw(0),
    write_chunk = FALSE
  )
  invisible(NULL)
}

# Writes the consolidated metadata of the store, inline in the root `zarr.json`
#' @rdname io-store-zarr-write
zarr_consolidate <- function(path) {
  # Rarr writes empty attributes as lists, which Python rejects, so the
  # metadata is collected here (reading keeps empty objects as objects)
  read_meta <- function(file) {
    jsonlite::fromJSON(file, simplifyVector = FALSE)
  }
  files <- list.files(path, "^zarr\\.json$", recursive = TRUE)
  keys <- dirname(files)
  members <- keys != "."
  metadata <- lapply(file.path(path, files[members]), read_meta)
  names(metadata) <- keys[members]
  if (length(metadata) == 0L) {
    metadata <- empty_object()
  }
  root_file <- file.path(path, "zarr.json")
  root <- read_meta(root_file)
  root$consolidated_metadata <- list(
    kind = "inline",
    must_understand = FALSE,
    metadata = metadata
  )
  zarr_write_json(root, root_file)
  invisible(path)
}
