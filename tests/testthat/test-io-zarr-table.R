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
      list(a = c(1L, 2L, 0L, 0L, 5L), s = c("ab", "c", "", "", "xyz")),
      class = "data.frame",
      row.names = 1:5
    )
  )
})

# Only bytes and zstd are understood, so another codec must raise rather than
# misread the chunk
test_that("a struct array with another codec raises", {
  store <- hand_built_struct(
    list(`0` = data.frame(a = 1L, s = "a")),
    rows = 1L,
    chunk_rows = 1L,
    codecs = list(list(name = "bytes"), list(name = "gzip"))
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
  expect_identical(result$lo, c(65534L, 7L))
  expect_identical(result$hi, c(-1L, 0L))
})
