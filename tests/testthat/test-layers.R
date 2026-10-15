layer_adata <- function(...) {
  AnnData(matrix(as.numeric(1:6), 2, 3), ...)
}
lay <- function(v = 0) matrix(v, 2, 3)

# Python 0.13.4 puts X last when X is given with layers (confirmed by oracle)
test_that("key order follows Python for several constructions", {
  adata <- layer_adata(layers = list(a = lay()))
  expect_identical(names(adata$layers), c("a", NA))
  adata$layers[["c"]] <- lay()
  expect_identical(names(adata$layers), c("a", NA, "c"))
  adata$X <- NULL
  expect_identical(names(adata$layers), c("a", "c"))
  adata$X <- lay(1)
  expect_identical(names(adata$layers), c("a", "c", NA))
  adata$layers[["a"]] <- lay(2)
  expect_identical(names(adata$layers), c("a", "c", NA))
  # No X gives no NA key, and an NA entry in layers supplies X in input order
  expect_identical(
    names(
      AnnData(shape = c(2L, 3L), layers = list(a = lay(), b = lay()))$layers
    ),
    c("a", "b")
  )
  x <- lay(3)
  adata <- AnnData(layers = setNames(list(x, lay()), c(NA, "a")))
  expect_identical(names(adata$layers), c(NA, "a"))
  expect_identical(adata$X, x)
  expect_identical(adata$shape, c(2L, 3L))
})

# Both spellings of the NA key address X (ADR 0004)
test_that("NA and NA_character_ address X", {
  adata <- layer_adata()
  expect_identical(adata$layers[[NA]], adata$X)
  expect_identical(adata$layers[[NA_character_]], adata$X)
  adata$layers[[NA]] <- lay(5)
  expect_identical(adata$X, lay(5))
  adata$layers[[NA_character_]] <- NULL
  expect_null(adata$X)
  expect_false(NA %in% names(adata$layers))
  expect_length(adata$layers, 0L)
})

# Constructor rules for layers[None] and X
test_that("constructor handles an NA layer together with X or shape", {
  x <- lay(1)
  adata <- AnnData(x, layers = setNames(list(x), NA))
  expect_identical(names(adata$layers), NA_character_)
  expect_anndata_condition(
    AnnData(x, layers = setNames(list(lay(2)), NA)),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    AnnData(layers = setNames(list(x), NA), shape = c(2L, 3L)),
    "anndata_invalid_argument_error"
  )
})

# Python raises ValueError for wrong shapes, with no X-style reshape. A 1-D
# value becomes a column first (aligned_mapping.py:78), so it only fits n x 1
test_that("one column data accepts a vector layer", {
  adata <- AnnData(matrix(1:2 + 0, 2, 1))
  adata$layers[["k"]] <- c(5, 6)
  expect_identical(adata$layers[["k"]], matrix(c(5, 6), 2, 1))
})

# Wrong shapes error for named layers and for X, and vectors are not reshaped
test_that("wrong shapes error and vectors are not reshaped", {
  adata <- layer_adata()
  for (key in list("k", NA)) {
    expect_anndata_condition(
      adata$layers[[key]] <- matrix(0, 3, 3),
      "anndata_dimension_error"
    )
    expect_anndata_condition(
      adata$layers[[key]] <- c(1, 2, 3),
      "anndata_dimension_error"
    )
  }
  expect_anndata_condition(
    layer_adata(layers = list(a = matrix(0, 3, 3))),
    "anndata_dimension_error"
  )
})

# More than 2 dimensions warns for named layers only, X warns in its setter
test_that("non-2-D layers warn except under the NA key", {
  adata <- layer_adata()
  arr <- array(0, c(2, 3, 2))
  expect_anndata_condition(
    adata$layers[["k"]] <- arr,
    "anndata_non_2d_warning"
  )
  expect_no_warning(adata$layers[[NA]] <- arr)
  expect_anndata_condition(adata$X <- arr, "anndata_non_2d_warning")
})

# Python converts data frames to arrays in layers
test_that("data frames become matrices in layers", {
  adata <- layer_adata()
  adata$layers[["d"]] <- as.data.frame(lay(1))
  expect_true(is.matrix(adata$layers[["d"]]))
  expect_identical(dim(adata$layers[["d"]]), c(2L, 3L))
})

# Replacing layers keeps X with Python's FutureWarning unless NA is given
test_that("assigning layers keeps X and warns unless NA is explicit", {
  adata <- layer_adata(layers = list(a = lay()))
  x <- adata$X
  # expect_warning (not a tryCatch) so that the assignment completes
  expect_warning(
    adata$layers <- list(b = lay(1)),
    class = "anndata_future_warning"
  )
  expect_identical(names(adata$layers), c("b", NA))
  expect_identical(adata$X, x)
  expect_warning(adata$layers <- list(), class = "anndata_future_warning")
  expect_identical(names(adata$layers), NA_character_)
  expect_warning(adata$layers <- NULL, class = "anndata_future_warning")
  expect_identical(adata$X, x)
  # An explicit NA entry silences the warning, and NULL drops X
  new_x <- lay(9)
  expect_no_warning(
    adata$layers <- setNames(list(lay(1), new_x), c("b", NA))
  )
  expect_identical(names(adata$layers), c("b", NA))
  expect_identical(adata$X, new_x)
  expect_no_warning(adata$layers <- setNames(list(lay(1), NULL), c("b", NA)))
  expect_identical(names(adata$layers), "b")
  expect_null(adata$X)
  expect_no_warning(adata$layers <- list(c = lay(2)))
  expect_identical(names(adata$layers), "c")
})

# clear() keeps X with a warning by default, and keep_x controls it
test_that("clear follows Python's keep_x behaviour", {
  adata <- layer_adata(layers = list(a = lay()))
  expect_warning(adata$layers$clear(), class = "anndata_future_warning")
  expect_identical(names(adata$layers), NA_character_)
  adata$layers[["a"]] <- lay()
  expect_no_warning(adata$layers$clear(keep_x = TRUE))
  expect_identical(names(adata$layers), NA_character_)
  adata$layers[["a"]] <- lay()
  expect_no_warning(adata$layers$clear(keep_x = FALSE))
  expect_length(adata$layers, 0L)
  expect_null(adata$X)
  expect_anndata_condition(
    adata$layers$clear(keep_x = "yes"),
    "anndata_invalid_argument_error"
  )
})

# X and layers[[NA]] are one storage, and layers keep reference semantics
test_that("layers alias X and are shared through aliases", {
  a <- layer_adata()
  b <- a
  b$layers[["k"]] <- lay(4)
  expect_identical(a$layers[["k"]], lay(4))
  expect_identical(as.list(a$layers)[[1L]], a$X)
})
