dense_sparse <- matrix(
  c(0, 1, 0, 2, 3, 0, 0, 0, 0, 0, 4, 5),
  3,
  4,
  byrow = TRUE
)

# The 3 x 4 matrix of the fixtures in the requested format, holding `data`
# values and carrying the On-disk dtype record where it differs from the default
sparse_expected <- function(format, data = "float64", record = NULL) {
  matrix <- if (identical(data, "bool")) {
    Matrix::Matrix(dense_sparse != 0, sparse = TRUE)
  } else {
    Matrix::Matrix(dense_sparse, sparse = TRUE)
  }
  matrix <- methods::as(matrix, "generalMatrix")
  matrix <- methods::as(
    matrix,
    if (format == "csr") "RsparseMatrix" else "CsparseMatrix"
  )
  dtypes <- c(
    data = if (data %in% c("float64", "bool")) NA else data,
    record
  )
  dtypes <- dtypes[!is.na(dtypes)]
  if (length(dtypes) > 0L) set_dtype(matrix, dtypes) else matrix
}

sparse_int_dtypes <- c(
  "int8",
  "int16",
  "int32",
  "int64",
  "uint8",
  "uint16",
  "uint32",
  "uint64"
)

# Expected R values for every sparse fixture (an Element at the key `x`)
sparse_cases <- function() {
  csc_wide <- Matrix::sparseMatrix(
    i = c(1, 300, 151),
    j = c(1, 1, 2),
    x = c(1, 2, 3),
    dims = c(300, 2)
  )
  cases <- list()
  for (format in c("csr", "csc")) {
    for (data in c("bool", "float32", "float64", sparse_int_dtypes)) {
      cases[[paste0(format, "_", data)]] <- sparse_expected(format, data)
    }
  }
  empty <- function(dim) {
    methods::new(
      "dgRMatrix",
      Dim = as.integer(dim),
      p = integer(as.integer(dim[[1L]]) + 1L),
      j = integer(),
      x = numeric()
    )
  }
  c(
    cases,
    list(
      csr_array_float64 = sparse_expected("csr"),
      csr_empty = empty(c(3, 4)),
      csr_0_rows = empty(c(0, 4)),
      csr_indices_int64 = sparse_expected(
        "csr",
        record = c(indices = "int64", indptr = "int64")
      ),
      csr_indices_min_dtype = sparse_expected(
        "csr",
        record = c(indices = "uint8")
      ),
      csr_indices_int64_min_dtype = sparse_expected(
        "csr",
        record = c(indices = "uint8", indptr = "int64")
      ),
      csc_indices_int64 = sparse_expected(
        "csc",
        record = c(indices = "int64", indptr = "int64")
      ),
      csc_indices_min_dtype = sparse_expected(
        "csc",
        record = c(indices = "uint8")
      ),
      csc_indices_int64_min_dtype = sparse_expected(
        "csc",
        record = c(indices = "uint8", indptr = "int64")
      ),
      csc_wide = csc_wide,
      csc_wide_min_dtype = set_dtype(csc_wide, c(indices = "uint16"))
    )
  )
}

# Python -> R: every committed sparse fixture reads as the matrix Python holds,
# with the dtypes recorded where they differ from the defaults
test_that("Python-written sparse matrices read as the expected R values", {
  for (name in names(sparse_cases())) {
    expect_identical(
      read_fixture_elem(name),
      sparse_cases()[[name]],
      info = name
    )
  }
})

# R -> R: reading and writing must keep values, classes and dtype records
test_that("sparse matrices round trip through R", {
  for (name in names(sparse_cases())) {
    value <- sparse_cases()[[name]]
    expect_identical(
      read_written(write_fixture_like(value)),
      value,
      info = name
    )
  }
})

# Python -> R -> Python: R must write what Python wrote, dtypes included
test_that("R rewrites every sparse fixture structurally equivalent to Python", {
  skip_if_no_python()
  case_names <- names(sparse_cases())
  written <- character()
  for (name in case_names) {
    written[[name]] <- write_fixture_like(read_fixture_elem(name))
  }
  originals <- fixture_path(file.path("h5ad", paste0(case_names, ".h5")))
  expect_all_equivalent(written, originals)
})

# R -> Python -> R: Python reads what R writes and R reads Python's rewrite as
# the same matrix
test_that("Python reads and rewrites the sparse matrices R writes", {
  skip_if_no_python()
  cases <- sparse_cases()
  written <- character()
  for (name in names(cases)) {
    written[[name]] <- write_fixture_like(cases[[name]])
  }
  rewritten <- python_rewrite(written)
  for (i in seq_along(cases)) {
    expect_identical(
      read_written(rewritten[[i]]),
      cases[[i]],
      info = names(cases)[[i]]
    )
  }
})

