# Tests of the shape and chunks columns of array_info() (lazy/03), the backend
# neutral facts that lazy seeds need.

# The array nodes of a tree from h5_tree.py or zarr_tree.py
tree_arrays <- function(tree) {
  Filter(function(node) identical(node$kind, "dataset"), tree)
}

# Truth is Python's shape for every array: `NULL` (null datasets) is rank 0
expect_info_shapes <- function(store, tree, label) {
  for (node in tree_arrays(tree)) {
    info <- array_info(store, node$path)
    expect_identical(
      info$shape[[1L]],
      as.numeric(unlist(node$shape)),
      info = paste(label, node$path)
    )
    chunks <- if (is.null(node$chunks)) {
      NULL
    } else {
      as.numeric(unlist(node$chunks))
    }
    expect_identical(info$chunks[[1L]], chunks, info = paste(label, node$path))
  }
}

test_that("array_info() shape matches Python for every h5ad fixture array", {
  # The shape column feeds lazy seeds, so it must equal what h5py reports
  files <- list.files(
    fixture_path("h5ad"),
    pattern = "\\.h5(ad)?$",
    full.names = TRUE
  )
  prefetch_h5_trees(files)
  for (file in files) {
    store <- rhdf5::H5Fopen(file, flags = "H5F_ACC_RDONLY")
    expect_info_shapes(store, h5_tree(file), basename(file))
    rhdf5::h5closeAll()
  }
})

test_that("array_info() shape matches Python for every zarr fixture array", {
  # Same check for zarr v3 and v2, which read metadata not Rarr
  manifest <- zarr_fixture_manifest()
  dirs <- character()
  for (variant in c("v3", "v2")) {
    for (case in names(manifest$variants[[variant]]$cases)) {
      dirs <- c(
        dirs,
        zarr_fixture_path(file.path(variant, paste0(case, ".zarr")))
      )
    }
  }
  dirs <- dirs[dir.exists(dirs)]
  expect_gt(length(dirs), 0L)
  prefetch_h5_trees(dirs)
  for (dir in dirs) {
    expect_info_shapes(zarr_open(dir), h5_tree(dir), dir)
  }
})

test_that("array_info() chunks are NULL for contiguous HDF5 datasets", {
  # Python writes small datasets without chunking, so seeds must pick a grid
  store <- local_h5_store()
  write_elem(store, "x", matrix(as.numeric(1:6), nrow = 2))
  info <- array_info(store, "/x")
  expect_identical(info$shape[[1L]], c(2, 3))
  expect_null(info$chunks[[1L]])
})

test_that("array_info() chunks are in numpy order for chunked HDF5 datasets", {
  # HDF5 chunk shapes are row-major, the same order as Python
  store <- local_h5_store()
  write_elem(
    store,
    "x",
    matrix(as.numeric(1:60), nrow = 10),
    dataset_kwargs = list(compression = "gzip")
  )
  info <- array_info(store, "/x")
  expect_identical(info$shape[[1L]], c(10, 6))
  # A small compressed dataset is one chunk, and the order is not square
  expect_identical(info$chunks[[1L]], c(10, 6))
})

test_that("array_info() scalars have a shape of length 0 and no chunks", {
  # Scalar and null datasets have no dimensions
  store <- local_h5_store()
  write_elem(store, "s", 1.5)
  info <- array_info(store, "/s")
  expect_identical(info$shape[[1L]], numeric())
  expect_null(info$chunks[[1L]])
})

test_that("array_info() chunks are the inner chunk shape of zarr arrays", {
  # Readers see inner chunks of a sharded v3 array, as zarr-python's `chunks`
  dir <- withr::local_tempdir()
  store <- zarr_create(file.path(dir, "r.zarr"))
  write_elem(
    store,
    "x",
    matrix(as.numeric(1:60), nrow = 10),
    dataset_kwargs = list(chunks = c(5, 2))
  )
  info <- array_info(store, "/x")
  expect_identical(info$shape[[1L]], c(10, 6))
  expect_identical(info$chunks[[1L]], c(5, 2))
  write_elem(store, "s", 1.5)
  expect_null(array_info(store, "/s")$chunks[[1L]])
})
