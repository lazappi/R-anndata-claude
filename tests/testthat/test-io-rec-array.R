# Field dtypes are not kept (ADR 0005), so these are the R values rhdf5 gives
# for each fixture, with the marker class
rec <- function(...) new_rec_array(data.frame(..., check.names = FALSE))

rec_array_cases <- function() {
  list(
    rec_array_basic = rec(
      i = 1:2,
      f = c(1.5, 2.5),
      fixed = c("ab", "c"),
      uni = c("x", "yé")
    ),
    rec_array_widths = rec(
      u1 = c(1L, 255L),
      i2 = c(-2L, 7L),
      u4 = c(3, 4e9),
      i8 = c(4, -9),
      f4 = c(0.5, 1.5),
      b = c(TRUE, FALSE)
    ),
    rec_array_rank_genes_groups = rec(
      `0` = c("g1", "g2"),
      `1` = c("g3", "g4")
    ),
    rec_array_object_field = rec(o = c("a", "bé"), f = c(1, 2))
  )
}

# Fixtures with non-ASCII text, which anndata cannot read back once R has
# written it as a fixed-length string
rec_array_non_ascii <- c("rec_array_basic", "rec_array_object_field")

# The cases R can write: the ASCII fixtures plus one built in R
rec_array_writable <- function() {
  cases <- rec_array_cases()[setdiff(
    names(rec_array_cases()),
    rec_array_non_ascii
  )]
  cases$ascii_basic <- rec(
    i = 1:2,
    f = c(1.5, 2.5),
    fixed = c("ab", "c"),
    uni = c("x", "y")
  )
  cases
}

# What R reads back after writing: int32, float64 and strings only, so logical
# fields come back as integer
rec_array_written <- function(name) {
  value <- rec_array_writable()[[name]]
  if (name == "rec_array_widths") {
    value$b <- as.integer(value$b)
  }
  value
}

# Python -> R: rec-arrays read as data frames keeping field names, order and
# values, including 64-bit and unsigned fields that do not fit an R integer
test_that("Python-written rec-arrays read as the expected R values", {
  for (name in names(rec_array_cases())) {
    expect_identical(
      read_fixture_elem(name),
      rec_array_cases()[[name]],
      info = name
    )
  }
})

# R -> R: the values (not the dtypes) must survive a write and read
test_that("rec-arrays round trip through R", {
  for (name in names(rec_array_writable())) {
    expect_identical(
      read_written(write_fixture_like(rec_array_writable()[[name]])),
      rec_array_written(name),
      info = name
    )
  }
})

# Python -> R -> Python: the file is equivalent except for rec-array field
# dtypes (ADR 0005), and Python sees the same field values
test_that("R rewrites the ASCII rec-array fixtures with the same values", {
  skip_if_no_python()
  for (name in setdiff(names(rec_array_cases()), rec_array_non_ascii)) {
    original <- fixture_path(file.path("h5ad", paste0(name, ".h5")))
    written <- write_fixture_like(read_fixture_elem(name))
    expect_structurally_equivalent(written, original, rec_array_paths = "/x")
    expect_rec_array_values_equal(written, original)
  }
})

# The relaxation of structural equivalence must only cover the dtype of the
# named datasets, so a rec-array with different values must still be reported
test_that("the rec-array relaxation still reports different values", {
  skip_if_no_python()
  a <- write_fixture_like(rec_array_writable()$ascii_basic)
  b <- write_fixture_like(rec(
    i = 1:2,
    f = c(1.5, 9),
    fixed = c("ab", "c"),
    uni = c("x", "y")
  ))
  expect_failure(expect_rec_array_values_equal(a, b))
})

# R -> Python -> R: Python reads and rewrites what R writes with the same field
# values, and R reads the rewrite as the same rec-array
test_that("Python reads and rewrites the rec-arrays R writes", {
  skip_if_no_python()
  for (name in names(rec_array_writable())) {
    written <- write_fixture_like(rec_array_writable()[[name]])
    rewritten <- withr::local_tempfile(fileext = ".h5")
    run_python("rewrite.py", written, rewritten)
    expect_rec_array_values_equal(written, rewritten)
    expect_identical(
      read_written(rewritten),
      rec_array_written(name),
      info = name
    )
  }
})

