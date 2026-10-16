# Tests of the zarr write backend of the store layer (ticket zarr-io/05), below
# any encoding: groups, attributes and arrays of every kind in a v3 store.

skip_if_not_installed("Rarr", "2.1.48")

# u-umlaut, euro sign and a four-byte character, built here because literal
# non-ASCII text in R files gives an R CMD check warning
non_ascii <- intToUtf8(c(0xfc, 0x20ac, 0x1f600))

# The root of a new v3 store
local_zarr_store <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  zarr_create(file.path(dir, "r.zarr"))
}

# Writes `value` with the writer for its type and reads it back from the store
zarr_write_read <- function(value, scalar = FALSE, env = parent.frame()) {
  store <- local_zarr_store(env)
  plain <- drop_dtype(value)
  if (is.character(plain)) {
    write_string_dataset(store, "x", plain, scalar, NULL)
  } else if (is.logical(plain)) {
    write_bool_dataset(store, "x", plain, scalar, NULL)
  } else if (is.complex(plain)) {
    write_complex_dataset(store, "x", plain, scalar, NULL)
  } else {
    write_dataset(store, "x", value, scalar = scalar)
  }
  array_read(store, "/x")
}

# What Python's zarr sees in a store R wrote (zarr_describe.py), keyed by path
python_describe <- function(store) {
  lines <- run_python("zarr_describe.py", store$root)
  nodes <- lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)
  unlist(nodes, recursive = FALSE)
}

test_that("a new store is a v3 root group Python can open", {
  # The root is the starting point of every write, so it must be a valid group
  skip_if_no_python()
  store <- local_zarr_store()
  expect_true(is_store_file(store))
  expect_identical(group_members(store), character())
  expect_identical(python_describe(store)[["/"]]$kind, "group")
})

test_that("groups are created, found and deleted", {
  # The encodings create a group per Element and replace Elements by deleting
  store <- local_zarr_store()
  group <- group_create(store, "g")
  expect_identical(node_path(group), "/g")
  inner <- group_create(group, "h")
  expect_identical(node_path(inner), "/g/h")
  expect_true(member_exists(store, "g"))
  expect_identical(group_members(group), "h")
  expect_error(
    group_create(store, "g"),
    class = "anndata_invalid_value_error"
  )
  member_delete(store, "g")
  expect_false(member_exists(store, "g"))
})

test_that("attributes round trip with their JSON types", {
  # Attributes carry the Encoding type and version and the sparse shape, so
  # scalars, arrays, empty arrays and objects must all read back as written
  store <- local_zarr_store()
  group <- group_create(store, "g")
  attr_write(group, "text", "hello")
  attr_write(group, "texts", c("a", "b"))
  attr_write(group, "one_text", "a", scalar = FALSE)
  attr_write(group, "none", character())
  attr_write(group, "flag", TRUE)
  attr_write(group, "shape", c(3, 4), dtype = "int64", scalar = FALSE)
  attr_write(group, "number", 1.5)
  attr_write(group, "object", list(key = "value", n = 2))
  expect_identical(attr_read(group, "text"), "hello")
  expect_identical(attr_read(group, "texts"), c("a", "b"))
  expect_identical(attr_read(group, "one_text"), "a")
  expect_identical(attr_read(group, "none"), character())
  expect_true(attr_read(group, "flag"))
  expect_identical(attr_read(group, "shape"), c(3L, 4L))
  expect_identical(attr_read(group, "number"), 1.5)
  expect_identical(attr_read(group, "object"), list(key = "value", n = 2L))
  expect_true(attr_exists(group, "text"))
  expect_false(attr_exists(group, "absent"))
  # The members of the group are untouched by the attribute writes
  expect_identical(group_members(store), "g")
})

test_that("attributes of an array are written to the array", {
  # The encodings open the array they just wrote and add the Encoding
  # attributes to it, which must not change the array
  store <- local_zarr_store()
  write_dataset(store, "x", c(1.5, 2, 3))
  node <- node_open(store, "x")
  set_elem_attr(node, "encoding-type", "array")
  set_elem_attr(node, "encoding-version", "0.2.0")
  expect_identical(read_elem_attr(node, "encoding-type"), "array")
  expect_identical(array_read(store, "/x"), c(1.5, 2, 3))
})

