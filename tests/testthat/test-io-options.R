# The ids of the filters of a dataset ("1" is gzip, "32000" is lzf) and its
# chunks, which are NULL when the dataset is not chunked
dataset_filters <- function(path, name) {
  store <- rhdf5::H5Fopen(path, flags = "H5F_ACC_RDONLY")
  on.exit(rhdf5::H5Fclose(store), add = TRUE)
  dset <- rhdf5::H5Dopen(store, name)
  on.exit(rhdf5::H5Dclose(dset), add = TRUE, after = FALSE)
  plist <- rhdf5::H5Dget_create_plist(dset)
  on.exit(rhdf5::H5Pclose(plist), add = TRUE, after = FALSE)
  n <- rhdf5::H5Pget_nfilters(plist)
  filters <- vapply(
    seq_len(n),
    function(i) as.character(rhdf5::H5Pget_filter(plist, i)[[1L]]),
    character(1)
  )
  list(
    filters = filters,
    chunk = if (identical(rhdf5::H5Pget_layout(plist), "H5D_CHUNKED")) {
      rhdf5::H5Pget_chunk(plist)
    }
  )
}

options_adata <- function() {
  sparse <- methods::as(
    Matrix::sparseMatrix(
      i = c(1, 3, 4),
      j = c(1, 2, 3),
      x = c(1, 2, 3),
      dims = c(4, 3)
    ),
    "CsparseMatrix"
  )
  adata <- AnnData(
    X = sparse,
    obs = data.frame(
      label = c("a", "b", "c", "d"),
      n = c(1, 2, 3, 4),
      row.names = paste0("cell", 0:3)
    ),
    var = data.frame(row.names = paste0("gene", 0:2)),
    obsm = list(pca = matrix(as.numeric(1:8), 4)),
    layers = list(dense = matrix(as.numeric(1:12), 4)),
    uns = list(note = "text", vec = c(1.5, 2.5), flag = c(TRUE, FALSE))
  )
  adata$raw <- adata
  adata
}

# The chunk shapes are h5py's `guess_chunk`, with values observed in Python
test_that("guess_chunk matches h5py", {
  expect_identical(guess_chunk(c(5000, 1000), 4L), c(157L, 63L))
  expect_identical(guess_chunk(2e6, 8L), 3907L)
  expect_identical(guess_chunk(c(3000, 3000), 8L), c(94L, 94L))
  expect_identical(guess_chunk(c(30, 20), 8L), c(30L, 20L))
  expect_identical(guess_chunk(0, 8L), 1024L)
  expect_identical(guess_chunk(c(0, 3), 8L), c(512L, 2L))
})

# Python compresses every dataset except scalars and the null Element
test_that("write_h5ad compresses datasets with gzip and lzf", {
  adata <- options_adata()
  gzip <- withr::local_tempfile(fileext = ".h5ad")
  lzf <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(adata, gzip, compression = "gzip", compression_opts = 3L)
  write_h5ad(adata$copy(), lzf, compression = "lzf")

  for (name in c(
    "X/data",
    "X/indices",
    "layers/dense",
    "obsm/pca",
    "obs/n",
    "obs/label/values",
    "obs/label/mask",
    "obs/_index/values",
    "uns/vec",
    "uns/flag",
    "raw/X/data"
  )) {
    expect_identical(dataset_filters(gzip, name)$filters, "1", info = name)
    expect_identical(dataset_filters(lzf, name)$filters, "32000", info = name)
  }
  expect_identical(dataset_filters(gzip, "layers/dense")$chunk, c(4L, 3L))
  expect_identical(dataset_filters(gzip, "X/data")$chunk, 3L)
  # Scalars are never compressed
  expect_identical(dataset_filters(gzip, "uns/note")$filters, character())

  expect_identical(
    read_h5ad(gzip)$layers[["dense"]],
    adata$layers[["dense"]]
  )
  expect_identical(read_h5ad(lzf)$uns$vec, adata$uns$vec)
})

test_that("write_h5ad without compression writes unfiltered datasets", {
  path <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(options_adata(), path)
  expect_identical(dataset_filters(path, "layers/dense")$filters, character())
})

# Python reads the compressed files and sees the same object
test_that("Python reads compressed files like uncompressed ones", {
  skip_if_no_python()
  adata <- options_adata()
  plain <- withr::local_tempfile(fileext = ".h5ad")
  gzip <- withr::local_tempfile(fileext = ".h5ad")
  lzf <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(adata, plain)
  write_h5ad(adata$copy(), gzip, compression = "gzip")
  write_h5ad(adata$copy(), lzf, compression = "lzf")
  expect_python_equal(c(gzip, lzf), c(plain, plain))
  expect_all_equivalent(c(gzip, lzf), c(plain, plain))
})

