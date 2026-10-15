integer_dtypes <- c(
  "int8",
  "int16",
  "int32",
  "int64",
  "uint8",
  "uint16",
  "uint32",
  "uint64"
)

# Writes `x` at `name` and reads it back, returning the value read
dataset_round_trip <- function(x, name = "x", store = local_h5_store()) {
  write_dataset(store, name, x)
  read_dataset(store, name)
}

# The on-disk dtype string h5ls reports, which is what Python sees
disk_dtype <- function(store, name) {
  listing <- rhdf5::h5ls(store, recursive = FALSE, all = TRUE)
  listing$dtype[listing$name == name]
}

# The record must not change how a value prints or computes, because it is
# carried on ordinary R vectors and matrices
test_that("a dtype record is invisible to printing and arithmetic", {
  plain <- matrix(c(1.5, 2, 3, 4), 2, 2)
  typed <- set_dtype(plain, "float32")
  expect_identical(get_dtype(typed), "float32")
  expect_identical(capture.output(print(typed)), capture.output(print(plain)))
  expect_identical(capture.output(typed), capture.output(plain))
  expect_equal(as.vector(typed + 1), as.vector(plain + 1))
  expect_equal(sum(typed), sum(plain))
  expect_identical(drop_dtype(typed), plain)
  expect_true(is.matrix(typed))
  expect_identical(dim(typed), dim(plain))

  vec <- set_dtype(c(1L, 2L), "int8")
  expect_identical(capture.output(print(vec)), "[1] 1 2")
  expect_identical(drop_dtype(vec), c(1L, 2L))
})

# Records on S4 sparse matrices must not add a class or change their show
test_that("sparse matrices carry a record without changing class", {
  csc <- Matrix::sparseMatrix(i = 1, j = 2, x = 1, dims = c(2, 3))
  typed <- set_dtype(
    csc,
    c(data = "float32", indices = "int64", indptr = "int32")
  )
  expect_s4_class(typed, "dgCMatrix")
  expect_identical(capture.output(show(typed)), capture.output(show(csc)))
  expect_identical(drop_dtype(typed), csc)
})

# Every integer width has to accept its limits and refuse the first value
# beyond them, so nothing is wrapped or truncated on write
test_that("check_dtype_fits accepts the range and rejects values outside", {
  # dtype = c(lowest, highest, first value above the highest)
  limits <- list(
    int8 = c(-128, 127, 128),
    int16 = c(-32768, 32767, 32768),
    int32 = c(-2^31, 2^31 - 1, 2^31),
    int64 = c(-2^63, 2^63 - 1024, 2^63),
    uint8 = c(0, 255, 256),
    uint16 = c(0, 65535, 65536),
    uint32 = c(0, 2^32 - 1, 2^32),
    uint64 = c(0, 2^64 - 2048, 2^64)
  )
  for (dtype in names(limits)) {
    range <- limits[[dtype]]
    expect_no_error(check_dtype_fits(range[1:2], dtype, "/x"))
    expect_anndata_condition(
      check_dtype_fits(range[[3]], dtype, "/x"),
      "anndata_dtype_overflow_error"
    )
    expect_anndata_condition(
      check_dtype_fits(range[[1]] - 2^11, dtype, "/x"),
      "anndata_dtype_overflow_error"
    )
  }
})

# Integers cannot hold NA or fractions, and float32 cannot hold huge values,
# but float32 keeps NaN and infinities
test_that("check_dtype_fits rejects missing, fractional and huge floats", {
  for (bad in list(NA_real_, NaN, Inf, 1.5)) {
    expect_anndata_condition(
      check_dtype_fits(c(1, bad), "int16", "/x"),
      "anndata_dtype_overflow_error"
    )
  }
  expect_anndata_condition(
    check_dtype_fits(c(1, 1e39), "float32", "/x"),
    "anndata_dtype_overflow_error"
  )
  expect_no_error(check_dtype_fits(
    c(NA, NaN, Inf, -Inf, 1e38),
    "float32",
    "/x"
  ))
  expect_no_error(check_dtype_fits(1e300, "float64", "/x"))
})

# The error must name the path, as the spec requires
test_that("overflow errors name the path and dtype", {
  err <- expect_anndata_condition(
    check_dtype_fits(300, "uint8", "/obsm/emb"),
    "anndata_dtype_overflow_error"
  )
  expect_identical(err$path, "/obsm/emb")
  expect_identical(err$dtype, "uint8")
  expect_match(conditionMessage(err), "/obsm/emb", fixed = TRUE)
})

