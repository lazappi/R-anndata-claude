adata_fixture_names <- c(
  "anndata_full",
  "anndata_no_raw",
  "anndata_empty_slots",
  "anndata_sparse_x",
  "anndata_no_x",
  "anndata_0_obs",
  "anndata_0_vars",
  "anndata_raw_own_var",
  "anndata_raw_0_obs",
  "anndata_raw_0_vars"
)

adata_fixture_files <- function() {
  fixture_path(file.path("h5ad", paste0(adata_fixture_names, ".h5ad")))
}

# AnnData objects built in R that cover the Slots, with alphabetical keys
# because h5py lists the members of a dict that way
r_built_adatas <- function() {
  obs <- data.frame(
    group = factor(c("a", "b", "a", "b")),
    n = c(1, 2, 3, 4),
    row.names = paste0("cell", 0:3)
  )
  var <- data.frame(
    score = c(0.5, 1.5, 2.5),
    row.names = paste0("gene", 0:2)
  )
  x <- matrix(as.numeric(1:12), 4)
  sparse <- methods::as(
    Matrix::sparseMatrix(
      i = c(1, 3, 4),
      j = c(1, 2, 3),
      x = c(1, 2, 3),
      dims = c(4, 3)
    ),
    "CsparseMatrix"
  )
  full <- AnnData(
    X = x,
    obs = obs,
    var = var,
    obsm = list(pca = matrix(as.numeric(1:8), 4)),
    varm = list(load = matrix(as.numeric(1:6), 3)),
    obsp = list(conn = matrix(as.numeric(1:16), 4)),
    varp = list(corr = matrix(as.numeric(1:9), 3)),
    layers = list(counts = sparse),
    uns = list(note = "text", sub = list(k = c(1, 2, 3)))
  )
  with_raw <- full$copy()
  with_raw$raw <- full
  # Raw has a variable and a varm key that the object lacks
  own_var <- AnnData(matrix(as.numeric(1:8), 4), obs = obs)
  own_var$raw <- full
  raw_zero_obs <- AnnData(matrix(0, 0, 3))
  raw_zero_obs$raw <- raw_zero_obs
  raw_zero_vars <- AnnData(matrix(0, 2, 0))
  raw_zero_vars$raw <- raw_zero_vars
  list(
    full = full,
    with_raw = with_raw,
    raw_own_var = own_var,
    raw_zero_obs = raw_zero_obs,
    raw_zero_vars = raw_zero_vars,
    sparse_x = AnnData(sparse),
    no_x = AnnData(shape = c(2L, 3L)),
    empty_slots = AnnData(matrix(0, 2, 3)),
    zero_obs = AnnData(matrix(0, 0, 3)),
    zero_vars = AnnData(matrix(0, 2, 0))
  )
}

# Python -> R: the fixtures read with the Slots Python wrote, including raw
# with its own var and varm, no X, empty Slots and zero-length axes
test_that("Python-written h5ad files read as the expected AnnData", {
  full <- read_adata_fixture("anndata_full")
  expect_s3_class(full, "AnnData")
  expect_identical(full$shape, c(4L, 3L))
  expect_identical(full$obs_names, paste0("cell", 0:3))
  expect_identical(full$var_names, paste0("gene", 0:2))
  expect_identical(colnames(full$obs), c("group", "n"))
  expect_identical(levels(full$obs$group), c("a", "b"))
  expect_identical(get_dtype(full$X), "float32")
  expect_identical(names(full$obsm), "pca")
  expect_identical(names(full$varm), "load")
  expect_identical(names(full$obsp), "conn")
  expect_identical(names(full$varp), "corr")
  expect_true("counts" %in% names(full$layers))
  expect_identical(full$uns$note, "text")
  expect_identical(full$raw$shape, c(4L, 3L))

  expect_null(read_adata_fixture("anndata_no_raw")$raw)

  empty <- read_adata_fixture("anndata_empty_slots")
  expect_identical(empty$shape, c(2L, 3L))
  for (slot in c("obsm", "varm", "obsp", "varp")) {
    expect_length(empty[[slot]], 0L)
  }
  expect_length(empty$uns, 0L)
  expect_false(is.null(empty$X))

  expect_true(is_sparse(read_adata_fixture("anndata_sparse_x")$X))

  no_x <- read_adata_fixture("anndata_no_x")
  expect_null(no_x$X)
  expect_identical(no_x$shape, c(2L, 3L))

  expect_identical(read_adata_fixture("anndata_0_obs")$shape, c(0L, 3L))
  expect_identical(read_adata_fixture("anndata_0_vars")$shape, c(2L, 0L))

  own <- read_adata_fixture("anndata_raw_own_var")
  expect_identical(own$shape, c(4L, 2L))
  expect_identical(own$var_names, paste0("gene", 0:1))
  expect_identical(own$raw$shape, c(4L, 3L))
  expect_identical(own$raw$var_names, paste0("gene", 0:2))
  expect_identical(names(own$raw$varm), "load")
  expect_identical(read_adata_fixture("anndata_raw_0_obs")$raw$shape, c(0L, 3L))
  expect_identical(
    read_adata_fixture("anndata_raw_0_vars")$raw$shape,
    c(2L, 0L)
  )
})

