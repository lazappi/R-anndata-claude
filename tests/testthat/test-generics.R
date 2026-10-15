generics_adata <- function() {
  AnnData(
    matrix(as.numeric(1:6), 3, 2),
    obs = list(obs_names = c("a", "b", "c")),
    var = list(var_names = c("v1", "v2"))
  )
}

# Python's `shape` is (n_obs, n_vars), and nrow()/ncol() derive from dim()
test_that("dim(), nrow() and ncol() give the shape", {
  adata <- generics_adata()

  expect_identical(dim(adata), c(3L, 2L))
  expect_identical(nrow(adata), 3L)
  expect_identical(ncol(adata), 2L)
})

# dimnames() must be the obs and var names so matrix-like code works
test_that("dimnames() gives obs and var names", {
  expect_identical(
    dimnames(generics_adata()),
    list(c("a", "b", "c"), c("v1", "v2"))
  )
})

# Python's len(adata) is n_obs, not the number of elements
test_that("length() is n_obs", {
  expect_identical(length(generics_adata()), 3L)
  expect_identical(length(AnnData(shape = c(0L, 5L))), 0L)
})

# `[` and t() come from other tickets, but the spec lists them as generics
test_that("`[` and t() work as generics", {
  adata <- generics_adata()

  expect_identical(dim(adata[1:2, ]), c(2L, 2L))
  expect_identical(dim(t(adata)), c(2L, 3L))
})

# Python's __eq__ raises NotImplementedError, so every comparison must error
test_that("comparison operators raise a classed error", {
  a <- generics_adata()
  b <- generics_adata()

  expect_anndata_condition(a == b, "anndata_not_implemented_error")
  expect_anndata_condition(a != b, "anndata_not_implemented_error")
  expect_anndata_condition(a < b, "anndata_not_implemented_error")
  expect_anndata_condition(a > b, "anndata_not_implemented_error")
  expect_anndata_condition(a <= b, "anndata_not_implemented_error")
  expect_anndata_condition(a >= b, "anndata_not_implemented_error")
  expect_anndata_condition(a == 1, "anndata_not_implemented_error")
  expect_anndata_condition(1 == a, "anndata_not_implemented_error")
})

# Only comparisons are Python's __eq__ case, so arithmetic must not claim it
test_that("arithmetic operators do not raise the comparison error", {
  a <- generics_adata()

  err <- tryCatch(a + 1, error = identity)
  expect_s3_class(err, "error")
  expect_false(inherits(err, "anndata_not_implemented_error"))
})
