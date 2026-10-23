legacy_zarr_dir <- local({
  dir <- NULL
  function() {
    if (is.null(dir)) {
      dir <<- tempfile("legacy-zarr")
      dir.create(dir)
      utils::untar(fixture_path("legacy-zarr-fixtures.tar.gz"), exdir = dir)
    }
    dir
  }
})

# Reads the Element at `path` of a legacy fixture, returning the value and the
# paths of the old format warnings raised (each is muffled, as Python records
# them without stopping)
read_legacy_elem <- function(file, path, env = parent.frame()) {
  if (endsWith(file, ".zarr")) {
    store <- zarr_open(file.path(legacy_zarr_dir(), file))
  } else {
    store <- rhdf5::H5Fopen(
      fixture_path(file.path("legacy", file)),
      flags = "H5F_ACC_RDONLY"
    )
    withr::defer(rhdf5::h5closeAll(), envir = env)
  }
  warned <- character()
  value <- withCallingHandlers(
    read_elem(store, path),
    anndata_old_format_warning = function(cnd) {
      warned <<- c(warned, cnd$path)
      rlang::cnd_muffle(cnd)
    }
  )
  list(value = value, warned = sort(warned))
}

# The paths Python warned about under `prefix` (the Element itself and members)
table_warned <- function(file, prefix) {
  messages <- vapply(
    legacy_table()$fixtures[[file]]$warnings,
    function(w) w$message,
    character(1)
  )
  paths <- sub(
    "^Element '(.*)' was written without encoding metadata[.]$",
    "\\1",
    messages[grepl("^Element '", messages)]
  )
  sort(paths[paths == prefix | startsWith(paths, paste0(prefix, "/"))])
}

# A dense table entry (`values` are rows) as an R array
table_dense <- function(entry) {
  if (length(entry$shape) == 1L) {
    return(unlist(entry$values))
  }
  table_matrix(entry$values)
}

# Why: unencoded Elements are read as `read_basic` does, with values and one
# old format warning per Element equal to what Python 0.13.4 gave for the same
# files (the committed expectation table), for the 0.6.22 and 0.7.8 releases
test_that("unencoded dense Elements read to the values Python reads", {
  values <- legacy_table()$fixtures[["0.6.22-dense.h5ad"]]$values
  cases <- list(
    list("/X", values$X),
    list("/layers/counts", values$layers$counts),
    list("/obsm/X_pca", values$obsm$X_pca),
    list("/varm/PCs", values$varm$PCs),
    list("/uns/arr", values$uns$arr)
  )
  for (case in cases) {
    result <- read_legacy_elem("0.6.22-dense.h5ad", case[[1]])
    expect_equal(
      unname(drop_dtype(result$value)),
      unname(table_dense(case[[2]])),
      tolerance = 1e-6,
      info = case[[1]]
    )
    expect_equal(result$warned, table_warned("0.6.22-dense.h5ad", case[[1]]))
  }
  # float32 on disk is kept
  x <- read_legacy_elem("0.6.22-dense.h5ad", "/X")$value
  expect_equal(get_dtype(x), "float32")
})

# Why: 0.6.22 stores scalars and strings as 1-element arrays, which Python reads
# as arrays (not scalars), so they must keep a dim of 1 to be written back as
# arrays
test_that("1-element arrays of 0.6.22 stay arrays", {
  result <- read_legacy_elem("0.6.22-dense.h5ad", "/uns")
  expect_equal(result$warned, table_warned("0.6.22-dense.h5ad", "/uns"))
  # The `*_categories` members are cleaned up later (legacy-formats/04)
  expect_setequal(
    names(result$value),
    c("arr", "cat_categories", "neighbors", "scalar", "str", "str_categories")
  )
  expect_equal(dim(result$value$scalar), 1L)
  expect_equal(as.vector(result$value$scalar), 3)
  expect_equal(dim(result$value$str), 1L)
  expect_equal(as.vector(result$value$str), "hello")
  n <- result$value$neighbors$params$n
  expect_equal(dim(n), 1L)
  expect_equal(as.vector(n), 3)
  # Python gives its two connectivity matrices as csr_matrix
  expect_s4_class(result$value$neighbors$connectivities, "dgRMatrix")
})

# Why: 0.7.x writes scalars and strings as 0-d datasets, which Python reads as
# a numpy scalar and a str
test_that("0-d datasets of 0.7.8 read as scalars", {
  for (file in c("0.7.8-dense.h5ad", "0.7.8-dense.zarr")) {
    result <- read_legacy_elem(file, "/uns")
    expect_equal(result$warned, table_warned(file, "/uns"), info = file)
    expect_null(dim(result$value$scalar))
    expect_equal(as.vector(result$value$scalar), 3, info = file)
    expect_equal(result$value$str, "hello", info = file)
    expect_equal(as.vector(result$value$neighbors$params$n), 3, info = file)
    expect_equal(as.vector(result$value$arr), 0:2, info = file)
  }
})