# Python's h5py rejects these, and we validate before touching the file
test_that("write_h5ad checks compression and compression_opts", {
  adata <- options_adata()
  path <- withr::local_tempfile(fileext = ".h5ad")
  bad <- list(
    list(compression = "bzip"),
    list(compression = c("gzip", "lzf")),
    list(compression = "lzf", compression_opts = 3L),
    list(compression = "gzip", compression_opts = 10L),
    list(compression = "gzip", compression_opts = -1L),
    list(compression = "gzip", compression_opts = 1.5),
    list(compression = "gzip", compression_opts = "a"),
    list(compression_opts = 3L)
  )
  for (args in bad) {
    expect_error(
      do.call(write_h5ad, c(list(adata, path), args)),
      class = "anndata_invalid_argument_error"
    )
  }
  expect_false(file.exists(path))
  # Level 0 and the default level are accepted
  write_h5ad(adata, path, compression = "gzip", compression_opts = 0L)
  write_h5ad(adata, path, compression = "gzip")
  expect_identical(dataset_filters(path, "obsm/pca")$filters, "1")
})

test_that("write_elem takes compression in dataset_kwargs", {
  path <- withr::local_tempfile(fileext = ".h5")
  store <- rhdf5::H5Fcreate(path)
  write_elem(store, "x", matrix(1, 4, 4), list(compression = "gzip"))
  rhdf5::H5Fclose(store)
  expect_identical(dataset_filters(path, "x")$filters, "1")
})

test_that("compression covers empty arrays", {
  adata <- AnnData(matrix(0, 0, 3))
  adata$uns$empty <- numeric()
  path <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(adata, path, compression = "gzip")
  expect_identical(dataset_filters(path, "uns/empty")$chunk, 1024L)
  expect_identical(read_h5ad(path)$shape, c(0L, 3L))
})

# Python writes sparse X as a plain `array` dataset and keeps its dtype
test_that("as_dense writes sparse X and raw X dense", {
  adata <- options_adata()
  path <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(adata, path, as_dense = c("X", "raw.X"))
  back <- read_h5ad(path)
  expected <- matrix(0, 4, 3)
  expected[cbind(c(1, 3, 4), c(1, 2, 3))] <- c(1, 2, 3)
  expect_identical(back$X, expected)
  expect_identical(back$raw$X, expected)
  # Layers stay as they are
  expect_true(is.matrix(back$layers[["dense"]]))

  store <- rhdf5::H5Fopen(path, flags = "H5F_ACC_RDONLY")
  on.exit(rhdf5::H5Fclose(store), add = TRUE)
  x <- rhdf5::H5Oopen(store, "X")
  expect_identical(read_elem_attr(x, "encoding-type"), "array")
  rhdf5::H5Oclose(x)
})

test_that("as_dense keeps the On-disk dtype and leaves dense X alone", {
  sparse <- set_dtype(
    methods::as(Matrix::Matrix(diag(3), sparse = TRUE), "CsparseMatrix"),
    c(data = "float32")
  )
  path <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(AnnData(sparse), path, as_dense = "X")
  expect_identical(get_dtype(read_h5ad(path)$X), "float32")

  write_h5ad(AnnData(matrix(1, 2, 2)), path, as_dense = "X")
  expect_identical(read_h5ad(path)$X, matrix(1, 2, 2))
  write_h5ad(AnnData(shape = c(2L, 2L)), path, as_dense = "X")
  expect_null(read_h5ad(path)$X)
})

test_that("as_dense can be compressed", {
  path <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(options_adata(), path, as_dense = "X", compression = "gzip")
  expect_identical(dataset_filters(path, "X")$filters, "1")
})

test_that("Python reads files written with as_dense", {
  skip_if_no_python()
  adata <- options_adata()
  path <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(adata, path, as_dense = c("X", "raw/X"))
  dense <- adata$copy()
  dense$X <- as.matrix(adata$X)
  dense_raw <- AnnData(as.matrix(adata$X), obs = adata$obs, var = adata$var)
  dense$raw <- dense_raw
  expected <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(dense, expected)
  expect_python_equal(path, expected)
})

