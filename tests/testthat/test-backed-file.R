backed_kinds <- c("dense", "csr", "csc")
backed_modes <- c("r", "r+")

# The table row of an operation for one kind of X and one mode
backed_row <- function(operation, kind, mode, table = "operations") {
  backed_cases()[[table]][[operation]][[kind]][[mode]]
}

# Python's record of the object's state after an operation, which R mirrors
expect_backed_state <- function(adata, state) {
  expect_equal(adata$isbacked, state$isbacked)
  expect_equal(basename(adata$filename %||% ""), state$filename %||% "")
  expect_equal(adata$file$is_open, state$file_is_open)
  expect_equal(adata$file$filemode, state$file_mode)
}

# The 4 x 3 matrix the table's files hold, from a list of rows
table_matrix <- function(rows) {
  do.call(rbind, lapply(rows, unlist))
}

# Runs `code(case)` for every kind of X and mode, with the table row of
# `operation` and the backed object, to check R against each row
for_each_backed <- function(operation, code, ..., table = "operations") {
  for (kind in backed_kinds) {
    for (mode in backed_modes) {
      case <- local_backed(kind, mode, ...)
      row <- backed_row(operation, kind, mode, table)
      code(case, row, kind)
    }
  }
}

# Reading X gives a handle on the file and not the values, and the object is
# backed with the file open in the mode requested (rows read_X, layers_none,
# X_handle and metadata)
test_that("a backed object keeps X on disk and the file open", {
  for_each_backed("read_X", function(case, row, kind) {
    adata <- case$adata
    x <- adata$X
    expect_s3_class(x, "backed_x")
    expect_equal(dim(x), unlist(row$result$shape))
    expect_equal(x$dtype, "float32")
    expect_equal(
      x$encoding,
      c(dense = "array", csr = "csr_matrix", csc = "csc_matrix")[[kind]]
    )
    expect_identical(adata$layers[[NA]], x)
    expect_backed_state(adata, row$state_after)
  })
  for_each_backed("metadata", function(case, row, kind) {
    adata <- case$adata
    expect_true(adata$isbacked)
    expect_equal(adata$filename, case$path)
    expect_equal(adata$file$filename, case$path)
    expect_equal(adata$shape, unlist(row$result$shape))
    expect_true(NA_character_ %in% adata$layers$keys())
  })
})

# Python reads the other Slots into memory in backed mode, layers included
# (rows layers_other and close_then_layers_other)
test_that("layers other than X are read into memory", {
  for_each_backed("layers_other", function(case, row, kind) {
    layer <- case$adata$layers[["l"]]
    expect_false(inherits(layer, "backed_x"))
    expect_equal(
      unname(as.matrix(drop_dtype(layer))),
      table_matrix(row$result$value)
    )
    expect_backed_state(case$adata, row$state_after)
  })
  for_each_backed("close_then_layers_other", function(case, row, kind) {
    case$adata$file$close()
    layer <- case$adata$layers[["l"]]
    expect_equal(
      unname(as.matrix(drop_dtype(layer))),
      table_matrix(row$result$value$value)
    )
    # Slots in memory do not open the file
    expect_backed_state(case$adata, row$state_after)
  })
})

# raw$X stays on disk too (row read_raw_X, run on a file with raw), and a file
# without raw gives NULL
test_that("raw X stays on disk", {
  for_each_backed("read_raw_X", function(case, row, kind) {
    expect_null(case$adata$raw)
    expect_null(row$result)
  })
  for (kind in backed_kinds) {
    case <- local_backed(kind, "r", raw = TRUE)
    row <- backed_row("read_raw_X", kind, "r", "raw_operations")
    raw_x <- case$adata$raw$X
    expect_s3_class(raw_x, "backed_x")
    # The table has no raw X for dense (Python's file has no raw there), the
    # shape is the 4 x 3 of the source
    expect_equal(dim(raw_x), c(4L, 3L))
    expect_equal(raw_x$dtype, "float32")
    expect_equal(raw_x$path, "/raw/X")
    expect_equal(case$adata$X$path, "/X")
    expect_backed_state(case$adata, row$state_after)
  }
})

# print() adds `backed at '<file>'` and lists X first (rows repr and
# close_then_repr), and printing never opens the file
test_that("a backed object prints its file", {
  for_each_backed("repr", function(case, row, kind) {
    expected <- gsub("<dir>", case$dir, row$result$repr, fixed = TRUE)
    expect_equal(format(case$adata), expected)
    expect_output(print(case$adata), expected, fixed = TRUE)
    expect_equal(
      case$adata$file$format(),
      gsub("<dir>", case$dir, row$result$file_repr, fixed = TRUE)
    )
  })
  for_each_backed("close_then_repr", function(case, row, kind) {
    case$adata$file$close()
    expected <- gsub("<dir>", case$dir, row$result$repr, fixed = TRUE)
    expect_equal(format(case$adata), expected)
    expect_false(case$adata$file$is_open)
  })
})

