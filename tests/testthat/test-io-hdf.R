# Why: every read_hdf row of the table must give Python's X, dtype and names
# (default "0", "1", ... names without the row_names/col_names datasets), or
# the error for an empty or missing key
test_that("read_hdf() matches the table", {
  rows <- Filter(
    function(r) identical(r$reader, "read_hdf"),
    other_formats_table()$readers
  )
  expect_gte(length(rows), 7L)
  for (row in rows) {
    args <- c(
      list(fixture_path(file.path("other_formats", row$source$file))),
      row$args
    )
    if (!is.null(row$error)) {
      expect_error(
        do.call(read_hdf, args),
        class = if (row$args$key == "") {
          "anndata_invalid_value_error"
        } else {
          "anndata_key_error"
        },
        info = row$name
      )
      next
    }
    adata <- do.call(read_hdf, args)
    x <- row$result$X
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

# Why: argument and file checks that are not rows of the table
test_that("read_hdf() rejects bad arguments", {
  path <- fixture_path("other_formats/hdf_names.h5")
  expect_error(read_hdf(path, 1L), class = "anndata_error")
  expect_error(
    read_hdf(file.path(tempdir(), "missing.h5"), "data"),
    class = "anndata_file_not_found_error"
  )
})