# Without a record R writes int32 and float64, as Python does for the
# equivalent values
test_that("values without a record write native dtypes", {
  expect_identical(write_dtype(c(1.5, 2), "/x"), "float64")
  expect_identical(write_dtype(1:3, "/x"), "int32")
  expect_identical(write_dtype(set_dtype(c(1, 2), "uint8"), "/x"), "uint8")
})

# Vectors, matrices and arrays of every dtype must come back with the same
# dtype on disk, which is the core of the mechanism
test_that("every dtype round trips as vector, matrix and array", {
  shapes <- list(
    vector = c(1, 2, 3),
    matrix = matrix(c(1, 2, 3, 4, 5, 6), 2, 3),
    array = array(as.numeric(1:24), c(2, 3, 4))
  )
  for (dtype in numeric_dtypes) {
    for (shape in names(shapes)) {
      store <- local_h5_store()
      x <- shapes[[shape]]
      if (dtype %in% c("float32", "float64")) {
        x <- x + 0.5
      }
      typed <- record_dtype(x, dtype)
      write_dataset(store, "x", typed)
      expect_identical(
        sub("BE$", "LE", disk_dtype(store, "x")),
        h5_numeric_types[[dtype]],
        info = paste(dtype, shape)
      )
      result <- read_dataset(store, "x")
      expect_identical(dim(result), dim(x), info = paste(dtype, shape))
      expect_identical(
        as.double(result),
        as.double(x),
        info = paste(dtype, shape)
      )
      # int32 and float64 are what R returns natively, so need no record
      if (dtype %in% c("int32", "float64")) {
        expect_null(get_dtype(result))
      } else {
        expect_identical(get_dtype(result), dtype, info = paste(dtype, shape))
      }
    }
  }
})

# int8, int16 and uint16 read as integer, so the record is what tells the
# writer to use the narrow dtype again
test_that("small integer dtypes read as integer with a record", {
  for (dtype in c("int8", "int16", "uint8", "uint16")) {
    store <- local_h5_store()
    result <- dataset_round_trip(set_dtype(c(1, 2, 3), dtype), store = store)
    expect_type(result, "integer")
    expect_identical(get_dtype(result), dtype)
  }
})

# int32 is R's native integer, so no record is needed
test_that("int32 and float64 read without a record", {
  expect_null(get_dtype(dataset_round_trip(1:3)))
  expect_null(get_dtype(dataset_round_trip(c(0.5, 1))))
  expect_type(dataset_round_trip(1:3), "integer")
})

# Python writes the matrix with shape dim(x), so the first dimension must stay
# the first on disk and x[i, j] must be the on-disk [i, j]
test_that("h5py sees the shape and dtype of written values", {
  skip_if_no_python()
  path <- withr::local_tempfile(fileext = ".h5")
  rhdf5::h5createFile(path)
  fid <- rhdf5::H5Fopen(path)
  x <- matrix(as.numeric(1:6), 2, 3)
  write_dataset(fid, "matrix", set_dtype(x, "uint16"))
  write_dataset(fid, "array", array(as.numeric(1:24), c(2, 3, 4)))
  write_dataset(fid, "vector", set_dtype(c(1, 2, 3), "int8"))
  expect_identical(
    read_dataset(fid, "matrix"),
    set_dtype(matrix(1:6, 2, 3), "uint16")
  )
  rhdf5::h5closeAll()
  nodes <- jsonlite::fromJSON(
    run_python("h5_tree.py", path),
    simplifyVector = FALSE
  )
  found <- Filter(function(node) node$kind == "dataset", nodes)
  by_path <- setNames(found, vapply(found, function(n) n$path, ""))
  expect_identical(unlist(by_path[["/matrix"]]$shape), c(2L, 3L))
  expect_identical(by_path[["/matrix"]]$dtype, "uint16")
  expect_identical(unlist(by_path[["/array"]]$shape), c(2L, 3L, 4L))
  expect_identical(by_path[["/array"]]$dtype, "float64")
  expect_identical(unlist(by_path[["/vector"]]$shape), 3L)
  expect_identical(by_path[["/vector"]]$dtype, "int8")
})

