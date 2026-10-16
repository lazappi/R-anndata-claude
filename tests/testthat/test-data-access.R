make_access <- function() {
  x <- matrix(as.numeric(1:6), nrow = 3, dimnames = NULL)
  adata <- AnnData(
    x,
    obs = data.frame(
      group = c("a", "b", "a"),
      row.names = c("o1", "o2", "o3")
    ),
    var = data.frame(score = c(0.5, 1.5), row.names = c("v1", "v2")),
    uns = list(zeta = 1, alpha = 2)
  )
  adata$layers[["l"]] <- x * 10
  adata
}

# to_df is the dense view of X with the names as dimnames and no annotations
test_that("to_df returns X as a data frame with names", {
  adata <- make_access()
  df <- adata$to_df()
  expect_s3_class(df, "data.frame")
  expect_equal(rownames(df), c("o1", "o2", "o3"))
  expect_equal(colnames(df), c("v1", "v2"))
  expect_equal(df$v2, c(4, 5, 6))
})

# Python densifies sparse X and reads a layer when `layer` is given
test_that("to_df densifies sparse values and reads layers", {
  adata <- make_access()
  adata$X <- methods::as(
    Matrix::Matrix(adata$X, sparse = TRUE),
    "CsparseMatrix"
  )
  expect_equal(adata$to_df()$v1, c(1, 2, 3))
  expect_equal(adata$to_df(layer = "l")$v1, c(10, 20, 30))
})

# Python raises ValueError for a missing X and KeyError for a missing layer
test_that("to_df errors without X or for an unknown layer", {
  adata <- make_access()
  expect_anndata_condition(
    adata$to_df(layer = "nope"),
    "anndata_key_error"
  )
  adata$X <- NULL
  expect_anndata_condition(adata$to_df(), "anndata_missing_x_error")
})

# R data frames need unique row names, unlike a pandas index
test_that("to_df errors on duplicate obs_names", {
  adata <- make_access()
  suppressWarnings(adata$obs_names <- c("o1", "o1", "o3"))
  expect_anndata_condition(adata$to_df(), "anndata_names_not_unique_error")
})

# Duplicate var_names are allowed as column names, as in pandas
test_that("to_df keeps duplicate var_names as column names", {
  adata <- make_access()
  suppressWarnings(adata$var_names <- c("v1", "v1"))
  expect_equal(colnames(adata$to_df()), c("v1", "v1"))
})

# obs_vector takes an obs column or the values of a variable across obs
test_that("obs_vector reads obs columns and variables", {
  adata <- make_access()
  quiet_deprecated({
    expect_equal(adata$obs_vector("group"), c("a", "b", "a"))
    expect_equal(adata$obs_vector("v2"), c(4, 5, 6))
    expect_equal(adata$obs_vector("v2", layer = "l"), c(40, 50, 60))
  })
})

# var_vector is the transposed counterpart
test_that("var_vector reads var columns and observations", {
  adata <- make_access()
  quiet_deprecated({
    expect_equal(adata$var_vector("score"), c(0.5, 1.5))
    expect_equal(adata$var_vector("o2"), c(2, 5))
    expect_equal(adata$var_vector("o2", layer = "l"), c(20, 50))
  })
})

# Python raises KeyError when the key is found nowhere and ValueError when it
# is in both places
test_that("obs_vector and var_vector error on unknown or ambiguous keys", {
  adata <- make_access()
  expect_anndata_condition(
    quiet_deprecated(adata$obs_vector("zzz")),
    "anndata_key_error"
  )
  expect_anndata_condition(
    quiet_deprecated(adata$var_vector("zzz")),
    "anndata_key_error"
  )
  adata$obs$v1 <- c(1, 2, 3)
  expect_anndata_condition(
    quiet_deprecated(adata$obs_vector("v1")),
    "anndata_ambiguous_key_error"
  )
})

# An unknown layer is a KeyError when the key is a variable name
test_that("obs_vector errors on an unknown layer", {
  adata <- make_access()
  expect_anndata_condition(
    quiet_deprecated(adata$obs_vector("v1", layer = "nope")),
    "anndata_key_error"
  )
})

# The ambiguity check is symmetric, and `k` must be a single string
test_that("var_vector errors on ambiguous keys and bad k", {
  adata <- make_access()
  adata$var$o1 <- c(1, 2)
  expect_anndata_condition(
    quiet_deprecated(adata$var_vector("o1")),
    "anndata_ambiguous_key_error"
  )
  expect_anndata_condition(
    quiet_deprecated(adata$obs_vector(c("a", "b"))),
    "anndata_invalid_argument_error"
  )
})

