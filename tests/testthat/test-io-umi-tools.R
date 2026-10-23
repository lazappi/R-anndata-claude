# Why: every read_umi_tools row of the table must give Python's CSR X, dtype,
# shape and category-ordered names
test_that("read_umi_tools() matches the table", {
  rows <- Filter(
    function(r) identical(r$reader, "read_umi_tools"),
    other_formats_table()$readers
  )
  expect_gte(length(rows), 4L)
  for (row in rows) {
    args <- c(
      list(fixture_path(file.path("other_formats", row$source$file))),
      row$args
    )
    adata <- do.call(read_umi_tools, args)
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

# Why: the index names, summed duplicates, float counts and bad input are not
# all in the table
test_that("read_umi_tools() sums duplicates and rejects bad input", {
  read_lines <- function(lines, ...) {
    path <- withr::local_tempfile(fileext = ".tsv")
    writeLines(lines, path)
    read_umi_tools(path, ...)
  }
  dup <- read_lines(c("gene\tcell\tcount", "g1\tc1\t2", "g1\tc1\t3"))
  expect_equal(as.matrix(drop_dtype(dup$X))[[1L]], 5)
  expect_identical(frame_index_name(dup$obs), "cell")
  expect_identical(frame_index_name(dup$var), "gene")
  frac <- read_lines(c("gene\tcell\tcount", "g1\tc1\t1.5"))
  expect_identical(get_dtype(frac$X) %||% native_dtype(frac$X), "float64")
  # pandas parses 1.0 and nan as float64 counts, so X is float64
  for (count in c("1.0", "2e3", "nan")) {
    float_counts <- read_lines(c(
      "gene\tcell\tcount",
      paste0("g1\tc1\t", count)
    ))
    expect_identical(
      get_dtype(float_counts$X) %||% native_dtype(float_counts$X),
      "float64",
      info = count
    )
  }
  # Python raises for a header-only file (scipy cannot infer the shape) and
  # for an empty file
  expect_error(
    read_lines("gene\tcell\tcount"),
    class = "anndata_invalid_value_error"
  )
  expect_error(read_lines(character()), class = "anndata_invalid_value_error")
  expect_error(
    read_umi_tools(file.path(tempdir(), "missing.tsv")),
    class = "anndata_file_not_found_error"
  )
  expect_error(read_umi_tools(I("gene")), class = "anndata_error")
  expect_error(
    read_lines(c("gene\tcell", "g1\tc1")),
    class = "anndata_invalid_value_error"
  )
  expect_error(
    read_lines(c("gene\tcell\tcount", "g1\tc1")),
    class = "anndata_invalid_value_error"
  )
  expect_error(
    read_lines(c("gene\tcell\tcount", "g1\tc1\tx")),
    class = "anndata_invalid_value_error"
  )
  expect_error(
    read_umi_tools(fixture_path("other_formats/umi_tools.tsv"), dtype = "x"),
    class = "anndata_error"
  )
  expect_error(read_umi_tools(1L), class = "anndata_error")
})