# Zero-length and one-element values are the edge cases of the dim handling
test_that("empty and single values round trip", {
  expect_identical(dataset_round_trip(numeric(0)), numeric(0))
  expect_identical(
    dataset_round_trip(matrix(numeric(0), 0, 3)),
    matrix(numeric(0), 0, 3)
  )
  expect_identical(dataset_round_trip(2.5), 2.5)
  scalar_store <- local_h5_store()
  write_dataset(scalar_store, "s", 2.5, scalar = TRUE)
  expect_identical(read_dataset(scalar_store, "s"), 2.5)
})

# Reading must work from a nested group and an absolute path as readers will
test_that("datasets in groups read by relative and absolute path", {
  store <- local_h5_store()
  group <- rhdf5::H5Gcreate(store, "g")
  write_dataset(group, "x", set_dtype(c(1, 2), "int8"))
  expect_identical(get_dtype(read_dataset(group, "x")), "int8")
  expect_identical(get_dtype(read_dataset(store, "/g/x")), "int8")
})

# Python int scalars are int64 on disk, and small values must come back
test_that("int64 and uint64 read as double below 2^53 and keep the record", {
  for (dtype in c("int64", "uint64")) {
    result <- dataset_round_trip(set_dtype(c(0, 1, 2^53 - 1), dtype))
    expect_type(result, "double")
    expect_identical(as.vector(result), c(0, 1, 2^53 - 1))
    expect_identical(get_dtype(result), dtype)
  }
  negative <- dataset_round_trip(set_dtype(c(-(2^53 - 1), 1), "int64"))
  expect_identical(as.vector(negative), c(-(2^53 - 1), 1))
})

# 64-bit values from 2^53 up cannot be held exactly, so reading must fail
# rather than lose precision
test_that("int64 and uint64 at or beyond 2^53 raise an error naming the path", {
  for (dtype in c("int64", "uint64")) {
    for (value in c(2^53, 2^60)) {
      store <- local_h5_store()
      write_dataset(store, "big", set_dtype(c(1, value), dtype))
      err <- expect_anndata_condition(
        read_dataset(store, "big"),
        "anndata_dtype_overflow_error"
      )
      expect_identical(err$path, "/big")
    }
  }
  store <- local_h5_store()
  write_dataset(store, "huge", set_dtype(2^63 + 2048, "uint64"))
  expect_anndata_condition(
    read_dataset(store, "huge"),
    "anndata_dtype_overflow_error"
  )
})

# uint32 does not fit R's integer but is exact as double
test_that("uint32 values above the integer range read exactly", {
  result <- dataset_round_trip(set_dtype(c(1, 4e9), "uint32"))
  expect_identical(as.vector(result), c(1, 4e9))
  expect_identical(get_dtype(result), "uint32")
})

# -2^31 has the bit pattern of NA_integer_, and it must not become NA
test_that("an int32 dataset holding -2^31 reads as double and writes back", {
  store <- local_h5_store()
  write_dataset(store, "x", set_dtype(c(1, -2^31, 3), "int32"))
  result <- read_dataset(store, "x")
  expect_type(result, "double")
  expect_identical(as.vector(result), c(1, -2^31, 3))
  expect_identical(get_dtype(result), "int32")
  expect_no_condition(suppressMessages(write_dataset(store, "y", result)))
  expect_identical(
    sub("BE$", "LE", disk_dtype(store, "y")),
    "H5T_STD_I32LE"
  )
  expect_identical(as.vector(read_dataset(store, "y")), c(1, -2^31, 3))
})

# A matrix with -2^31 keeps its shape through the double conversion
test_that("-2^31 in a matrix keeps the dim", {
  x <- set_dtype(matrix(c(-2^31, 2, 3, 4), 2, 2), "int32")
  result <- dataset_round_trip(x)
  expect_identical(dim(result), c(2L, 2L))
  expect_identical(as.vector(result), c(-2^31, 2, 3, 4))
})

# Values changed after reading must not be wrapped to fit the old dtype
test_that("writing values that no longer fit the record errors", {
  store <- local_h5_store()
  read <- dataset_round_trip(set_dtype(c(1, 2), "uint8"), store = store)
  changed <- read + 300L
  expect_identical(get_dtype(changed), "uint8")
  err <- expect_anndata_condition(
    write_dataset(store, "again", changed),
    "anndata_dtype_overflow_error"
  )
  expect_identical(err$path, "/again")
})