# Python's Element for a rec-array is a dataset, not a group
test_that("a rec-array is written as a compound dataset with rec-array 0.2.0", {
  path <- write_fixture_like(rec_array_writable()$ascii_basic)
  store <- rhdf5::H5Fopen(path, flags = "H5F_ACC_RDONLY")
  withr::defer(rhdf5::h5closeAll())
  elem <- rhdf5::H5Oopen(store, "x")
  expect_identical(read_elem_attr(elem, "encoding-type"), "rec-array")
  expect_identical(read_elem_attr(elem, "encoding-version"), "0.2.0")
  expect_identical(rhdf5::H5Iget_type(elem), "H5I_DATASET")
  expect_false(rhdf5::H5Aexists(elem, "rhdf5-NA.OK"))
})

# anndata decodes fixed-length strings as ASCII and fails on anything else, so
# R must refuse to write a file Python cannot read (the two non-ASCII fixtures
# still read fine, see the first test)
test_that("non-ASCII text in a field raises on write", {
  for (name in rec_array_non_ascii) {
    err <- expect_anndata_condition(
      write_fixture_like(read_fixture_elem(name)),
      "anndata_io_registry_error"
    )
    expect_identical(err$path, "/x", info = name)
  }
})

# Logical, raw and factor fields have no rhdf5 compound type of their own
test_that("logical, raw and factor fields are written as int32 and strings", {
  value <- rec(
    l = c(TRUE, FALSE),
    r = as.raw(c(1, 255)),
    f = factor(c("u", "v"))
  )
  expect_identical(
    read_written(write_fixture_like(value)),
    rec(l = 1:0, r = c(1L, 255L), f = c("u", "v"))
  )
})

# A 64-bit field that a double cannot hold exactly must raise with the path
# and never round
test_that("an int64 field of 2^53 or more raises on read", {
  err <- expect_anndata_condition(
    read_fixture_elem("rec_array_int64_big"),
    "anndata_dtype_overflow_error"
  )
  expect_identical(err$path, "/x")
})

# Python's structured arrays have no missing integers or strings
test_that("missing values in integer and string fields raise on write", {
  for (value in list(
    rec(i = c(1L, NA)),
    rec(s = c("a", NA))
  )) {
    err <- expect_anndata_condition(
      write_fixture_like(value),
      "anndata_io_registry_error"
    )
    expect_identical(err$path, "/x")
  }
})

# NA and NaN in a double field are both written as NaN, as for arrays
test_that("NA in a double field is written as NaN", {
  read <- read_written(write_fixture_like(rec(f = c(1, NA))))
  expect_true(is.nan(read$f[[2L]]))
})

# rhdf5 cannot write an empty compound or a field type it does not know
test_that("empty and unsupported rec-arrays raise on write", {
  bad <- list(
    no_rows = rec(i = integer()),
    no_fields = new_rec_array(data.frame(row.names = 1:2)),
    complex_field = rec(z = 1i),
    duplicate_fields = new_rec_array(
      structure(
        list(1, 2),
        names = c("a", "a"),
        row.names = 1L,
        class = "data.frame"
      )
    )
  )
  for (name in names(bad)) {
    err <- expect_anndata_condition(
      write_fixture_like(bad[[name]]),
      "anndata_io_registry_error"
    )
    expect_identical(err$path, "/x", info = name)
  }
})

# A rec-array inside uns-like dicts is how scanpy stores rank_genes_groups
test_that("a rec-array inside a dict round trips", {
  value <- list(
    names = rec_array_cases()$rec_array_rank_genes_groups,
    params = list(groupby = "g")
  )
  expect_identical(read_written(write_fixture_like(value)), value)
})

# `new_rec_array()` only wraps data frames
test_that("new_rec_array rejects other values", {
  expect_anndata_condition(new_rec_array(1:3), "anndata_invalid_value_error")
})
