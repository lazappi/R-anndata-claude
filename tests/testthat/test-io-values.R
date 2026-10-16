dense_dtypes <- c(
  "int8",
  "int16",
  "int32",
  "int64",
  "uint8",
  "uint16",
  "uint32",
  "uint64",
  "float32",
  "float64"
)

# The R value Python's `arange(1, n + 1)` of `dtype` reads as, with the On-disk
# dtype record where R's type differs
typed_expected <- function(dtype, n) {
  integer_like <- dtype %in% c("int8", "int16", "int32", "uint8", "uint16")
  values <- if (integer_like) seq_len(n) else as.double(seq_len(n))
  record_dtype(values, dtype)
}

# Expected R values for every fixture an Element can be read from, named by
# the fixture case (an Element at the key `x` of `<case>.h5`)
expected_values <- function() {
  cases <- list()
  for (dtype in dense_dtypes) {
    cases[[paste0("array_", dtype)]] <- typed_expected(dtype, 3L)
    # `[[` drops the record, so it is restored for the scalar
    cases[[paste0("scalar_", dtype)]] <- record_dtype(
      typed_expected(dtype, 1L)[[1L]],
      dtype
    )
  }
  strings <- c("a", "bé", "", "日本")
  c(
    cases,
    list(
      # Python `int` is int64 on disk
      scalar_python_int = set_dtype(7, "int64"),
      scalar_python_float = 2.5,
      scalar_python_bool = TRUE,
      scalar_python_str = "héllo",
      scalar_str_empty = "",
      scalar_bool = TRUE,
      scalar_complex128 = 1 + 2i,
      array_bool = c(TRUE, FALSE, TRUE),
      array_bool_2d = matrix(
        c(TRUE, FALSE, TRUE, FALSE, FALSE, TRUE),
        2,
        3,
        TRUE
      ),
      array_complex128 = c(1 + 2i, -3.5 + 0.25i),
      array_float64_special = c(1.5, -2.25, NaN, Inf),
      array_float64_2d = matrix(as.double(0:5), 2, 3, byrow = TRUE),
      array_int32_2d = matrix(0:5, 2, 3, byrow = TRUE),
      array_float64_3d = aperm(array(as.double(0:23), c(4, 3, 2))),
      array_float64_empty = numeric(0),
      array_float64_0x3 = matrix(numeric(0), 0, 3),
      array_float64_1elem = as_array(2.5),
      array_int32_min = set_dtype(c(-2^31, 0, 5), "int32"),
      scalar_int32_min = set_dtype(-2^31, "int32"),
      string_array_1d = strings,
      string_array_object = strings,
      string_array_2d = matrix(letters[1:6], 2, 3, byrow = TRUE),
      string_array_1elem = as_array("a"),
      string_array_empty = character(0),
      null = NULL
    )
  )
}

# The Encoding type and whether the dataspace is scalar, as Python sees them
written_encoding <- function(value) {
  path <- write_fixture_like(value)
  store <- rhdf5::H5Fopen(path)
  on.exit(rhdf5::h5closeAll())
  elem <- rhdf5::H5Oopen(store, "x")
  info <- h5_info(store, "/x")
  list(
    type = read_elem_attr(elem, "encoding-type"),
    version = read_elem_attr(elem, "encoding-version"),
    scalar = identical(info$stype, "SCALAR")
  )
}

# Python -> R: every committed fixture reads as the value Python holds, with
# the On-disk dtype recorded where R's type differs
test_that("Python-written Elements read as the expected R values", {
  for (name in names(expected_values())) {
    expect_identical(
      read_fixture_elem(name),
      expected_values()[[name]],
      info = name
    )
  }
})

# bytes is read only, and Python holds the value as bytes, so R holds it as raw
test_that("bytes reads as a raw vector", {
  expect_identical(read_fixture_elem("bytes_scalar"), charToRaw("raw bytes"))
})

# rhdf5 reads complex64 as garbage, so the reader must refuse it
test_that("reading complex64 raises a classed error naming the path", {
  err <- expect_anndata_condition(
    read_fixture_elem("array_complex64"),
    "anndata_dtype_error"
  )
  expect_identical(err$path, "/x")
})

# The R round trip: every readable Element must write back and read as the
# same value, including its On-disk dtype record
test_that("Elements round trip through R", {
  for (name in names(expected_values())) {
    value <- expected_values()[[name]]
    expect_identical(
      read_written(write_fixture_like(value)),
      value,
      info = name
    )
  }
})

# Python -> R -> Python: what R writes after reading a fixture must match the
# fixture's groups, dtypes, shapes, attributes and values
test_that("R rewrites every fixture structurally equivalent to Python", {
  skip_if_no_python()
  for (name in names(expected_values())) {
    original <- fixture_path(file.path("h5ad", paste0(name, ".h5")))
    value <- read_fixture_elem(name)
    expect_structurally_equivalent(write_fixture_like(value), original)
  }
})

