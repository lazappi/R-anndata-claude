subset_adata <- function() {
  AnnData(
    matrix(as.numeric(1:12), 4, 3),
    obs = list(
      obs_names = c("a", "b", "c", "d"),
      g = factor(c("x", "y", "z", "x"), levels = c("x", "y", "z"))
    ),
    var = list(var_names = c("v1", "v2", "v3"), n = c(10, 20, 30)),
    uns = list(note = "kept", g_colors = c("red", "green", "blue")),
    obsm = list(emb = matrix(as.numeric(1:8), 4, 2)),
    varm = list(load = matrix(as.numeric(1:6), 3, 2)),
    obsp = list(dist = matrix(as.numeric(1:16), 4, 4)),
    varp = list(cor = matrix(as.numeric(1:9), 3, 3)),
    layers = list(counts = matrix(as.numeric(101:112), 4, 3)),
    raw = list(
      X = matrix(as.numeric(1:20), 4, 5),
      var = list(var_names = paste0("r", 1:5)),
      varm = list(rl = matrix(as.numeric(1:10), 5, 2))
    )
  )
}

# Every Slot follows the spec: obs-side Slots on i, var-side on j, uns whole,
# raw on observations only
test_that("subsetting restricts each Slot on the right axes", {
  adata <- subset_adata()
  sub <- adata[c(3, 1), c(2, 3)]
  expect_identical(sub$obs_names, c("c", "a"))
  expect_identical(sub$var_names, c("v2", "v3"))
  expect_identical(sub$X, adata$X[c(3, 1), c(2, 3)])
  expect_identical(
    sub$layers[["counts"]],
    adata$layers[["counts"]][c(3, 1), 2:3]
  )
  expect_identical(sub$obs$g, droplevels(adata$obs$g[c(3, 1)]))
  expect_identical(sub$var$n, c(20, 30))
  expect_identical(sub$obsm[["emb"]], adata$obsm[["emb"]][c(3, 1), ])
  expect_identical(sub$varm[["load"]], adata$varm[["load"]][2:3, ])
  expect_identical(sub$obsp[["dist"]], adata$obsp[["dist"]][c(3, 1), c(3, 1)])
  expect_identical(sub$varp[["cor"]], adata$varp[["cor"]][2:3, 2:3])
  expect_identical(sub$uns$note, "kept")
  expect_identical(sub$raw$shape, c(2L, 5L))
  expect_identical(sub$raw$X, adata$raw$X[c(3, 1), ])
  expect_identical(sub$raw$var_names, paste0("r", 1:5))
  expect_identical(sub$raw$varm[["rl"]], adata$raw$varm[["rl"]])
  expect_identical(adata$shape, c(4L, 3L))
})

# Index kinds follow R semantics on each axis
test_that("positive, negative, logical and character indices work", {
  adata <- subset_adata()
  expect_identical(adata[c(2, 2, 1), ]$obs_names, c("b", "b", "a"))
  expect_identical(adata[-1, ]$obs_names, c("b", "c", "d"))
  expect_identical(adata[c(TRUE, FALSE, FALSE, TRUE), ]$obs_names, c("a", "d"))
  expect_identical(adata[c("d", "a"), ]$obs_names, c("d", "a"))
  expect_identical(adata[, 2]$var_names, "v2")
  expect_identical(adata[, -2]$var_names, c("v1", "v3"))
  expect_identical(adata[, c(FALSE, TRUE, TRUE)]$var_names, c("v2", "v3"))
  expect_identical(adata[, c("v3", "v1")]$var_names, c("v3", "v1"))
  expect_identical(adata[2:3]$shape, c(2L, 3L))
  expect_identical(adata[1:4, 1:3]$shape, c(4L, 3L))
})

# Dimensions are never dropped, even for a single observation and variable
test_that("subsetting never drops dimensions", {
  sub <- subset_adata()[1, 1]
  expect_s3_class(sub, "AnnData")
  expect_identical(sub$shape, c(1L, 1L))
  expect_identical(dim(sub$X), c(1L, 1L))
})

# Spec: duplicated names match the first occurrence
test_that("duplicate names match the first occurrence", {
  adata <- suppressWarnings(
    AnnData(
      matrix(as.numeric(1:6), 3, 2),
      obs = list(obs_names = c("a", "a", "b"))
    )
  )
  sub <- adata["a", ]
  expect_identical(sub$X, adata$X[1, , drop = FALSE])
})

# Invalid indices error with the index class
test_that("invalid indices raise anndata_index_error", {
  adata <- subset_adata()
  expect_anndata_condition(adata["zzz", ], "anndata_index_error")
  expect_anndata_condition(adata[5, ], "anndata_index_error")
  expect_anndata_condition(adata[NA_integer_, ], "anndata_index_error")
  expect_anndata_condition(adata[c(1, -2), ], "anndata_index_error")
  expect_anndata_condition(adata[, c(TRUE, FALSE)], "anndata_index_error")
})

