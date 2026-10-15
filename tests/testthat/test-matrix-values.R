dense <- matrix(c(0, 1, 0, 2, 0, 3), nrow = 2)

csc <- function() {
  methods::as(Matrix::Matrix(dense, sparse = TRUE), "CsparseMatrix")
}
csr <- function() methods::as(csc(), "RsparseMatrix")
lcsc <- function() methods::as(csc() > 0, "CsparseMatrix")

# The On-disk dtype record is only a test double until h5ad-io defines it
with_dtype <- function(x, dtype = "float32") {
  attr(x, "anndata_dtype") <- dtype
  x
}

# Accepted classes must pass through unchanged so values are never copied or
# altered needlessly
test_that("accepted classes round-trip unchanged", {
  accepted <- list(
    dense,
    matrix(1:6, nrow = 2),
    matrix(c(TRUE, FALSE), nrow = 2, ncol = 3),
    csc(),
    csr(),
    lcsc(),
    methods::as(lcsc(), "RsparseMatrix")
  )
  for (x in accepted) {
    expect_identical(as_anndata_matrix(x), x)
  }
})

# Spec: other Matrix classes are coerced, sparse to CSC and dense to base
test_that("other Matrix classes are coerced to the documented target", {
  expect_s4_class(
    as_anndata_matrix(methods::as(csc(), "TsparseMatrix")),
    "dgCMatrix"
  )
  expect_s4_class(
    as_anndata_matrix(methods::as(lcsc(), "TsparseMatrix")),
    "lgCMatrix"
  )
  expect_s4_class(
    as_anndata_matrix(methods::as(csc() != 0, "nMatrix")),
    "lgCMatrix"
  )
  sym <- methods::as(Matrix::crossprod(csc()), "symmetricMatrix")
  expect_s4_class(as_anndata_matrix(sym), "dgCMatrix")
  expect_identical(
    as_anndata_matrix(Matrix::Matrix(dense, sparse = FALSE)),
    dense
  )
  expect_identical(
    as_anndata_matrix(Matrix::Matrix(dense > 0, sparse = FALSE)),
    dense > 0
  )
})

test_that("coercion keeps the dtype record", {
  x <- with_dtype(methods::as(csc(), "TsparseMatrix"))
  expect_identical(attr(as_anndata_matrix(x), "anndata_dtype"), "float32")
})

# Spec: obsm, varm and layers may hold arrays with 2 or more dimensions
test_that("arrays need allow_array", {
  arr <- array(1:24, dim = c(2, 3, 4))
  expect_identical(as_anndata_matrix(arr, allow_array = TRUE), arr)
  expect_anndata_condition(
    as_anndata_matrix(arr),
    "anndata_unsupported_value_error"
  )
})

test_that("unsupported values error with a classed condition", {
  bad <- list(
    "a",
    NULL,
    1:3,
    matrix(letters[1:4], 2),
    data.frame(a = 1:2),
    list(1, 2),
    matrix(1i, 2, 2)
  )
  for (x in bad) {
    expect_anndata_condition(
      as_anndata_matrix(x),
      "anndata_unsupported_value_error"
    )
  }
})

test_that("subsetting rows, columns and both keeps format and dtype", {
  for (x in list(dense, csc(), csr(), lcsc())) {
    x <- with_dtype(x)
    by_row <- matrix_subset(x, i = 2:1)
    by_col <- matrix_subset(x, j = c(3, 1, 1))
    both <- matrix_subset(x, i = 2, j = 2:3)
    for (res in list(by_row, by_col, both)) {
      expect_identical(class(drop_dtype(res)), class(drop_dtype(x)))
      expect_identical(attr(res, "anndata_dtype"), "float32")
    }
    expect_identical(dim(by_row), c(2L, 3L))
    expect_identical(dim(by_col), c(2L, 3L))
    expect_identical(dim(both), c(1L, 2L))
  }
  expect_identical(
    as.matrix(matrix_subset(csr(), i = 2, j = 2:3)),
    dense[2, 2:3, drop = FALSE]
  )
})

test_that("arrays subset on the first two dimensions", {
  arr <- with_dtype(array(1:24, dim = c(2, 3, 4)))
  res <- matrix_subset(arr, i = 2, j = c(1, 3))
  expect_identical(dim(res), c(1L, 2L, 4L))
  expect_identical(attr(res, "anndata_dtype"), "float32")
  expect_identical(
    matrix_subset(arr, i = 2)[1, , ],
    arr[2, , ]
  )
})

test_that("transposing keeps format and dtype", {
  for (x in list(dense, csc(), csr(), lcsc())) {
    res <- matrix_transpose(with_dtype(x))
    expect_identical(class(drop_dtype(res)), class(drop_dtype(x)))
    expect_identical(dim(res), c(3L, 2L))
    expect_identical(attr(res, "anndata_dtype"), "float32")
    expect_equal(
      as.vector(as.matrix(res)),
      as.vector(t(as.matrix(x)))
    )
  }
  arr <- array(1:24, dim = c(2, 3, 4))
  expect_identical(dim(matrix_transpose(arr)), c(3L, 2L, 4L))
  expect_identical(matrix_transpose(arr)[3, 2, 4], arr[2, 3, 4])
})

test_that("matrix_dim reports dimensions for every kind", {
  expect_identical(matrix_dim(dense), c(2L, 3L))
  expect_identical(matrix_dim(csr()), c(2L, 3L))
  expect_identical(matrix_dim(array(0, c(2, 3, 4))), c(2L, 3L, 4L))
})
