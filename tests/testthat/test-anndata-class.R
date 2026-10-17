dense_x <- matrix(as.numeric(1:6), nrow = 3)
csc_x <- function() {
  methods::as(Matrix::Matrix(dense_x, sparse = TRUE), "CsparseMatrix")
}
csr_x <- function() methods::as(csc_x(), "RsparseMatrix")

# Each accepted matrix type must construct and be returned by `$X` unchanged
test_that("construction from each matrix type keeps X and its format", {
  lcsc <- methods::as(csc_x() > 0, "CsparseMatrix")
  for (x in list(
    dense_x,
    matrix(1:6, nrow = 3),
    matrix(c(TRUE, FALSE), nrow = 3, ncol = 2),
    csc_x(),
    csr_x(),
    lcsc,
    methods::as(lcsc, "RsparseMatrix")
  )) {
    adata <- AnnData(x)
    expect_s3_class(adata, "AnnData")
    expect_identical(adata$X, x)
    expect_identical(adata$shape, c(3L, 2L))
    expect_identical(adata$n_obs, 3L)
    expect_identical(adata$n_vars, 2L)
  }
})

# Python names observations "0"..."n-1" by default and files must match
test_that("default names are 0 to n-1", {
  adata <- AnnData(dense_x)
  expect_identical(adata$obs_names, c("0", "1", "2"))
  expect_identical(adata$var_names, c("0", "1"))
  expect_s4_class(adata$obs, "DataFrame")
  expect_s4_class(adata$var, "DataFrame")
  expect_identical(nrow(adata$obs), 3L)
})

# obs and var go through the annotation frame helpers
test_that("obs and var are built from lists and data frames", {
  adata <- AnnData(
    dense_x,
    obs = list(type = c("a", "b", "c"), obs_names = c("c1", "c2", "c3")),
    var = data.frame(id = c("g1", "g2"), row.names = c("x", "y"))
  )
  expect_identical(adata$obs_names, c("c1", "c2", "c3"))
  expect_identical(adata$var_names, c("x", "y"))
  expect_identical(names(adata$obs), "type")
  expect_identical(names(adata$var), "id")
})

# Shape-only objects have no X
test_that("NULL X with shape gives an object without X", {
  adata <- AnnData(shape = c(4L, 5L))
  expect_null(adata$X)
  expect_identical(adata$shape, c(4L, 5L))
  expect_identical(adata$obs_names, as.character(0:3))
  expect_identical(adata$var_names, as.character(0:4))
  # whole numbers given as doubles are fine
  expect_identical(AnnData(shape = c(2, 3))$shape, c(2L, 3L))
})

# Python infers the shape from obs and var when neither X nor shape is given
test_that("shape is inferred from obs and var", {
  # a data frame with automatic row names warns, as Python does for RangeIndex
  expect_anndata_condition(
    AnnData(obs = data.frame(a = 1:3)),
    "anndata_implicit_modification_warning"
  )
  adata <- suppressWarnings(AnnData(
    obs = data.frame(a = 1:3),
    var = list(b = c("x", "y"))
  ))
  expect_identical(adata$shape, c(3L, 2L))
  expect_null(adata$X)
  expect_identical(AnnData()$shape, c(0L, 0L))
})

# The inference helper walks the slots in Python's order, and the constructor
# cannot yet be given those slots
test_that("shape inference follows Python's order across slots", {
  m <- function(n, p) matrix(0, n, p)
  expect_identical(
    infer_shape(obs = data.frame(a = 1:3), var = NULL),
    c(3L, NA_integer_)
  )
  expect_identical(
    infer_shape(obsm = list(a = m(4, 2)), varm = list(b = m(5, 2))),
    c(4L, 5L)
  )
  expect_identical(
    infer_shape(layers = list(l = m(6, 7))),
    c(6L, 7L)
  )
  expect_identical(
    infer_shape(obsp = list(p = m(3, 3)), varp = list(p = m(2, 2))),
    c(3L, 2L)
  )
  # a data frame wins over the mappings
  expect_identical(
    infer_shape(obs = data.frame(a = 1:2), layers = list(l = m(6, 7))),
    c(2L, 7L)
  )
  expect_identical(infer_shape(), c(NA_integer_, NA_integer_))
})

