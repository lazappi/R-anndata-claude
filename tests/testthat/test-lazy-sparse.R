# Tests of the sparse lazy seed (ticket lazy/05): StoreSparseSeed realises to
# what read_h5ad()/read_zarr() read, stays sparse, and chunks like Python.

skip_if_not_installed("Rarr", "2.1.48")

sparse_case_names <- sub(
  "\\.h5$",
  "",
  list.files(fixture_path("h5ad"), pattern = "^cs[rc]_.*\\.h5$")
)

# Opens fixture `case` of `format` and returns its store, closed at test end
sparse_fixture_store <- function(case, format, env = parent.frame()) {
  if (format == "h5ad") {
    withr::defer(rhdf5::h5closeAll(), envir = env)
    return(rhdf5::H5Fopen(
      fixture_path(file.path("h5ad", paste0(case, ".h5"))),
      flags = "H5F_ACC_RDONLY"
    ))
  }
  variant <- if (format == "zarr_v3") "v3" else "v2"
  zarr_open(zarr_variant_paths(variant)[[case]])
}

test_that("sparse fixtures are found", {
  # Guards the case list, so the loops below cannot silently run on nothing
  expect_gt(length(sparse_case_names), 20L)
})

test_that("a seed realises to the values read_elem() gives and stays sparse", {
  # The acceptance criterion: lazy values equal eager values for every sparse
  # fixture on every format, with the On-disk dtype record, and blocks are
  # SVT_SparseMatrix
  for (format in lazy_formats) {
    available <- names(zarr_variant_paths(
      if (format == "zarr_v2") "v2" else "v3"
    ))
    for (case in sparse_case_names) {
      if (format != "h5ad" && !case %in% available) {
        next
      }
      label <- paste(format, case)
      store <- sparse_fixture_store(case, format)
      truth <- tryCatch(read_elem(store, "x"), error = function(e) e)
      seed <- store_sparse_seed(store, "/x")
      if (inherits(truth, "error")) {
        # Values the eager read refuses (such as indices above the R integer)
        # are refused when realised too
        expect_error(
          store_sparse_values(seed),
          class = class(truth)[[1L]],
          label = label
        )
        next
      }
      # The data dtype record and the values equal the eager read. The index
      # dtypes are not kept by a block, which is rebuilt over int32 indices
      values <- store_sparse_values(seed)
      data_dtype <- function(m) {
        unname(c(get_dtype(m), data = NA_character_)["data"])
      }
      expect_identical(data_dtype(values), data_dtype(truth), label = label)
      expect_identical(
        as.matrix(drop_dtype(values)),
        as.matrix(drop_dtype(truth)),
        label = label
      )
      expect_true(DelayedArray::is_sparse(seed), label = label)
      # The type follows the dtype: logical, integer for small integers
      expected <- as.matrix(drop_dtype(truth))
      storage.mode(expected) <- DelayedArray::type(seed)
      block <- DelayedArray::extract_sparse_array(seed, list(NULL, NULL))
      expect_s4_class(block, "SVT_SparseMatrix")
      expect_identical(
        unname(as.matrix(block)),
        unname(expected),
        label = label
      )
      expect_identical(
        unname(as.matrix(DelayedArray::DelayedArray(seed))),
        unname(expected),
        label = label
      )
    }
  }
})

test_that("seed types follow the data dtype", {
  # Fixed from the dtype as for dense seeds: bool logical, small integers
  # integer, everything else double (as read_h5ad() gives)
  expected <- c(
    csr_bool = "logical",
    csr_int8 = "integer",
    csr_uint16 = "integer",
    csr_int32 = "integer",
    csr_uint32 = "double",
    csr_int64 = "double",
    csr_uint64 = "double",
    csr_float32 = "double",
    csc_uint8 = "integer"
  )
  for (case in names(expected)) {
    store <- sparse_fixture_store(case, "h5ad")
    expect_identical(
      DelayedArray::type(store_sparse_seed(store, "/x")),
      unname(expected[[case]]),
      label = case
    )
  }
})

