# What a file holds, as the table records it (`disk()` in backed_cases.py)
read_written_x <- function(path) {
  as.matrix(drop_dtype(read_h5ad(path)$X))
}

# X as a plain matrix with no dtype record
plain_x <- function(x) unname(as.matrix(drop_dtype(as.matrix(x))))

expect_written_like <- function(path, written) {
  adata <- read_h5ad(path)
  expect_equal(unname(read_written_x(path)), table_matrix(written$X$value))
  expect_equal(rownames(adata$obs), unlist(written$obs_names))
  keys <- names(adata$layers)
  expect_equal(keys[!is.na(keys)], setdiff(unlist(written$layers), "None"))
  expect_equal(adata$shape, unlist(written$shape))
}

# Writing a backed object to a new file copies X from disk, leaves the original
# file alone and points the object at the new file, closed (rows write_new,
# write_h5ad_new and write_h5ad_new_closed)
test_that("writing a backed object to a new file backs it by that file", {
  for (operation in c("write_new", "write_h5ad_new", "write_h5ad_new_closed")) {
    for_each_backed(operation, function(case, row, kind) {
      adata <- case$adata
      if (operation == "write_h5ad_new_closed") {
        adata$file$close()
      }
      new <- file.path(case$dir, "new.h5ad")
      if (operation == "write_h5ad_new") {
        write_h5ad(adata, new)
        # The function leaves the object backed by the original file
        expect_equal(adata$filename, case$path)
      } else {
        adata$write(new)
        expect_backed_state(adata, row$state_after)
        expect_equal(adata$filename, new)
      }
      expect_written_like(new, row$current_after)
      # The object reads X from the new file afterwards
      expect_equal(
        plain_x(adata$X),
        table_matrix(row$current_after$X$value)
      )
    })
  }
})

# Without a filename the backing file is updated in place and X, which is on
# disk already, is kept (rows write_no_arg and write_same)
test_that("writing a backed object to its own file updates it in place", {
  for (operation in c("write_no_arg", "write_same")) {
    for_each_backed(operation, function(case, row, kind) {
      adata <- case$adata
      adata$obs$g <- c("c", "c", "d", "d")
      if (operation == "write_no_arg") {
        adata$write()
      } else {
        adata$write(case$path)
      }
      expect_backed_state(adata, row$state_after)
      expect_equal(row$original_changed, TRUE)
      expect_written_like(case$path, row$original_after)
      expect_equal(
        as.character(read_h5ad(case$path)$obs$g),
        c("c", "c", "d", "d")
      )
      expect_equal(
        plain_x(adata$X),
        table_matrix(row$original_after$X$value)
      )
    })
  }
})

# A sparse X written as dense is replaced in place (row write_as_dense)
test_that("as_dense turns a backed sparse X into a dense dataset", {
  for_each_backed("write_as_dense", function(case, row, kind) {
    new <- file.path(case$dir, "new.h5ad")
    case$adata$write(new, as_dense = "X")
    expect_true(row$result$X_is_dataset)
    x <- read_h5ad(new)$X
    expect_false(methods::is(x, "sparseMatrix"))
    expect_equal(
      unname(as.matrix(drop_dtype(x))),
      unname(as.matrix(
        drop_dtype(read_h5ad(case$path)$X)
      ))
    )
  })
})

# A backed object has no filename to write to when it is in memory
test_that("write() needs a filename for an object in memory", {
  expect_anndata_condition(
    backed_source("dense")$write(),
    class = "anndata_invalid_argument_error"
  )
})

# A View of a backed object writes its subset and stays as it was (row
# view_write_new), and cannot overwrite the file that backs it
test_that("a View of a backed object writes its subset", {
  for_each_backed("view_write_new", function(case, row, kind) {
    view <- case$adata[c(1, 3), c(1, 3)]
    new <- file.path(case$dir, "view.h5ad")
    view$write(new)
    expect_written_like(new, row$result$written)
    expect_backed_state(case$adata, row$state_after)
    expect_anndata_condition(
      view$write(case$path),
      class = "anndata_invalid_argument_error"
    )
  })
})