# R -> R: writing and reading must keep every Slot of objects built in R,
# including the `NA` layer (X), which is stored at /X
test_that("AnnData objects built in R round trip through R", {
  for (label in names(r_built_adatas())) {
    adata <- r_built_adatas()[[label]]
    path <- withr::local_tempfile(fileext = ".h5ad")
    write_h5ad(adata, path)
    expect_identical(
      adata_parts(read_h5ad(path)),
      adata_parts(adata),
      info = label
    )
  }
})

# Python -> R -> Python: R must write the same groups, datasets, attributes and
# dtypes as Python did, and Python must read both as equal AnnData objects
test_that("R rewrites every h5ad fixture equivalent to Python", {
  skip_if_no_python()
  written <- character()
  for (name in adata_fixture_names) {
    written[[name]] <- withr::local_tempfile(fileext = ".h5ad")
    write_h5ad(read_adata_fixture(name), written[[name]])
  }
  originals <- adata_fixture_files()
  expect_all_equivalent(unname(written), originals)
  expect_python_equal(unname(written), originals)
})

# R -> Python -> R: Python reads and rewrites what R writes, and R reads that
# back as the object R built
test_that("Python reads and rewrites the AnnData objects R writes", {
  skip_if_no_python()
  built <- r_built_adatas()
  written <- character()
  for (label in names(built)) {
    written[[label]] <- withr::local_tempfile(fileext = ".h5ad")
    write_h5ad(built[[label]], written[[label]])
  }
  rewritten <- python_rewrite_h5ad(unname(written))
  for (i in seq_along(built)) {
    expect_identical(
      adata_parts(read_h5ad(rewritten[[i]])),
      adata_parts(built[[i]]),
      info = names(built)[[i]]
    )
  }
})

# The root layout Python's reader needs, checked offline
test_that("write_h5ad writes the root attributes and the empty dict groups", {
  path <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(AnnData(matrix(0, 2, 3)), path)

  attrs <- rhdf5::h5readAttributes(path, "/")
  expect_identical(attrs[["encoding-type"]], "anndata")
  expect_identical(attrs[["encoding-version"]], "0.1.0")
  listing <- rhdf5::h5ls(path)
  for (key in c("obsm", "varm", "obsp", "varp", "layers", "uns")) {
    group_attrs <- rhdf5::h5readAttributes(path, key)
    expect_identical(group_attrs[["encoding-type"]], "dict", info = key)
    expect_false(any(listing$group == paste0("/", key)), info = key)
  }
  expect_true(all(c("X", "obs", "var") %in% listing$name))
})

# ADR 0004: X is the `NA` layer, so it is written to /X and never to /layers
test_that("the NA layer is written to X and not inside layers", {
  adata <- AnnData(matrix(0, 2, 3), layers = list(a = matrix(1, 2, 3)))
  path <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(adata, path)

  listing <- rhdf5::h5ls(path)
  expect_identical(listing$name[listing$group == "/layers"], "a")
  expect_true("X" %in% listing$name[listing$group == "/"])
  expect_setequal(names(read_h5ad(path)$layers), c(NA, "a"))
})