test_that("block reads with any index form equal subsetting the eager values", {
  # Repeated and unsorted positions follow base matrices, on every format and
  # for both CSR and CSC
  for (case in c("csr_float32", "csc_float64")) {
    for (format in lazy_formats) {
      store <- sparse_fixture_store(case, format)
      truth <- as.matrix(drop_dtype(read_elem(store, "x")))
      arr <- DelayedArray::DelayedArray(store_sparse_seed(store, "/x"))
      i <- c(nrow(truth), 1L, 1L)
      j <- c(ncol(truth), 1L)
      label <- paste(format, case)
      expect_identical(
        unname(as.matrix(arr[i, j])),
        unname(truth[i, j]),
        label = label
      )
      expect_identical(
        unname(as.matrix(arr[i, ])),
        unname(truth[i, ]),
        label = label
      )
      # Sparse blocks, with repeated and unsorted positions too, and a sorted
      # subset of the DelayedArray stays sparse
      expect_s4_class(
        DelayedArray::extract_sparse_array(arr@seed, list(i, j)),
        "SVT_SparseMatrix"
      )
      expect_true(DelayedArray::is_sparse(arr[1:2, ]), label = label)
      expect_identical(
        unname(as.matrix(arr[0, ])),
        unname(truth[0, ]),
        label = label
      )
    }
  }
})

test_that("block reads read only their slices of data and indices", {
  # Lazy means the seed holds no data: a block reads indptr (once), then data
  # and indices at the offsets of the selected major positions only
  dir <- withr::local_tempdir()
  s <- zarr_create(file.path(dir, "m.zarr"))
  m <- Matrix::sparseMatrix(
    i = c(1, 2, 3, 3, 4),
    j = c(1, 2, 1, 3, 3),
    x = c(1, 2, 3, 4, 5),
    dims = c(4, 3)
  )
  write_elem(s, "x", methods::as(m, "RsparseMatrix"))
  seed <- store_sparse_seed(s, "/x")
  reads <- character()
  real <- array_read
  testthat::local_mocked_bindings(
    array_read = function(store, path, selection = NULL, call = NULL) {
      reads[length(reads) + 1L] <<- path
      real(store, path, selection, call)
    }
  )
  block <- lazy_sparse_block(seed, list(3L, NULL))
  expect_identical(
    as.matrix(drop_dtype(block)),
    as.matrix(m)[3, , drop = FALSE]
  )
  expect_identical(reads, c("/x/indptr", "/x/data", "/x/indices"))
  # indptr is cached, so a second block does not read it again
  reads <- character()
  lazy_sparse_block(seed, list(1L, NULL))
  expect_identical(reads, c("/x/data", "/x/indices"))
})

test_that("chunkdim follows Python's default and explicit chunks", {
  # Rows of the lazy table: the major axis is cut every 1000 (or `chunks`), the
  # minor axis never, and errors match Python's messages
  m <- Matrix::sparseMatrix(
    i = c(1, 2, 4),
    j = c(1, 2, 3),
    x = c(1, 2, 3),
    dims = c(4, 3)
  )
  dir <- withr::local_tempdir()
  h5 <- file.path(dir, "m.h5")
  rhdf5::h5createFile(h5)
  fid <- rhdf5::H5Fopen(h5)
  write_elem(fid, "csr", methods::as(m, "RsparseMatrix"))
  write_elem(fid, "csc", methods::as(m, "CsparseMatrix"))
  rhdf5::h5closeAll()
  zarr <- zarr_create(file.path(dir, "m.zarr"))
  write_elem(zarr, "csr", methods::as(m, "RsparseMatrix"))
  write_elem(zarr, "csc", methods::as(m, "CsparseMatrix"))
  withr::defer(rhdf5::h5closeAll())
  stores <- list(
    h5ad = rhdf5::H5Fopen(h5, flags = "H5F_ACC_RDONLY"),
    zarr_v3 = zarr
  )
  first <- function(row) {
    vapply(row$result$chunks, function(axis) axis[[1L]], numeric(1))
  }
  for (format in names(stores)) {
    store <- stores[[format]]
    chunkdim <- function(path, ...) {
      DelayedArray::chunkdim(store_sparse_seed(store, path, ...))
    }
    expect_identical(
      chunkdim("/csr"),
      as.integer(first(lazy_row(
        "read_elem_lazy",
        "csr_float32_default",
        format
      ))),
      label = format
    )
    expect_identical(
      chunkdim("/csr", chunks = c(2, -1)),
      as.integer(first(
        lazy_row("read_elem_lazy", "csr_float32_chunks_2_minus1", format)
      )),
      label = format
    )
    expect_identical(
      chunkdim("/csc", chunks = c(-1, 2)),
      as.integer(first(
        lazy_row("read_elem_lazy", "csc_float64_chunks_minus1_2", format)
      )),
      label = format
    )
    # NA and the axis length stand for the whole axis
    expect_identical(chunkdim("/csr", chunks = c(NA, 3)), c(4L, 3L))
  }
})

