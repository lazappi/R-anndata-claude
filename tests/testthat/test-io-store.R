test_that("selections read the same values as subsetting the whole array", {
  # Selections are for backed and lazy reading, they must match numpy's x[i, j]
  store <- local_h5_store()
  matrix <- matrix(as.double(1:12), 3, 4)
  write_dataset(store, "num", matrix)
  write_bool_dataset(store, "bool", matrix > 4, FALSE, rlang::current_env())
  write_string_dataset(
    store,
    "str",
    matrix(as.character(1:12), 3, 4),
    FALSE,
    rlang::current_env()
  )
  write_dataset(store, "vec", as.double(1:10))

  for (name in c("num", "bool", "str")) {
    whole <- array_read(store, paste0("/", name))
    part <- array_read(store, paste0("/", name), list(c(1, 3), c(2, 4)))
    expect_equal(
      as.vector(part),
      as.vector(whole[c(1, 3), c(2, 4)]),
      info = name
    )
    expect_equal(dim(part), c(2L, 2L), info = name)
    rows <- array_read(store, paste0("/", name), list(2L, NULL))
    expect_equal(as.vector(rows), as.vector(whole[2L, ]), info = name)
  }
  expect_equal(
    as.vector(array_read(store, "/vec", list(c(2, 5)))),
    c(2, 5)
  )
  expect_equal(
    as.vector(array_read(store, "/vec", list(NULL))),
    as.double(1:10)
  )
})

test_that("invalid selections are rejected", {
  # HDF5 hyperslabs need increasing indices, and a wrong rank must not crash
  store <- local_h5_store()
  write_dataset(store, "m", matrix(as.double(1:12), 3, 4))
  expect_anndata_condition(
    array_read(store, "/m", list(c(3, 1), NULL)),
    "anndata_invalid_value_error"
  )
  expect_anndata_condition(
    array_read(store, "/m", list(1L)),
    "anndata_invalid_value_error"
  )
  # Out of range and repeated indices must not reach HDF5
  expect_anndata_condition(
    array_read(store, "/m", list(4L, NULL)),
    "anndata_invalid_value_error"
  )
  expect_anndata_condition(
    array_read(store, "/m", list(c(1, 1), NULL)),
    "anndata_invalid_value_error"
  )
})

test_that("a selection of complex values is subset in R", {
  # Compounds are read whole and subset in R, which must match numpy
  store <- local_h5_store()
  x <- matrix(complex(real = 1:6, imaginary = 6:1), 2, 3)
  write_complex_dataset(store, "c", x, FALSE, rlang::current_env())
  expect_equal(
    array_read(store, "/c", list(2L, c(1, 3))),
    x[2L, c(1, 3), drop = FALSE]
  )
})

test_that("a selection reads 64-bit values with their dtype record", {
  # The selection must go through the same dtype handling as a whole read
  store <- local_h5_store()
  write_dataset(store, "i", set_dtype(c(1, 2, 3), "int64"))
  part <- array_read(store, "/i", list(2:3))
  expect_equal(get_dtype(part), "int64")
  expect_equal(as.vector(drop_dtype(part)), c(2, 3))
})

test_that("attributes round trip through the store layer", {
  # The encodings write strings, string arrays, logicals and int64 arrays
  store <- local_h5_store()
  group <- group_create(store, "g")
  withr::defer(node_close(group))
  attr_write(group, "s", "text")
  attr_write(group, "arr", c("a", "b"), scalar = FALSE)
  attr_write(group, "none", character(), scalar = FALSE)
  attr_write(group, "flag", TRUE)
  attr_write(group, "shape", c(3, 4), dtype = "int64")

  expect_true(attr_exists(group, "s"))
  expect_false(attr_exists(group, "missing"))
  expect_equal(as.character(attr_read(group, "s")), "text")
  expect_equal(as.character(attr_read(group, "arr")), c("a", "b"))
  expect_equal(attr_read(group, "none"), character())
  expect_equal(read_elem_attr(group, "flag"), "TRUE")
  expect_equal(read_elem_attr(group, "missing"), "")
  expect_equal(as.vector(attr_read(group, "shape")), c(3, 4))
})

test_that("groups, members and paths work through the store layer", {
  # write_elem() and the readers rely on these for every encoding
  store <- local_h5_store()
  expect_true(is_store_file(store))
  group <- group_create(store, "g")
  withr::defer(node_close(group))
  expect_false(is_store_file(group))
  expect_equal(node_path(group), "/g")
  expect_equal(elem_path(group, "x"), "/g/x")
  expect_equal(elem_path(store, "x"), "/x")
  group_create(group, "a") |> node_close()
  group_create(group, "b") |> node_close()
  expect_equal(group_members(group), c("a", "b"))
  expect_true(member_exists(group, "a"))
  member_delete(group, "a")
  expect_false(member_exists(group, "a"))
})

test_that("an object that is not a store is rejected", {
  # The error names the class so that a wrong handle is easy to spot
  expect_anndata_condition(
    node_path("x"),
    class = "anndata_invalid_value_error"
  )
})
