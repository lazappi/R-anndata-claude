copy_adata <- function() {
  AnnData(
    matrix(as.numeric(1:6), 3, 2),
    obs = list(obs_names = c("a", "b", "c"), g = c(1, 2, 3)),
    var = list(var_names = c("v1", "v2"), n = c(10, 20)),
    uns = list(note = "kept"),
    obsm = list(emb = matrix(as.numeric(1:6), 3, 2)),
    varm = list(load = matrix(as.numeric(1:4), 2, 2)),
    obsp = list(dist = matrix(as.numeric(1:9), 3, 3)),
    varp = list(cor = matrix(as.numeric(1:4), 2, 2)),
    layers = list(counts = matrix(as.numeric(11:16), 3, 2)),
    raw = list(X = matrix(as.numeric(1:9), 3, 3))
  )
}

# Reference semantics (ADR 0002): `b <- a` aliases, `copy()` does not
test_that("assignment aliases and copy() is independent", {
  a <- copy_adata()
  b <- a
  b$uns[["new"]] <- 1
  expect_identical(a$uns[["new"]], 1)
  cp <- a$copy()
  cp$X <- matrix(0, 3, 2)
  cp$obs$g <- c(9, 9, 9)
  cp$uns[["other"]] <- 2
  cp$raw$X <- matrix(0, 3, 3)
  expect_identical(a$X, matrix(as.numeric(1:6), 3, 2))
  expect_identical(a$obs$g, c(1, 2, 3))
  expect_null(a$uns[["other"]])
  expect_identical(a$raw$X, matrix(as.numeric(1:9), 3, 3))
})

# copy() must keep every Slot, including the raw and X under the NA key
test_that("copy() keeps every Slot", {
  a <- copy_adata()
  cp <- a$copy()
  expect_identical(cp$X, a$X)
  expect_identical(cp$obs_names, a$obs_names)
  expect_identical(cp$var$n, a$var$n)
  expect_identical(cp$layers[["counts"]], a$layers[["counts"]])
  expect_identical(cp$obsm[["emb"]], a$obsm[["emb"]])
  expect_identical(cp$varp[["cor"]], a$varp[["cor"]])
  expect_identical(cp$uns, a$uns)
  expect_identical(cp$raw$X, a$raw$X)
  expect_identical(cp$raw$var_names, a$raw$var_names)
  expect_null(AnnData(shape = c(2, 2))$copy()$raw)
})

# Backed mode is not supported yet, so a filename must error
test_that("copy() with a filename is not supported", {
  expect_anndata_condition(
    copy_adata()$copy(filename = "x.h5ad"),
    "anndata_not_supported_error"
  )
})

# transpose swaps the axes and their Slots, drops raw and keeps uns
test_that("transpose swaps obs and var and their Slots", {
  a <- copy_adata()
  tr <- a$transpose()
  expect_identical(tr$shape, c(2L, 3L))
  expect_identical(tr$obs_names, a$var_names)
  expect_identical(tr$var_names, a$obs_names)
  expect_identical(tr$X, t(a$X))
  expect_identical(tr$layers[["counts"]], t(a$layers[["counts"]]))
  expect_identical(tr$obs$n, a$var$n)
  expect_identical(tr$var$g, a$obs$g)
  expect_identical(tr$obsm[["load"]], a$varm[["load"]])
  expect_identical(tr$varm[["emb"]], a$obsm[["emb"]])
  expect_identical(tr$obsp[["cor"]], a$varp[["cor"]])
  expect_identical(tr$varp[["dist"]], a$obsp[["dist"]])
  expect_identical(tr$uns, a$uns)
  expect_null(tr$raw)
  expect_identical(t(a)$shape, c(2L, 3L))
  expect_identical(tr$transpose()$X, a$X)
})

# Without X the shape must still swap
test_that("transpose works without X", {
  expect_identical(AnnData(shape = c(3, 2))$transpose()$shape, c(2L, 3L))
})

# Index names live on the frames and must swap with them
test_that("copy and transpose keep index names", {
  a <- AnnData(
    matrix(1, 2, 2),
    obs = list(cell = c("a", "b")),
    var = list(gene = c("x", "y"))
  )
  expect_identical(frame_index_name(a$copy()$obs), frame_index_name(a$obs))
  expect_identical(frame_index_name(a$copy()$var), frame_index_name(a$var))
  expect_identical(frame_index_name(t(a)$obs), frame_index_name(a$var))
  expect_identical(frame_index_name(t(a)$var), frame_index_name(a$obs))
})

# Sparse format (CSR stays CSR) and dtype records must survive both
test_that("sparse format and dtype records survive copy and transpose", {
  csr <- methods::as(
    Matrix::sparseMatrix(i = c(1, 2), j = c(1, 3), x = c(1, 2), dims = c(3, 4)),
    "RsparseMatrix"
  )
  csc <- methods::as(csr, "CsparseMatrix")
  attr(csr, "anndata_dtype") <- "float32"
  attr(csc, "anndata_dtype") <- "float32"
  dense <- matrix(as.numeric(1:12), 3, 4)
  attr(dense, "anndata_dtype") <- "int32"
  a <- AnnData(csr, layers = list(csc = csc, dense = dense))
  for (result in list(a$copy(), t(a))) {
    expect_s4_class(result$X, "dgRMatrix")
    expect_s4_class(result$layers[["csc"]], "dgCMatrix")
    expect_identical(attr(result$X, "anndata_dtype"), "float32")
    expect_identical(attr(result$layers[["csc"]], "anndata_dtype"), "float32")
    expect_identical(attr(result$layers[["dense"]], "anndata_dtype"), "int32")
  }
})
