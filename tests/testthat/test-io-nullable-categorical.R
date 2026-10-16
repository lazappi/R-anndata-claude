# A factor as R holds one read from Python, with the categories record kept for
# categories that are not strings
make_factor <- function(values, levels, ordered = FALSE, categories = NULL) {
  out <- factor(values, levels = levels, ordered = ordered)
  if (!is.null(categories)) {
    attr(out, "anndata_categories") <- categories
  }
  out
}

numbered_factor <- function(n) {
  levels <- paste0("c", seq_len(n) - 1L)
  make_factor(c(levels[[1L]], levels[[2L]], levels[[n]]), levels)
}

# Expected R values for the nullable and categorical fixtures, named by the
# fixture case (an Element at the key `x` of `<case>.h5`)
nullable_categorical_values <- function() {
  levels3 <- c("c0", "c1", "c2")
  list(
    nullable_int64 = set_nullable(set_dtype(c(1, NA, 3), "int64")),
    nullable_int8 = set_nullable(set_dtype(c(1L, NA, 3L), "int8")),
    nullable_uint16 = set_nullable(set_dtype(c(1L, NA, 3L), "uint16")),
    nullable_int32_nomissing = set_nullable(1:3),
    nullable_int_empty = set_nullable(integer(0)),
    nullable_bool = set_nullable(c(TRUE, NA, FALSE)),
    nullable_bool_nomissing = set_nullable(c(TRUE, FALSE)),
    nullable_str = set_nullable(c("a", NA, "bé", ""), "NaN"),
    nullable_str_nomissing = set_nullable(c("a", "bé", ""), "NaN"),
    nullable_str_pdna = set_nullable(c("a", NA, "日本"), "NA"),
    # Python writes a plain string-array with the setting off
    nullable_str_allow_nullable_false = c("a", "bé", ""),
    categorical = make_factor(levels3, levels3),
    categorical_ordered = make_factor(levels3, levels3, ordered = TRUE),
    categorical_missing = make_factor(c("c0", NA, "c2"), levels3),
    categorical_numeric = make_factor(
      c("0", "1", "2"),
      c("0", "1", "2"),
      categories = set_dtype(c(0, 1, 2), "int64")
    ),
    categorical_bool = make_factor(
      c("TRUE", "FALSE", "TRUE"),
      c("FALSE", "TRUE"),
      categories = c(FALSE, TRUE)
    ),
    categorical_126 = numbered_factor(126L),
    categorical_127 = numbered_factor(127L),
    categorical_32767 = numbered_factor(32767L),
    categorical_32768 = numbered_factor(32768L),
    categorical_unused = make_factor(
      c("a", "b", "a"),
      c("a", "b", "unused")
    ),
    categorical_one_level = make_factor("a", "a"),
    categorical_empty = make_factor(character(0), c("a", "b")),
    categorical_nonascii = make_factor(
      c("é", "日本", "é"),
      c("é", "日本")
    )
  )
}

# The Encoding type and version of the Element written for `value`
elem_encoding <- function(value) {
  store <- rhdf5::H5Fopen(write_fixture_like(value))
  on.exit(rhdf5::h5closeAll())
  elem <- rhdf5::H5Oopen(store, "x")
  c(
    type = read_elem_attr(elem, "encoding-type"),
    version = read_elem_attr(elem, "encoding-version")
  )
}

# The on-disk dtype of the dataset at `path` in the file written for `value`
written_dtype <- function(value, path) {
  store <- rhdf5::H5Fopen(write_fixture_like(value))
  on.exit(rhdf5::h5closeAll())
  h5_dtype(store, path)
}

# Python -> R: each fixture reads as the value Python holds, including the
# records that bring its Encoding type and dtype back on write
test_that("Python-written nullable and categorical Elements read as expected", {
  expected <- nullable_categorical_values()
  for (name in names(expected)) {
    expect_identical(read_fixture_elem(name), expected[[name]], info = name)
  }
})

# R -> R: every value written reads back identical, so the records are enough
# to restore the Encoding type and dtypes
test_that("nullable and categorical Elements round trip through R", {
  expected <- nullable_categorical_values()
  for (name in names(expected)) {
    value <- expected[[name]]
    expect_identical(
      read_written(write_fixture_like(value)),
      value,
      info = name
    )
  }
})

# Python -> R -> Python: what R writes after reading a fixture has the groups,
# dtypes, attributes and values of the fixture
test_that("R rewrites every nullable and categorical fixture equivalently", {
  skip_if_no_python()
  case_names <- names(nullable_categorical_values())
  written <- character()
  for (name in case_names) {
    written[[name]] <- write_fixture_like(read_fixture_elem(name))
  }
  originals <- fixture_path(file.path("h5ad", paste0(case_names, ".h5")))
  expect_all_equivalent(written, originals)
})

