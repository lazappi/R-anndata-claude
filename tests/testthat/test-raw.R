raw_x <- function() matrix(as.numeric(1:12), 3, 4)

# 3 observations and 2 variables, with a Raw of 4 variables
raw_adata <- function() {
  AnnData(
    matrix(as.numeric(1:6), 3, 2, dimnames = NULL),
    obs = list(obs_names = c("a", "b", "c"), g = c(1, 2, 3)),
    var = list(var_names = c("v1", "v2")),
    raw = list(
      X = raw_x(),
      var = list(var_names = c("r1", "r2", "r3", "r4"), s = 1:4),
      varm = list(emb = matrix(as.numeric(1:8), 4, 2))
    )
  )
}

# Fields of a Raw built from a named list, with observations shared
test_that("a Raw built from a list exposes its fields", {
  raw <- raw_adata()$raw
  expect_identical(raw$X, raw_x())
  expect_identical(raw$shape, c(3L, 4L))
  expect_identical(raw$n_obs, 3L)
  expect_identical(raw$n_vars, 4L)
  expect_identical(raw$obs_names, c("a", "b", "c"))
  expect_identical(raw$var_names, c("r1", "r2", "r3", "r4"))
  expect_identical(names(raw$var), "s")
  expect_identical(names(raw$varm), "emb")
})

# No raw means NULL, and an empty list is the same as no raw (Python `not raw`)
test_that("raw is NULL unless given", {
  expect_null(AnnData(raw_x())$raw)
  expect_null(AnnData(raw_x(), raw = list())$raw)
})

# Python builds the Raw from the object itself when X is missing
test_that("a list without X takes X, var and varm from the parent", {
  adata <- AnnData(
    raw_x(),
    var = list(var_names = paste0("g", 1:4)),
    varm = list(pc = matrix(0, 4, 2)),
    raw = list(var = list(var_names = letters[1:4]))
  )
  expect_identical(adata$raw$X, raw_x())
  expect_identical(adata$raw$var_names, paste0("g", 1:4))
  expect_identical(names(adata$raw$varm), "pc")
})

# The constructor takes an AnnData as well as a list (Python reads its slots)
test_that("raw can be given as an AnnData", {
  other <- AnnData(
    raw_x(),
    var = list(var_names = paste0("g", 1:4)),
    varm = list(pc = matrix(0, 4, 2))
  )
  adata <- AnnData(matrix(0, 3, 2), raw = other)
  expect_identical(adata$raw$X, raw_x())
  expect_identical(adata$raw$var_names, paste0("g", 1:4))
  expect_identical(names(adata$raw$varm), "pc")
})

# Wrong row count is a dimension error, as Python's ValueError
test_that("a raw X needs one row per observation", {
  expect_anndata_condition(
    AnnData(matrix(0, 3, 2), raw = list(X = matrix(0, 2, 4))),
    "anndata_dimension_error"
  )
})

# var must have one row per column of X
test_that("raw var must match the columns of raw X", {
  expect_anndata_condition(
    AnnData(
      matrix(0, 3, 2),
      raw = list(X = raw_x(), var = list(var_names = c("a", "b")))
    ),
    "anndata_dimension_error"
  )
})

# varm is validated against the Raw (rows = raw variables)
test_that("raw varm is validated against the raw variables", {
  expect_anndata_condition(
    AnnData(
      matrix(0, 3, 2),
      raw = list(X = raw_x(), varm = list(bad = matrix(0, 3, 2)))
    ),
    "anndata_dimension_error"
  )
})

# Bad forms of the raw argument are rejected with a classed error
test_that("invalid raw arguments error", {
  expect_anndata_condition(
    AnnData(matrix(0, 3, 2), raw = 1),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    AnnData(matrix(0, 3, 2), raw = list(X = raw_x(), bogus = 1)),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    AnnData(matrix(0, 3, 2), raw = list(raw_x())),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    AnnData(matrix(0, 3, 2), raw = list(X = "a")),
    "anndata_unsupported_value_error"
  )
})

