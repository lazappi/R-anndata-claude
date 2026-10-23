legacy_h5ad_files <- c(
  "0.10.9-neighbors.h5ad",
  "0.6.22-dense.h5ad",
  "0.6.22-sparse.h5ad",
  "0.7.8-dense.h5ad",
  "0.7.8-sparse.h5ad"
)

# Reads a legacy file backed and in memory, returning both and the paths of
# the old format warnings raised by the backed read
read_both_ways <- function(file, env = parent.frame()) {
  path <- fixture_path(file.path("legacy", file))
  memory <- quietly_read(function() read_h5ad(path))
  warned <- character()
  backed <- withCallingHandlers(
    read_h5ad(path, backed = "r"),
    anndata_old_format_warning = function(cnd) {
      warned <<- c(warned, cnd$path)
      rlang::cnd_muffle(cnd)
    },
    anndata_future_warning = function(cnd) rlang::cnd_muffle(cnd)
  )
  withr::defer(backed$file$close(), envir = env)
  list(memory = memory, backed = backed, warned = warned)
}

# Why: Python reads every legacy h5ad file with backed = "r", so the backed
# object must have the same obs, var, obsp, uns and Raw as an in-memory read,
# with X and raw X left on disk
test_that("legacy h5ad files read in backed mode as they do in memory", {
  for (file in legacy_h5ad_files) {
    both <- read_both_ways(file)
    memory <- both$memory
    backed <- both$backed
    expect_true(backed$isbacked, info = file)
    expect_equal(dim(backed), dim(memory), info = file)
    expect_equal(backed$obs, memory$obs, info = file)
    expect_equal(backed$var, memory$var, info = file)
    expect_setequal(names(backed$obsp), names(memory$obsp))
    expect_equal(names(backed$uns), names(memory$uns), info = file)
    expect_equal(is.null(backed$raw), is.null(memory$raw), info = file)
    if (!is.null(memory$raw)) {
      expect_equal(dim(backed$raw), dim(memory$raw), info = file)
    }
  }
})

# Why: backed X of a legacy dense dataset or h5sparse group, and the Raw X, must
# read the same values as the in-memory matrix (shape orientation, data path
# and dtype), and the unencoded X must raise the old format warning
test_that("backed legacy X gives the values of the in-memory read", {
  for (file in setdiff(legacy_h5ad_files, "0.10.9-neighbors.h5ad")) {
    both <- read_both_ways(file)
    # The sparse X of 0.7.8 has encoding metadata, so it does not warn
    expect_equal(
      "/X" %in% both$warned,
      file != "0.7.8-sparse.h5ad",
      info = file
    )
    loaded <- both$backed$to_memory()
    expect_equal(
      unname(as.matrix(drop_dtype(loaded$X))),
      unname(as.matrix(drop_dtype(both$memory$X))),
      info = file
    )
    expect_equal(
      unname(as.matrix(drop_dtype(loaded$raw$X))),
      unname(as.matrix(drop_dtype(both$memory$raw$X))),
      info = file
    )
  }
})

# Why: Python's read_lazy only reads the current encodings, so the neighbors
# stores (written by a current release) work and keep the matrices in uns
# (nothing moves to obsp), while the legacy dataframes and `raw.X` raise
# (0.6.22 zarr cannot be read by Python at all, so it is not tested)
test_that("read_lazy follows Python for legacy files", {
  for (path in c(
    fixture_path("legacy/0.10.9-neighbors.h5ad"),
    file.path(legacy_zarr_dir(), "0.10.9-neighbors.zarr")
  )) {
    lazy <- suppressWarnings(read_lazy(path))
    expect_equal(length(lazy$obsp), 0L, info = path)
    expect_equal(names(lazy$uns), "neighbors", info = path)
    expect_setequal(
      names(lazy$uns$neighbors),
      c("connectivities", "distances", "params")
    )
  }
  failing <- c(
    fixture_path(file.path(
      "legacy",
      setdiff(legacy_h5ad_files, "0.10.9-neighbors.h5ad")
    )),
    file.path(legacy_zarr_dir(), c("0.7.8-dense.zarr", "0.7.8-sparse.zarr"))
  )
  for (path in failing) {
    expect_error(
      quietly_read(function() suppressWarnings(read_lazy(path))),
      class = "anndata_error",
      info = path
    )
  }
})

# Why: reading a legacy file and writing it must give the current encodings,
# and Python must read the written file as equal to its own rewrite
test_that("legacy files written by R equal Python's rewrite", {
  skip_if_no_python()
  paths <- fixture_path(file.path("legacy", legacy_h5ad_files))
  rewritten <- python_rewrite_h5ad(paths)
  written <- withr::local_tempfile(
    pattern = legacy_h5ad_files,
    fileext = ".h5ad"
  )
  for (i in seq_along(paths)) {
    adata <- quietly_read(function() read_h5ad(paths[[i]]))
    write_h5ad(adata, written[[i]])
  }
  expect_python_equal(written, rewritten)
  for (i in seq_along(written)) {
    elem <- rhdf5::H5Fopen(written[[i]], flags = "H5F_ACC_RDONLY")
    expect_equal(
      read_elem_attr(rhdf5::H5Oopen(elem, "obs"), "encoding-type"),
      "dataframe",
      info = legacy_h5ad_files[[i]]
    )
    rhdf5::h5closeAll()
  }
})

# Why: the zarr stores of 0.7.8 must read and rewrite like the h5ad files
test_that("legacy zarr stores written by R equal Python's rewrite", {
  skip_if_no_python()
  stores <- file.path(
    legacy_zarr_dir(),
    c("0.7.8-dense.zarr", "0.7.8-sparse.zarr", "0.10.9-neighbors.zarr")
  )
  rewritten <- python_rewrite_h5ad(stores)
  written <- withr::local_tempfile(
    pattern = basename(stores),
    fileext = ".h5ad"
  )
  for (i in seq_along(stores)) {
    adata <- quietly_read(function() read_zarr(stores[[i]]))
    write_h5ad(adata, written[[i]])
  }
  expect_python_equal(written, rewritten)
})