# Python raises NotImplementedError and ValueError for these
test_that("write_h5ad checks as_dense", {
  adata <- options_adata()
  no_raw <- AnnData(matrix(0, 2, 2))
  path <- withr::local_tempfile(fileext = ".h5ad")
  for (value in list("x", "layers", c("X", "obs"), "", c("raw", "X"))) {
    expect_error(
      write_h5ad(adata, path, as_dense = value),
      class = "anndata_not_supported_error"
    )
  }
  expect_error(
    write_h5ad(adata, path, as_dense = NA_character_),
    class = "anndata_invalid_argument_error"
  )
  expect_error(
    write_h5ad(adata, path, as_dense = 1),
    class = "anndata_invalid_argument_error"
  )
  for (value in c("raw/X", "raw.X")) {
    expect_error(
      write_h5ad(no_raw, path, as_dense = value),
      class = "anndata_invalid_argument_error"
    )
  }
  expect_false(file.exists(path))
  # The 3-D check comes first, as in Python
  tall <- AnnData(matrix(0, 2, 3))
  suppressWarnings(tall$X <- array(0, c(2, 3, 4)))
  expect_error(
    write_h5ad(tall, path, as_dense = "x"),
    class = "anndata_non_2d_error"
  )
})

# Dense datasets read as sparse, in the format and chunks asked for
test_that("read_h5ad reads dense X and raw X as sparse", {
  dense <- matrix(c(0, 1, 0, 2, 0, 0, 0, 3, 4, 0), 5)
  adata <- AnnData(dense)
  adata$raw <- adata
  path <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(adata, path)

  csr <- read_h5ad(path, as_sparse = c("X", "raw.X"), chunk_size = 2L)
  expect_s4_class(csr$X, "dgRMatrix")
  expect_s4_class(csr$raw$X, "dgRMatrix")
  expect_identical(as.matrix(csr$X), dense)
  expect_identical(as.matrix(csr$raw$X), dense)

  csc <- read_h5ad(path, as_sparse = "X", as_sparse_fmt = "csc", chunk_size = 1)
  expect_s4_class(csc$X, "dgCMatrix")
  expect_identical(as.matrix(csc$X), dense)
  expect_identical(read_h5ad(path, as_sparse = "raw/X")$X, dense)
  expect_identical(read_h5ad(path, as_sparse = character())$X, dense)
})

test_that("read_h5ad as_sparse keeps the dtype and handles empty matrices", {
  path <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(AnnData(set_dtype(matrix(c(0, 1, 0, 2), 2), "float32")), path)
  expect_identical(
    get_dtype(read_h5ad(path, as_sparse = "X")$X),
    c(data = "float32")
  )
  write_h5ad(AnnData(matrix(c(TRUE, FALSE, FALSE, TRUE), 2)), path)
  expect_s4_class(read_h5ad(path, as_sparse = "X")$X, "lgRMatrix")
  for (shape in list(c(0L, 3L), c(3L, 0L))) {
    write_h5ad(AnnData(matrix(0, shape[[1L]], shape[[2L]])), path)
    for (fmt in c("csr", "csc")) {
      sparse <- read_h5ad(path, as_sparse = "X", as_sparse_fmt = fmt)$X
      expect_identical(dim(sparse), shape)
    }
  }
})

test_that("read_h5ad as_sparse accepts a missing X and a missing raw", {
  path <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(AnnData(shape = c(2L, 2L)), path)
  expect_null(read_h5ad(path, as_sparse = c("X", "raw/X"))$X)
})

test_that("read_h5ad checks as_sparse, as_sparse_fmt and chunk_size", {
  path <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(AnnData(matrix(1, 2, 2)), path)
  for (value in list("x", "layers", c("X", "obs"), "")) {
    expect_error(
      read_h5ad(path, as_sparse = value),
      class = "anndata_not_supported_error"
    )
  }
  expect_error(
    read_h5ad(path, as_sparse_fmt = "coo"),
    class = "anndata_not_supported_error"
  )
  expect_error(
    read_h5ad(path, as_sparse = 1),
    class = "anndata_invalid_argument_error"
  )
  # Python hangs on 0 and -1, so these are errors here
  for (value in list(0, -1, 1.5, NA, "a", c(1, 2))) {
    expect_error(
      read_h5ad(path, chunk_size = value),
      class = "anndata_invalid_argument_error"
    )
  }
  # Python fails with an AttributeError on a matrix that is already sparse
  write_h5ad(AnnData(options_adata()$X), path)
  expect_error(
    read_h5ad(path, as_sparse = "X"),
    class = "anndata_invalid_argument_error"
  )
})

test_that("read_h5ad restores its options after an error", {
  path <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(AnnData(options_adata()$X), path)
  expect_error(read_h5ad(path, as_sparse = "X"))
  expect_s4_class(read_h5ad(path)$X, "dgCMatrix")
})

# Python's mapping keys that contain a slash fail the write
test_that("write_h5ad rejects keys with a forward slash", {
  adata <- AnnData(matrix(0, 2, 2))
  adata$uns[["a/b"]] <- 1
  path <- withr::local_tempfile(fileext = ".h5ad")
  expect_error(
    write_h5ad(adata, path),
    class = "anndata_forward_slash_key_error"
  )
})
