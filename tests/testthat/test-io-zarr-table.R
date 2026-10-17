# Edge cases of the zarr table backend (rec-array `struct` arrays) that the
# Python fixtures do not reach: several chunks, other codecs and field types.

skip_if_not_installed("Rarr", "2.1.48")

# A store whose array `x` is a struct of an int32 `a` and a 3-byte
# null-terminated string `s`, with `chunk_rows` records per chunk.
# `chunks` is a named list of data frames (names are the chunk indices) and
# the others are left out of the store.
hand_built_struct <- function(chunks, rows, chunk_rows, codecs = NULL) {
  path <- tempfile(fileext = ".zarr")
  withr::defer(unlink(path, recursive = TRUE), envir = parent.frame())
  store <- zarr_create(path)
  dir <- file.path(path, "x")
  dir.create(file.path(dir, "c"), recursive = TRUE)
  fields <- list(
    list(name = "a", data_type = "int32"),
    list(
      name = "s",
      data_type = list(
        name = "null_terminated_bytes",
        configuration = list(length_bytes = 3L)
      )
    )
  )
  meta <- list(
    shape = list(rows),
    data_type = list(name = "struct", configuration = list(fields = fields)),
    chunk_grid = list(
      name = "regular",
      configuration = list(chunk_shape = list(chunk_rows))
    ),
    chunk_key_encoding = list(
      name = "default",
      configuration = list(separator = "/")
    ),
    fill_value = list(a = 0L, s = "MA=="),
    codecs = codecs %||% zarr_codecs("int32"),
    attributes = empty_object(),
    zarr_format = 3L,
    node_type = "array",
    storage_transformers = list()
  )
  zarr_write_json(meta, file.path(dir, "zarr.json"))
  for (index in names(chunks)) {
    chunk <- chunks[[index]]
    records <- lapply(seq_len(nrow(chunk)), function(i) {
      text <- charToRaw(chunk$s[[i]])
      c(
        zarr_encode_values(chunk$a[[i]], "int32"),
        text,
        raw(3L - length(text))
      )
    })
    writeBin(
      zarr_zstd(do.call(c, records)),
      file.path(dir, "c", index)
    )
  }
  store
}

# Reading must cut the grid into chunks, treat a missing chunk as zeros and drop
# the padding of the last, partial chunk
test_that("a struct array of several chunks is read, with a missing chunk", {
  store <- hand_built_struct(
    list(
      `0` = data.frame(a = 1:2, s = c("ab", "c")),
      `2` = data.frame(a = c(5L, 0L), s = c("xyz", ""))
    ),
    rows = 5L,
    chunk_rows = 2L
  )
  expect_identical(
    table_read(store, "x"),
    structure(
      list(
        a = c(1L, 2L, 0L, 0L, 5L),
        s = set_dtype(c("ab", "c", "", "", "xyz"), "null_terminated_bytes:3")
      ),
      class = "data.frame",
      row.names = 1:5
    )
  )
})

# Only bytes, zstd, gzip and blosc are understood, so another codec must raise
# rather than misread the chunk
test_that("a struct array with another codec raises", {
  store <- hand_built_struct(
    list(`0` = data.frame(a = 1L, s = "a")),
    rows = 1L,
    chunk_rows = 1L,
    codecs = list(list(name = "bytes"), list(name = "crc32c"))
  )
  expect_error(table_read(store, "x"), "codecs")
})

# Field types outside the numeric, bool and string ones have no R value
test_that("a struct field of an unsupported type raises", {
  store <- hand_built_struct(
    list(`0` = data.frame(a = 1L, s = "a")),
    rows = 1L,
    chunk_rows = 1L
  )
  file <- file.path(store$root, "x", "zarr.json")
  meta <- jsonlite::fromJSON(file, simplifyVector = FALSE)
  meta$data_type$configuration$fields[[1L]]$data_type <- "complex128"
  zarr_write_json(meta, file)
  expect_error(table_read(store, "x"), "unsupported type")
})

# zarr stores strings as UTF-32, so unlike HDF5 it can hold non-ASCII text
test_that("non-ASCII rec-array text is written to zarr", {
  value <- new_rec_array(data.frame(s = c("yé", "b"), f = c(1, 2)))
  path <- tempfile(fileext = ".zarr")
  withr::defer(unlink(path, recursive = TRUE))
  write_elem(zarr_create(path), "x", value)
  expect_identical(read_elem(zarr_open(path), "x"), value)
})

