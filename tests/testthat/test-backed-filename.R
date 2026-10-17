# The 4 x 3 matrix every backed file starts with (1 to 12 by row)
filename_x <- matrix(as.numeric(1:12), nrow = 4, byrow = TRUE)

# What X holds as a plain matrix, whatever its class
plain_x <- function(x) unname(as.matrix(drop_dtype(as.matrix(x))))

# Setting the same path changes nothing, and NULL on an object in memory too
# (rows filename_same, filename_set_none)
test_that("setting the current filename or NULL in memory is a no-op", {
  for_each_backed("filename_same", function(case, row, kind) {
    case$adata$filename <- case$path
    expect_backed_state(case$adata, row$state_after)
  })
  adata <- backed_source("dense")
  adata$filename <- NULL
  expect_false(adata$isbacked)
  expect_null(adata$filename)
})

# NULL reads X into memory, forgets the file and keeps the mode, twice is fine
# (rows filename_none and filename_none_twice)
test_that("setting filename to NULL ends backed mode", {
  for_each_backed("filename_none", function(case, row, kind) {
    case$adata$filename <- NULL
    expect_backed_state(case$adata, row$state_after)
    expect_equal(plain_x(case$adata$X), filename_x)
    expect_false(inherits(case$adata$X, "backed_x"))
    case$adata$filename <- NULL
    expect_backed_state(case$adata, row$state_after)
  })
})

# A new path moves the file, which is reopened in "r+" mode whatever the mode
# was (rows filename_new and filename_new_closed)
test_that("setting a new filename moves the backing file", {
  for (closed in c(FALSE, TRUE)) {
    operation <- if (closed) "filename_new_closed" else "filename_new"
    for_each_backed(operation, function(case, row, kind) {
      if (closed) {
        case$adata$file$close()
      }
      moved <- file.path(case$dir, "moved.h5ad")
      case$adata$filename <- moved
      expect_backed_state(case$adata, row$state_after)
      expect_true(case$adata$isbacked)
      expect_false(file.exists(case$path))
      expect_equal(plain_x(case$adata$X), filename_x)
      expect_equal(plain_x(read_h5ad(moved)$X), filename_x)
    })
  }
})

# A move to a missing directory fails and leaves the object backed by the
# closed old file (row filename_missing_dir)
test_that("a failed move keeps the old filename", {
  for_each_backed("filename_missing_dir", function(case, row, kind) {
    expect_anndata_condition(
      case$adata$filename <- file.path(case$dir, "nodir", "x.h5ad"),
      class = "anndata_file_not_found_error"
    )
    expect_backed_state(case$adata, row$state_after)
    expect_equal(plain_x(read_h5ad(case$path)$X), filename_x)
  })
})

# After X was assigned there is nothing to write to the old file, so a new
# name fails (row filename_after_X_assign)
test_that("setting a filename after assigning X asks for a filename", {
  for_each_backed("filename_after_X_assign", function(case, row, kind) {
    case$adata$X <- matrix(0, 4, 3)
    expect_anndata_condition(
      case$adata$filename <- file.path(case$dir, "x.h5ad"),
      class = "anndata_invalid_argument_error"
    )
    expect_backed_state(case$adata, row$state_after)
    expect_true(file.exists(case$path))
  })
})

# A View of a backed object cannot be given a filename (row view_filename_set)
test_that("setting a filename on a View of a backed object fails", {
  case <- local_backed("dense", "r+")
  view <- case$adata[c(1, 3), c(1, 3)]
  expect_anndata_condition(
    view$filename <- file.path(case$dir, "v.h5ad"),
    class = "anndata_invalid_argument_error"
  )
})

# An object in memory is written to the file (X dense) and becomes backed in
# "r+" mode, leaving the layers and the source file alone (rows
# filename_set_new and filename_set_new_X_none)
test_that("setting a filename on an object in memory makes it backed", {
  for (kind in backed_kinds) {
    row <- backed_cases()$in_memory[[kind]]$filename_set_new
    case <- local_backed(kind)
    adata <- read_h5ad(case$path)
    path <- file.path(case$dir, "mem.h5ad")
    adata$filename <- path
    withr::defer(adata$file$close())
    expect_backed_state(adata, row$state)
    expect_true(inherits(adata$X, "backed_dense"))
    expect_equal(plain_x(adata$X), filename_x)
    expect_equal(plain_x(adata$layers[["l"]]), filename_x)
    expect_false("l" %in% adata$file$keys())
    expect_true("X" %in% adata$file$keys())
    expect_equal(adata$layers$keys(), c("l", NA))
    expect_equal(plain_x(read_h5ad(case$path)$X), filename_x)
  }
})

# Without X the file has no X and the object is backed with X absent
# (row filename_set_new_X_none)
test_that("setting a filename without X writes a file with no X", {
  case <- local_backed("dense")
  adata <- read_h5ad(case$path)
  adata$X <- NULL
  adata$filename <- file.path(case$dir, "mem.h5ad")
  withr::defer(adata$file$close())
  expect_true(adata$isbacked)
  expect_null(adata$X)
  expect_false(adata$file$has("X"))
})

# filename is settable now, but only to a single path (or NULL)
test_that("filename rejects values that are not a path", {
  adata <- backed_source("dense")
  expect_anndata_condition(
    adata$filename <- 1L,
    class = "anndata_invalid_argument_error"
  )
})

# A failed write leaves the object in memory (row filename_set_missing_dir)
test_that("a failed first write keeps the object in memory", {
  case <- local_backed("dense")
  adata <- read_h5ad(case$path)
  expect_error(
    adata$filename <- file.path(case$dir, "nodir", "x.h5ad")
  )
  expect_false(adata$isbacked)
  expect_null(adata$filename)
})