# The result must be independent of the original (spec: MVP copy semantics)
test_that("the subset is independent of the original", {
  adata <- subset_adata()
  sub <- adata[1:2, ]
  sub$X <- matrix(0, 2, 3)
  expect_identical(adata$X, matrix(as.numeric(1:12), 4, 3))
})

# Sparse format is preserved by subsetting
test_that("sparse matrices stay sparse", {
  adata <- AnnData(Matrix::rsparsematrix(5, 4, 0.5))
  sub <- adata[2:3, ]
  expect_s4_class(sub$X, class(adata$X))
  expect_identical(dim(sub$X), c(2L, 4L))
})

# Unused categories are removed and the colors follow, when the setting is on
test_that("unused categories and their colors are subset", {
  sub <- subset_adata()[c(1, 4), ]
  expect_identical(levels(sub$obs$g), "x")
  expect_identical(sub$uns$g_colors, "red")
  sub <- subset_adata()[c(2, 3), ]
  expect_identical(levels(sub$obs$g), c("y", "z"))
  expect_identical(sub$uns$g_colors, c("green", "blue"))
})

# Colors of the wrong length are dropped, as in Python
test_that("colors that do not match the categories are removed", {
  adata <- subset_adata()
  adata$uns[["g_colors"]] <- c("red", "green")
  expect_null(adata[1, ]$uns$g_colors)
})

# With the setting off every level is kept and colors are untouched
test_that("categories are kept when remove_unused_categories is off", {
  old <- get_setting("remove_unused_categories")
  set_setting("remove_unused_categories", FALSE)
  withr::defer(set_setting("remove_unused_categories", old))
  sub <- subset_adata()[1, ]
  expect_identical(levels(sub$obs$g), c("x", "y", "z"))
  expect_identical(sub$uns$g_colors, c("red", "green", "blue"))
})

# Raw subsetting reuses the index logic and keeps the raw variables
test_that("Raw subsetting accepts R indices", {
  raw <- subset_adata()$raw
  sub <- raw[c("c", "a"), c("r2", "r4")]
  expect_identical(sub$obs_names, c("c", "a"))
  expect_identical(sub$var_names, c("r2", "r4"))
  expect_identical(sub$shape, c(2L, 2L))
  expect_identical(sub$X, subset_adata()$raw$X[c(3, 1), c(2, 4)])
  expect_identical(
    sub$varm[["rl"]],
    subset_adata()$raw$varm[["rl"]][c(2, 4), ]
  )
  expect_anndata_condition(raw["zzz", ], "anndata_index_error")
  expect_anndata_condition(raw[, 9], "anndata_index_error")
})

# On-disk dtype records must survive subsetting in every array Slot
test_that("dtype records are preserved", {
  tag <- function(x) {
    attr(x, "anndata_dtype") <- "float32"
    x
  }
  adata <- AnnData(
    tag(matrix(as.numeric(1:6), 3, 2)),
    obsm = list(emb = tag(matrix(as.numeric(1:6), 3, 2))),
    obsp = list(dist = tag(matrix(as.numeric(1:9), 3, 3))),
    layers = list(l = tag(matrix(as.numeric(1:6), 3, 2)))
  )
  sub <- adata[2:3, 1]
  for (value in list(
    sub$X,
    sub$obsm[["emb"]],
    sub$obsp[["dist"]],
    sub$layers[["l"]]
  )) {
    expect_identical(attr(value, "anndata_dtype"), "float32")
  }
})

# Indices on the variable axis and degenerate selections
test_that("variable indices, empty and repeated selections behave", {
  adata <- subset_adata()
  expect_anndata_condition(adata[, "zzz"], "anndata_index_error")
  expect_anndata_condition(adata[, 4], "anndata_index_error")
  expect_anndata_condition(adata[, 0], "anndata_index_error")
  expect_anndata_condition(adata[1.5, ], "anndata_index_error")
  expect_identical(adata[integer(0), ]$shape, c(0L, 3L))
  expect_identical(adata[c(1, 1), ]$obs_names, c("a", "a"))
  expect_identical(adata[]$shape, c(4L, 3L))
})

# Category removal and colors apply to var columns as well
test_that("var categories and var colors are subset", {
  adata <- AnnData(
    matrix(0, 2, 3),
    var = list(
      var_names = c("a", "b", "c"),
      k = factor(c("p", "q", "r"))
    ),
    uns = list(k_colors = c("red", "green", "blue"))
  )
  sub <- adata[, c(1, 3)]
  expect_identical(levels(sub$var$k), c("p", "r"))
  expect_identical(sub$uns$k_colors, c("red", "blue"))
})
