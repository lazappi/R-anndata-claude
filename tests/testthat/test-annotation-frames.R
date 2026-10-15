df_names <- function(x) rownames(x)

# NULL and an empty list both mean "no columns", with default names when the
# length is known (Python: mk_index)
test_that("NULL and empty list give default names", {
  for (anno in list(NULL, list())) {
    out <- as_annotation_frame(anno, "obs", expected = 3L)
    expect_s4_class(out, "DataFrame")
    expect_identical(df_names(out), c("0", "1", "2"))
    expect_identical(ncol(out), 0L)
  }
})

# With no length Python builds an empty frame
test_that("NULL with no length gives zero rows", {
  out <- as_annotation_frame(NULL, "var")
  expect_identical(nrow(out), 0L)
})

# Named lists give columns and take the index from the names element
test_that("named lists use the index element", {
  for (nm in c("obs_names", "row_names")) {
    anno <- list(a = 1:2, b = c("x", "y"))
    anno[[nm]] <- c("c1", "c2")
    out <- as_annotation_frame(anno, "obs", expected = 2L)
    expect_identical(df_names(out), c("c1", "c2"))
    expect_identical(names(out), c("a", "b"))
  }
  anno <- list(a = 1:2, var_names = c("g1", "g2"))
  out <- as_annotation_frame(anno, "var", expected = 2L)
  expect_identical(df_names(out), c("g1", "g2"))
  anno <- list(a = 1:2, col_names = c("g1", "g2"))
  out <- as_annotation_frame(anno, "var", expected = 2L)
  expect_identical(df_names(out), c("g1", "g2"))
})

# obs ignores the var index element, as Python only looks at its own
test_that("a list ignores the other axis's index element", {
  out <- as_annotation_frame(
    list(a = 1:2, var_names = c("g1", "g2")),
    "obs",
    2L
  )
  expect_identical(df_names(out), c("0", "1"))
  expect_identical(names(out), c("a", "var_names"))
})

# Python replaces the index with defaults when no length is given
test_that("a list with no length gets default names", {
  out <- as_annotation_frame(list(a = 1:2, obs_names = c("c1", "c2")), "obs")
  expect_identical(df_names(out), c("0", "1"))
})

# Mismatched lengths use the message for the source that fixed the length
test_that("length mismatches raise dimension errors", {
  expect_error(
    as_annotation_frame(list(a = 1:2), "obs", expected = 3L),
    class = "anndata_dimension_error"
  )
  expect_error(
    as_annotation_frame(list(a = 1:2), "var", expected = 3L, source = "shape"),
    class = "anndata_dimension_error"
  )
  expect_error(
    as_annotation_frame(data.frame(a = 1:2), "obs", expected = 3L),
    class = "anndata_dimension_error"
  )
  expect_error(
    as_annotation_frame(S4Vectors::DataFrame(a = 1:2), "var", expected = 1L),
    class = "anndata_dimension_error"
  )
})

# Python raises for anything that is not a mapping, frame or None
test_that("unsupported inputs error", {
  expect_error(
    as_annotation_frame(1:3, "obs"),
    class = "anndata_unsupported_value_error"
  )
  expect_error(
    as_annotation_frame(list(1:2), "obs"),
    class = "anndata_unsupported_value_error"
  )
})

# Character row names are kept without a warning
test_that("data frames with character row names are kept", {
  df <- data.frame(a = 1:2, row.names = c("c1", "c2"))
  expect_no_warning(out <- as_annotation_frame(df, "obs", expected = 2L))
  expect_s4_class(out, "DataFrame")
  expect_identical(df_names(out), c("c1", "c2"))
  expect_identical(out$a, 1:2)
})

# Python warns for the default integer index of a frame and names it 0..n-1
test_that("automatic row names warn and become 0..n-1", {
  expect_warning(
    out <- as_annotation_frame(data.frame(a = 1:2), "obs"),
    class = "anndata_implicit_modification_warning"
  )
  expect_identical(df_names(out), c("0", "1"))
  expect_warning(
    out <- as_annotation_frame(S4Vectors::DataFrame(a = 1:2), "var"),
    class = "anndata_implicit_modification_warning"
  )
  expect_identical(df_names(out), c("0", "1"))
})