# The encoding type follows the storage order, and shape is an int64 pair
test_that("the Encoding type and shape follow the matrix", {
  for (format in c("csr", "csc")) {
    path <- write_fixture_like(sparse_expected(format))
    store <- rhdf5::H5Fopen(path)
    elem <- rhdf5::H5Oopen(store, "x")
    expect_identical(
      read_elem_attr(elem, "encoding-type"),
      paste0(format, "_matrix")
    )
    expect_identical(read_elem_attr(elem, "encoding-version"), "0.1.0")
    expect_identical(
      as.vector(rhdf5::H5Aread(rhdf5::H5Aopen(elem, "shape"))),
      c(3L, 4L)
    )
    rhdf5::h5closeAll()
  }
})

# Python writes the smallest index dtype when the setting is on, and R must
# honour it for matrices that carry no record
test_that("indices use the minimum dtype when the setting is on", {
  old <- anndata_settings$write_csr_csc_indices_with_min_possible_dtype
  anndata_settings$write_csr_csc_indices_with_min_possible_dtype <- TRUE
  withr::defer(
    anndata_settings$write_csr_csc_indices_with_min_possible_dtype <- old
  )
  path <- write_fixture_like(sparse_expected("csr"))
  store <- rhdf5::H5Fopen(path)
  withr::defer(rhdf5::h5closeAll())
  expect_identical(h5_dtype(store, "/x/indices"), "uint8")
  expect_identical(h5_dtype(store, "/x/indptr"), "int32")
})

# Python's bool has no missing value, so a logical NA must not write silently
test_that("logical NA in a sparse matrix raises", {
  for (format in c("csr", "csc")) {
    value <- sparse_expected(format, "bool")
    value@x[[1L]] <- NA
    err <- expect_anndata_condition(
      write_fixture_like(value),
      "anndata_io_registry_error"
    )
    expect_identical(err$path, "/x")
  }
})

# Floats follow the dense rule, NA and NaN are both written as NaN
test_that("NA in double sparse data is written as NaN", {
  value <- sparse_expected("csc")
  value@x[[1L]] <- NA
  read <- read_written(write_fixture_like(value))
  expect_true(is.nan(read@x[[1L]]))
  expect_identical(read@x[-1L], value@x[-1L])
})

# A recorded dtype that the values no longer fit must raise with the path of
# the component, never wrap
test_that("sparse data outside its recorded dtype raises", {
  value <- set_dtype(sparse_expected("csr"), c(data = "uint8"))
  value@x[[1L]] <- 300
  err <- expect_anndata_condition(
    write_fixture_like(value),
    "anndata_dtype_overflow_error"
  )
  expect_identical(err$path, "/x/data")
})

# A file whose indptr does not match the shape must fail with the path, rather
# than build an invalid matrix
test_that("inconsistent sparse components raise on read", {
  store <- local_h5_store()
  write_elem(store, "x", sparse_expected("csr"))
  group <- rhdf5::H5Gopen(store, "x")
  rhdf5::H5Ldelete(group, "indptr")
  write_dataset(group, "indptr", c(0L, 1L))
  err <- expect_anndata_condition(
    read_elem(store, "x"),
    "anndata_io_registry_error"
  )
  expect_identical(err$path, "/x")
})

# Sparse subsets and transposes keep their dtype record, so they must write the
# recorded dtype too
test_that("a subset keeps its sparse dtype record on write", {
  value <- sparse_expected("csc", "int8")
  subset <- matrix_subset(value, 1:2, 1:3)
  expect_identical(
    read_written(write_fixture_like(subset)),
    subset
  )
})

# scipy allows unsorted indices within a major slice but Matrix does not, so
# reading sorts them with their data (ADR 0006) and the matrix keeps its values
test_that("unsorted sparse indices are sorted on read", {
  for (format in c("csr", "csc")) {
    store <- local_h5_store()
    expected <- sparse_expected(format)
    write_elem(store, "x", expected)
    group <- rhdf5::H5Gopen(store, "x")
    indices <- if (format == "csr") expected@j else expected@i
    data <- expected@x
    indptr <- expected@p
    # Reverse the entries within each major slice
    slice <- rep.int(seq_along(diff(indptr)), diff(indptr))
    ord <- order(slice, -seq_along(slice))
    rhdf5::H5Ldelete(group, "indices")
    rhdf5::H5Ldelete(group, "data")
    write_dataset(group, "indices", as.integer(indices[ord]))
    write_dataset(group, "data", as.double(data[ord]))
    expect_equal(read_elem(store, "x"), expected, info = format)
  }
})