# R -> Python -> R: Python reads what R writes and writes it back unchanged
test_that("Python reads and rewrites nullable and categorical Elements", {
  skip_if_no_python()
  expected <- nullable_categorical_values()
  written <- character()
  for (name in names(expected)) {
    written[[name]] <- write_fixture_like(expected[[name]])
  }
  rewritten <- python_rewrite(written)
  for (i in seq_along(expected)) {
    expect_identical(
      read_written(rewritten[[i]]),
      expected[[i]],
      info = names(expected)[[i]]
    )
  }
})

# New values choose the nullable Element Python would write for them
test_that("integer, logical and character values with NA are nullable", {
  expect_identical(
    elem_encoding(c(1L, NA)),
    c(type = "nullable-integer", version = "0.1.0")
  )
  expect_identical(
    elem_encoding(c(TRUE, NA)),
    c(type = "nullable-boolean", version = "0.1.0")
  )
  expect_identical(
    elem_encoding(c("a", NA)),
    c(type = "nullable-string-array", version = "0.1.0")
  )
  # A length-1 NA is still an array, since Python has no missing scalar
  expect_identical(
    drop_dtype(read_written(write_fixture_like(NA_integer_))),
    NA_integer_
  )
  # Without NA the plain Elements are written, as Python writes numpy arrays
  expect_identical(elem_encoding(1:2)[["type"]], "array")
  expect_identical(elem_encoding(c(TRUE, FALSE))[["type"]], "array")
  expect_identical(elem_encoding(c("a", "b"))[["type"]], "string-array")
  # Doubles have no nullable encoding, NA is a NaN
  expect_identical(elem_encoding(c(1, NA))[["type"]], "array")
})

# The values under the mask are the filler Python writes
test_that("values written under the mask are zero, FALSE or empty", {
  store <- rhdf5::H5Fopen(write_fixture_like(c(5L, NA)))
  withr::defer(rhdf5::h5closeAll())
  expect_identical(
    drop_dtype(read_elem(store, "x/values")),
    c(5L, 0L)
  )
  expect_identical(read_elem(store, "x/mask"), c(FALSE, TRUE))
})

# NA positions and the default na-value must survive a write from plain R values
test_that("nullable values written from R read back with NA in place", {
  value <- read_written(write_fixture_like(c("a", NA, "c")))
  expect_identical(drop_dtype(value), c("a", NA, "c"))
  expect_identical(get_nullable(value), "NaN")
  value <- read_written(write_fixture_like(c(TRUE, NA)))
  expect_identical(drop_dtype(value), c(TRUE, NA))
})

# The records are invisible, so nullable values behave like plain vectors
test_that("a nullable value computes like a plain vector", {
  value <- read_fixture_elem("nullable_int8")
  expect_identical(sum(value, na.rm = TRUE), 4L)
  expect_identical(is.na(value), c(FALSE, TRUE, FALSE))
})

# The decision for ticket 06: honour the setting as Python does
test_that("allow_write_nullable_strings FALSE writes string-array or raises", {
  local_anndata_settings(list(allow_write_nullable_strings = FALSE))
  # A read nullable string without NA is a plain string-array, as in Python
  expect_identical(
    elem_encoding(read_fixture_elem("nullable_str_nomissing"))[["type"]],
    "string-array"
  )
  expect_identical(
    read_written(write_fixture_like(as_array("a"))),
    as_array("a")
  )
  err <- expect_anndata_condition(
    write_fixture_like(c("a", NA)),
    "anndata_nullable_strings_error"
  )
  expect_identical(err$path, "/x")
  # Python has the same error for the same value (nullable_str_na_*)
  manifest <- jsonlite::read_json(fixture_path("manifest.json"))
  expect_identical(
    manifest$errors$nullable_str_na_allow_nullable_false$type,
    "ValueError"
  )
})

test_that("allow_write_nullable_strings TRUE and NULL write nullable strings", {
  for (setting in list(TRUE, NULL)) {
    local_anndata_settings(list(allow_write_nullable_strings = setting))
    expect_identical(
      elem_encoding(read_fixture_elem("nullable_str_nomissing"))[["type"]],
      "nullable-string-array"
    )
  }
})

# Nullable Elements are 1-d, so a matrix with NA cannot be written
test_that("a matrix with NA raises an io registry error", {
  err <- expect_anndata_condition(
    write_fixture_like(matrix(c(1L, NA, 3L, 4L), 2, 2)),
    "anndata_io_registry_error"
  )
  expect_identical(err$path, "/x")
})