# Spec: shape and X together is an error
test_that("giving shape and X is an error", {
  expect_anndata_condition(
    AnnData(dense_x, shape = c(3L, 2L)),
    "anndata_invalid_argument_error"
  )
})

test_that("invalid shape is an error", {
  for (shape in list(1:3, c(1.5, 2), c(-1L, 2L), c(NA, 2L), "a")) {
    expect_anndata_condition(
      AnnData(shape = shape),
      "anndata_invalid_argument_error"
    )
  }
})

# obs and var lengths must agree with the shape
test_that("length mismatches raise dimension errors", {
  expect_anndata_condition(
    AnnData(dense_x, obs = list(a = 1:2)),
    "anndata_dimension_error"
  )
  expect_anndata_condition(
    AnnData(dense_x, var = data.frame(a = 1:3)),
    "anndata_dimension_error"
  )
  expect_anndata_condition(
    AnnData(shape = c(3L, 2L), obs = list(a = 1:2)),
    "anndata_dimension_error"
  )
})

test_that("non-character names warn about implicit modification", {
  expect_anndata_condition(
    AnnData(dense_x, obs = list(obs_names = 1:3)),
    "anndata_implicit_modification_warning"
  )
})

test_that("unsupported X values error by class", {
  expect_anndata_condition(
    AnnData(letters),
    "anndata_unsupported_value_error"
  )
  expect_anndata_condition(
    AnnData(matrix(letters[1:6], 3)),
    "anndata_unsupported_value_error"
  )
})

# Python warns after construction when names repeat
test_that("duplicate names warn when check_uniqueness is on", {
  dup <- list(obs_names = c("a", "a", "b"))
  expect_anndata_condition(
    AnnData(dense_x, obs = dup),
    "anndata_names_not_unique_warning"
  )
  expect_anndata_condition(
    AnnData(dense_x, var = list(var_names = c("g", "g"))),
    "anndata_names_not_unique_warning"
  )
  # NA names are ignored
  expect_no_warning(
    AnnData(dense_x, obs = list(obs_names = c("a", NA, NA)))
  )
  local_anndata_settings(list(check_uniqueness = FALSE))
  expect_no_warning(AnnData(dense_x, obs = dup))
})

# Backed mode belongs to a later sub-project
test_that("filename and filemode are not yet supported", {
  expect_anndata_condition(
    AnnData(dense_x, filename = "a.h5ad"),
    "anndata_not_supported_error"
  )
  expect_anndata_condition(
    AnnData(dense_x, filemode = "r"),
    "anndata_not_supported_error"
  )
})

# Python makes everything after uns keyword-only
test_that("arguments after uns must be named", {
  expect_error(AnnData(dense_x, NULL, NULL, NULL, list()))
  expect_error(AnnData(dense_x, bogus = 1))
})

test_that("fixed read-only fields have their Python values", {
  adata <- AnnData(dense_x)
  expect_false(adata$is_view)
  expect_false(adata$isbacked)
  expect_null(adata$filename)
  for (field in c(
    "n_obs",
    "n_vars",
    "shape",
    "is_view",
    "isbacked"
  )) {
    expect_anndata_condition(
      adata[[field]] <- 1L,
      "anndata_read_only_error"
    )
  }
})

# X is stored in layers under the NA key (ADR 0004), so the internal storage
# must hold it there for ticket 06 to extend
test_that("X lives in the layers storage under the NA key", {
  adata <- AnnData(dense_x)
  store <- as.list(adata$layers)
  expect_identical(names(store), NA_character_)
  expect_identical(store[[1L]], dense_x)
  expect_length(AnnData(shape = c(2L, 2L))$layers, 0L)
})

# X is validated the same way however it is set
test_that("setting X validates its shape and removes it with NULL", {
  adata <- AnnData(dense_x)
  adata$X <- dense_x * 2
  expect_identical(adata$X, dense_x * 2)
  expect_anndata_condition(adata$X <- "a", "anndata_unsupported_value_error")
  adata$X <- csr_x()
  expect_identical(adata$X, csr_x())
  adata$X <- NULL
  expect_null(adata$X)
  expect_identical(adata$shape, c(3L, 2L))
})