test_that("numeric arrays read back with their values, shape and dtype", {
  # Every numeric dtype is given explicitly, never Rarr's smallest fit
  values <- list(
    vector = c(1.5, NaN, -Inf, 3),
    matrix = matrix(c(1, 2, 3, 4, 5, 6), 2, 3),
    cube = array(as.double(1:24), c(2, 3, 4)),
    integers = c(1L, -5L, 100L),
    int_matrix = matrix(1:6, 2, 3),
    float32 = set_dtype(c(0.5, 1.25, -2), "float32"),
    int8 = set_dtype(c(-128L, 0L, 127L), "int8"),
    int16 = set_dtype(c(-32768L, 0L, 32767L), "int16"),
    uint8 = set_dtype(c(0L, 7L, 255L), "uint8"),
    uint16 = set_dtype(c(0L, 7L, 65535L), "uint16"),
    uint32_small = set_dtype(c(0, 7, 2^31 - 1), "uint32"),
    int64_small = set_dtype(c(-3, 0, 2^31 - 1), "int64"),
    uint64_small = set_dtype(c(0, 5, 17), "uint64")
  )
  for (name in names(values)) {
    value <- values[[name]]
    expect_identical(zarr_write_read(value), value, label = name)
  }
})

test_that("integers beyond the R integer range are written exactly", {
  # Rarr cannot write int64 or uint64 from doubles, uint32 above 2^31 or the
  # int32 minimum, so these use the split-parts writer
  values <- list(
    int32_min = set_dtype(c(-2^31, 4, 2^31 - 1), "int32"),
    uint32_big = set_dtype(c(0, 2^31, 2^32 - 1), "uint32"),
    int64_big = set_dtype(c(-2^40, 2^52 + 1, 5, -1), "int64"),
    uint64_big = set_dtype(c(0, 2^40 + 7, 2^53 - 1), "uint64"),
    int64_matrix = set_dtype(
      matrix(c(2^33, -2^33, 1, 2, 3, 2^34), 2, 3),
      "int64"
    )
  )
  for (name in names(values)) {
    value <- values[[name]]
    expect_identical(zarr_write_read(value), value, label = name)
  }
})

test_that("scalars are 0-d arrays", {
  # Scalars have no shape and are stored in the chunk with the key `c`
  expect_identical(zarr_write_read(2.5, scalar = TRUE), 2.5)
  expect_identical(zarr_write_read(7L, scalar = TRUE), 7L)
  expect_identical(zarr_write_read(0, scalar = TRUE), 0)
  big <- set_dtype(2^40, "int64")
  expect_identical(zarr_write_read(big, scalar = TRUE), big)
  small <- set_dtype(-2^31, "int32")
  expect_identical(zarr_write_read(small, scalar = TRUE), small)
  expect_identical(zarr_write_read(TRUE, scalar = TRUE), TRUE)
  expect_identical(zarr_write_read("text", scalar = TRUE), "text")
  expect_identical(zarr_write_read("", scalar = TRUE), "")
  expect_identical(
    zarr_write_read(complex(real = 1, imaginary = -2), scalar = TRUE),
    complex(real = 1, imaginary = -2)
  )
})

test_that("empty arrays have metadata and no chunks", {
  # Python gives an empty dimension a chunk of size 1 and writes no chunk
  expect_identical(
    zarr_write_read(matrix(numeric(), 0, 3)),
    matrix(numeric(), 0, 3)
  )
  expect_identical(
    zarr_write_read(matrix(numeric(), 2, 0)),
    matrix(numeric(), 2, 0)
  )
  expect_identical(zarr_write_read(numeric()), numeric())
  expect_identical(zarr_write_read(character()), character())
  expect_identical(zarr_write_read(logical()), logical())
})

test_that("bool arrays round trip", {
  value <- matrix(c(TRUE, FALSE, FALSE, TRUE, TRUE, TRUE), 2, 3)
  expect_identical(zarr_write_read(value), value)
  expect_identical(zarr_write_read(c(FALSE, FALSE)), c(FALSE, FALSE))
})

test_that("complex arrays round trip", {
  value <- matrix(complex(real = 1:6, imaginary = -(1:6) / 2), 2, 3)
  expect_identical(zarr_write_read(value), value)
})

test_that("string arrays keep their values, order and non-ASCII text", {
  # Variable-length UTF-8, written in C order for arrays of two dimensions
  texts <- c("a", "", non_ascii, "bcd", "e\nf", "g")
  expect_identical(zarr_write_read(texts), texts)
  matrix_texts <- matrix(texts, 2, 3)
  expect_identical(zarr_write_read(matrix_texts), matrix_texts)
  expect_identical(zarr_write_read(""), "")
  expect_identical(zarr_write_read(c("", "")), c("", ""))
  expect_identical(zarr_write_read(non_ascii, scalar = TRUE), non_ascii)
})