# Why: the zarr store of 0.7.8 has the same unencoded Elements as the h5ad file
# and Python warns for the same paths
test_that("unencoded Elements read from a zarr store", {
  values <- legacy_table()$fixtures[["0.7.8-dense.zarr"]]$values
  for (case in list(
    list("/layers/counts", values$layers$counts),
    list("/obsm/X_pca", values$obsm$X_pca)
  )) {
    result <- read_legacy_elem("0.7.8-dense.zarr", case[[1]])
    expect_equal(
      unname(drop_dtype(result$value)),
      unname(table_dense(case[[2]])),
      tolerance = 1e-6,
      info = case[[1]]
    )
    expect_equal(result$warned, table_warned("0.7.8-dense.zarr", case[[1]]))
  }
})

# Why: h5sparse groups (a group with `h5sparse_format` and `h5sparse_shape`)
# are matrices of the stated format, not dicts, and Python warns once for the
# group
test_that("h5sparse groups read to a CSR matrix", {
  values <- legacy_table()$fixtures[["0.6.22-sparse.h5ad"]]$values
  cases <- list(
    list("/X", values$X),
    list("/layers/counts", values$layers$counts),
    list("/uns/neighbors/connectivities", values$obsp$connectivities),
    list("/uns/neighbors/distances", values$obsp$distances)
  )
  for (case in cases) {
    result <- read_legacy_elem("0.6.22-sparse.h5ad", case[[1]])
    expect_s4_class(result$value, "dgRMatrix")
    expect_equal(
      unname(as.matrix(drop_dtype(result$value))),
      unname(table_matrix(case[[2]]$values)),
      tolerance = 1e-6,
      info = case[[1]]
    )
    expect_equal(result$warned, table_warned("0.6.22-sparse.h5ad", case[[1]]))
  }
})

# Why: h5sparse_format picks CSC too, and the group is read for any attribute
# value Python's `sparse_dataset` accepts
test_that("an h5sparse group with a csc format reads to a CSC matrix", {
  path <- withr::local_tempfile(fileext = ".h5")
  rhdf5::h5createFile(path)
  store <- rhdf5::H5Fopen(path)
  withr::defer(rhdf5::h5closeAll())
  m <- methods::as(
    Matrix::Matrix(
      matrix(c(1, 0, 2, 0, 3, 4), nrow = 2),
      sparse = TRUE
    ),
    "CsparseMatrix"
  )
  group <- rhdf5::H5Gcreate(store, "m")
  set_elem_attr(group, "h5sparse_format", "csc")
  attr_write(group, "h5sparse_shape", c(2L, 3L), scalar = FALSE)
  write_dataset(group, "data", m@x)
  write_dataset(group, "indices", m@i)
  write_dataset(group, "indptr", m@p)
  rhdf5::H5Gclose(group)

  warned <- FALSE
  value <- withCallingHandlers(
    read_elem(store, "m"),
    anndata_old_format_warning = function(cnd) {
      warned <<- TRUE
      rlang::cnd_muffle(cnd)
    }
  )
  expect_true(warned)
  expect_s4_class(value, "dgCMatrix")
  expect_equal(unname(as.matrix(drop_dtype(value))), as.matrix(m))
})

# Why: a missing shape attribute must be a classed error, not an rhdf5 failure
test_that("an h5sparse group without a shape raises an error", {
  store <- local_h5_store()
  group <- rhdf5::H5Gcreate(store, "m")
  set_elem_attr(group, "h5sparse_format", "csr")
  rhdf5::H5Gclose(group)
  expect_anndata_condition(
    suppressWarnings(read_elem(store, "m")),
    "anndata_io_registry_error"
  )
})

# Why: the warning is a classed condition naming the path, as Python's
# OldFormatWarning does
test_that("the old format warning is classed and names the path", {
  store <- local_h5_store()
  write_elem(store, "d", list(a = 1L))
  rhdf5::H5Adelete(rhdf5::H5Gopen(store, "d"), "encoding-type")
  rhdf5::H5Adelete(rhdf5::H5Gopen(store, "d"), "encoding-version")
  cnd <- expect_warning(
    read_elem(store, "d"),
    class = "anndata_old_format_warning"
  )
  expect_s3_class(cnd, "anndata_warning")
  expect_equal(cnd$path, "/d")
  expect_match(conditionMessage(cnd), "without encoding metadata", fixed = TRUE)
})

# Why: writing always uses the current encodings, so what was read from an
# unencoded Element is written with the encoding of its value
test_that("unencoded Elements are written back with current encodings", {
  value <- read_legacy_elem("0.6.22-dense.h5ad", "/uns")$value
  store <- local_h5_store()
  write_elem(store, "uns", value)
  expect_equal(
    read_elem_attr(rhdf5::H5Gopen(store, "uns"), "encoding-type"),
    "dict"
  )
  back <- read_elem(store, "uns")
  expect_equal(back$arr, value$arr)
  expect_equal(dim(back$scalar), 1L)
})

# Why: an unencoded root is how every 0.6 and 0.7 file starts, and Python
# reads it without a warning for the root itself, but a root with no obs gives
# nothing to build an AnnData from
test_that("an unencoded root without obs is a legacy error", {
  path <- withr::local_tempfile(fileext = ".h5ad")
  rhdf5::h5createFile(path)
  expect_error(read_h5ad(path), class = "anndata_legacy_format_error")
})