test_that("chunks errors are Python's", {
  # The messages of csr_*_chunks_bad_length and *_chunks_minor_axis in the table
  store <- sparse_fixture_store("csr_float32", "h5ad")
  bad_length <- lazy_row(
    "read_elem_lazy",
    "csr_float32_chunks_bad_length",
    "h5ad"
  )
  expect_error(
    store_sparse_seed(store, "/x", chunks = c(1, 2, 3)),
    "must be a tuple of two integers",
    class = "anndata_invalid_value_error"
  )
  expect_match(bad_length$error$message, "tuple of two integers")
  csr_minor <- lazy_row(
    "read_elem_lazy",
    "csr_float32_chunks_minor_axis",
    "h5ad"
  )
  expect_match(csr_minor$error$message, "Only the major axis can be chunked")
  expect_error(
    store_sparse_seed(store, "/x", chunks = c(2, 2)),
    "Only the major axis can be chunked",
    class = "anndata_invalid_value_error"
  )
  csc <- sparse_fixture_store("csc_float64", "h5ad")
  expect_error(
    store_sparse_seed(csc, "/x", chunks = c(2, 2)),
    "Only the major axis can be chunked",
    class = "anndata_invalid_value_error"
  )
})

test_that("a tall matrix is cut every 1000 major positions", {
  # dask_chunks rows tall_csr_f32 and tall_csr_stride_100
  dir <- withr::local_tempdir()
  s <- zarr_create(file.path(dir, "t.zarr"))
  m <- Matrix::sparseMatrix(
    i = c(1, 2500),
    j = c(1, 4),
    x = c(1, 2),
    dims = c(2500, 4)
  )
  write_elem(s, "csr", methods::as(m, "RsparseMatrix"))
  write_elem(s, "csc", methods::as(m, "CsparseMatrix"))
  expect_identical(
    DelayedArray::chunkdim(store_sparse_seed(s, "/csr")),
    c(1000L, 4L)
  )
  expect_identical(
    DelayedArray::chunkdim(store_sparse_seed(s, "/csr", chunks = c(100, -1))),
    c(100L, 4L)
  )
  expect_identical(
    DelayedArray::chunkdim(store_sparse_seed(s, "/csc")),
    c(2500L, 4L)
  )
  expect_identical(
    DelayedArray::chunkdim(store_sparse_seed(s, "/csc", chunks = c(-1, 2))),
    c(2500L, 2L)
  )
})

test_that("a wide CSC matrix is cut every 1000 columns", {
  # dask_chunks row tall_csc_f64 mirrored: the CSC major axis is the columns
  dir <- withr::local_tempdir()
  s <- zarr_create(file.path(dir, "w.zarr"))
  m <- Matrix::sparseMatrix(
    i = c(1, 3),
    j = c(1, 1500),
    x = c(1, 2),
    dims = c(3, 1500)
  )
  write_elem(s, "csc", methods::as(m, "CsparseMatrix"))
  expect_identical(
    DelayedArray::chunkdim(store_sparse_seed(s, "/csc")),
    c(3L, 1000L)
  )
  expect_identical(
    DelayedArray::chunkdim(store_sparse_seed(s, "/csc", chunks = c(-1, 100))),
    c(3L, 100L)
  )
  expect_identical(
    unname(as.matrix(DelayedArray::DelayedArray(store_sparse_seed(s, "/csc")))),
    unname(as.matrix(m))
  )
})

test_that("an empty axis has a chunk of zero", {
  # Python's chunk layout for a zero-length axis is (0,), and DelayedArray
  # rejects chunks larger than the dimension
  dir <- withr::local_tempdir()
  s <- zarr_create(file.path(dir, "e.zarr"))
  m <- methods::as(
    Matrix::Matrix(0, nrow = 0, ncol = 3, sparse = TRUE),
    "RsparseMatrix"
  )
  write_elem(s, "x", m)
  seed <- store_sparse_seed(s, "/x")
  expect_identical(DelayedArray::chunkdim(seed), c(0L, 3L))
  expect_identical(dim(as.matrix(DelayedArray::DelayedArray(seed))), c(0L, 3L))
})

test_that("non-sparse Elements are rejected", {
  # A dense array is not a CSR or CSC group
  dir <- withr::local_tempdir()
  s <- zarr_create(file.path(dir, "d.zarr"))
  write_elem(s, "x", matrix(as.numeric(1:6), nrow = 2))
  expect_error(store_sparse_seed(s, "/x"), class = "anndata_dtype_error")
})