# ADR 0002: reference semantics
test_that("assignment aliases the object", {
  a <- AnnData(dense_x)
  b <- a
  b$X <- dense_x + 1
  expect_identical(a$X, dense_x + 1)
  expect_identical(a, b)
})

# On-disk dtype records must survive being held by the object
test_that("the on-disk dtype record is kept on X", {
  x <- dense_x
  attr(x, "anndata_dtype") <- "float32"
  expect_identical(attr(AnnData(x)$X, "anndata_dtype"), "float32")
})

# Python's X setter: a scalar fills the matrix with a FutureWarning
test_that("a scalar X fills the matrix and warns", {
  adata <- AnnData(shape = c(3L, 2L))
  expect_anndata_condition(adata$X <- 5, "anndata_future_warning")
  suppressWarnings(adata$X <- 5)
  expect_identical(adata$X, matrix(5, 3, 2))
  suppressWarnings(adata$X <- 2L)
  expect_identical(adata$X, matrix(2L, 3, 2))
})

# Python reshapes (C order) any 2-D or 1-D value of the right size, with a
# FutureWarning, so a vector fits a single row or column
test_that("a value of the right size is reshaped with a warning", {
  adata <- AnnData(shape = c(3L, 1L))
  expect_anndata_condition(adata$X <- c(1, 2, 3), "anndata_future_warning")
  suppressWarnings(adata$X <- c(1, 2, 3))
  expect_identical(adata$X, matrix(c(1, 2, 3), 3, 1))

  adata <- AnnData(shape = c(1L, 2L))
  suppressWarnings(adata$X <- matrix(c(1, 2), 2, 1))
  expect_identical(adata$X, matrix(c(1, 2), 1, 2))

  # numpy: arange(6).reshape(2, 3) set on shape (3, 2) is [[0,1],[2,3],[4,5]]
  adata <- AnnData(shape = c(3L, 2L))
  value <- matrix(0:5, 2, 3, byrow = TRUE)
  expect_anndata_condition(adata$X <- value, "anndata_future_warning")
  suppressWarnings(adata$X <- value)
  expect_identical(adata$X, matrix(0:5, 3, 2, byrow = TRUE))
})

# Python raises after the reshape warning when sizes differ or the value is
# sparse
test_that("values that cannot be reshaped error", {
  adata <- AnnData(dense_x)
  expect_anndata_condition(
    adata$X <- matrix(0, 2, 2),
    "anndata_future_warning"
  )
  for (value in list(matrix(0, 2, 2), c(1, 2, 3), matrix(0, 3, 1))) {
    expect_anndata_condition(
      suppressWarnings(adata$X <- value),
      "anndata_dimension_error"
    )
  }
  expect_anndata_condition(
    suppressWarnings(adata$X <- Matrix::t(csc_x())),
    "anndata_dimension_error"
  )
  expect_identical(adata$X, dense_x)
})

# Python allows 3-D X with a UserWarning, and refuses to reshape it
test_that("more than 2 dimensions warn or error", {
  adata <- AnnData(dense_x)
  ok <- array(0, c(3, 2, 2))
  expect_anndata_condition(adata$X <- ok, "anndata_non_2d_warning")
  suppressWarnings(adata$X <- ok)
  expect_identical(adata$X, ok)
  expect_anndata_condition(
    adata$X <- array(0, c(2, 3, 2)),
    "anndata_dimension_error"
  )
})

# Python: removing X twice is fine
test_that("NULL X can be assigned repeatedly", {
  adata <- AnnData(dense_x)
  adata$X <- NULL
  expect_no_condition(adata$X <- NULL)
  expect_null(adata$X)
})

# The sparse format and dtype record must survive assignment
test_that("assigning keeps the sparse format and dtype record", {
  adata <- AnnData(shape = c(3L, 2L))
  for (x in list(csc_x(), csr_x())) {
    adata$X <- x
    expect_identical(class(adata$X), class(x))
  }
  x <- matrix(0, 3, 2)
  attr(x, "anndata_dtype") <- "float32"
  adata$X <- x
  expect_identical(attr(adata$X, "anndata_dtype"), "float32")
})
