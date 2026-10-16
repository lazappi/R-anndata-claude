# Expected R values for every dict fixture (an Element at the key `x`), members
# in the alphabetical order h5py lists them
mapping_cases <- function() {
  list(
    dict_nested = list(
      a = c(1, 2),
      n = set_dtype(3, "int64"),
      s = "str",
      sub = list(flag = TRUE, names = c("x", "y"))
    ),
    dict_empty = stats::setNames(list(), character()),
    dict_with_null = list(nothing = NULL, x = 1)
  )
}

# Python -> R: dicts read as named lists, keeping nested dicts, empty dicts and
# null members (which `[[<-` would silently drop)
test_that("Python-written dicts read as the expected R values", {
  for (name in names(mapping_cases())) {
    expect_identical(
      read_fixture_elem(name),
      mapping_cases()[[name]],
      info = name
    )
  }
})

# R -> R: reading and writing must keep names, nesting, NULL and dtype records
test_that("dicts round trip through R", {
  for (name in names(mapping_cases())) {
    value <- mapping_cases()[[name]]
    expect_identical(
      read_written(write_fixture_like(value)),
      value,
      info = name
    )
  }
})

# Python -> R -> Python: R must write the same groups, members and attributes
test_that("R rewrites every dict fixture structurally equivalent to Python", {
  skip_if_no_python()
  for (name in names(mapping_cases())) {
    original <- fixture_path(file.path("h5ad", paste0(name, ".h5")))
    value <- read_fixture_elem(name)
    expect_structurally_equivalent(write_fixture_like(value), original)
  }
})

# R -> Python -> R: Python reads and rewrites what R writes, and R reads that
# back as the same list
test_that("Python reads and rewrites the dicts R writes", {
  skip_if_no_python()
  for (name in names(mapping_cases())) {
    value <- mapping_cases()[[name]]
    rewritten <- withr::local_tempfile(fileext = ".h5")
    run_python("rewrite.py", write_fixture_like(value), rewritten)
    expect_identical(read_written(rewritten), value, info = name)
  }
})

# Python writes a dict as a group with Encoding attributes
test_that("a dict is written as a group with dict 0.1.0", {
  path <- write_fixture_like(list(a = 1))
  store <- rhdf5::H5Fopen(path, flags = "H5F_ACC_RDONLY")
  withr::defer(rhdf5::h5closeAll())
  elem <- rhdf5::H5Oopen(store, "x")
  expect_identical(read_elem_attr(elem, "encoding-type"), "dict")
  expect_identical(read_elem_attr(elem, "encoding-version"), "0.1.0")
  expect_identical(rhdf5::H5Iget_type(elem), "H5I_GROUP")
})

# A dict cannot hold unnamed members, so these must fail with the path rather
# than lose or rename data
test_that("lists without complete unique names raise on write", {
  bad <- list(
    unnamed = list(1, 2),
    partly_named = list(a = 1, 2),
    empty_name = stats::setNames(list(1, 2), c("a", "")),
    na_name = stats::setNames(list(1, 2), c("a", NA)),
    duplicated = stats::setNames(list(1, 2), c("a", "a"))
  )
  for (name in names(bad)) {
    err <- expect_anndata_condition(
      write_fixture_like(bad[[name]]),
      "anndata_io_registry_error"
    )
    expect_identical(err$path, "/x", info = name)
  }
})

# The error path must be that of the nested member, not the top level
test_that("a bad nested list reports the nested path", {
  err <- expect_anndata_condition(
    write_fixture_like(list(sub = list(1, 2))),
    "anndata_io_registry_error"
  )
  expect_identical(err$path, "/x/sub")
})

# A classed list (here a data.frame stand-in) must not be written as a dict
test_that("a classed list is not written as a dict", {
  value <- structure(list(a = 1), class = "something_else")
  err <- expect_anndata_condition(
    write_fixture_like(value),
    "anndata_io_registry_error"
  )
  expect_identical(err$path, "/x")
})

# Values that have no encoding inside a dict still raise with their own path
test_that("an unencodable member raises with its path", {
  err <- expect_anndata_condition(
    write_fixture_like(list(f = function() 1)),
    "anndata_io_registry_error"
  )
  expect_identical(err$path, "/x/f")
})

# Writing to the root replaces its members, as Python does for `write_elem(f,
# "/", {...})`
test_that("a dict can be written to the root", {
  store <- local_h5_store()
  write_elem(store, "/", list(a = 1, b = list(c = "z")))
  expect_identical(
    read_elem(store, "/"),
    list(a = 1, b = list(c = "z"))
  )
})