test_that("a nullable record on a float vector is ignored", {
  value <- set_nullable(c(1.5, NA))
  expect_identical(elem_encoding(value)[["type"]], "array")
})

# A mask of another length would give pandas a broken array
test_that("a mask of the wrong length raises", {
  store <- local_h5_store()
  group <- make_encoded_group(store, "x", "nullable-integer", "0.1.0")
  write_elem(group, "values", 1:3)
  write_elem(group, "mask", c(FALSE, TRUE))
  err <- expect_anndata_condition(
    read_elem(store, "x"),
    "anndata_io_registry_error"
  )
  expect_identical(err$path, "/x")
})

# R factors become categorical, with the code dtype pandas picks
test_that("factors are written as categorical with the smallest code dtype", {
  expect_identical(
    elem_encoding(factor(c("a", "b"))),
    c(type = "categorical", version = "0.2.0")
  )
  small <- numbered_factor(126L)
  expect_identical(written_dtype(small, "/x/codes"), "int8")
  expect_identical(written_dtype(numbered_factor(127L), "/x/codes"), "int16")
  expect_identical(written_dtype(numbered_factor(32766L), "/x/codes"), "int16")
  expect_identical(written_dtype(numbered_factor(32767L), "/x/codes"), "int32")
  # The dtype is chosen from the levels, whatever dtype the file had
  expect_identical(
    written_dtype(factor("a", levels = c("a", "b")), "/x/codes"),
    "int8"
  )
})

test_that("factor NA is code -1 and ordered sets the attribute", {
  store <- rhdf5::H5Fopen(
    write_fixture_like(factor(c("b", NA, "a"), ordered = TRUE))
  )
  withr::defer(rhdf5::h5closeAll())
  expect_identical(drop_dtype(read_elem(store, "x/codes")), c(1L, -1L, 0L))
  elem <- rhdf5::H5Oopen(store, "x")
  expect_identical(read_elem_attr(elem, "ordered"), "TRUE")
  value <- read_elem(store, "x")
  expect_s3_class(value, "ordered")
  expect_identical(as.character(value), c("b", NA, "a"))
})

# A length-1 codes or categories vector would be a scalar without as_array()
test_that("a factor of length 1 or 0 is written as arrays", {
  one <- factor("a")
  expect_identical(read_written(write_fixture_like(one)), one)
  none <- factor(character(0), levels = "a")
  expect_identical(read_written(write_fixture_like(none)), none)
})

# Categories that are not strings are written back with their dtype, but only
# while the levels still match them
test_that("non-string categories are restored only while levels match", {
  value <- read_fixture_elem("categorical_numeric")
  expect_identical(
    written_dtype(value, "/x/categories"),
    "int64"
  )
  levels(value) <- c("a", "b", "c")
  expect_null(attr(
    read_written(write_fixture_like(value)),
    "anndata_categories"
  ))
  expect_identical(
    levels(read_written(write_fixture_like(value))),
    c("a", "b", "c")
  )
})

# Python raises for these, so R must not build an invalid factor
test_that("categorical with bad codes or duplicate categories raises", {
  store <- local_h5_store()
  group <- make_encoded_group(store, "x", "categorical", "0.2.0")
  write_elem(group, "codes", 5:5)
  write_elem(group, "categories", as_array("a"))
  err <- expect_anndata_condition(
    read_elem(store, "x"),
    "anndata_io_registry_error"
  )
  expect_identical(err$path, "/x")

  group <- make_encoded_group(store, "y", "categorical", "0.2.0")
  write_elem(group, "codes", 0:1)
  write_elem(group, "categories", c("a", "a"))
  err <- expect_anndata_condition(
    read_elem(store, "y"),
    "anndata_io_registry_error"
  )
  expect_identical(err$path, "/y")
})

# Float categories become levels, with 100000 not in scientific notation, and
# are written back as float64
test_that("float categories read as strings with a record", {
  store <- local_h5_store()
  group <- make_encoded_group(store, "x", "categorical", "0.2.0")
  write_elem(group, "codes", c(0L, 1L))
  write_elem(group, "categories", c(1.5, 100000))
  value <- read_elem(store, "x")
  expect_identical(levels(value), c("1.5", "100000"))
  expect_identical(attr(value, "anndata_categories"), c(1.5, 100000))
  expect_identical(written_dtype(value, "/x/categories"), "float64")
  expect_identical(
    attr(read_written(write_fixture_like(value)), "anndata_categories"),
    c(1.5, 100000)
  )
})