test_that("a null Element is a 0-d bool array", {
  # Python writes null as a 0-d bool array, which is neither read nor shaped
  store <- local_zarr_store()
  null_write(store, "n")
  info <- array_info(store, "/n")
  expect_identical(info$dtype, "bool")
  expect_identical(info$rank, 0L)
})

test_that("large arrays are split into chunks of at most 2^20 values", {
  # Chunking is Rarr's job, so a multi-chunk array must read back whole
  expect_identical(zarr_chunk_shape(c(3, 4)), c(3, 4))
  expect_identical(zarr_chunk_shape(c(0, 3)), c(1, 3))
  expect_identical(zarr_chunk_shape(2^22), 2^20)
  expect_identical(zarr_chunk_shape(c(2^21, 2^21)), c(1, 2^20))
  withr::local_options(anndata.zarr_chunk_limit = 10)
  value <- as.double(seq_len(25))
  expect_identical(zarr_write_read(value), value)
})

test_that("split-parts arrays with several chunks keep their values", {
  # The split-parts writer renames chunk files, so it needs more than one chunk
  # along the first dimension of a 2-d array (a small chunk limit makes that
  # cheap)
  withr::local_options(anndata.zarr_chunk_limit = 12)
  value <- set_dtype(
    matrix(c(2^40 + 1:15, -2^40 - 1:15), 10, 3),
    "int64"
  )
  expect_identical(zarr_write_read(value), value)
  complex_value <- matrix(complex(real = 1:30, imaginary = 1), 10, 3)
  expect_identical(zarr_write_read(complex_value), complex_value)
})

test_that("writing to a zarr v2 store is not supported", {
  # Writing v2 is zarr-io/11, so a v2 store must not be written as v3
  store <- zarr_open(zarr_fixture_path("v2/scalar_int32.zarr"))
  expect_error(
    group_create(store, "g"),
    class = "anndata_not_supported_error"
  )
  expect_error(
    attr_write(store, "a", "b"),
    class = "anndata_not_supported_error"
  )
  expect_error(
    write_dataset(store, "y", 1),
    class = "anndata_not_supported_error"
  )
  expect_error(
    member_delete(store, "x"),
    class = "anndata_not_supported_error"
  )
})