# Every numeric width must decode, including the negative ones and float32,
# which the written fixtures reach only partly
test_that("struct fields of every numeric width are read", {
  store <- hand_built_struct(
    list(`0` = data.frame(a = c(-2L, 7L), s = c("a", "b"))),
    rows = 2L,
    chunk_rows = 2L
  )
  file <- file.path(store$root, "x", "zarr.json")
  meta <- jsonlite::fromJSON(file, simplifyVector = FALSE)
  # The int32 bytes read as two 16-bit fields keep the same chunk bytes
  meta$data_type$configuration$fields <- list(
    list(name = "lo", data_type = "uint16"),
    list(name = "hi", data_type = "int16"),
    meta$data_type$configuration$fields[[2L]]
  )
  zarr_write_json(meta, file)
  result <- table_read(store, "x")
  expect_identical(drop_dtype(result$lo), c(65534L, 7L))
  expect_identical(get_dtype(result$lo), "uint16")
  expect_identical(drop_dtype(result$hi), c(-1L, 0L))
  expect_identical(get_dtype(result$hi), "int16")
})

# The field types of a written array, from its metadata
struct_field_types <- function(path) {
  meta <- jsonlite::fromJSON(
    file.path(path, "x", "zarr.json"),
    simplifyVector = FALSE
  )
  vapply(
    meta$data_type$configuration$fields,
    function(field) {
      type <- field$data_type
      if (is.character(type)) {
        type
      } else {
        paste0(type$name, ":", type$configuration$length_bytes)
      }
    },
    character(1)
  )
}

# Writes `value` as `x` of a new store, returning the store path
write_struct <- function(value, ..., env = parent.frame()) {
  path <- tempfile(fileext = ".zarr")
  withr::defer(unlink(path, recursive = TRUE), envir = env)
  write_elem(zarr_create(path), "x", value, dataset_kwargs = list(...))
  path
}

# R-built values get the field types Python writes for the equivalent values
# (zarr-io/14): int32, float64, bool and UTF-32 sized by the longest UTF-8 byte
# length counted as characters
test_that("R-built rec-array fields get the types Python would write", {
  value <- new_rec_array(data.frame(
    i = 1:2,
    d = c(1.5, NA),
    l = c(TRUE, FALSE),
    s = c("ab", "yé")
  ))
  path <- write_struct(value)
  expect_identical(
    struct_field_types(path),
    c("int32", "float64", "bool", "fixed_length_utf32:12")
  )
  expect_identical(read_elem(zarr_open(path), "x")$l, c(TRUE, FALSE))
})

# Field dtypes need a record on the R value to survive a read and a write
test_that("rec-array field dtypes round trip through R", {
  v3 <- zarr_variant_paths("v3")
  value <- read_elem(zarr_open(v3[["rec_array_widths"]]), "x")
  expect_identical(
    vapply(value, function(field) get_dtype(field) %||% "", character(1)),
    c(
      u1 = "uint8",
      i2 = "int16",
      u4 = "uint32",
      i8 = "int64",
      f4 = "float32",
      b = ""
    )
  )
  written <- write_struct(value)
  expect_identical(
    struct_field_types(written),
    c("uint8", "int16", "uint32", "int64", "float32", "bool")
  )
  expect_identical(read_elem(zarr_open(written), "x"), value)
  basic <- read_elem(zarr_open(v3[["rec_array_basic"]]), "x")
  expect_identical(get_dtype(basic$fixed), "null_terminated_bytes:3")
  expect_identical(
    struct_field_types(write_struct(basic)),
    c("int32", "float64", "null_terminated_bytes:3", "fixed_length_utf32:12")
  )
})

# A record must never wrap or truncate values
test_that("a value outside its recorded field dtype raises", {
  value <- new_rec_array(data.frame(a = 1L))
  value$a <- set_dtype(300L, "uint8")
  expect_anndata_condition(
    write_struct(value),
    "anndata_dtype_overflow_error"
  )
})

# Python writes empty numeric rec-arrays, and so must zarr (HDF5 cannot)
test_that("a rec-array with no records round trips in zarr", {
  value <- new_rec_array(data.frame(a = integer(), s = character()))
  path <- write_struct(value)
  expect_false(dir.exists(file.path(path, "x", "c")))
  expect_identical(read_elem(zarr_open(path), "x"), value)
})

# Python does not shard rec-arrays by default, but honours `shards`
test_that("rec-arrays are sharded only when shards is given", {
  value <- new_rec_array(data.frame(a = 1:5, s = letters[1:5]))
  is_sharded <- function(path) {
    meta <- jsonlite::fromJSON(file.path(path, "x", "zarr.json"))
    "sharding_indexed" %in% meta$codecs$name
  }
  expect_false(is_sharded(write_struct(value)))
  for (shards in list("auto", 5)) {
    path <- write_struct(value, shards = shards)
    expect_true(is_sharded(path))
    expect_identical(read_elem(zarr_open(path), "x"), value)
  }
  expect_false(is_sharded(write_struct(value, shards = NULL)))
})

# Python must read the sharded stores R writes with the same fields and values
test_that("Python reads sharded rec-arrays written by R", {
  skip_if_no_python()
  v3 <- zarr_variant_paths("v3")
  cases <- v3[c("rec_array_basic", "rec_array_widths")]
  # The stores are removed when the test ends, not when the function returns
  test_env <- environment()
  written <- vapply(
    cases,
    function(path) {
      write_struct(
        read_elem(zarr_open(path), "x"),
        shards = "auto",
        env = test_env
      )
    },
    character(1)
  )
  expect_all_equivalent(unname(written), unname(cases))
})

