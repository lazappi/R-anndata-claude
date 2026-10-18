# Tests of read_lazy() (ticket lazy/07): a lazy AnnData from h5ad and zarr.

skip_if_not_installed("Rarr", "2.1.48")

test_that("read_lazy() gives an AnnData with lazy slots", {
  # X, layers, obs and var must stay on disk, and their shape must match
  paths <- lazy_small_paths()
  for (path in paths) {
    adata <- read_lazy(path)
    expect_s3_class(adata, "AnnData")
    expect_equal(unname(adata$shape), c(4L, 3L))
    expect_s4_class(adata$X, "DelayedArray")
    expect_s4_class(adata$layers[["csr"]], "DelayedArray")
    expect_s4_class(adata$obs, "LazyDFrame")
    expect_equal(adata$obs_names, paste0("o", 0:3))
  }
})

test_that("read_lazy() realises to what read_h5ad() and read_zarr() give", {
  # Realised lazy values must equal the eager read of the same file
  paths <- lazy_small_paths()
  eager <- read_h5ad(paths$h5ad)
  lazy <- read_lazy(paths$h5ad)
  expect_equal(as.matrix(lazy$X), as.matrix(eager$X), ignore_attr = TRUE)
  expect_equal(
    as.matrix(lazy$layers[["csc"]]),
    as.matrix(eager$layers[["csc"]]),
    ignore_attr = TRUE
  )
  expect_equal(
    as.matrix(lazy$layers[["dense_bool"]]),
    as.matrix(eager$layers[["dense_bool"]]),
    ignore_attr = TRUE
  )
})

test_that("read_lazy() with load_annotation_index = FALSE", {
  # Python's dummy range index replaces the names, as the table row records
  paths <- lazy_small_paths()
  adata <- read_lazy(paths$h5ad, load_annotation_index = FALSE)
  expect_equal(adata$obs_names, as.character(0:3))
  expect_equal(adata$var_names, as.character(0:2))
})

test_that("read_lazy() reads obsm, obsp, varm and raw lazily", {
  # The slots other than X and layers must be lazy too, raw included
  dir <- withr::local_tempdir()
  x <- matrix(as.numeric(1:6), nrow = 3)
  adata <- AnnData(
    X = x,
    obsm = list(pca = matrix(as.numeric(1:6), nrow = 3)),
    varm = list(load = matrix(as.numeric(1:4), nrow = 2)),
    obsp = list(graph = matrix(as.numeric(1:9), nrow = 3)),
    uns = list(u = 1)
  )
  adata$raw <- adata
  paths <- c(h5ad = file.path(dir, "a.h5ad"), zarr = file.path(dir, "a.zarr"))
  write_h5ad(adata, paths[["h5ad"]])
  write_zarr(adata, paths[["zarr"]])
  for (path in paths) {
    lazy <- read_lazy(path)
    expect_s4_class(lazy$obsm[["pca"]], "DelayedArray")
    expect_s4_class(lazy$varm[["load"]], "DelayedArray")
    expect_s4_class(lazy$obsp[["graph"]], "DelayedArray")
    expect_s4_class(lazy$raw$X, "DelayedArray")
    expect_equal(as.matrix(lazy$obsm[["pca"]]), x, ignore_attr = TRUE)
    expect_equal(lazy$uns[["u"]], 1, ignore_attr = TRUE)
  }
})

test_that("read_lazy() on zarr realises the same values as read_zarr()", {
  # The zarr v3 path must agree with the eager reader, as the h5ad one does
  paths <- lazy_small_paths()
  eager <- read_zarr(paths$zarr_v3)
  lazy <- read_lazy(paths$zarr_v3)
  expect_equal(as.matrix(lazy$X), as.matrix(eager$X), ignore_attr = TRUE)
  expect_equal(
    as.matrix(lazy$layers[["dense_i"]]),
    as.matrix(eager$layers[["dense_i"]]),
    ignore_attr = TRUE
  )
})

test_that("the dummy index of load_annotation_index = FALSE does not warn", {
  # Python's range index is already a string index, so no implicit conversion
  paths <- lazy_small_paths()
  expect_no_warning(read_lazy(paths$h5ad, load_annotation_index = FALSE))
})

test_that("an AnnData accepts a DelayedArray X", {
  # as_anndata_matrix() keeps lazy arrays as they are, which read_lazy() needs
  x <- DelayedArray::DelayedArray(matrix(as.numeric(1:6), nrow = 3))
  adata <- AnnData(X = x)
  expect_s4_class(adata$X, "DelayedArray")
  expect_equal(unname(adata$shape), c(3L, 2L))
})

test_that("read_lazy() checks its arguments", {
  # Flags must be a single TRUE or FALSE
  expect_anndata_condition(
    read_lazy(tempfile(fileext = ".h5ad"), load_annotation_index = "yes"),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    read_lazy(tempfile(fileext = ".zarr")),
    "anndata_file_not_found_error"
  )
})

test_that("read_lazy() rejects NA flags and a missing h5ad file", {
  # NA is not a valid flag and a missing .h5ad path is a file error
  expect_anndata_condition(
    read_lazy(tempfile(fileext = ".h5ad"), load_annotation_index = NA),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    read_lazy(tempfile(fileext = ".h5ad")),
    "anndata_file_not_found_error"
  )
})