# Python needs a filename to copy a backed object, then writes it and reads the
# copy in the same mode (rows copy, copy_filename, copy_filename_closed,
# copy_same_path and copy_twice)
test_that("copy() of a backed object writes a backed copy", {
  for_each_backed("copy", function(case, row, kind) {
    expect_anndata_condition(
      case$adata$copy(),
      class = "anndata_invalid_argument_error"
    )
  })
  for (operation in c("copy_filename", "copy_filename_closed")) {
    for_each_backed(operation, function(case, row, kind) {
      if (operation == "copy_filename_closed") {
        case$adata$file$close()
      }
      path <- file.path(case$dir, "copy.h5ad")
      copy <- case$adata$copy(path)
      withr::defer(copy$file$close())
      expect_backed_state(copy, row$result$copy)
      expect_equal(copy$filename, path)
      expect_s3_class(copy$X, "backed_x")
      expect_written_like(path, row$result$file)
      # The original is closed by the write, as in Python
      expect_backed_state(case$adata, row$state_after)
    })
  }
  for_each_backed("copy_same_path", function(case, row, kind) {
    copy <- case$adata$copy(case$path)
    withr::defer(copy$file$close())
    expect_backed_state(copy, row$result$summary)
    expect_equal(
      plain_x(copy$X),
      table_matrix(row$original_after$X$value)
    )
  })
  for_each_backed("copy_twice", function(case, row, kind) {
    path <- file.path(case$dir, "copy.h5ad")
    first <- case$adata$copy(path)
    withr::defer(first$file$close())
    # Python overwrites the first copy's open file in "r+" mode and fails in
    # "r" mode, rhdf5 cannot truncate an open file in either (see ticket)
    expect_error(case$adata$copy(path))
  })
})

# to_memory() reads X, and raw X, into memory and leaves the original backed
# (rows to_memory, to_memory_copy and to_memory_closed)
test_that("to_memory() loads a backed object and leaves it backed", {
  for (operation in c("to_memory", "to_memory_copy", "to_memory_closed")) {
    for_each_backed(operation, function(case, row, kind) {
      if (operation == "to_memory_closed") {
        case$adata$file$close()
      }
      memory <- case$adata$to_memory(copy = operation == "to_memory_copy")
      expect_backed_state(memory, row$result$memory)
      expect_false(inherits(memory$X, "backed_x"))
      expect_equal(
        unname(as.matrix(drop_dtype(memory$X))),
        table_matrix(row$result$X$value)
      )
      expect_true(case$adata$isbacked)
      expect_backed_state(case$adata, row$state_after)
    })
  }
})

# A View of a backed object loads only its subset (rows view_to_memory and
# view_to_memory_copy)
test_that("to_memory() of a View of a backed object loads its subset", {
  for (operation in c("view_to_memory", "view_to_memory_copy")) {
    for_each_backed(operation, function(case, row, kind) {
      memory <- case$adata[c(1, 3), c(1, 3)]$to_memory()
      expect_backed_state(memory, row$result$memory)
      expect_equal(plain_x(memory$X), table_matrix(row$result$X$value))
      expect_true(case$adata$isbacked)
    })
  }
})

# Compression options reach the datasets written from a backed source (rows
# write_gzip and write_lzf), and a missing directory is an error that leaves
# the object backed by its own file (row write_h5ad_missing_dir)
test_that("backed objects write with compression and fail on a bad path", {
  for (compression in c("gzip", "lzf")) {
    for_each_backed(paste0("write_", compression), function(case, row, kind) {
      new <- file.path(case$dir, "new.h5ad")
      case$adata$write(new, compression = compression)
      expect_written_like(new, row$current_after)
    })
  }
  for_each_backed("write_h5ad_missing_dir", function(case, row, kind) {
    expect_error(case$adata$write(file.path(case$dir, "nodir", "x.h5ad")))
    expect_equal(case$adata$filename, case$path)
  })
})

# as_dense also applies when a backed sparse X is updated in place (the branch
# of write_h5ad_in_place that replaces X), and a backed raw cannot be written
# in place because its X would be deleted before it is read (Python fails there
# too, rows raw_operations write_no_arg)
test_that("in-place writes handle as_dense and backed raw", {
  for (kind in c("csr", "csc")) {
    case <- local_backed(kind, "r+")
    case$adata$write(as_dense = "X")
    expect_false(methods::is(read_h5ad(case$path)$X, "sparseMatrix"))
    expect_equal(
      plain_x(read_h5ad(case$path)$X),
      table_matrix(
        backed_row("write_as_dense", kind, "r+")$current_after$X$value
      )
    )
  }
  case <- local_backed("dense", "r+", raw = TRUE)
  expect_anndata_condition(
    case$adata$write(),
    class = "anndata_not_supported_error"
  )
})

# Raw X is read into memory by to_memory() (row to_memory on a file with raw)
test_that("to_memory() loads raw X", {
  for (kind in backed_kinds) {
    case <- local_backed(kind, "r", raw = TRUE)
    memory <- case$adata$to_memory()
    expect_false(inherits(memory$raw$X, "backed_x"))
    expect_equal(dim(memory$raw$X), c(4L, 3L))
    expect_s3_class(case$adata$raw$X, "backed_x")
  }
})

# Files written from backed objects are Structurally equivalent to what Python
# writes for the same object
test_that("a backed object is written as Python writes it", {
  mine <- character()
  originals <- character()
  for (kind in backed_kinds) {
    case <- local_backed(kind, "r")
    new <- file.path(case$dir, "new.h5ad")
    case$adata$write(new)
    mine <- c(mine, new)
    originals <- c(originals, case$path)
  }
  expect_all_equivalent(mine, python_rewrite_h5ad(originals))
})
