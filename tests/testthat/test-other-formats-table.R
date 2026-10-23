other_formats_table <- function() {
  jsonlite::fromJSON(
    fixture_path("other_formats_cases.json"),
    simplifyVector = FALSE
  )
}

# Guards the committed table and input files against drifting from what Python
# gives
test_that("the committed other-formats table matches the generator", {
  expect_generator_current("other_formats_cases.py")
})

# The table is the reference for every other-formats ticket, so check it is for
# the pinned Python version and that its rows are well formed
test_that("the other-formats reader rows are well formed", {
  table <- other_formats_table()
  expect_identical(table$version, "0.13.4")
  names_out <- vapply(table$readers, function(x) x$name, character(1))
  expect_false(anyDuplicated(names_out) > 0L)
  for (row in table$readers) {
    expect_true(xor(is.null(row$error), is.null(row$result)), info = row$name)
    if (identical(row$source$kind, "file")) {
      # an input that is missing on purpose is the only one without a file
      expect_true(
        file.exists(fixture_path(file.path(
          "other_formats",
          row$source$file
        ))) ||
          row$name == "mtx_missing",
        info = row$name
      )
    } else {
      expect_type(row$source$lines, "list")
    }
    if (!is.null(row$error)) {
      expect_true(nzchar(row$error$class), info = row$name)
      # messages must not name the machine that generated the table
      expect_false(grepl("other_formats/", row$error$message), info = row$name)
    }
  }
})

# The spec lists the inputs the table must cover, so a missing one fails here
test_that("the other-formats table covers every input in the spec", {
  table <- other_formats_table()
  rows <- table$readers
  files <- unlist(lapply(rows, function(x) x$source$file))
  readers <- vapply(rows, function(x) x$reader, character(1))
  expect_setequal(
    unique(readers),
    c(
      "read_csv",
      "read_text",
      "read_mtx",
      "read_umi_tools",
      "read_hdf",
      "read_excel"
    )
  )
  # csv and text with and without header and row names, comments, whitespace
  # and other delimiters
  expect_true(
    all(
      c(
        "header_rownames.csv",
        "header_only.csv",
        "rownames_only.csv",
        "numbers.csv",
        "comments.txt",
        "whitespace.txt",
        "tabs.tab",
        "semicolon.data"
      ) %in%
        files
    )
  )
  # compression, streams of lines and the dtype argument
  expect_true(any(grepl("\\.gz$", files)))
  expect_true(any(grepl("\\.bz2$", files)))
  expect_true(any(vapply(
    rows,
    function(x) identical(x$source$kind, "lines"),
    logical(1)
  )))
  expect_true(any(vapply(rows, function(x) !is.null(x$args$dtype), logical(1))))
  # mtx: coordinate and array, integer, real and pattern
  expect_true(
    all(
      c(
        "coordinate_integer.mtx",
        "coordinate_real.mtx",
        "coordinate_pattern.mtx",
        "array_real.mtx"
      ) %in%
        files
    )
  )
  # hdf with and without names, and with an empty key
  keys <- unlist(lapply(rows, function(x) x$args$key))
  expect_true("" %in% keys)
  expect_true(all(c("hdf_names.h5", "hdf_plain.h5") %in% files))
  # umi_tools and xlsx
  expect_true(any(grepl("^umi_tools", files)))
  expect_true("sheets.xlsx" %in% files)
  # errors raised for bad inputs
  errors <- unlist(lapply(rows, function(x) x$error$class))
  expect_true(all(c("ValueError", "IndexError", "KeyError") %in% errors))
})

# Every write_csvs case must name a described object, and the cases must cross
# the options and the uns value kinds listed in the spec
test_that("the write_csvs table covers every case in the spec", {
  table <- other_formats_table()$write_csvs
  cases <- table$cases
  expect_false(anyDuplicated(vapply(cases, function(x) x$name, "")) > 0L)
  for (case in cases) {
    expect_true(case$adata %in% names(table$adatas), info = case$name)
    expect_null(case$error, info = case$name)
    expect_true(length(case$files) > 0L, info = case$name)
  }
  args <- lapply(cases, function(x) x$args)
  skip <- vapply(args, function(a) isTRUE(a$skip_data), logical(1))
  expect_true(any(skip))
  expect_true(any(vapply(
    args,
    function(a) identical(a$skip_data, FALSE),
    logical(1)
  )))
  expect_true(any(vapply(args, function(a) !is.null(a$sep), logical(1))))
  dirnames <- vapply(cases, function(x) x$dirname, character(1))
  expect_true(any(grepl("\\.csv$", dirnames)))
  # Sparse X, an object with no X, and uns values that are sparse, scalar,
  # nested or unwritable
  kinds <- unlist(lapply(table$adatas, function(a) {
    c(
      a$X$kind,
      vapply(a$uns, function(u) u$kind, character(1))
    )
  }))
  expect_true(all(
    c("dense", "sparse", "scalar", "vector", "matrix", "dict", "array3") %in%
      kinds
  ))
  expect_true(any(vapply(table$adatas, function(a) is.null(a$X), logical(1))))
  warned <- unlist(lapply(cases, function(x) {
    vapply(x$warnings, function(w) w$class, character(1))
  }))
  expect_true("WriteWarning" %in% warned)
  messages <- unlist(lapply(cases, function(x) {
    vapply(x$warnings, function(w) w$message, character(1))
  }))
  expect_true(any(grepl("sparse annotation", messages)))
  expect_true(any(grepl("Omitting to write 'cube'", messages)))
})
