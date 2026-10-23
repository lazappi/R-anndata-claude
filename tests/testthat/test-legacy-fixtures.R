# Guards the committed expectations (and the generator of the fixtures) against
# drifting from what Python 0.13.4 reads
test_that("the committed legacy expectations match Python", {
  expect_generator_current("legacy_cases.py")
})

# Every committed fixture needs a row in the expectation table, and every row
# a fixture, so a ticket cannot test a file Python never read
test_that("the legacy table has one row per fixture", {
  table <- legacy_table()
  h5ad <- list.files(fixture_path("legacy"), pattern = "[.]h5ad$")
  zarr_dir <- withr::local_tempdir()
  utils::untar(fixture_path("legacy-zarr-fixtures.tar.gz"), exdir = zarr_dir)
  zarr <- list.files(zarr_dir, pattern = "[.]zarr$")
  expect_setequal(names(table$fixtures), c(h5ad, zarr))
  expect_identical(table$anndata, "0.13.4")
  for (row in table$fixtures) {
    expect_true(row$status %in% c("ok", "error"))
    expect_true(is.list(row$warnings))
  }
})

# The readable fixtures give the values and legacy warnings recorded in the
# spike (one OldFormatWarning per Element written without encoding metadata)
test_that("the legacy table records the 0.13.4 values and warnings", {
  fixtures <- legacy_table()$fixtures

  old <- fixtures[["0.6.22-dense.h5ad"]]
  expect_identical(old$status, "ok")
  expect_identical(old$values$shape, list(6L, 4L))
  expect_identical(old$values$obs$index_name, "index")
  expect_identical(old$values$obs$columns$cat$categories, list("a", "b", "c"))
  # raw.varm is written by 0.6.22 and read back into raw
  expect_named(old$values$raw$varm, "PCs")
  categories <- vapply(old$warnings, `[[`, character(1), "category")
  # The FutureWarning is the move of uns["neighbors"] to obsp
  expect_setequal(unique(categories), c("OldFormatWarning", "FutureWarning"))
  messages <- vapply(old$warnings, `[[`, character(1), "message")
  expect_true(
    "Element '/X' was written without encoding metadata." %in% messages
  )

  # Sparse X is read as a csr_matrix
  expect_identical(
    fixtures[["0.6.22-sparse.h5ad"]]$values$X$type,
    "csr_matrix"
  )

  # The neighbors move is the only legacy behaviour of 0.10.9
  moved <- fixtures[["0.10.9-neighbors.h5ad"]]
  expect_setequal(names(moved$values$obsp), c("connectivities", "distances"))
  expect_true(all(
    vapply(moved$warnings, `[[`, character(1), "category") == "FutureWarning"
  ))
})

# 0.13.4 cannot read a 0.6.22 zarr store, and the table lists the layouts that
# have no fixture or no expectation
test_that("the legacy table lists the unsupported layouts", {
  table <- legacy_table()
  expect_identical(
    table$fixtures[["0.6.22-dense.zarr"]]$status,
    "error"
  )
  unsupported <- table$unsupported
  expect_gte(length(unsupported), 6L)
  zarr <- Filter(
    function(x) identical(x$fixture, "0.6.22-dense.zarr"),
    unsupported
  )
  expect_length(zarr, 1L)
  expect_match(zarr[[1]]$behaviour$message, "json2", fixed = TRUE)
  for (entry in unsupported) {
    expect_true(nzchar(entry$layout))
    expect_true(nzchar(entry$reason))
  }
})
