# Why: every read_mtx row of the table must give Python's CSR X, dtype, shape
# and names, or the error, for coordinate and array files of every field
test_that("read_mtx() matches the table", {
  rows <- Filter(
    function(r) identical(r$reader, "read_mtx"),
    other_formats_table()$readers
  )
  expect_gte(length(rows), 11L)
  for (row in rows) {
    args <- c(
      list(fixture_path(file.path("other_formats", row$source$file))),
      row$args
    )
    if (!is.null(row$error)) {
      expect_error(
        do.call(read_mtx, args),
        class = "anndata_file_not_found_error",
        info = row$name
      )
      next
    }
    adata <- do.call(read_mtx, args)
    x <- row$result$X
    expect_s4_class(adata$X, "RsparseMatrix")
    expect_identical(dim(adata$X), as.integer(unlist(x$shape)), info = row$name)
    expect_equal(
      unname(as.matrix(drop_dtype(adata$X))),
      do.call(rbind, lapply(x$values, unlist)),
      info = row$name
    )
    expect_identical(
      get_dtype(adata$X) %||% native_dtype(adata$X),
      x$dtype,
      info = row$name
    )
    expect_identical(adata$obs_names, unlist(row$result$obs_names))
    expect_identical(adata$var_names, unlist(row$result$var_names))
  }
})

# Why: scipy expands symmetric files, skips comments and reads compressed
# files, which the table does not all cover (skew-symmetric, array symmetric)
test_that("read_mtx() handles symmetry, array layouts and bad input", {
  read_lines <- function(lines, ...) {
    path <- withr::local_tempfile(fileext = ".mtx")
    writeLines(lines, path)
    read_mtx(path, ...)
  }
  skew <- read_lines(c(
    "%%MatrixMarket matrix coordinate real skew-symmetric",
    "2 2 1",
    "2 1 3"
  ))
  expect_equal(
    unname(as.matrix(drop_dtype(skew$X))),
    matrix(c(0, 3, -3, 0), 2)
  )
  sym_array <- read_lines(c(
    "%%MatrixMarket matrix array real symmetric",
    "2 2",
    "1",
    "2",
    "3"
  ))
  expect_equal(
    unname(as.matrix(drop_dtype(sym_array$X))),
    matrix(c(1, 2, 2, 3), 2)
  )
  # duplicate entries are summed before the cast, as scipy does
  dup <- read_lines(
    c(
      "%%MatrixMarket matrix coordinate real general",
      "1 1 2",
      "1 1 0.6",
      "1 1 0.6"
    ),
    dtype = "int32"
  )
  expect_equal(as.matrix(drop_dtype(dup$X))[[1L]], 1)
  gz <- withr::local_tempfile(fileext = ".mtx.gz")
  con <- gzfile(gz, "wt")
  writeLines(
    c("%%MatrixMarket matrix coordinate real general", "1 1 1", "1 1 4"),
    con
  )
  close(con)
  expect_equal(as.matrix(drop_dtype(read_mtx(gz)$X))[[1L]], 4)
  expect_error(
    read_lines("not matrix market"),
    class = "anndata_invalid_value_error"
  )
  expect_error(
    read_lines("%%MatrixMarket matrix coordinate complex general"),
    class = "anndata_invalid_value_error"
  )
  expect_error(
    read_lines(c(
      "%%MatrixMarket matrix coordinate real general",
      "1 1 2",
      "1 1 4"
    )),
    class = "anndata_invalid_value_error"
  )
  expect_error(
    read_lines(c(
      "%%MatrixMarket matrix coordinate real general",
      "1 1 1",
      "1 1 x"
    )),
    class = "anndata_invalid_value_error"
  )
  path <- fixture_path("other_formats/coordinate_real.mtx")
  expect_error(read_mtx(path, dtype = "float16"), class = "anndata_error")
  expect_error(read_mtx(1L), class = "anndata_error")
})