# A variable lookup needs X, and that is a key error unlike to_df
test_that("vectors from variables error when X is NULL", {
  adata <- make_access()
  adata$X <- NULL
  expect_anndata_condition(
    quiet_deprecated(adata$obs_vector("v1")),
    "anndata_key_error"
  )
  expect_anndata_condition(
    quiet_deprecated(adata$var_vector("o1")),
    "anndata_key_error"
  )
})

# Sparse values must give plain vectors like dense ones
test_that("vectors from sparse values are plain vectors", {
  adata <- make_access()
  adata$X <- methods::as(
    Matrix::Matrix(adata$X, sparse = TRUE),
    "CsparseMatrix"
  )
  quiet_deprecated({
    expect_identical(adata$obs_vector("v2"), c(4, 5, 6))
    expect_identical(adata$var_vector("o2"), c(2, 5))
  })
})

# R row names cannot be missing, so to_df rejects NA obs_names
test_that("to_df errors on missing obs_names", {
  adata <- make_access()
  suppressWarnings(adata$obs_names <- c("o1", NA, "o3"))
  expect_anndata_condition(adata$to_df(), "anndata_names_not_unique_error")
})

# The advice is copied from Python, and its braces must survive cli
# interpolation
test_that("deprecation messages carry the Python advice", {
  adata <- make_access()
  cnd <- expect_warning(adata$obsm_keys(), class = "anndata_deprecated_warning")
  expect_match(
    gsub("\\s+", " ", conditionMessage(cnd)),
    paste0(
      "Use obsm instead of obsm_keys. ",
      "(e.g. `k in adata.obsm` or `adata.obsm.keys() | {'u'}`)"
    ),
    fixed = TRUE
  )
  cnd <- expect_warning(
    adata$obs_vector("group"),
    class = "anndata_deprecated_warning"
  )
  expect_match(
    gsub("\\s+", " ", conditionMessage(cnd)),
    "Use anndata.acc.A instead of obs_vector. E.g. `vec = adata[A.obs['foo']]`",
    fixed = TRUE
  )
})

# The key methods list names, and uns_keys is sorted as in Python
test_that("key methods return character vectors", {
  adata <- make_access()
  adata$obsm[["pca"]] <- matrix(0, 3, 2)
  adata$varm[["load"]] <- matrix(0, 2, 2)
  empty <- AnnData(matrix(0, 2, 2))
  quiet_deprecated({
    expect_equal(adata$obs_keys(), "group")
    expect_equal(adata$var_keys(), "score")
    expect_equal(adata$obsm_keys(), "pca")
    expect_equal(adata$varm_keys(), "load")
    expect_equal(adata$uns_keys(), c("alpha", "zeta"))
    expect_identical(empty$obs_keys(), character())
    expect_identical(empty$obsm_keys(), character())
    expect_identical(empty$uns_keys(), character())
  })
})

# Python 0.13.4 warns (FutureWarning) on every call of these methods, even for
# invalid keys, so each must signal the class with the Python message
test_that("deprecated methods warn with the Python message", {
  adata <- make_access()
  calls <- list(
    obs_keys = function() adata$obs_keys(),
    var_keys = function() adata$var_keys(),
    obsm_keys = function() adata$obsm_keys(),
    varm_keys = function() adata$varm_keys(),
    uns_keys = function() adata$uns_keys(),
    obs_vector = function() adata$obs_vector("group"),
    var_vector = function() adata$var_vector("score")
  )
  for (method in names(calls)) {
    cnd <- expect_warning(
      calls[[method]](),
      class = "anndata_deprecated_warning"
    )
    expect_s3_class(cnd, "anndata_future_warning")
    expect_match(
      conditionMessage(cnd),
      paste0("The method `", method, "` is deprecated and will be removed"),
      fixed = TRUE
    )
  }
  # An invalid key still warns, before the error
  expect_warning(
    try(adata$obs_vector("zzz"), silent = TRUE),
    class = "anndata_deprecated_warning"
  )
})

# Internal callers (printing, to_df, copy) and non-deprecated access must not
# trigger the deprecation warnings
test_that("non-deprecated paths do not warn", {
  adata <- make_access()
  adata$obsm[["pca"]] <- matrix(0, 3, 2)
  expect_no_warning(format(adata))
  expect_no_warning(adata$to_df())
  expect_no_warning(adata$copy())
  expect_no_warning(adata$strings_to_categoricals())
  expect_no_warning(adata$obsm$keys())
})