# Python: adata.raw = other stores other's X, var and varm
test_that("assigning an AnnData sets raw", {
  adata <- AnnData(matrix(0, 3, 2))
  other <- AnnData(
    raw_x(),
    var = list(var_names = paste0("g", 1:4)),
    varm = list(pc = matrix(0, 4, 2))
  )
  adata$raw <- other
  expect_identical(adata$raw$X, raw_x())
  expect_identical(adata$raw$var_names, paste0("g", 1:4))
  expect_identical(names(adata$raw$varm), "pc")
  expect_identical(adata$raw$obs_names, adata$obs_names)
})

# Python: adata.raw = None deletes the Raw, and anything else is an error
test_that("assigning NULL removes raw and other values error", {
  adata <- raw_adata()
  adata$raw <- NULL
  expect_null(adata$raw)
  expect_anndata_condition(
    adata$raw <- raw_x(),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    adata$raw <- list(X = raw_x()),
    "anndata_invalid_argument_error"
  )
  # A failed assignment leaves the old value alone
  adata <- raw_adata()
  try(adata$raw <- 1, silent = TRUE)
  expect_identical(adata$raw$shape, c(3L, 4L))
})

# Python builds the new Raw from the parent when the AnnData has no X
test_that("assigning an AnnData without X copies the parent's X", {
  adata <- AnnData(raw_x())
  adata$raw <- AnnData(shape = c(3L, 4L))
  expect_identical(adata$raw$X, raw_x())
})

# Rows of the assigned X must match the parent, as in the constructor
test_that("assigning an AnnData with the wrong number of rows errors", {
  adata <- AnnData(matrix(0, 3, 2))
  expect_anndata_condition(
    adata$raw <- AnnData(matrix(0, 2, 2)),
    "anndata_dimension_error"
  )
})

# Nested assignment through `adata$raw$...` must not trip the raw setter
test_that("nested assignment through raw works", {
  adata <- raw_adata()
  adata$raw$var$s <- 4:1
  expect_identical(adata$raw$var$s, 4:1)
  adata$raw$varm[["more"]] <- matrix(0, 4, 1)
  expect_identical(names(adata$raw$varm), c("emb", "more"))
  adata$raw$X[1, 1] <- 100
  expect_identical(adata$raw$X[1, 1], 100)
  expect_anndata_condition(
    adata$raw$X <- matrix(0, 2, 2),
    "anndata_dimension_error"
  )
  expect_anndata_condition(
    adata$raw$X <- NULL,
    "anndata_invalid_argument_error"
  )
})

# Dimensions and names are derived, so they are read-only
test_that("derived raw fields are read-only", {
  raw <- raw_adata()$raw
  for (field in c("n_obs", "n_vars", "shape", "obs_names", "var_names")) {
    expect_anndata_condition(
      raw[[field]] <- 1L,
      "anndata_read_only_error"
    )
  }
})

# Subsetting on both axes, by each kind of index (Python raw[i, j])
test_that("raw[i, j] subsets with R indices", {
  raw <- raw_adata()$raw
  sub <- raw[c(3, 1), c("r4", "r2")]
  expect_identical(sub$X, raw_x()[c(3, 1), c(4, 2)])
  expect_identical(sub$var_names, c("r4", "r2"))
  expect_identical(sub$var$s, c(4L, 2L))
  expect_identical(sub$obs_names, c("c", "a"))
  expect_identical(sub$varm$emb, matrix(as.numeric(1:8), 4, 2)[c(4, 2), ])
  expect_identical(raw[-1, c(TRUE, FALSE, FALSE, TRUE)]$shape, c(2L, 2L))
})

# The doc example adata$raw[, "gene"]$X, and obs-only raw[i]
test_that("raw[, j] and raw[i] keep the other axis whole", {
  raw <- raw_adata()$raw
  expect_identical(raw[, "r2"]$X, raw_x()[, 2, drop = FALSE])
  expect_identical(raw[2]$shape, c(1L, 4L))
  expect_identical(raw[2, ]$X, raw_x()[2, , drop = FALSE])
  expect_identical(raw[]$shape, c(3L, 4L))
})

