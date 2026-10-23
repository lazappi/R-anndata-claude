# Field dtypes are kept (ADR 0008), so these are the R values and On-disk dtype
# records read for each fixture, with the marker class
rec <- function(...) new_rec_array(data.frame(..., check.names = FALSE))

rec_array_cases <- function() {
  list(
    rec_array_basic = rec(
      i = 1:2,
      f = c(1.5, 2.5),
      fixed = set_dtype(c("ab", "c"), "h5_fixed_ascii:3"),
      uni = c("x", "yé")
    ),
    rec_array_widths = rec(
      u1 = set_dtype(c(1L, 255L), "uint8"),
      i2 = set_dtype(c(-2L, 7L), "int16"),
      u4 = set_dtype(c(3, 4e9), "uint32"),
      i8 = set_dtype(c(4, -9), "int64"),
      f4 = set_dtype(c(0.5, 1.5), "float32"),
      b = c(TRUE, FALSE)
    ),
    rec_array_rank_genes_groups = rec(
      `0` = c("g1", "g2"),
      `1` = c("g3", "g4")
    ),
    rec_array_object_field = rec(o = c("a", "bé"), f = c(1, 2))
  )
}

# Python -> R: rec-arrays read as data frames keeping field names, order,
# values and the field dtypes, including 64-bit and unsigned fields that do not
# fit an R integer
test_that("Python-written rec-arrays read as the expected R values", {
  for (name in names(rec_array_cases())) {
    expect_identical(
      read_fixture_elem(name),
      rec_array_cases()[[name]],
      info = name
    )
  }
})

# R -> R: values and dtypes survive a write and read, for every fixture
test_that("rec-arrays round trip through R", {
  for (name in names(rec_array_cases())) {
    expect_identical(
      read_written(write_fixture_like(rec_array_cases()[[name]])),
      rec_array_cases()[[name]],
      info = name
    )
  }
})

# Python -> R -> Python: the whole file is structurally equivalent with no
# exemption, including field dtypes, and Python sees the same field values
test_that("R rewrites the rec-array fixtures with identical structure", {
  skip_if_no_python()
  case_names <- names(rec_array_cases())
  written <- character()
  for (name in case_names) {
    written[[name]] <- write_fixture_like(read_fixture_elem(name))
  }
  originals <- fixture_path(file.path("h5ad", paste0(case_names, ".h5")))
  expect_all_equivalent(written, originals)
  for (i in seq_along(written)) {
    expect_rec_array_values_equal(written[[i]], originals[[i]])
  }
})

# The relaxation of structural equivalence must only cover the dtype of the
# named datasets, so a rec-array with different values must still be reported
test_that("the rec-array relaxation still reports different values", {
  skip_if_no_python()
  a <- write_fixture_like(rec(i = 1:2, f = c(1.5, 2.5)))
  b <- write_fixture_like(rec(i = 1:2, f = c(1.5, 9)))
  expect_failure(expect_rec_array_values_equal(a, b))
})

# R -> Python -> R: Python reads and rewrites what R writes (default fields,
# widened fixed strings and records), and R reads the rewrite as the same
test_that("Python reads and rewrites the rec-arrays R writes", {
  skip_if_no_python()
  cases <- c(
    rec_array_cases(),
    list(
      plain = rec(
        i = 1:2,
        f = c(1.5, 2.5),
        s = c("x", "yé"),
        b = c(TRUE, FALSE)
      ),
      wide = rec(
        a = set_dtype(c("ab", "c"), "h5_fixed_ascii:6"),
        u = set_dtype(c("e", "b"), "h5_fixed_utf8:4"),
        v = set_dtype(c("p", "q"), "h5_vlen_ascii")
      )
    )
  )
  written <- character()
  for (name in names(cases)) {
    written[[name]] <- write_fixture_like(cases[[name]])
  }
  rewritten <- python_rewrite(written)
  # Python's rewrite changes string field types, so the records are dropped
  plain <- function(x) {
    x[] <- lapply(x, drop_dtype)
    x
  }
  for (i in seq_along(cases)) {
    expect_rec_array_values_equal(written[[i]], rewritten[[i]])
    expect_identical(
      plain(read_written(rewritten[[i]])),
      plain(read_written(written[[i]])),
      info = names(cases)[[i]]
    )
  }
})

# Python's Element for a rec-array is a dataset, not a group
test_that("a rec-array is written as a compound dataset with rec-array 0.2.0", {
  path <- write_fixture_like(rec_array_cases()$rec_array_widths)
  store <- rhdf5::H5Fopen(path, flags = "H5F_ACC_RDONLY")
  withr::defer(rhdf5::h5closeAll())
  elem <- rhdf5::H5Oopen(store, "x")
  expect_identical(read_elem_attr(elem, "encoding-type"), "rec-array")
  expect_identical(read_elem_attr(elem, "encoding-version"), "0.2.0")
  expect_identical(rhdf5::H5Iget_type(elem), "H5I_DATASET")
  expect_false(rhdf5::H5Aexists(elem, "rhdf5-NA.OK"))
})