# The reader must cut a shard into inner chunks and treat a missing one as
# zeros (`zarr_shard_files()` writes the index as Python does)
test_that("a shard of several inner chunks with a missing one is read", {
  store <- hand_built_struct(
    list(
      `0` = data.frame(a = 1:2, s = c("ab", "c")),
      `2` = data.frame(a = c(5L, 0L), s = c("xyz", ""))
    ),
    rows = 5L,
    chunk_rows = 2L
  )
  dir <- file.path(store$root, "x")
  file <- file.path(dir, "zarr.json")
  meta <- jsonlite::fromJSON(file, simplifyVector = FALSE)
  meta$codecs <- zarr_shard_codecs(meta$codecs, 2L)
  meta$chunk_grid$configuration$chunk_shape <- list(6L)
  zarr_write_json(meta, file)
  zarr_shard_files(dir, 2L, 6L)
  expect_identical(list.files(file.path(dir, "c")), "0")
  result <- table_read(store, "x")
  expect_identical(drop_dtype(result$a), c(1L, 2L, 0L, 0L, 5L))
  expect_identical(drop_dtype(result$s), c("ab", "c", "", "", "xyz"))
})

# A shard index at the start is not read, so it must raise and not misread
test_that("a shard index at the start raises", {
  value <- new_rec_array(data.frame(a = 1:3))
  path <- write_struct(value, shards = "auto")
  file <- file.path(path, "x", "zarr.json")
  meta <- jsonlite::fromJSON(file, simplifyVector = FALSE)
  meta$codecs[[1L]]$configuration$index_location <- "start"
  zarr_write_json(meta, file)
  expect_anndata_condition(
    read_elem(zarr_open(path), "x"),
    "anndata_not_supported_error"
  )
})

# The compressor codecs of a written rec-array, from its metadata (inside the
# shard codec when sharded)
struct_codec_names <- function(path) {
  meta <- jsonlite::fromJSON(
    file.path(path, "x", "zarr.json"),
    simplifyVector = FALSE
  )
  codecs <- meta$codecs
  if (identical(codecs[[1L]]$name, "sharding_indexed")) {
    codecs <- codecs[[1L]]$configuration$codecs
  }
  vapply(codecs, function(codec) codec$name, character(1))
}

# The `compressors` argument must be honoured and read back for rec-arrays
# (zarr-io/15), sharded or not
test_that("rec-arrays round trip with every compressor", {
  value <- new_rec_array(data.frame(
    a = 1:40,
    d = seq(0.5, by = 1.5, length.out = 40),
    s = rep(c("ab", "yé", "c"), length.out = 40)
  ))
  compressors <- list(
    none = NULL,
    zstd = list(name = "zstd", level = 3L),
    gzip = list(name = "gzip", level = 9L),
    blosc = list(name = "blosc", cname = "zstd", clevel = 3L),
    blosc_plain = "blosc"
  )
  for (case in names(compressors)) {
    name <- sub("_plain$", "", case)
    expected <- if (name == "none") "bytes" else c("bytes", name)
    for (shards in list(NULL, "auto")) {
      path <- write_struct(
        value,
        compressors = compressors[[case]],
        shards = shards
      )
      info <- paste(case, if (is.null(shards)) "unsharded" else "sharded")
      expect_identical(struct_codec_names(path), expected, info = info)
      expect_identical(read_elem(zarr_open(path), "x"), value, info = info)
    }
  }
})

# Python must read the compressed stores R writes, with the same fields and
# values
test_that("Python reads compressed rec-arrays written by R", {
  skip_if_no_python()
  v3 <- zarr_variant_paths("v3")
  cases <- v3[c("rec_array_basic", "rec_array_widths")]
  test_env <- environment()
  compressors <- list(
    none = NULL,
    zstd = "zstd",
    gzip = "gzip",
    blosc = "blosc"
  )
  written <- character()
  expected <- character()
  for (compressor in names(compressors)) {
    for (case in cases) {
      written <- c(
        written,
        write_struct(
          read_elem(zarr_open(case), "x"),
          compressors = compressors[[compressor]],
          env = test_env
        )
      )
      expected <- c(expected, case)
    }
  }
  expect_all_equivalent(written, expected)
})

# Python's own compressed rec-arrays (one variant per compressor) must read as
# the default ones do
test_that("rec-arrays Python wrote with each compressor are read", {
  v3 <- zarr_variant_paths("v3")
  for (name in c("zstd", "blosc", "gzip", "none")) {
    paths <- zarr_variant_paths(paste0("v3_", name))
    for (case in c("rec_array_widths", "rec_array_basic")) {
      expect_true(case %in% names(paths), info = paste(name, case))
      expect_identical(
        read_elem(zarr_open(paths[[case]]), "x"),
        read_elem(zarr_open(v3[[case]]), "x"),
        info = paste(name, case)
      )
    }
  }
})
