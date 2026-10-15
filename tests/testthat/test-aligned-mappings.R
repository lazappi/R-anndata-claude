make_adata <- function(...) {
  AnnData(
    matrix(0, 3, 2),
    obs = list(obs_names = c("a", "b", "c")),
    var = list(var_names = c("x", "y")),
    ...
  )
}
csc <- function(n, p) {
  methods::as(
    Matrix::Matrix(matrix(as.numeric(seq_len(n * p)), n, p), sparse = TRUE),
    "CsparseMatrix"
  )
}

# Basic mapping operations from the spec: [[, $, names, length, as.list, removal
test_that("obsm supports get, set, names, length, as.list and removal", {
  adata <- make_adata()
  expect_length(adata$obsm, 0L)
  expect_identical(names(adata$obsm), character())
  m <- matrix(as.numeric(1:6), 3)
  adata$obsm[["pca"]] <- m
  adata$obsm$other <- matrix(0, 3, 1)
  expect_identical(adata$obsm[["pca"]], m)
  expect_identical(adata$obsm$pca, m)
  expect_identical(names(adata$obsm), c("pca", "other"))
  expect_length(adata$obsm, 2L)
  expect_identical(names(as.list(adata$obsm)), c("pca", "other"))
  expect_null(adata$obsm[["missing"]])
  adata$obsm[["pca"]] <- NULL
  expect_identical(names(adata$obsm), "other")
  adata$obsm$other <- NULL
  expect_length(adata$obsm, 0L)
})

# Mappings have reference semantics through the parent
test_that("mapping edits are visible through an alias", {
  a <- make_adata()
  b <- a
  b$varm[["k"]] <- matrix(0, 2, 2)
  expect_identical(names(a$varm), "k")
})

# Whole-list assignment replaces the content, and invalid lists change nothing
test_that("assigning a whole named list replaces the mapping", {
  adata <- make_adata(obsm = list(a = matrix(0, 3, 1)))
  adata$obsm <- list(b = matrix(1, 3, 2), c = matrix(2, 3, 1))
  expect_identical(names(adata$obsm), c("b", "c"))
  adata$obsm <- list()
  expect_length(adata$obsm, 0L)
  adata$obsm <- list(b = matrix(1, 3, 2))
  adata$obsm <- NULL
  expect_length(adata$obsm, 0L)
  adata$obsm <- list(b = matrix(1, 3, 2))
  expect_anndata_condition(
    adata$obsm <- list(ok = matrix(0, 3, 1), bad = matrix(0, 2, 1)),
    "anndata_dimension_error"
  )
  expect_identical(names(adata$obsm), "b")
  expect_anndata_condition(
    adata$obsm <- list(matrix(0, 3, 1)),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    adata$obsm <- list(a = matrix(0, 3, 1), a = matrix(0, 3, 1)),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    adata$obsm <- matrix(0, 3, 1),
    "anndata_invalid_argument_error"
  )
})

# Python's axis arrays check the first dimension, pairwise arrays both
test_that("axis arrays check the first dimension", {
  adata <- make_adata()
  expect_anndata_condition(
    adata$obsm[["a"]] <- matrix(0, 2, 2),
    "anndata_dimension_error"
  )
  expect_anndata_condition(
    adata$varm[["a"]] <- matrix(0, 3, 2),
    "anndata_dimension_error"
  )
  adata$varm[["ok"]] <- matrix(0, 2, 5)
  # a rejected value is not stored
  expect_identical(names(adata$varm), "ok")
})

