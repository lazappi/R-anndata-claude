# Tests of read_elem_lazy() (ticket lazy/07): every encoding, the chunks
# argument and its errors, on h5ad, zarr v3 and zarr v2.

skip_if_not_installed("Rarr", "2.1.48")

# Path of fixture `case` (an Element "x") for `format`
lazy_fixture_path <- function(case, format) {
  if (format == "h5ad") {
    return(fixture_path(file.path("h5ad", paste0(case, ".h5"))))
  }
  zarr_variant_paths(if (format == "zarr_v3") "v3" else "v2")[[case]]
}

# What read_elem() gives for `key` of the store at `path`, closing the store
lazy_eager_elem <- function(path, key) {
  if (dir.exists(path)) {
    return(read_elem(zarr_open(path), key))
  }
  store <- rhdf5::H5Fopen(path, flags = "H5F_ACC_RDONLY")
  on.exit(rhdf5::H5Fclose(store))
  read_elem(store, key)
}

test_that("an Element is read lazily as the DelayedArray of its encoding", {
  # Dense arrays and CSR/CSC matrices are DelayedArrays whose realised values
  # equal read_elem(), and sparse ones stay sparse
  paths <- lazy_small_paths()
  for (format in names(paths)) {
    dense <- read_elem_lazy(paths[[format]], "X")
    expect_s4_class(dense, "DelayedArray")
    expect_false(DelayedArray::is_sparse(dense))
    expect_identical(dim(dense), c(4L, 3L))
    for (layer in c("csr", "csc")) {
      sparse <- read_elem_lazy(paths[[format]], paste0("layers/", layer))
      expect_s4_class(sparse, "DelayedArray")
      expect_true(DelayedArray::is_sparse(sparse))
    }
  }
})

test_that("lazy values equal what read_h5ad() and read_zarr() give", {
  # Acceptance criterion: realised values equal the eager read for dense and
  # sparse Elements, categorical and nullable columns and dataframes
  paths <- lazy_small_paths()
  eager <- list(
    h5ad = read_h5ad(paths$h5ad),
    zarr_v3 = read_zarr(paths$zarr_v3)
  )
  for (format in names(paths)) {
    path <- paths[[format]]
    truth <- eager[[format]]
    expect_equal(
      as.matrix(read_elem_lazy(path, "X")),
      as.matrix(truth$X),
      ignore_attr = TRUE
    )
    for (layer in c("dense_i", "dense_bool", "csr", "csc")) {
      expect_equal(
        as.matrix(read_elem_lazy(path, paste0("layers/", layer))),
        as.matrix(truth$layers[[layer]]),
        ignore_attr = TRUE,
        label = paste(format, layer)
      )
    }
    cat <- read_elem_lazy(path, "obs/cat")
    expect_s4_class(cat, "LazyCategorical")
    expect_identical(as.vector(cat), truth$obs$cat)
    for (column in c("ni", "nb")) {
      nullable <- read_elem_lazy(path, paste0("obs/", column), chunks = 2)
      expect_s4_class(nullable, "LazyNullable")
      expect_identical(as.vector(nullable), truth$obs[[column]])
    }
    obs <- read_elem_lazy(path, "obs")
    expect_s4_class(obs, "LazyDFrame")
    expect_identical(lazy_dataframe_realise(obs), truth$obs)
  }
})

test_that("an Element in a store handle is read lazily", {
  # The store may be an open handle as well as a path
  paths <- lazy_small_paths()
  handle <- zarr_open(paths$zarr_v3)
  expect_identical(
    dim(read_elem_lazy(handle, "layers/csr")),
    c(4L, 3L)
  )
  h5 <- rhdf5::H5Fopen(paths$h5ad, flags = "H5F_ACC_RDONLY")
  withr::defer(rhdf5::H5Fclose(h5))
  expect_identical(dim(read_elem_lazy(h5, "/X")), c(4L, 3L))
})