# R -> Python -> R: Python must read what R writes and write it back so that R
# sees the same value
test_that("Python reads and rewrites what R writes", {
  skip_if_no_python()
  for (name in names(expected_values())) {
    # Python cannot write a complex scalar it has read back (it reads a Python
    # `complex`, which has no writer)
    if (name == "scalar_complex128") {
      next
    }
    value <- expected_values()[[name]]
    written <- write_fixture_like(value)
    rewritten <- withr::local_tempfile(fileext = ".h5")
    run_python("rewrite.py", written, rewritten)
    # Python's reader turns a scalar into a Python int or float, which it
    # writes as int64 or float64, so the dtype changes in Python and not in R
    if (grepl("^scalar_u?int", name)) {
      value <- set_dtype(as.double(drop_dtype(value)), "int64")
    } else if (name == "scalar_float32") {
      value <- drop_dtype(value)
    }
    expect_identical(read_written(rewritten), value, info = name)
  }
})

# Python's scalar and 1-element array encodings are told apart in R by `dim`,
# so each side of the rule needs a test in both directions
test_that("scalars and 1-element arrays keep their Encoding type", {
  scalars <- list(1.5, 2L, TRUE, 1 + 2i)
  for (value in scalars) {
    written <- written_encoding(value)
    expect_identical(written$type, "numeric-scalar")
    expect_true(written$scalar)
    written <- written_encoding(as_array(value))
    expect_identical(written$type, "array")
    expect_false(written$scalar)
  }
  expect_identical(written_encoding("a")$type, "string")
  expect_true(written_encoding("a")$scalar)
  expect_identical(written_encoding(as_array("a"))$type, "string-array")
  expect_false(written_encoding(as_array("a"))$scalar)
  expect_identical(written_encoding(c(1, 2))$type, "array")
  expect_identical(written_encoding(matrix(1, 1, 1))$type, "array")
  expect_identical(written_encoding(NULL)$type, "null")

  # An Element read from disk is written back with the type it was read with
  expect_identical(dim(read_fixture_elem("array_float64_1elem")), 1L)
  expect_null(dim(read_fixture_elem("scalar_float64")))
  expect_identical(
    written_encoding(read_fixture_elem("string_array_1elem"))$type,
    "string-array"
  )
  expect_identical(
    written_encoding(read_fixture_elem("scalar_python_str"))$type,
    "string"
  )
})

test_that("as_array gives atomic vectors a dim and rejects other values", {
  expect_identical(dim(as_array(1.5)), 1L)
  expect_identical(dim(as_array(c(1, 2))), 2L)
  expect_identical(as_array(matrix(1, 2, 2)), matrix(1, 2, 2))
  expect_identical(as_array(character()), array(character(), 0L))
  expect_anndata_condition(
    as_array(list(1)),
    "anndata_invalid_value_error"
  )
  expect_anndata_condition(as_array(NULL), "anndata_invalid_value_error")
})

# Python has no NA for floats, so the spec collapses NA and NaN on write
test_that("NA_real_ is written as NaN", {
  value <- read_written(write_fixture_like(c(1, NA, NaN)))
  expect_true(all(is.nan(value[2:3])))
  expect_identical(value[[1L]], 1)
})

# A value that no longer fits its recorded dtype must raise, never wrap
test_that("a value outside its recorded dtype raises", {
  value <- set_dtype(c(1, 300), "uint8")
  expect_anndata_condition(
    write_fixture_like(value),
    "anndata_dtype_overflow_error"
  )
})

# Complex values have no nullable encoding, so NA must raise rather than write a
# wrong value
test_that("NA in complex values raises", {
  err <- expect_anndata_condition(
    write_fixture_like(c(1 + 2i, NA)),
    "anndata_io_registry_error"
  )
  expect_identical(err$path, "/x")
})

# Only encodable values are written, and the error names the path and class
test_that("unencodable values raise an io registry error", {
  values <- list(
    mean,
    new.env(),
    list(1, 2),
    Sys.Date(),
    as.raw(1:2),
    quote(x)
  )
  for (value in values) {
    err <- expect_anndata_condition(
      write_fixture_like(value),
      "anndata_io_registry_error"
    )
    expect_identical(err$path, "/x")
  }
})

# The registry error must carry the class so users can tell what failed
test_that("the unencodable error names the R class", {
  err <- expect_anndata_condition(
    write_fixture_like(Sys.Date()),
    "anndata_io_registry_error"
  )
  expect_identical(err$r_class, "Date")
})

# Reading the nested path form must work too, since Elements live below groups
test_that("Elements are read and written below a group", {
  store <- local_h5_store()
  group <- rhdf5::H5Gcreate(store, "uns")
  write_elem(group, "m", matrix(c(1.5, 2, 3, 4, 5, 6), 2, 3))
  write_elem(group, "s", "text")
  expect_identical(
    read_elem(store, "uns/m"),
    matrix(c(1.5, 2, 3, 4, 5, 6), 2, 3)
  )
  expect_identical(read_elem(group, "s"), "text")
})