# Python-confirmed (.ralph/oracle/aligned.py): obsp (3, 2) and varp (3, 3) on a
# 3 x 2 object raise ValueError. A data frame in obsp is accepted by Python,
# but the spec only allows matrices, so it is a deliberate error here.
test_that("pairwise arrays check both dimensions", {
  adata <- make_adata()
  adata$obsp[["g"]] <- matrix(0, 3, 3)
  adata$varp[["g"]] <- csc(2, 2)
  expect_anndata_condition(
    adata$obsp[["bad"]] <- matrix(0, 3, 2),
    "anndata_dimension_error"
  )
  expect_anndata_condition(
    adata$varp[["bad"]] <- matrix(0, 3, 3),
    "anndata_dimension_error"
  )
  expect_anndata_condition(
    adata$obsp[["bad"]] <- data.frame(a = 1:3),
    "anndata_unsupported_value_error"
  )
})

# Arrays with 2 or more dimensions are accepted, and only the aligned
# dimensions are checked
test_that("higher-dimensional arrays are accepted", {
  adata <- make_adata()
  arr <- array(0, c(3, 2, 4))
  adata$obsm[["arr"]] <- arr
  expect_identical(adata$obsm[["arr"]], arr)
  expect_anndata_condition(
    adata$obsm[["bad"]] <- array(0, c(2, 2, 2)),
    "anndata_dimension_error"
  )
})

# Python reshapes 1-D numpy arrays to a column
test_that("plain vectors become one column matrices", {
  adata <- make_adata()
  adata$obsm[["v"]] <- c(1, 2, 3)
  expect_identical(adata$obsm[["v"]], matrix(c(1, 2, 3), ncol = 1))
  expect_anndata_condition(
    adata$obsm[["bad"]] <- c(1, 2),
    "anndata_dimension_error"
  )
})

# Python rejects values that are not arrays (a list raises) and keeps string
# arrays, which R does not accept as matrix values
test_that("unsupported values error by class", {
  adata <- make_adata()
  expect_anndata_condition(
    adata$obsm[["a"]] <- letters[1:3],
    "anndata_unsupported_value_error"
  )
  expect_anndata_condition(
    adata$obsm[["a"]] <- matrix(letters[1:6], 3),
    "anndata_unsupported_value_error"
  )
  expect_anndata_condition(
    adata$obsm[["a"]] <- list(1, 2, 3),
    "anndata_unsupported_value_error"
  )
})

# Python accepts any key (even 1 or ""), but an R list cannot hold NA or empty
# names, so keys are restricted to single non-empty strings
test_that("keys must be single non-empty strings", {
  adata <- make_adata()
  for (key in list(NA_character_, "", 1, c("a", "b"))) {
    expect_anndata_condition(
      adata$obsm[[key]] <- matrix(0, 3, 1),
      "anndata_invalid_argument_error"
    )
  }
})

# Sparse format and dtype metadata must survive storage unchanged
test_that("values keep their sparse format and dtype record", {
  adata <- make_adata()
  csr <- methods::as(csc(3, 2), "RsparseMatrix")
  adata$obsm[["csc"]] <- csc(3, 2)
  adata$obsm[["csr"]] <- csr
  adata$obsp[["csr"]] <- methods::as(csc(3, 3), "RsparseMatrix")
  expect_s4_class(adata$obsm[["csc"]], "dgCMatrix")
  expect_s4_class(adata$obsm[["csr"]], "dgRMatrix")
  expect_s4_class(adata$obsp[["csr"]], "dgRMatrix")
  typed <- structure(matrix(1, 3, 2), anndata_dtype = "float32")
  adata$obsm[["typed"]] <- typed
  expect_identical(adata$obsm[["typed"]], typed)
  col <- set_dtype(matrix(1, 3, 1), "int8")
  adata$obsm[["col"]] <- set_dtype(c(1, 1, 1), "int8")
  expect_identical(adata$obsm[["col"]], col)
  # other Matrix classes are coerced as for X
  adata$obsm[["tmat"]] <- methods::as(csc(3, 2), "TsparseMatrix")
  expect_s4_class(adata$obsm[["tmat"]], "dgCMatrix")
})

