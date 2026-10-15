# Construction from an AnnData must reuse its Slots (anndata.py:396-411)
test_that("X as an AnnData copies its Slots", {
  src <- AnnData(
    matrix(as.numeric(1:6), nrow = 3),
    obs = list(g = c("a", "b", "c"), obs_names = c("r1", "r2", "r3")),
    uns = list(k = 1),
    obsm = list(emb = matrix(1, 3, 2)),
    layers = list(counts = matrix(2, 3, 2)),
    raw = list(X = matrix(0, 3, 2))
  )
  adata <- AnnData(src)
  expect_identical(adata$X, src$X)
  expect_identical(adata$obs_names, c("r1", "r2", "r3"))
  expect_identical(adata$uns, src$uns)
  expect_identical(adata$obsm[["emb"]], src$obsm[["emb"]])
  expect_identical(adata$layers[["counts"]], src$layers[["counts"]])
  expect_identical(adata$raw$X, src$raw$X)
})

# Python rejects other arguments next to an AnnData X
test_that("X as an AnnData with other arguments errors", {
  src <- AnnData(matrix(1, 2, 2))
  extra <- list(
    obs = list(a = 1:2),
    var = list(a = 1:2),
    uns = list(a = 1),
    obsm = list(a = matrix(1, 2, 1)),
    varm = list(a = matrix(1, 2, 1)),
    obsp = list(a = matrix(1, 2, 2)),
    varp = list(a = matrix(1, 2, 2))
  )
  for (arg in names(extra)) {
    expect_anndata_condition(
      do.call(AnnData, c(list(src), extra[arg])),
      "anndata_invalid_argument_error"
    )
  }
})

# Names of a data frame X become obs_names and var_names
test_that("X as a data.frame or DataFrame supplies names", {
  df <- data.frame(a = c(1, 2), b = c(3, 4), row.names = c("r1", "r2"))
  for (x in list(df, S4Vectors::DataFrame(df))) {
    adata <- AnnData(x)
    expect_identical(adata$obs_names, c("r1", "r2"))
    expect_identical(adata$var_names, c("a", "b"))
    expect_identical(adata$X, matrix(c(1, 2, 3, 4), 2))
  }
})

# Automatic row names are Python's RangeIndex and give the default names
test_that("X as a data.frame with automatic row names uses defaults", {
  adata <- AnnData(data.frame(a = c(1, 2), b = c(3, 4)))
  expect_identical(adata$obs_names, c("0", "1"))
  expect_identical(adata$var_names, c("a", "b"))
})

# Given obs and var must agree with the names of X
test_that("names of X must match given obs and var", {
  df <- data.frame(a = c(1, 2), b = c(3, 4), row.names = c("r1", "r2"))
  ok <- AnnData(df, obs = data.frame(g = 1:2, row.names = c("r1", "r2")))
  expect_identical(ok$obs_names, c("r1", "r2"))
  expect_anndata_condition(
    AnnData(df, obs = data.frame(g = 1:2, row.names = c("x", "y"))),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    AnnData(df, var = list(var_names = c("a", "z"))),
    "anndata_invalid_argument_error"
  )
  # obs without names of its own takes the names of X
  adata <- AnnData(df, obs = list(g = c("u", "v")))
  expect_identical(adata$obs_names, c("r1", "r2"))
})

# The match check applies to DataFrame input too
test_that("names of a DataFrame X must match given obs and var", {
  df <- S4Vectors::DataFrame(
    a = c(1, 2),
    b = c(3, 4),
    row.names = c("r1", "r2")
  )
  expect_anndata_condition(
    AnnData(df, obs = data.frame(g = 1:2, row.names = c("x", "y"))),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    AnnData(df, var = list(var_names = c("a", "z"))),
    "anndata_invalid_argument_error"
  )
  ok <- AnnData(df, var = list(var_names = c("a", "b")))
  expect_identical(ok$var_names, c("a", "b"))
})

# Python warns when the frame mixes dtypes, and rejects non-numeric values
test_that("a data frame X must be homogeneous", {
  expect_warning(
    adata <- AnnData(data.frame(a = 1:2, b = c(1.5, 2.5))),
    class = "anndata_implicit_modification_warning"
  )
  expect_identical(typeof(adata$X), "double")
  expect_no_warning(AnnData(data.frame(a = c(1, 2), b = c(3, 4))))
  expect_anndata_condition(
    AnnData(data.frame(a = c("x", "y"))),
    "anndata_unsupported_value_error"
  )
})

# Every Slot argument can be given in one call
test_that("all Slot arguments construct together", {
  adata <- AnnData(
    matrix(as.numeric(1:6), nrow = 3),
    uns = list(a = 1),
    obsm = list(o = matrix(1, 3, 1)),
    varm = list(v = matrix(1, 2, 1)),
    obsp = list(op = matrix(1, 3, 3)),
    varp = list(vp = matrix(1, 2, 2)),
    layers = list(l = matrix(1, 3, 2)),
    raw = list(X = matrix(0, 3, 2))
  )
  expect_identical(names(adata$obsm), "o")
  expect_identical(names(adata$varm), "v")
  expect_identical(names(adata$obsp), "op")
  expect_identical(names(adata$varp), "vp")
  expect_true("l" %in% names(adata$layers))
  expect_identical(adata$raw$shape, c(3L, 2L))
  expect_identical(adata$uns, list(a = 1))
})