# float32 narrows on write and widens exactly on read
test_that("float32 values keep NaN and Inf", {
  x <- set_dtype(c(1.5, NaN, Inf, -Inf), "float32")
  result <- dataset_round_trip(x)
  expect_identical(as.vector(result), c(1.5, NaN, Inf, -Inf))
  expect_identical(get_dtype(result), "float32")
})

# Non-numeric datasets are not this helper's job, so it must refuse them
test_that("reading a non-numeric dataset errors", {
  store <- local_h5_store()
  rhdf5::h5write(c("a", "b"), store, "s")
  expect_anndata_condition(
    read_dataset(store, "s"),
    "anndata_dtype_error"
  )
})

# The record has to survive the core-object operations on every Slot
test_that("records survive subset, copy and transpose of an AnnData", {
  typed <- function(x, dtype) set_dtype(x, dtype)
  adata <- AnnData(
    typed(matrix(as.numeric(1:6), 3, 2), "float32"),
    obsm = list(emb = typed(matrix(as.numeric(1:6), 3, 2), "int8")),
    layers = list(l = typed(matrix(as.numeric(1:6), 3, 2), "uint16"))
  )
  results <- list(adata[2:3, 1], adata$copy(), t(adata))
  for (result in results) {
    expect_identical(get_dtype(result$X), "float32")
    expect_identical(get_dtype(result$layers[["l"]]), "uint16")
  }
  expect_identical(get_dtype(results[[1]]$obsm[["emb"]]), "int8")
  expect_identical(get_dtype(results[[2]]$obsm[["emb"]]), "int8")
})

# Sparse records name each component, and a partial record fills in the rest
test_that("sparse dtypes use the record and fall back to native types", {
  csc <- Matrix::sparseMatrix(
    i = c(1, 3),
    j = c(1, 2),
    x = c(1, 2),
    dims = c(3, 2)
  )
  expect_identical(
    sparse_write_dtypes(csc, "/X"),
    c(data = "float64", indices = "int32", indptr = "int32")
  )
  typed <- set_dtype(
    csc,
    c(data = "float32", indices = "int64", indptr = "int64")
  )
  expect_identical(
    sparse_write_dtypes(typed, "/X"),
    c(data = "float32", indices = "int64", indptr = "int64")
  )
  logical <- methods::as(csc, "lMatrix")
  expect_identical(sparse_write_dtypes(logical, "/X")[["data"]], "bool")
})

# write_csr_csc_indices_with_min_possible_dtype shrinks indices, not indptr,
# using the minor axis size (columns for CSR, rows for CSC)
test_that("min possible index dtype follows the minor axis size", {
  old <- anndata_settings$write_csr_csc_indices_with_min_possible_dtype
  anndata_settings$write_csr_csc_indices_with_min_possible_dtype <- TRUE
  withr::defer(
    anndata_settings$write_csr_csc_indices_with_min_possible_dtype <- old
  )
  csc <- Matrix::sparseMatrix(i = 1, j = 1, x = 1, dims = c(255, 70000))
  expect_identical(sparse_write_dtypes(csc, "/X")[["indices"]], "uint8")
  csr <- methods::as(csc, "RsparseMatrix")
  expect_identical(sparse_write_dtypes(csr, "/X")[["indices"]], "uint32")
  wide <- Matrix::sparseMatrix(i = 1, j = 1, x = 1, dims = c(256, 3))
  expect_identical(sparse_write_dtypes(wide, "/X")[["indices"]], "uint16")
  expect_identical(sparse_write_dtypes(wide, "/X")[["indptr"]], "int32")
  expect_identical(min_index_dtype(2^32), "uint64")
})

# Sparse parts that no longer fit their recorded dtype must error with the
# path of the offending component
test_that("sparse components are checked against their dtype", {
  csc <- Matrix::sparseMatrix(i = 1, j = 1, x = 1e39, dims = c(2, 2))
  typed <- set_dtype(
    csc,
    c(data = "float32", indices = "int32", indptr = "int32")
  )
  err <- expect_anndata_condition(
    sparse_write_dtypes(typed, "/X"),
    "anndata_dtype_overflow_error"
  )
  expect_identical(err$path, "/X/data")
})