# Python accepts a data frame in obsm if its index equals the obs_names
test_that("data frames in obsm and varm need matching row names", {
  adata <- make_adata()
  df <- data.frame(a = 1:3, b = c("u", "v", "w"), row.names = c("a", "b", "c"))
  adata$obsm[["df"]] <- df
  stored <- adata$obsm[["df"]]
  expect_s4_class(stored, "DataFrame")
  expect_identical(rownames(stored), c("a", "b", "c"))
  expect_identical(names(stored), c("a", "b"))
  adata$varm[["df"]] <- S4Vectors::DataFrame(
    z = c(1, 2),
    row.names = c("x", "y")
  )
  expect_s4_class(adata$varm[["df"]], "DataFrame")
  # wrong names, wrong order, automatic row names and wrong length all fail
  for (bad in list(
    data.frame(a = 1:3, row.names = c("a", "b", "z")),
    data.frame(a = 1:3, row.names = c("c", "b", "a")),
    data.frame(a = 1:3),
    data.frame(a = 1:2, row.names = c("a", "b"))
  )) {
    expect_anndata_condition(
      adata$obsm[["bad"]] <- bad,
      "anndata_names_mismatch_error"
    )
  }
})

# Python sets the value's index name to the parent's index name
test_that("a stored data frame takes the index name of the parent", {
  obs <- data.frame(row.names = c("a", "b", "c"))
  attr(obs, "index_name") <- "cell"
  adata <- AnnData(matrix(0, 3, 2), obs = obs)
  adata$obsm[["df"]] <- data.frame(a = 1:3, row.names = c("a", "b", "c"))
  expect_identical(
    S4Vectors::metadata(adata$obsm[["df"]])[["index_name"]],
    "cell"
  )
})

# The constructor takes the same arguments and infers the shape from them
test_that("the constructor accepts obsm, varm, obsp and varp", {
  adata <- AnnData(
    matrix(0, 3, 2),
    obsm = list(a = matrix(0, 3, 2)),
    varm = list(b = matrix(0, 2, 4)),
    obsp = list(c = csc(3, 3)),
    varp = list(d = matrix(0, 2, 2))
  )
  expect_identical(names(adata$obsm), "a")
  expect_identical(names(adata$varm), "b")
  expect_identical(names(adata$obsp), "c")
  expect_identical(names(adata$varp), "d")
  inferred <- AnnData(
    obsm = list(a = matrix(0, 4, 1)),
    varp = list(p = csc(5, 5))
  )
  expect_identical(inferred$shape, c(4L, 5L))
  expect_anndata_condition(
    AnnData(matrix(0, 3, 2), obsm = list(a = matrix(0, 4, 1))),
    "anndata_dimension_error"
  )
  expect_anndata_condition(
    AnnData(matrix(0, 3, 2), varp = list(a = matrix(0, 3, 3))),
    "anndata_dimension_error"
  )
})

# A mapping from another object can be assigned, remove() works and keys
# named like methods are reachable with [[ (while $ prefers the key)
test_that("mappings can be copied between objects and keys may match methods", {
  a <- make_adata(obsm = list(k = matrix(1, 3, 1)))
  b <- make_adata()
  b$obsm <- a$obsm
  expect_identical(b$obsm[["k"]], a$obsm[["k"]])
  b$obsm$remove("k")
  expect_length(b$obsm, 0L)
  expect_length(a$obsm, 1L)
  b$obsm[["get"]] <- matrix(2, 3, 1)
  expect_identical(b$obsm[["get"]], matrix(2, 3, 1))
  expect_identical(b$obsm$get, matrix(2, 3, 1))
})

# Python's repr of the mapping classes
test_that("mappings print like Python's repr", {
  adata <- make_adata(obsm = list(a = matrix(0, 3, 1), b = matrix(0, 3, 1)))
  expect_output(
    print(adata$obsm),
    "AxisArrays with keys: 'a', 'b'",
    fixed = TRUE
  )
  expect_output(print(adata$obsp), "PairwiseArrays with keys: ", fixed = TRUE)
})