test_that("Python reads every kind of array R wrote", {
  # The acceptance criterion: same values, dtype and shape in Python
  skip_if_no_python()
  store <- local_zarr_store()
  write_dataset(store, "float64", c(1.5, 2, 3))
  write_dataset(store, "matrix", matrix(c(1, 2, 3, 4, 5, 6), 2, 3))
  write_dataset(store, "int32", matrix(1:6, 2, 3))
  write_dataset(store, "float32", set_dtype(c(0.5, 2), "float32"))
  write_dataset(store, "uint8", set_dtype(c(0, 255), "uint8"))
  write_dataset(store, "int64", set_dtype(c(-2^40, 2^40, 3), "int64"))
  write_dataset(store, "uint64", set_dtype(c(0, 2^40 + 1), "uint64"))
  write_dataset(store, "uint32", set_dtype(c(0, 2^32 - 1), "uint32"))
  write_dataset(store, "int32_min", set_dtype(c(-2^31, 1), "int32"))
  write_dataset(store, "scalar", 2.5, scalar = TRUE)
  write_dataset(store, "scalar_int64", set_dtype(-2^40, "int64"), scalar = TRUE)
  write_bool_dataset(store, "bool", c(TRUE, FALSE, TRUE), FALSE, NULL)
  write_bool_dataset(store, "bool_scalar", TRUE, TRUE, NULL)
  write_complex_dataset(
    store,
    "complex",
    complex(real = 1:2, imaginary = 3:4),
    FALSE,
    NULL
  )
  write_complex_dataset(store, "complex_scalar", 1i, TRUE, NULL)
  write_string_dataset(store, "strings", c("a", "", non_ascii), FALSE, NULL)
  write_string_dataset(
    store,
    "strings_2d",
    matrix(c("a", "b", "c", "d", "e", "f"), 2),
    FALSE,
    NULL
  )
  write_string_dataset(store, "string_scalar", non_ascii, TRUE, NULL)
  write_dataset(store, "empty", matrix(numeric(), 0, 3))
  null_write(store, "null")
  group <- group_create(store, "group")
  attr_write(group, "encoding-type", "dict")
  attr_write(group, "shape", c(3, 4), dtype = "int64", scalar = FALSE)
  attr_write(group, "flag", TRUE)

  seen <- python_describe(store)
  # `flat` is the values in numpy's (row-major) order, as nested JSON lists
  # flatten
  check <- function(path, dtype, shape, flat) {
    node <- seen[[path]]
    expect_identical(node$kind, "array", label = path)
    expect_identical(node$dtype, dtype, label = path)
    expect_equal(as.numeric(unlist(node$shape)), shape, label = path)
    expect_equal(unlist(node$value) %||% numeric(), flat, label = path)
  }
  check("/float64", "float64", 3, c(1.5, 2, 3))
  check("/matrix", "float64", c(2, 3), c(1, 3, 5, 2, 4, 6))
  check("/int32", "int32", c(2, 3), c(1, 3, 5, 2, 4, 6))
  check("/float32", "float32", 2, c(0.5, 2))
  check("/uint8", "uint8", 2, c(0, 255))
  check("/int64", "int64", 3, c(-2^40, 2^40, 3))
  check("/uint64", "uint64", 2, c(0, 2^40 + 1))
  check("/uint32", "uint32", 2, c(0, 2^32 - 1))
  check("/int32_min", "int32", 2, c(-2^31, 1))
  check("/scalar", "float64", numeric(), 2.5)
  check("/scalar_int64", "int64", numeric(), -2^40)
  check("/bool", "bool", 3, c(TRUE, FALSE, TRUE))
  check("/bool_scalar", "bool", numeric(), TRUE)
  check("/complex", "complex128", 2, c(1, 3, 2, 4))
  check("/complex_scalar", "complex128", numeric(), c(0, 1))
  check("/strings", "StringDType()", 3, c("a", "", non_ascii))
  check(
    "/strings_2d",
    "StringDType()",
    c(2, 3),
    c("a", "c", "e", "b", "d", "f")
  )
  check("/string_scalar", "StringDType()", numeric(), non_ascii)
  check("/empty", "float64", c(0, 3), numeric())
  check("/null", "bool", numeric(), FALSE)
  expect_identical(seen[["/group"]]$kind, "group")
  expect_identical(seen[["/group"]]$attrs$`encoding-type`, "dict")
  expect_identical(seen[["/group"]]$attrs$shape, list(3L, 4L))
  expect_true(seen[["/group"]]$attrs$flag)
})

test_that("consolidated metadata is written inline and Python opens it", {
  # Python writes consolidated metadata after all Elements, so R must too
  skip_if_no_python()
  store <- local_zarr_store()
  group <- group_create(store, "g")
  attr_write(group, "encoding-type", "dict")
  write_dataset(group, "x", c(1, 2, 3))
  zarr_consolidate(store$root)
  root_meta <- jsonlite::fromJSON(
    file.path(store$root, "zarr.json"),
    simplifyVector = FALSE
  )
  expect_identical(root_meta$consolidated_metadata$kind, "inline")
  expect_true(all(
    c("g", "g/x") %in% names(root_meta$consolidated_metadata$metadata)
  ))
  expect_equal(
    unlist(python_describe(store)[["/g/x"]]$value),
    c(1, 2, 3)
  )
  # The store still reads without relying on the consolidated metadata
  expect_identical(array_read(store, "/g/x"), c(1, 2, 3))
})

test_that("the chunk bytes of strings and scalars are the Python layout", {
  # The vlen-utf8 format is a count, then a length and the bytes of each value
  expect_identical(
    zarr_vlen_encode(c("ab", "", "c")),
    as.raw(c(
      3,
      0,
      0,
      0,
      2,
      0,
      0,
      0,
      0x61,
      0x62,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0x63
    ))
  )
  expect_identical(zarr_vlen_encode(character()), as.raw(c(0, 0, 0, 0)))
  expect_identical(zarr_encode_values(-1, "int64"), as.raw(rep(255, 8)))
  expect_identical(
    zarr_encode_values(2^32 + 1, "uint64"),
    as.raw(c(1, 0, 0, 0, 1, 0, 0, 0))
  )
  expect_identical(zarr_encode_values(-2^31, "int32"), as.raw(c(0, 0, 0, 128)))
  expect_identical(zarr_encode_values(c(TRUE, FALSE), "bool"), as.raw(1:0))
  # The compressed bytes are a zstd frame, which starts with a magic number
  expect_identical(
    zarr_zstd(as.raw(0:3))[1:4],
    as.raw(c(0x28, 0xb5, 0x2f, 0xfd))
  )
})