# Closing keeps the object backed and the file name, reading X reopens the file
# and reading anything else does not (rows close_then_X, close_then_obs,
# close_then_shape, close_then_layers_none and close_twice)
test_that("close() keeps the object backed and reading X reopens the file", {
  for_each_backed("close_then_X", function(case, row, kind) {
    case$adata$file$close()
    expect_false(case$adata$file$is_open)
    expect_s3_class(case$adata$X, "backed_x")
    expect_backed_state(case$adata, row$state_after)
  })
  for_each_backed("close_then_layers_none", function(case, row, kind) {
    case$adata$file$close()
    expect_s3_class(case$adata$layers[[NA]], "backed_x")
    expect_backed_state(case$adata, row$state_after)
  })
  for_each_backed("close_then_obs", function(case, row, kind) {
    case$adata$file$close()
    expect_equal(rownames(case$adata$obs), unlist(row$result$value$value$index))
    expect_backed_state(case$adata, row$state_after)
  })
  for_each_backed("close_then_shape", function(case, row, kind) {
    case$adata$file$close()
    expect_equal(case$adata$shape, unlist(row$result$value$value))
    expect_backed_state(case$adata, row$state_after)
  })
  for_each_backed("close_twice", function(case, row, kind) {
    case$adata$file$close()
    expect_no_error(case$adata$file$close())
    expect_backed_state(case$adata, row$state_after)
  })
  for (kind in backed_kinds) {
    case <- local_backed(kind, "r", raw = TRUE)
    row <- backed_row("close_then_raw_X", kind, "r", "raw_operations")
    case$adata$file$close()
    expect_s3_class(case$adata$raw$X, "backed_x")
    expect_backed_state(case$adata, row$state_after)
  }
})

# Sparse handles print like Python's CSRDataset repr (the table's read_X row)
# and a dense one names its shape and dtype
test_that("backed_x prints its encoding, shape and dtype", {
  for (kind in backed_kinds) {
    case <- local_backed(kind, "r")
    x <- case$adata$X
    expect_output(print(x), format(x), fixed = TRUE)
    if (kind == "csr") {
      row <- backed_row("read_X", "csr", "r")
      expect_equal(format(x), row$result$repr)
    } else if (kind == "csc") {
      expect_equal(
        format(x),
        "CSCDataset: backend hdf5, shape (4, 3), data_dtype float32"
      )
    } else {
      expect_equal(format(x), "Backed dense array, shape (4, 3), dtype float32")
    }
  }
})

# The handle is released by close() and by garbage collection: HDF5 refuses a
# read-write open of a file this process still holds read-only
test_that("the file is released by close() and by garbage collection", {
  case <- local_backed("dense", "r")
  expect_false(file_is_free(case$path))
  case$adata$file$close()
  expect_true(file_is_free(case$path))

  dir <- withr::local_tempdir()
  path <- file.path(dir, "gc.h5ad")
  write_h5ad(backed_source("csr"), path)
  adata <- read_h5ad(path, backed = "r")
  expect_false(file_is_free(path))
  rm(adata)
  gc()
  expect_true(file_is_free(path))
})

# open() mirrors Python's open(): a new mode or file, an error for a bad mode
# and for a missing file, with the state Python leaves behind (rows file_open,
# file_open_other, file_open_bad_mode and file_open_missing)
test_that("file$open() reopens, changes the mode and rejects bad input", {
  for_each_backed("file_open", function(case, row, kind) {
    case$adata$file$open()
    expect_backed_state(case$adata, row$state_after)
  })
  for_each_backed("file_open_other", function(case, row, kind) {
    case$adata$file$close()
    case$adata$file$open(case$path, "r+")
    expect_equal(case$adata$file$filemode, row$result$mode)
    expect_backed_state(case$adata, row$state_after)
  })
  for_each_backed("file_open_bad_mode", function(case, row, kind) {
    expect_error(
      case$adata$file$open(case$path, "q"),
      class = "anndata_invalid_argument_error"
    )
    expect_backed_state(case$adata, row$state_after)
  })
  for_each_backed("file_open_missing", function(case, row, kind) {
    expect_error(
      case$adata$file$open(file.path(case$dir, "missing.h5ad"), "r"),
      class = "anndata_file_not_found_error"
    )
    expect_backed_state(case$adata, row$state_after)
  })
})

