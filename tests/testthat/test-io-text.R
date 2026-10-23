text_row_source <- function(row) {
  if (identical(row$source$kind, "file")) {
    fixture_path(file.path("other_formats", row$source$file))
  } else {
    as.character(unlist(row$source$lines))
  }
}

text_row_args <- function(row) {
  args <- list(text_row_source(row))
  # a JSON null is a missing entry, so `delimiter = NULL` needs the key check
  for (name in names(row$args)) {
    args[name] <- list(row$args[[name]])
  }
  args
}

expect_text_result <- function(adata, expected, name) {
  x <- expected$X
  values <- do.call(rbind, lapply(x$values, unlist))
  expect_equal(unname(drop_dtype(adata$X)), values, info = name)
  expect_identical(
    get_dtype(adata$X) %||% native_dtype(adata$X),
    x$dtype,
    info = name
  )
  expect_identical(adata$obs_names, unlist(expected$obs_names), info = name)
  expect_identical(adata$var_names, unlist(expected$var_names), info = name)
}

# Why: every read_text and read_csv row of the table must give Python's X,
# dtype and names, or the error class, for files, compressed files and lines.
test_that("read_text() and read_csv() match the table", {
  rows <- Filter(
    function(r) r$reader %in% c("read_text", "read_csv"),
    other_formats_table()$readers
  )
  expect_gt(length(rows), 30L)
  for (row in rows) {
    fn <- get(row$reader)
    args <- text_row_args(row)
    if (!is.null(row$error)) {
      expect_error(
        do.call(fn, args),
        class = "anndata_error",
        info = row$name
      )
      # Python's ValueErrors keep their message
      if (identical(row$error$class, "ValueError")) {
        err <- tryCatch(do.call(fn, args), error = identity)
        expect_identical(
          cli::ansi_strip(conditionMessage(err)),
          row$error$message,
          info = row$name
        )
      }
    } else {
      expect_text_result(do.call(fn, args), row$result, row$name)
    }
  }
})

# Why: lines given as a connection and a single line marked with I() are the
# other two input forms of the spec
test_that("read_text() reads connections and single lines", {
  path <- fixture_path("other_formats/header_rownames.csv")
  con <- file(path)
  from_con <- read_csv(con)
  expect_identical(from_con$obs_names, c("c1", "c2"))
  expect_identical(from_con$var_names, c("g1", "g2", "g3"))
  one <- read_csv(I("1,2,3"))
  expect_identical(dim(one), c(1L, 3L))
  expect_error(
    read_csv(file.path(tempdir(), "missing.csv")),
    class = "anndata_file_not_found_error"
  )
})

# Why: the dtype argument takes numpy names and the values keep that dtype on
# disk, so a written result has Python's dtype
test_that("read_csv() records the dtype and validates arguments", {
  path <- fixture_path("other_formats/header_rownames.csv")
  expect_identical(get_dtype(read_csv(path)$X), "float32")
  expect_identical(get_dtype(read_csv(path, dtype = "int64")$X), "int64")
  expect_null(get_dtype(read_csv(path, dtype = "float64")$X))
  expect_error(read_csv(path, dtype = "float16"), class = "anndata_error")
  expect_error(read_csv(path, delimiter = ""), class = "anndata_error")
  expect_error(
    read_csv(path, first_column_names = "yes"),
    class = "anndata_error"
  )
  expect_error(read_csv(1L), class = "anndata_error")
  # integer dtypes reject out of range values as numpy does
  expect_error(
    read_csv(I(c("a,b", "3000000000,2")), dtype = "int32"),
    class = "anndata_invalid_value_error"
  )
  expect_error(
    read_csv(I(c("a,b", "-1,2")), dtype = "uint8"),
    class = "anndata_invalid_value_error"
  )
  # integer dtypes reject fractions as numpy does
  expect_error(
    read_csv(I(c("a,b", "1.5,2")), dtype = "int32"),
    class = "anndata_invalid_value_error"
  )
})