# Python writes no X for an AnnData without one, and R must read that as NULL
test_that("an AnnData without X writes no X and reads back NULL", {
  path <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(AnnData(shape = c(2L, 3L)), path)

  expect_false("X" %in% rhdf5::h5ls(path)$name[rhdf5::h5ls(path)$group == "/"])
  expect_null(read_h5ad(path)$X)
})

# `write_h5ad()` replaces an existing file like Python's mode "w"
test_that("write_h5ad replaces an existing file", {
  path <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(AnnData(matrix(0, 2, 3)), path)
  write_h5ad(AnnData(matrix(0, 4, 5)), path)

  expect_identical(read_h5ad(path)$shape, c(4L, 5L))
})

# The method is the same as the function
test_that("adata$write_h5ad writes the same file as write_h5ad", {
  adata <- AnnData(matrix(as.numeric(1:6), 2))
  path <- withr::local_tempfile(fileext = ".h5ad")
  adata$write_h5ad(path)

  expect_identical(adata_parts(read_h5ad(path)), adata_parts(adata))
})

# Python converts strings in place by default and R must too, including raw$var
test_that("write_h5ad converts strings to categoricals in place", {
  obs <- data.frame(s = c("a", "a", "b"), row.names = c("x", "y", "z"))
  make <- function() {
    adata <- AnnData(matrix(0, 3, 2), obs = obs)
    adata$raw <- adata
    adata$raw$var <- data.frame(
      s = c("p", "p"),
      row.names = adata$var_names
    )
    adata
  }
  path <- withr::local_tempfile(fileext = ".h5ad")

  adata <- make()
  write_h5ad(adata, path)
  expect_s3_class(adata$obs$s, "factor")
  expect_s3_class(adata$raw$var$s, "factor")
  expect_s3_class(read_h5ad(path)$obs$s, "factor")

  adata <- make()
  write_h5ad(adata, path, convert_strings_to_categoricals = FALSE)
  expect_type(adata$obs$s, "character")
  expect_type(read_h5ad(path)$obs$s, "character")
})

# The constructor refuses higher-dimensional values, so they are assigned
adata_3d <- function(where) {
  adata <- AnnData(matrix(0, 2, 3))
  suppressWarnings(
    if (where == "X") {
      adata$X <- array(0, c(2, 3, 4))
    } else {
      adata$layers[["l"]] <- array(0, c(2, 3, 4))
    }
  )
  adata
}

# Python refuses X and layers above 2 dimensions on write
test_that("write_h5ad rejects X and layers with more than 2 dimensions", {
  path <- withr::local_tempfile(fileext = ".h5ad")
  expect_error(
    write_h5ad(adata_3d("X"), path),
    class = "anndata_non_2d_error"
  )
  expect_false(file.exists(path))

  adata <- adata_3d("layer")
  expect_error(write_h5ad(adata, path), class = "anndata_non_2d_error")
})

# Python warns on reading a file with a 3-D X and R must too
test_that("reading a file with a 3-D X warns", {
  path <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(AnnData(matrix(0, 2, 3)), path)
  store <- rhdf5::H5Fopen(path)
  write_elem(store, "X", array(0, c(2, 3, 4)))
  rhdf5::H5Fclose(store)

  expect_warning(read_h5ad(path), class = "anndata_non_2d_warning")
  adata <- suppressWarnings(read_h5ad(path))
  expect_identical(dim(adata$X), c(2L, 3L, 4L))
})

# Every unencodable Slot value must name its path, nothing is skipped
test_that("write_h5ad names the path of an unencodable value", {
  path <- withr::local_tempfile(fileext = ".h5ad")
  adata <- AnnData(matrix(0, 2, 3), uns = list(f = length))
  cnd <- expect_error(
    write_h5ad(adata, path),
    class = "anndata_io_registry_error"
  )
  expect_identical(cnd$path, "/uns/f")
})

