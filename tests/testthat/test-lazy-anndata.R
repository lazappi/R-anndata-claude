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

test_that("read_lazy() gives the lazy classes the default table row lists", {
  # Row `default`: every array slot is a dask array and obs/var are lazy frames
  # (Dataset2D), shape and names come from the file, uns is not a lazy frame
  row <- lazy_row("read_lazy", "default", "h5ad")$result
  expect_equal(unlist(row$shape), c(4L, 3L))
  expect_equal(unlist(row$obs_names), paste0("o", 0:3))
  expect_equal(unlist(row$var_names), paste0("v", 0:2))
  expect_equal(row$obs_type, "Dataset2D")
  paths <- lazy_small_paths()
  for (path in paths) {
    adata <- read_lazy(path)
    expect_equal(unname(adata$shape), unlist(row$shape))
    expect_equal(adata$obs_names, unlist(row$obs_names))
    expect_equal(adata$var_names, unlist(row$var_names))
    expect_s4_class(adata$obs, "LazyDFrame")
    expect_s4_class(adata$var, "LazyDFrame")
    expect_setequal(colnames(adata$obs), c("num", "ni", "nb", "cat"))
    for (key in names(adata$layers)) {
      expect_s4_class(adata$layers[[key]], "DelayedArray")
    }
  }
})

test_that("load_annotation_index rows give the names the table lists", {
  # Rows `load_annotation_index_true` and `_false`: the file names, or "0"...
  true_row <- lazy_row("read_lazy", "load_annotation_index_true", "h5ad")$result
  false_row <- lazy_row(
    "read_lazy",
    "load_annotation_index_false",
    "h5ad"
  )$result
  paths <- lazy_small_paths()
  for (path in paths) {
    kept <- read_lazy(path, load_annotation_index = TRUE)
    dropped <- read_lazy(path, load_annotation_index = FALSE)
    expect_equal(kept$obs_names, unlist(true_row$obs_names))
    expect_equal(dropped$obs_names, unlist(false_row$obs_names))
    expect_equal(dropped$var_names, unlist(false_row$var_names))
  }
})

test_that("lazy slots have the types of their on-disk dtypes", {
  # The table lists dtypes per layer, R's type() follows: float stays double,
  # integers and bool become integer and logical
  paths <- lazy_small_paths()
  for (path in paths) {
    adata <- read_lazy(path)
    expect_equal(DelayedArray::type(adata$X), "double")
    expect_equal(DelayedArray::type(adata$layers[["dense_i"]]), "integer")
    expect_equal(DelayedArray::type(adata$layers[["dense_bool"]]), "logical")
    expect_equal(DelayedArray::type(adata$layers[["csr"]]), "double")
  }
})

test_that("uns is read eagerly, unlike Python's lazy uns arrays", {
  # Documented deviation: Python's read_lazy keeps arrays in uns as dask arrays,
  # here uns is an ordinary list (a plain R vector has no lazy form)
  dir <- withr::local_tempdir()
  adata <- AnnData(X = matrix(1, 2, 2), uns = list(nested = list(k = 1:3)))
  path <- file.path(dir, "uns.h5ad")
  write_h5ad(adata, path)
  lazy <- read_lazy(path)
  expect_false(methods::is(lazy$uns[["nested"]][["k"]], "DelayedArray"))
  expect_equal(as.integer(lazy$uns[["nested"]][["k"]]), 1:3)
})

test_that("read_lazy() reads the zarr v2 fixture", {
  # Row `default` for zarr_v2: a v2 store reads like v3, with consolidated
  # metadata present so no warning
  path <- zarr_variant_paths("v2")[["anndata_full"]]
  adata <- expect_no_warning(read_lazy(path))
  eager <- read_zarr(path)
  expect_equal(unname(adata$shape), unname(eager$shape))
  expect_equal(adata$obs_names, eager$obs_names)
  expect_s4_class(adata$X, "DelayedArray")
  expect_equal(as.matrix(adata$X), as.matrix(eager$X), ignore_attr = TRUE)
})

test_that("an unconsolidated zarr v2 store warns like Python", {
  # Row `unconsolidated_zarr`: Python warns, reads group by group, and gives
  # the same object
  src <- zarr_variant_paths("v2")[["anndata_full"]]
  dir <- withr::local_tempdir()
  path <- file.path(dir, "unconsolidated.zarr")
  file.copy(src, dir, recursive = TRUE)
  file.rename(file.path(dir, basename(src)), path)
  unlink(file.path(path, ".zmetadata"))
  row <- lazy_row("read_lazy", "unconsolidated_zarr", "zarr_v2")
  expect_equal(
    row$warnings[[1]]$message,
    "Did not read zarr as consolidated. Consider consolidating your metadata."
  )
  cnd <- expect_warning(
    read_lazy(path),
    class = "anndata_unconsolidated_zarr_warning"
  )
  expect_match(
    gsub("\\s+", " ", conditionMessage(cnd)),
    "Did not read zarr as consolidated. Consider consolidating your metadata.",
    fixed = TRUE
  )
  adata <- suppressWarnings(read_lazy(path))
  expect_s4_class(adata$X, "DelayedArray")
  # read_elem_lazy() does not warn in Python
  expect_no_warning(read_elem_lazy(path, "X"))
})

test_that("read_lazy() takes an open handle (row open_handle)", {
  # Handles of an h5ad file and of a zarr store give the same lazy object as
  # the path
  paths <- lazy_small_paths()
  by_path <- read_lazy(paths$h5ad)
  h5 <- rhdf5::H5Fopen(paths$h5ad, flags = "H5F_ACC_RDONLY")
  withr::defer(rhdf5::H5Fclose(h5))
  from_h5 <- read_lazy(h5)
  expect_equal(from_h5$obs_names, by_path$obs_names)
  expect_equal(as.matrix(from_h5$X), as.matrix(by_path$X), ignore_attr = TRUE)
  from_zarr <- read_lazy(zarr_open(paths$zarr_v3))
  expect_s4_class(from_zarr$X, "DelayedArray")
  expect_equal(from_zarr$var_names, by_path$var_names)
})

test_that("a missing zarr directory is a file-not-found error", {
  # Row `missing_store` for zarr: FileNotFoundError, "does not exist"
  path <- file.path(withr::local_tempdir(), "missing.zarr")
  expect_anndata_condition(read_lazy(path), "anndata_file_not_found_error")
})