test_that("string arrays are lazy character arrays", {
  # A string-array Element is a 1-d DelayedArray, on every format
  for (format in lazy_formats) {
    path <- lazy_fixture_path("string_array_1d", format)
    truth <- as.vector(drop_dtype(lazy_eager_elem(path, "/x")))
    # Row string_array_chunks_2: chunks are accepted for a string array
    for (chunks in list(NULL, 2)) {
      lazy <- read_elem_lazy(path, "x", chunks = chunks)
      expect_s4_class(lazy, "DelayedArray")
      expect_identical(as.vector(lazy), truth)
    }
  }
})

test_that("encodings with no lazy reader raise Python's registry error", {
  # Table rows uns_dict_default and uns_scalar_default: dict and scalar
  # Elements raise IORegistryError in Python
  cases <- lazy_cases()$read_elem_lazy
  paths <- lazy_small_paths()
  adata <- read_h5ad(paths$h5ad)
  adata$uns[["u"]] <- 1L
  adata$uns[["nested"]] <- list(k = 1:3)
  file <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(adata, file)
  zarr <- withr::local_tempdir(fileext = ".zarr")
  write_zarr(adata, zarr)
  for (case in c("uns_dict_default", "uns_scalar_default")) {
    for (format in c("h5ad", "zarr_v3")) {
      expect_false(is.null(cases[[case]][[format]]$error))
      key <- if (case == "uns_dict_default") "uns" else "uns/u"
      expect_anndata_condition(
        read_elem_lazy(if (format == "h5ad") file else zarr, key),
        "anndata_io_registry_error"
      )
    }
  }
})

# The chunks argument and default of each dense or sparse row of the table,
# against the chunk grid of the seed
table_chunks <- function(row) {
  vapply(row$result$chunks, function(axis) as.integer(axis[[1L]]), integer(1))
}

lazy_chunk_rows <- list(
  dense_float32_default = list("X", NULL),
  dense_float32_chunks_2_2 = list("X", c(2, 2)),
  dense_float32_chunks_minus1_none = list("X", c(-1, NA)),
  dense_bool_default = list("layers/dense_bool", NULL),
  dense_bool_chunks_2_2 = list("layers/dense_bool", c(2, 2)),
  dense_bool_chunks_minus1_none = list("layers/dense_bool", c(-1, NA)),
  csr_float32_default = list("layers/csr", NULL),
  csr_float32_chunks_2_minus1 = list("layers/csr", c(2, -1)),
  csc_float64_default = list("layers/csc", NULL),
  csc_float64_chunks_minus1_2 = list("layers/csc", c(-1, 2)),
  # The chunk grid does not depend on the dtype, so other dtypes of the table
  # reuse the layers above
  dense_int64_default = list("layers/dense_i", NULL),
  dense_int64_chunks_2_2 = list("layers/dense_i", c(2, 2)),
  dense_int64_chunks_minus1_none = list("layers/dense_i", c(-1, NA)),
  csr_int64_default = list("layers/csr", NULL),
  csr_int64_chunks_2_minus1 = list("layers/csr", c(2, -1)),
  csr_bool_default = list("layers/csr", NULL),
  csr_bool_chunks_2_minus1 = list("layers/csr", c(2, -1)),
  csc_uint8_default = list("layers/csc", NULL),
  csc_uint8_chunks_minus1_2 = list("layers/csc", c(-1, 2))
)

test_that("chunks follow the rows of the lazy operations table", {
  # The chunk grid of each default and explicit chunks row, on h5ad and zarr v3
  cases <- lazy_cases()$read_elem_lazy
  paths <- lazy_small_paths()
  for (row in names(lazy_chunk_rows)) {
    spec <- lazy_chunk_rows[[row]]
    for (format in names(paths)) {
      lazy <- read_elem_lazy(paths[[format]], spec[[1L]], chunks = spec[[2L]])
      expect_identical(
        DelayedArray::chunkdim(DelayedArray::seed(lazy)),
        table_chunks(cases[[row]][[format]]),
        label = paste(row, format)
      )
    }
  }
})