test_that("write_h5ad and read_h5ad check their arguments", {
  path <- withr::local_tempfile(fileext = ".h5ad")
  expect_error(
    write_h5ad(matrix(0, 2, 3), path),
    class = "anndata_invalid_argument_error"
  )
  expect_error(
    write_h5ad(AnnData(matrix(0, 2, 3)), c(path, path)),
    class = "anndata_invalid_argument_error"
  )
  expect_error(read_h5ad(path), class = "anndata_file_not_found_error")
  expect_error(
    read_h5ad(path, backed = "r"),
    class = "anndata_not_supported_error"
  )
})

# A file with no encoding attributes is a legacy file, which is not supported
test_that("reading a file without encodings raises the legacy error", {
  path <- withr::local_tempfile(fileext = ".h5ad")
  rhdf5::h5createFile(path)

  expect_error(read_h5ad(path), class = "anndata_legacy_format_error")
})

# Python's `unwriteable()` is the reference, with the expectations committed
unwriteable_r_cases <- function() {
  with_raw <- AnnData(matrix(0, 2, 3))
  with_raw$raw <- with_raw
  list(
    plain = AnnData(matrix(0, 2, 3)),
    no_x = AnnData(shape = c(2L, 3L)),
    x_3d = adata_3d("X"),
    layer_3d = adata_3d("layer"),
    uns_nested = AnnData(
      matrix(0, 2, 3),
      uns = list(a = list(b = c(1, 2, 3)), s = "text")
    ),
    uns_none = AnnData(matrix(0, 2, 3), uns = list(n = NULL)),
    uns_date = AnnData(matrix(0, 2, 3), uns = list(d = Sys.Date())),
    uns_function = AnnData(matrix(0, 2, 3), uns = list(f = length)),
    uns_object = AnnData(matrix(0, 2, 3), uns = list(o = new.env())),
    obs_datetime = AnnData(
      matrix(0, 2, 3),
      obs = data.frame(
        t = as.POSIXct(c("2020-01-01", "2020-01-02"), tz = "UTC"),
        row.names = c("a", "b")
      )
    ),
    obsm_ok = AnnData(matrix(0, 2, 3), obsm = list(pca = matrix(0, 2, 2))),
    raw = with_raw
  )
}

test_that("unwriteable matches the Python results", {
  expected <- jsonlite::fromJSON(
    fixture_path("unwriteable_cases.json"),
    simplifyVector = FALSE
  )
  cases <- unwriteable_r_cases()
  expect_setequal(names(cases), names(expected))
  for (label in names(expected)) {
    expect_identical(
      cases[[label]]$unwriteable(),
      expected[[label]],
      info = label
    )
    for (store_type in c("h5", "zarr")) {
      expect_identical(
        cases[[label]]$unwriteable(store_type = store_type),
        expected[[label]],
        info = label
      )
    }
  }
})

# A partly named list cannot be written, so it must be reported (R only)
test_that("unwriteable reports lists that cannot be written", {
  adata <- AnnData(matrix(0, 2, 3), uns = list(a = list(1, 2)))
  expect_true(adata$unwriteable())
  expect_error(
    adata$unwriteable(store_type = "parquet"),
    class = "anndata_invalid_argument_error"
  )
})

# An object that unwriteable() accepts must really write
test_that("objects reported writeable can be written", {
  for (label in c("plain", "no_x", "uns_nested", "uns_none", "raw")) {
    adata <- unwriteable_r_cases()[[label]]
    path <- withr::local_tempfile(fileext = ".h5ad")
    expect_no_error(write_h5ad(adata, path))
  }
})

# Guards the committed Python results against a change of the cases
test_that("the committed unwriteable expectations match Python", {
  skip_if_no_python()
  fresh <- withr::local_tempfile(fileext = ".json")
  run_python("unwriteable_cases.py", fresh)
  expect_equal(
    readLines(fresh),
    readLines(fixture_path("unwriteable_cases.json"))
  )
})
