backed_cases <- function() {
  jsonlite::fromJSON(fixture_path("backed_cases.json"), simplifyVector = FALSE)
}

# Guards the committed backed operations table against drifting from Python
test_that("the committed backed operations table matches Python", {
  skip_if_no_python()
  fresh <- withr::local_tempfile(fileext = ".json")
  run_python("backed_cases.py", fresh)
  expect_equal(readLines(fresh), readLines(fixture_path("backed_cases.json")))
})

# The table must keep covering every operation the backed spec lists, so later
# tickets can test each row against its R equivalent
test_that("the backed operations table covers the operations in the spec", {
  cases <- backed_cases()
  expected <- c(
    # reading and slicing X
    "read_X",
    "X_row",
    "X_slices",
    "X_rows_list",
    "X_rows_bool",
    "X_unsorted_rows",
    "X_out_of_range_row",
    "read_raw_X",
    "layers_none",
    # Views of backed objects
    "view",
    "view_of_view",
    "view_X_assign",
    "view_copy",
    "view_write_new",
    # assigning X
    "X_assign_dense",
    "X_assign_csr",
    "X_assign_small",
    "X_assign_none",
    "X_item",
    # moving data
    "to_memory",
    "to_memory_copy",
    "copy",
    "copy_filename",
    "write_no_arg",
    "write_new",
    "write_h5ad_new",
    "filename_same",
    "filename_none",
    "filename_new",
    # chunks
    "chunked_X_3",
    "chunked_X_zero",
    "chunk_X_list",
    "chunk_X_int",
    "chunk_X_none",
    # the file manager and printing
    "close_then_X",
    "close_then_repr",
    "file_open",
    "file_open_bad_mode",
    "repr"
  )
  expect_in(expected, names(cases$operations))
  for (name in names(cases$operations)) {
    op <- cases$operations[[name]]
    expect_setequal(names(op), c("dense", "csr", "csc"))
    for (kind in names(op)) {
      expect_setequal(names(op[[kind]]), c("r", "r+"))
    }
  }
  # Operations that write to the backing file also run on a file with raw
  expect_in(
    c("write_new", "filename_none", "copy_same_path", "view_write_new"),
    names(cases$raw_operations)
  )
  expect_in(
    c(
      "in_memory",
      "read_h5ad",
      "read_elem_partial",
      "sparse_dataset",
      "settings"
    ),
    names(cases)
  )
})

# Python's surprising results are the reason the table exists, so keep the main
# ones visible: assigning X never writes, and writing with raw damages the file
test_that("the backed operations table records Python's quirks", {
  ops <- backed_cases()$operations
  assigned <- ops$X_assign_dense$dense[["r"]]
  expect_null(assigned$error)
  expect_false(assigned$state_after$isbacked)
  expect_false(assigned$original_changed)
  expect_equal(
    ops$read_X$csr[["r+"]]$result$type,
    "_CSRDataset"
  )
  # a closed file is reopened on access
  expect_true(ops$close_then_X$dense[["r"]]$result$file_is_open)
  expect_equal(
    backed_cases()$raw_operations$write_no_arg$dense[["r"]]$error$type,
    "AttributeError"
  )
  expect_equal(backed_cases()$settings$default, 1000)
})