test_that("chunks errors follow the rows of the lazy operations table", {
  # Rows *_chunks_bad_length and csr/csc *_chunks_minor_axis are errors in
  # Python, here anndata_invalid_value_error
  cases <- lazy_cases()$read_elem_lazy
  paths <- lazy_small_paths()
  errors <- list(
    dense_bool_chunks_bad_length = list("layers/dense_bool", 2),
    dense_float32_chunks_bad_length = list("X", 2),
    dense_int64_chunks_bad_length = list("layers/dense_i", 2),
    csr_bool_chunks_bad_length = list("layers/csr", 2),
    csr_float32_chunks_bad_length = list("layers/csr", 2),
    csr_int64_chunks_bad_length = list("layers/csr", 2),
    csr_bool_chunks_minor_axis = list("layers/csr", c(2, 2)),
    csr_float32_chunks_minor_axis = list("layers/csr", c(2, 2)),
    csr_int64_chunks_minor_axis = list("layers/csr", c(2, 2)),
    csc_float64_chunks_minor_axis = list("layers/csc", c(2, 2)),
    csc_uint8_chunks_minor_axis = list("layers/csc", c(2, 2))
  )
  for (row in names(errors)) {
    for (format in names(paths)) {
      expect_false(is.null(cases[[row]][[format]]$error), label = row)
      expect_anndata_condition(
        read_elem_lazy(
          paths[[format]],
          errors[[row]][[1L]],
          errors[[row]][[2L]]
        ),
        "anndata_invalid_value_error"
      )
    }
  }
})

test_that("chunks are ignored for categorical columns", {
  # Row categorical_chunks_ignored (nullable ones are in the values test)
  paths <- lazy_small_paths()
  lazy <- read_elem_lazy(paths$h5ad, "obs/cat", chunks = 2)
  expect_s4_class(lazy, "LazyCategorical")
})

test_that("bad arguments and stores raise classed errors", {
  # Argument validation of read_elem_lazy() and the store forms it rejects
  paths <- lazy_small_paths()
  expect_anndata_condition(
    read_elem_lazy(paths$h5ad, "X", chunks = "a"),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    read_elem_lazy(paths$h5ad, "X", chunks = numeric()),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    read_elem_lazy(paths$h5ad, c("X", "obs")),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    read_elem_lazy(1L, "X"),
    "anndata_invalid_value_error"
  )
  not_zarr <- withr::local_tempdir()
  expect_anndata_condition(
    read_elem_lazy(not_zarr, "X"),
    "anndata_invalid_value_error"
  )
})

test_that("an h5ad file opened from a path is released with its objects", {
  # The closer attribute on the handle closes the file once no lazy object
  # holds it, so a read-write open then works
  paths <- lazy_small_paths()
  lazy <- read_elem_lazy(paths$h5ad, "X")
  expect_false(file_is_free(paths$h5ad))
  rm(lazy)
  gc()
  expect_true(file_is_free(paths$h5ad))
})

test_that("dense fixtures on every format read lazily from a path", {
  # The path form works for zarr v2 as well, with the exact values of the
  # eager read
  for (format in lazy_formats) {
    path <- lazy_fixture_path("array_int32", format)
    lazy <- read_elem_lazy(path, "x")
    expect_equal(
      as.array(lazy),
      unclass(drop_dtype(lazy_eager_elem(path, "/x"))),
      ignore_attr = TRUE
    )
  }
})

test_that("a missing store raises the file-not-found error", {
  # Row missing_store of read_lazy: FileNotFoundError in Python
  expect_anndata_condition(
    read_elem_lazy(file.path(tempdir(), "missing.h5ad"), "X"),
    "anndata_file_not_found_error"
  )
})
