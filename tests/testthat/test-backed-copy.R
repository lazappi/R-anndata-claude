# The 25 x 3 float32 dense X of the table's `settings` section, in backed mode
local_copy_source <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  path <- file.path(dir, "orig.h5ad")
  x <- set_dtype(matrix(as.numeric(0:74), nrow = 25, byrow = TRUE), "float32")
  write_h5ad(AnnData(x), path)
  adata <- read_h5ad(path, backed = "r")
  withr::defer(adata$file$close(), envir = env)
  list(adata = adata, path = path, dir = dir, x = x)
}

# The 1-based rows and columns of a Python `slice(start, stop, step)` string
table_slice <- function(text) {
  parts <- strsplit(gsub("^slice\\(|\\)$", "", text), ", ")[[1L]]
  c(as.integer(parts[[1L]]) + 1L, as.integer(parts[[2L]]))
}

# The selections that writing `adata` reads from X, as rows (and columns) ranges
copied_selections <- function(adata, new, ...) {
  reads <- list()
  real_read <- array_read
  local_mocked_bindings(
    array_read = function(store, path, selection = NULL, call) {
      if (identical(path, "/X")) {
        reads[[length(reads) + 1L]] <<- selection
      }
      real_read(store, path, selection, call)
    }
  )
  write_h5ad(adata, new, ...)
  reads
}

# Python copies a backed dense X in runs of at least the setting's rows
# (table section `settings`, `slices`)
test_that("a backed dense X is copied in runs of the setting's rows", {
  table <- backed_cases()$settings$slices
  # A function per case, because a setting made in a loop leaks to later turns
  check_setting <- function(setting) {
    case <- local_copy_source()
    local_anndata_settings(list(min_rows_for_chunked_h5_copy = setting))
    new <- file.path(case$dir, "new.h5ad")
    reads <- copied_selections(case$adata, new)
    expected <- lapply(table[[paste0("setting_", setting)]], table_slice)
    got <- lapply(reads, function(selection) range(selection[[1L]]))
    expect_equal(got, lapply(expected, as.integer), info = setting)
    # Every block reads all columns
    expect_true(all(vapply(reads, function(s) is.null(s[[2L]]), logical(1))))
    expect_equal(
      unname(as.matrix(drop_dtype(read_h5ad(new)$X))),
      unname(case$x),
      ignore_attr = TRUE
    )
  }
  for (setting in c(1, 7, 10, 25, 26, 1000)) {
    check_setting(setting)
  }
})

# A compressed destination is chunked, and Python copies it chunk by chunk
# (row `gzip_destination`)
test_that("a compressed destination is copied in the chunks it has", {
  case <- local_copy_source()
  new <- file.path(case$dir, "new.h5ad")
  reads <- copied_selections(case$adata, new, compression = "gzip")
  expected <- backed_cases()$settings$slices$gzip_destination[[1L]]
  expect_length(reads, 1L)
  expect_equal(
    c(range(reads[[1L]][[1L]]), range(reads[[1L]][[2L]])),
    c(table_slice(expected[[1L]]), table_slice(expected[[2L]]))
  )
  expect_equal(
    unname(as.matrix(drop_dtype(read_h5ad(new)$X))),
    unname(case$x),
    ignore_attr = TRUE
  )
})

# The block layout itself, for chunked sources and destinations that the table
# covers with h5py (rows `chunked_source_*`)
test_that("blocks follow the source chunks and the destination chunks", {
  table <- backed_cases()$settings$slices
  rows <- function(blocks) lapply(blocks, function(b) range(b$rows))
  # A chunked source raises the run length to its chunk length
  expect_equal(
    rows(backed_copy_blocks(c(25L, 3L), c(5L, 3L), NULL, 3L)),
    lapply(table$chunked_source_5_setting_3, function(s) table_slice(s))
  )
  expect_equal(
    rows(backed_copy_blocks(c(25L, 3L), c(10L, 3L), NULL, 20L)),
    lapply(table$chunked_source_10_setting_20, function(s) table_slice(s))
  )
  # Destination chunks tile both dimensions, the last ones clipped
  blocks <- backed_copy_blocks(c(5L, 3L), NULL, c(2L, 2L), 1000L)
  expect_length(blocks, 6L)
  expect_equal(blocks[[2L]]$cols, 3L)
  expect_equal(blocks[[6L]]$rows, 5L)
  # No rows, no blocks
  expect_length(backed_copy_blocks(c(0L, 3L), NULL, NULL, 1000L), 0L)
})

# A source written with compression is chunked, a plain one is not
test_that("the chunk shape of a backed source is read from the file", {
  plain <- local_copy_source()
  expect_null(backed_source_chunks(plain$adata$X))
  dir <- withr::local_tempdir()
  path <- file.path(dir, "gz.h5ad")
  write_h5ad(AnnData(plain$x), path, compression = "gzip")
  chunked <- read_h5ad(path, backed = "r")
  withr::defer(chunked$file$close())
  expect_type(backed_source_chunks(chunked$X), "integer")
  expect_length(backed_source_chunks(chunked$X), 2L)
})

# Python's setting is a positive integer (table `settings$invalid`)
test_that("min_rows_for_chunked_h5_copy rejects what Python rejects", {
  withr::defer(anndata_settings$reset())
  for (value in list(0, -1, 1.5, "a", NA_integer_, c(1, 2))) {
    expect_anndata_condition(
      anndata_settings$min_rows_for_chunked_h5_copy <- value,
      "anndata_invalid_setting_error"
    )
  }
  expect_equal(
    anndata_settings$min_rows_for_chunked_h5_copy,
    backed_cases()$settings$default
  )
})

# Bool X has its own type and write path, so copy it in blocks as well
test_that("a backed bool X is copied in blocks and keeps its type", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "bool.h5ad")
  x <- matrix(rep(c(TRUE, FALSE, TRUE), 10), nrow = 10, ncol = 3)
  write_h5ad(AnnData(x), path)
  adata <- read_h5ad(path, backed = "r")
  withr::defer(adata$file$close())
  local_anndata_settings(list(min_rows_for_chunked_h5_copy = 4))
  new <- file.path(dir, "new.h5ad")
  write_h5ad(adata, new)
  expect_equal(unname(as.matrix(read_h5ad(new)$X)), x, ignore_attr = TRUE)
  expect_all_equivalent(new, python_rewrite_h5ad(path))
})