# Subsetting never touches the original
test_that("subsetting a Raw leaves the original alone", {
  adata <- raw_adata()
  adata$raw[1, 1]
  expect_identical(adata$raw$shape, c(3L, 4L))
  expect_identical(adata$shape, c(3L, 2L))
})

# Index errors share one class
test_that("invalid raw indices error", {
  raw <- raw_adata()$raw
  expect_anndata_condition(raw[, "zzz"], "anndata_index_error")
  expect_anndata_condition(raw[, 5], "anndata_index_error")
  expect_anndata_condition(raw[4, ], "anndata_index_error")
  expect_anndata_condition(raw[, c(1, -2)], "anndata_index_error")
  expect_anndata_condition(raw[, NA], "anndata_index_error")
  expect_anndata_condition(raw[, c(TRUE, FALSE)], "anndata_index_error")
  expect_anndata_condition(raw[, list(1)], "anndata_index_error")
})

# Subsetting observations of a Raw must also subset the parent's obs and obsm
test_that("a subset Raw has the matching observations in to_adata()", {
  adata <- raw_adata()
  adata$obsm[["pca"]] <- matrix(as.numeric(1:6), 3, 2)
  adata$obsp[["nn"]] <- matrix(as.numeric(1:9), 3, 3)
  adata$uns[["k"]] <- "v"
  full <- adata$raw[c(3, 1), c(1, 4)]$to_adata()
  expect_identical(full$obs_names, c("c", "a"))
  expect_identical(full$obs$g, c(3, 1))
  expect_identical(full$obsm$pca, matrix(as.numeric(1:6), 3, 2)[c(3, 1), ])
  expect_identical(
    full$obsp$nn,
    matrix(as.numeric(1:9), 3, 3)[c(3, 1), c(3, 1)]
  )
  expect_identical(full$uns$k, "v")
  expect_identical(full$X, raw_x()[c(3, 1), c(1, 4)])
})

# to_adata uses the raw variables with the parent's observation Slots
test_that("to_adata builds an AnnData from the Raw", {
  adata <- raw_adata()
  adata$obsm[["pca"]] <- matrix(as.numeric(1:6), 3, 2)
  full <- adata$raw$to_adata()
  expect_s3_class(full, "AnnData")
  expect_identical(full$shape, c(3L, 4L))
  expect_identical(full$X, raw_x())
  expect_identical(full$var_names, c("r1", "r2", "r3", "r4"))
  expect_identical(full$obs_names, c("a", "b", "c"))
  expect_identical(names(full$obsm), "pca")
  expect_identical(names(full$varm), "emb")
  expect_null(full$raw)
  # It is independent of the parent
  full$X[1, 1] <- 0
  expect_identical(adata$raw$X, raw_x())
})

# copy gives an independent Raw (varm is a reference object)
test_that("copy is independent of the original", {
  raw <- raw_adata()$raw
  other <- raw$copy()
  expect_identical(other$X, raw$X)
  other$varm[["extra"]] <- matrix(0, 4, 1)
  other$var$s <- 0L
  expect_identical(names(raw$varm), "emb")
  expect_identical(raw$var$s, 1:4)
})

# Sparse raw data keeps its class through subsetting
test_that("a sparse raw X keeps its format", {
  x <- Matrix::sparseMatrix(
    i = c(1, 2, 3),
    j = c(1, 2, 4),
    x = 1,
    dims = c(3, 4)
  )
  adata <- AnnData(matrix(0, 3, 2), raw = list(X = x))
  sub <- adata$raw[2:3, 1:2]
  expect_s4_class(sub$X, "dgCMatrix")
  expect_identical(sub$shape, c(2L, 2L))
})

# Names kept by obs_names changes (shared with the parent)
test_that("obs_names follow the parent", {
  adata <- raw_adata()
  adata$obs_names <- c("x", "y", "z")
  expect_identical(adata$raw$obs_names, c("x", "y", "z"))
})

# Duplicate raw observation indices do not warn when subsetting
test_that("repeated observations subset without warnings", {
  raw <- raw_adata()$raw
  expect_no_warning(sub <- raw[c(1, 1), ])
  expect_identical(sub$obs_names, c("a", "a"))
})
