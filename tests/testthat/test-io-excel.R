# Why: every read_excel row of the table must give Python's values, names and
# index name, and its error for a missing sheet.
# Python's `object` dtype (text in the first column) has no R equivalent, so
# the dtype is only compared for the rows where Python gives a numeric one
test_that("read_excel() matches the table", {
  skip_if_not_installed("readxl")
  rows <- Filter(
    function(r) identical(r$reader, "read_excel"),
    other_formats_table()$readers
  )
  expect_gte(length(rows), 8L)
  for (row in rows) {
    args <- c(
      list(fixture_path(file.path("other_formats", row$source$file))),
      row$args
    )
    if (!is.null(row$error)) {
      err <- tryCatch(do.call(read_excel, args), error = identity)
      expect_s3_class(err, "anndata_invalid_value_error")
      expect_identical(
        cli::ansi_strip(conditionMessage(err)),
        row$error$message,
        info = row$name
      )
      next
    }
    adata <- do.call(read_excel, args)
    x <- row$result$X
    expect_equal(
      unname(as.matrix(drop_dtype(adata$X))),
      do.call(rbind, lapply(x$values, unlist)),
      info = row$name
    )
    if (x$dtype != "object") {
      expect_identical(
        get_dtype(adata$X) %||% native_dtype(adata$X),
        x$dtype,
        info = row$name
      )
    }
    # names are always strings in R, also when Python keeps integers
    expect_identical(
      adata$obs_names,
      as.character(unlist(row$result$obs_names)),
      info = row$name
    )
    expect_identical(
      adata$var_names,
      as.character(unlist(row$result$var_names)),
      info = row$name
    )
    expect_identical(
      frame_index_name(adata$obs),
      row$result$obs_index_name,
      info = row$name
    )
  }
})

# Why: sheets the fixture cannot show (no Excel writer exists), so the cells
# are mocked: a sheet with only the label column gives X with no variables
# (Python's `df.values[:, 1:]`), text among the data and an empty sheet are
# errors
test_that("read_excel() handles odd sheets", {
  skip_if_not_installed("readxl")
  path <- fixture_path("other_formats/sheets.xlsx")
  cells <- function(...) {
    out <- list(...)
    names(out) <- seq_along(out)
    as.data.frame(out, check.names = FALSE)
  }
  reader <- read_excel
  read_mocked <- function(value) {
    testthat::local_mocked_bindings(
      read_excel = function(...) value,
      .package = "readxl"
    )
    reader(path, 0)
  }
  labels_only <- cells(c("cell", "a", "b"))
  adata <- read_mocked(labels_only)
  expect_identical(dim(adata$X), c(2L, 0L))
  expect_identical(adata$obs_names, c("a", "b"))
  expect_error(
    read_mocked(cells(c("cell", "a"), c("g", "x"))),
    class = "anndata_invalid_value_error"
  )
  expect_error(
    read_mocked(cells()),
    class = "anndata_invalid_value_error"
  )
})

# Why: argument checks and sheet positions that are not rows of the table
test_that("read_excel() rejects bad arguments", {
  skip_if_not_installed("readxl")
  path <- fixture_path("other_formats/sheets.xlsx")
  expect_error(read_excel(path, 99), class = "anndata_invalid_value_error")
  expect_error(read_excel(path, TRUE), class = "anndata_error")
  expect_error(
    read_excel(file.path(tempdir(), "missing.xlsx"), 0),
    class = "anndata_file_not_found_error"
  )
})