# Fields without a record are written as h5py writes text and numbers, so
# Python reads non-ASCII text (a fixed-length ASCII field it could not decode)
test_that("fields without a record are int32, float64, bool and vlen UTF-8", {
  path <- write_fixture_like(rec(
    i = 1:2,
    f = c(1.5, 2.5),
    b = c(TRUE, FALSE),
    s = c("a", "bé")
  ))
  members <- compound_members(path, "/x")
  expect_equal(members$class, c("integer", "float", "enum", "string"))
  expect_equal(members$size[1:2], c(4L, 8L))
  expect_true(members$variable[[4]])
  expect_true(members$utf8[[4]])
})

# A recorded width is widened, and non-ASCII text becomes variable-length
# UTF-8, rather than writing a file Python cannot read
test_that("string records are widened or made variable-length UTF-8", {
  value <- rec(
    a = set_dtype(c("abcdef", "c"), "h5_fixed_ascii:2"),
    b = set_dtype(c("é", "x"), "h5_fixed_ascii:1"),
    v = set_dtype(c("é", "x"), "h5_vlen_ascii")
  )
  path <- write_fixture_like(value)
  members <- compound_members(path, "/x")
  expect_equal(members$size[[1]], 6L)
  expect_equal(members$utf8, c(FALSE, TRUE, TRUE))
  expect_equal(members$variable, c(FALSE, TRUE, TRUE))
  expect_identical(
    drop_dtype(read_written(path)$b),
    c("é", "x")
  )
})

# Records of zarr are not HDF5 types and are ignored on write
test_that("a zarr string record is ignored by the HDF5 writer", {
  value <- rec(s = set_dtype(c("a", "b"), "fixed_length_utf32:12"))
  members <- compound_members(write_fixture_like(value), "/x")
  expect_true(members$variable[[1]])
})

# Logical and raw fields keep their kind, a factor is its strings
test_that("logical, raw and factor fields are written as bool, int32, string", {
  value <- rec(
    l = c(TRUE, FALSE),
    r = as.raw(c(1, 255)),
    f = factor(c("u", "v"))
  )
  expect_identical(
    read_written(write_fixture_like(value)),
    rec(l = c(TRUE, FALSE), r = c(1L, 255L), f = c("u", "v"))
  )
})

# A rec-array with no rows is written with its field types and Python reads it
test_that("a rec-array with no rows round trips", {
  value <- rec(
    i = set_dtype(integer(), "uint16"),
    f = numeric(),
    s = character(),
    b = logical()
  )
  path <- write_fixture_like(value)
  expect_identical(read_written(path), value)
  # Compression with no rows must also give a dataset
  zipped <- withr::local_tempfile(fileext = ".h5")
  rhdf5::h5createFile(zipped)
  store <- rhdf5::H5Fopen(zipped)
  write_elem(store, "x", value, list(compression = "gzip"))
  rhdf5::h5closeAll()
  expect_identical(read_written(zipped), value)
  skip_if_no_python()
  expect_length(python_rewrite(c(path, zipped)), 2L)
})

# `compression = "gzip"` compresses the compound with the level asked for and
# chunks it as h5py would, and the values still round trip
test_that("a rec-array is compressed with gzip", {
  value <- rec_array_cases()$rec_array_widths
  path <- withr::local_tempfile(fileext = ".h5")
  rhdf5::h5createFile(path)
  store <- rhdf5::H5Fopen(path)
  write_elem(
    store,
    "x",
    value,
    list(compression = "gzip", compression_opts = 7L)
  )
  write_elem(store, "y", value)
  write_elem(store, "z", value, list(compression = "lzf"))
  rhdf5::h5closeAll()
  store <- rhdf5::H5Fopen(path, flags = "H5F_ACC_RDONLY")
  withr::defer(rhdf5::h5closeAll())
  filters <- function(name) {
    dset <- rhdf5::H5Dopen(store, name)
    on.exit(rhdf5::H5Dclose(dset))
    plist <- rhdf5::H5Dget_create_plist(dset)
    on.exit(rhdf5::H5Pclose(plist), add = TRUE, after = FALSE)
    rhdf5::H5Pget_nfilters(plist)
  }
  expect_equal(filters("x"), 1L)
  expect_equal(filters("y"), 0L)
  # lzf is unavailable to the compound helper, so it is written uncompressed
  expect_equal(filters("z"), 0L)
  expect_identical(read_elem(store, "x"), value)
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

# A recorded dtype that cannot hold the values must raise rather than wrap
test_that("a value outside a recorded integer dtype raises on write", {
  expect_anndata_condition(
    write_fixture_like(rec(i = set_dtype(c(1L, 300L), "uint8"))),
    "anndata_dtype_overflow_error"
  )
})

# NA and NaN in a double field are both written as NaN, as for arrays
test_that("NA in a double field is written as NaN", {
  read <- read_written(write_fixture_like(rec(f = c(1, NA))))
  expect_true(is.nan(read$f[[2L]]))
})

# A field-less rec-array and a field type with no compound member raise
test_that("empty and unsupported rec-arrays raise on write", {
  bad <- list(
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
