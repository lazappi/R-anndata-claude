make_adata <- function() {
  AnnData(
    matrix(as.numeric(1:6), nrow = 3),
    obs = list(obs_names = c("a", "b", "c")),
    var = list(var_names = c("x", "y"))
  )
}

# Python gives a frame with a string index its own names
test_that("obs assignment takes the names the value brings", {
  adata <- make_adata()
  adata$obs <- data.frame(k = 1:3, row.names = c("d", "e", "f"))
  expect_identical(adata$obs_names, c("d", "e", "f"))
  expect_identical(names(adata$obs), "k")
  adata$var <- data.frame(k = 1:2, row.names = c("p", "q"))
  expect_identical(adata$var_names, c("p", "q"))
})

# Python resets names to "0".. for a value without an index, and warns for a
# data frame with the default integer index
test_that("obs assignment without names resets them as Python does", {
  adata <- make_adata()
  adata$obs <- list(k = 1:3)
  expect_identical(adata$obs_names, c("0", "1", "2"))
  adata <- make_adata()
  # the helper unwinds on the warning, so assign again to see the result
  expect_anndata_condition(
    adata$obs <- data.frame(k = 1:3),
    "anndata_implicit_modification_warning"
  )
  suppressWarnings(adata$obs <- data.frame(k = 1:3))
  expect_identical(adata$obs_names, c("0", "1", "2"))
  adata <- make_adata()
  adata$var <- NULL
  expect_identical(adata$var_names, c("0", "1"))
  expect_identical(ncol(adata$var), 0L)
})

# Python raises for a wrong row count and for non-frame values
test_that("obs and var assignment errors are classed", {
  adata <- make_adata()
  expect_anndata_condition(
    adata$obs <- data.frame(k = 1:4, row.names = letters[1:4]),
    "anndata_dimension_error"
  )
  expect_anndata_condition(
    adata$var <- data.frame(k = 1:3, row.names = letters[1:3]),
    "anndata_dimension_error"
  )
  expect_anndata_condition(adata$obs <- 1, "anndata_unsupported_value_error")
  expect_identical(adata$obs_names, c("a", "b", "c"))
})

# Python keeps the index name of the value
test_that("obs assignment keeps the index name", {
  adata <- make_adata()
  df <- data.frame(k = 1:3, row.names = c("d", "e", "f"))
  attr(df, "index_name") <- "bar"
  adata$obs <- df
  expect_identical(frame_index_name(adata$obs), "bar")
})

# Names are coerced to character and checked for length, as in Python
test_that("names assignment coerces and checks length", {
  adata <- make_adata()
  adata$obs_names <- c("p", "q", "r")
  expect_identical(adata$obs_names, c("p", "q", "r"))
  expect_identical(rownames(adata$obs), c("p", "q", "r"))
  adata$obs_names <- 1:3
  expect_identical(adata$obs_names, c("1", "2", "3"))
  adata$var_names <- factor(c("u", "v"))
  expect_identical(adata$var_names, c("u", "v"))
  expect_anndata_condition(
    adata$obs_names <- c("p", "q"),
    "anndata_dimension_error"
  )
  expect_anndata_condition(
    adata$var_names <- c("p", "q", "r"),
    "anndata_dimension_error"
  )
  expect_anndata_condition(
    adata$obs_names <- NULL,
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    adata$obs_names <- list("a", "b", "c"),
    "anndata_invalid_argument_error"
  )
  expect_identical(adata$obs_names, c("1", "2", "3"))
})

# Python accepts duplicates and NA when names are set, warning only at
# construction
test_that("names assignment accepts duplicates and NA without warning", {
  adata <- make_adata()
  expect_no_warning(adata$obs_names <- c("p", "p", "r"))
  expect_identical(adata$obs_names, c("p", "p", "r"))
  adata$obs_names <- c("p", NA, "r")
  expect_identical(adata$obs_names, c("p", NA, "r"))
})

# Python resets the index name when a plain list is assigned
test_that("names assignment resets the index name", {
  adata <- make_adata()
  df <- data.frame(k = 1:3, row.names = c("d", "e", "f"))
  attr(df, "index_name") <- "bar"
  adata$obs <- df
  adata$obs_names <- c("p", "q", "r")
  expect_null(frame_index_name(adata$obs))
})

# Python rewrites the index of data frames in obsm and varm
test_that("renaming propagates to data frames in obsm and varm", {
  adata <- make_adata()
  adata$obsm[["df"]] <- data.frame(z = 1:3, row.names = c("a", "b", "c"))
  adata$varm[["df"]] <- data.frame(z = 1:2, row.names = c("x", "y"))
  adata$obs_names <- c("p", "q", "r")
  expect_identical(rownames(adata$obsm[["df"]]), c("p", "q", "r"))
  adata$var <- data.frame(k = 1:2, row.names = c("u", "v"))
  expect_identical(rownames(adata$varm[["df"]]), c("u", "v"))
  adata$obs <- list(k = 1:3)
  expect_identical(rownames(adata$obsm[["df"]]), c("0", "1", "2"))
})

# uns must be a named list and replaces the old value
test_that("uns assignment replaces and validates", {
  adata <- make_adata()
  expect_identical(adata$uns, list())
  adata$uns <- list(a = 1)
  adata$uns <- list(b = 2)
  expect_identical(adata$uns, list(b = 2))
  adata$uns <- list()
  expect_identical(adata$uns, list())
  for (bad in list(NULL, 5, list(1, 2), data.frame(a = 1))) {
    expect_anndata_condition(
      adata$uns <- bad,
      "anndata_invalid_argument_error"
    )
  }
})

# Python's `uns[k] = v` mutates in place, which R does by reassignment
test_that("uns entries can be set one at a time", {
  adata <- make_adata()
  adata$uns[["k"]] <- 1
  adata$uns$m <- "z"
  expect_identical(adata$uns, list(k = 1, m = "z"))
  adata$uns[["k"]] <- NULL
  expect_identical(adata$uns, list(m = "z"))
})

# The constructor takes uns as Python does
test_that("construction accepts uns", {
  expect_identical(
    AnnData(shape = c(1L, 1L), uns = list(a = 1))$uns,
    list(a = 1)
  )
  expect_anndata_condition(
    AnnData(shape = c(1L, 1L), uns = 5),
    "anndata_invalid_argument_error"
  )
})