# The mode decides whether the file can be written: "r" opens read-only and
# "r+" read-write (rows file_setitem, file_delitem, file_contains, file_iter,
# file_getitem and file_getitem_missing)
test_that("file members can be read in both modes and written only in r+", {
  for_each_backed("file_iter", function(case, row, kind) {
    expect_equal(case$adata$file$keys(), unlist(row$result))
  })
  for_each_backed("file_contains", function(case, row, kind) {
    expect_equal(case$adata$file$has("X"), row$result$X)
    expect_equal(case$adata$file$has("nope"), row$result$nope)
  })
  for_each_backed("file_getitem", function(case, row, kind) {
    node <- case$adata$file$get("X")
    on.exit(node_close(node))
    expect_equal(
      read_elem_attr(node, "encoding-type"),
      c(dense = "array", csr = "csr_matrix", csc = "csc_matrix")[[kind]]
    )
  })
  for_each_backed("file_getitem_missing", function(case, row, kind) {
    expect_error(case$adata$file$get("nope"), class = "anndata_key_error")
  })
  for_each_backed("file_setitem", function(case, row, kind) {
    if (is.null(row$error)) {
      case$adata$file$set("extra", as.numeric(0:2))
      expect_true("extra" %in% case$adata$file$keys())
    } else {
      expect_error(
        case$adata$file$set("extra", as.numeric(0:2)),
        class = "anndata_read_only_error"
      )
    }
  })
  for_each_backed("file_delitem", function(case, row, kind) {
    if (is.null(row$error)) {
      case$adata$file$remove("layers")
      expect_false("layers" %in% case$adata$file$keys())
    } else {
      expect_error(
        case$adata$file$remove("layers"),
        class = "anndata_read_only_error"
      )
      expect_true("layers" %in% case$adata$file$keys())
    }
  })
})

# An in-memory object has a manager with no file (the in_memory section of the
# table), and its file operations fail without a file
test_that("an in-memory object has an empty file manager", {
  adata <- AnnData(matrix(0, 2, 2))
  expect_false(adata$isbacked)
  expect_null(adata$filename)
  expect_false(adata$file$is_open)
  expect_equal(adata$file$format(), "Backing file manager: no file is set.")
  expect_no_error(adata$file$close())
  expect_error(adata$file$open(), class = "anndata_invalid_argument_error")
  expect_error(adata$file$has("X"), class = "anndata_invalid_argument_error")
  expect_false(grepl("backed", format(adata), fixed = TRUE))
  expect_error(adata$file <- NULL, class = "anndata_read_only_error")
})

# read_h5ad(backed = ) takes the values in the read_h5ad section of the table,
# ignores as_sparse and refuses the rest like Python's assertion
test_that("read_h5ad() accepts the backed values Python does", {
  table <- backed_cases()$read_h5ad
  dir <- withr::local_tempdir()
  path <- file.path(dir, "file.h5ad")
  write_h5ad(backed_source("csr"), path)
  accepted <- list(
    true = TRUE,
    r = "r",
    `r+` = "r+",
    false = FALSE,
    none = NULL,
    zero = 0
  )
  for (label in names(accepted)) {
    row <- table[[label]]
    adata <- read_h5ad(path, backed = accepted[[label]])
    expect_equal(adata$isbacked, row$result$state$isbacked, info = label)
    expect_equal(adata$file$filemode, row$result$state$file_mode, info = label)
    expect_equal(
      adata$file$is_open,
      row$result$state$file_is_open,
      info = label
    )
    expect_equal(inherits(adata$X, "backed_x"), adata$isbacked, info = label)
    adata$file$close()
  }
  rejected <- list(
    a = "a",
    w = "w",
    rb = "rb",
    upper_R = "R",
    empty = "",
    one = 1
  )
  for (label in names(rejected)) {
    expect_equal(table[[label]]$error$type, "AssertionError")
    expect_error(
      read_h5ad(path, backed = rejected[[label]]),
      class = "anndata_invalid_argument_error",
      info = label
    )
  }
  expect_error(
    read_h5ad(file.path(dir, "missing.h5ad"), backed = "r"),
    class = "anndata_file_not_found_error"
  )
  adata <- read_h5ad(path, backed = "r", as_sparse = "X")
  expect_true(adata$isbacked)
  expect_equal(adata$X$encoding, "csr_matrix")
  adata$file$close()
})

# A read that fails must not leave the file open
test_that("a failed backed read closes the file", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "legacy.h5ad")
  rhdf5::h5createFile(path)
  expect_error(
    read_h5ad(path, backed = "r"),
    class = "anndata_legacy_format_error"
  )
  expect_true(file_is_free(path))
})