# Non-character names are coerced with the warning in every input form
test_that("non-character names are coerced with a warning", {
  expect_warning(
    out <- as_annotation_frame(
      list(a = 1:2, obs_names = c(10L, 20L)),
      "obs",
      expected = 2L
    ),
    class = "anndata_implicit_modification_warning"
  )
  expect_identical(df_names(out), c("10", "20"))
  expect_warning(
    as_annotation_frame(
      list(obs_names = factor(c("a", "b"))),
      "obs",
      expected = 2L
    ),
    class = "anndata_implicit_modification_warning"
  )
})

# Duplicates and NA are valid index values (ADR 0003)
test_that("names may contain duplicates and NA", {
  anno <- list(a = 1:4, obs_names = c("x", "x", NA, "y"))
  out <- as_annotation_frame(anno, "obs", expected = 4L)
  expect_identical(df_names(out), c("x", "x", NA, "y"))
  expect_identical(out$a, 1:4)
  # NA names kept in a frame input, character NA is not a warning
  df <- S4Vectors::DataFrame(a = 1:3)
  df <- with_frame_names(df, c("x", NA, "x"))
  expect_no_warning(out <- as_annotation_frame(df, "obs", expected = 3L))
  expect_identical(df_names(out), c("x", NA, "x"))
})

# The index name has to survive each conversion (pandas index.name)
test_that("the index name is preserved", {
  df <- data.frame(a = 1:2, row.names = c("c1", "c2"))
  attr(df, "index_name") <- "barcode"
  out <- as_annotation_frame(df, "obs", expected = 2L)
  expect_identical(frame_index_name(out), "barcode")
  out2 <- as_annotation_frame(out, "obs", expected = 2L)
  expect_identical(frame_index_name(out2), "barcode")
  expect_null(frame_index_name(as_annotation_frame(NULL, "obs", 2L)))
  expect_null(frame_index_name(as_annotation_frame(list(a = 1:2), "obs")))
})

# Every column type must come through, with NA kept and factor levels intact
test_that("column types and NA are preserved", {
  df <- data.frame(
    int = c(1L, NA),
    dbl = c(1.5, NA),
    chr = c("a", NA),
    lgl = c(TRUE, NA),
    fct = factor(c("u", NA), levels = c("u", "v")),
    ord = factor(c("lo", NA), levels = c("lo", "hi"), ordered = TRUE),
    row.names = c("c1", "c2")
  )
  for (anno in list(
    df,
    S4Vectors::DataFrame(df, check.names = FALSE),
    as.list(df)
  )) {
    out <- suppressWarnings(as_annotation_frame(anno, "obs", expected = 2L))
    for (col in names(df)) {
      expect_identical(out[[col]], df[[col]], info = col)
    }
  }
  expect_s3_class(out$ord, "ordered")
  expect_identical(levels(out$fct), c("u", "v"))
})

# Column names are never mangled
test_that("column names are not checked", {
  df <- data.frame(`a b` = 1:2, check.names = FALSE, row.names = c("x", "y"))
  out <- as_annotation_frame(df, "obs", expected = 2L)
  expect_identical(names(out), "a b")
})

# Python warns once for non-unique names and ignores NA
test_that("check_names_unique warns for duplicates only", {
  expect_warning(
    check_names_unique(c("a", "b", "a"), "obs"),
    class = "anndata_names_not_unique_warning"
  )
  expect_warning(
    check_names_unique(c("a", "b", "a"), "var"),
    class = "anndata_warning"
  )
  expect_no_warning(check_names_unique(c("a", "b"), "obs"))
  expect_no_warning(check_names_unique(c("a", NA, NA), "var"))
  expect_no_warning(check_names_unique(character(), "obs"))
})
