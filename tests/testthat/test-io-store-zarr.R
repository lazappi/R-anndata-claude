# Tests of the zarr read backend of the store layer (ticket zarr-io/04), below
# any encoding: groups, attributes, arrays and their On-disk dtype records.

# The zarr fixture store of a case in a variant
zarr_case_store <- function(variant, case) {
  zarr_open(zarr_fixture_path(file.path(variant, paste0(case, ".zarr"))))
}

# The h5ad fixture of a case read with the HDF5 backend, the oracle for the
# values of the same case in zarr (both were written by Python from one case)
h5_case_array <- function(case, path = "/x", env = parent.frame()) {
  file <- fixture_path(file.path("h5ad", paste0(case, ".h5")))
  if (!file.exists(file)) {
    return(NULL)
  }
  store <- rhdf5::H5Fopen(file, flags = "H5F_ACC_RDONLY")
  withr::defer(rhdf5::h5closeAll(), envir = env)
  array_read(store, path)
}

# Writes a zarr array of `bytes` by hand, for values Python fixtures lack.
# `type` is the v3 data type, and the v2 dtype is given for version 2.
local_zarr_array <- function(version, type, v2_dtype, bytes, shape, env) {
  root <- withr::local_tempdir(.local_envir = env)
  dir <- file.path(root, "x")
  dir.create(dir)
  count <- length(shape)
  write_json <- function(x, file) {
    jsonlite::write_json(x, file, auto_unbox = TRUE, null = "null")
  }
  shape <- as.list(shape)
  if (version == 3L) {
    write_json(
      list(zarr_format = 3, node_type = "group"),
      file.path(root, "zarr.json")
    )
    write_json(
      list(
        zarr_format = 3,
        node_type = "array",
        shape = shape,
        data_type = type,
        chunk_grid = list(
          name = "regular",
          configuration = list(chunk_shape = shape)
        ),
        chunk_key_encoding = list(
          name = "default",
          configuration = list(separator = "/")
        ),
        fill_value = 0,
        codecs = list(
          list(name = "bytes", configuration = list(endian = "little"))
        )
      ),
      file.path(dir, "zarr.json")
    )
    chunk <- file.path(
      dir,
      "c",
      paste(rep("0", max(count, 0L)), collapse = "/")
    )
    dir.create(dirname(chunk), recursive = TRUE)
  } else {
    write_json(list(zarr_format = 2), file.path(root, ".zgroup"))
    write_json(
      list(
        zarr_format = 2,
        shape = shape,
        chunks = shape,
        dtype = v2_dtype,
        compressor = NULL,
        fill_value = 0,
        filters = NULL,
        order = "C"
      ),
      file.path(dir, ".zarray")
    )
    chunk <- file.path(dir, paste(rep("0", max(count, 1L)), collapse = "."))
  }
  writeBin(bytes, chunk)
  zarr_open(root)
}

test_that("a store opens as a root group and is walked", {
  # The root of every fixture is a group whose members are the Elements
  for (variant in c("v3", "v2")) {
    store <- zarr_case_store(variant, "anndata_full")
    expect_identical(node_path(store), "/")
    expect_true(is_store_file(store))
    expect_identical(read_elem_attr(store, "encoding-type"), "anndata")
    expect_identical(read_elem_attr(store, "encoding-version"), "0.1.0")
    members <- group_members(store)
    expect_identical(members, sort(members, method = "radix"))
    expect_true(all(c("X", "obs", "var", "layers", "uns") %in% members))
    expect_true(member_exists(store, "obs"))
    expect_false(member_exists(store, "nothing"))
    obs <- node_open(store, "obs")
    expect_identical(node_path(obs), "/obs")
    expect_false(is_store_file(obs))
    expect_identical(read_elem_attr(obs, "encoding-type"), "dataframe")
    expect_true(attr_exists(obs, "column-order"))
    expect_false(attr_exists(obs, "nothing"))
    expect_identical(elem_path(obs, "a"), "/obs/a")
    expect_identical(node_path(group_root(obs)), "/")
    expect_error(
      node_open(store, "nothing"),
      class = "anndata_invalid_value_error"
    )
  }
})

test_that("attributes read as vectors", {
  # Lists of scalars become vectors, an empty list an empty character vector and
  # an integer list stays integer (the `shape` of a sparse matrix)
  for (variant in c("v3", "v2")) {
    store <- zarr_case_store(variant, "csr_float64")
    x <- node_open(store, "x")
    expect_identical(read_elem_attr(x, "encoding-type"), "csr_matrix")
    expect_equal(attr_read(x, "shape"), c(3, 4))
    empty <- zarr_case_store(variant, "df_no_columns")
    expect_identical(
      attr_read(node_open(empty, "x"), "column-order"),
      character()
    )
  }
})

test_that("consolidated, unconsolidated and unsharded stores read alike", {
  # Metadata is read from each node, so consolidation and sharding must make no
  # difference to what is read
  cases <- function(variant) {
    names(zarr_fixture_manifest()$variants[[variant]]$cases)
  }
  reference <- array_read(zarr_case_store("v3", "array_float64_2d"), "x")
  for (variant in c("v3_unsharded", "v3_zstd", "v3_blosc")) {
    expect_true("array_float64_2d" %in% cases(variant), info = variant)
    store <- zarr_case_store(variant, "array_float64_2d")
    expect_identical(array_read(store, "x"), reference, info = variant)
  }
  # The unconsolidated variant only holds whole objects, so walk one
  expect_true("anndata_full" %in% cases("v3_unconsolidated"))
  full <- zarr_case_store("v3", "anndata_full")
  unconsolidated <- zarr_case_store("v3_unconsolidated", "anndata_full")
  expect_identical(group_members(unconsolidated), group_members(full))
  expect_identical(
    array_read(unconsolidated, "obs/_index/values"),
    array_read(full, "obs/_index/values")
  )
  expect_identical(
    attr_read(node_open(unconsolidated, "obs"), "column-order"),
    attr_read(node_open(full, "obs"), "column-order")
  )
})

test_that("every array fixture reads as the same case does from h5ad", {
  # The h5ad and zarr fixtures of a case come from the same Python value, so the
  # values, dims and On-disk dtype records must be identical. Complex64 is the
  # only dtype neither backend reads, and both must say so
  manifest <- zarr_fixture_manifest()
  checked <- 0L
  for (variant in names(manifest$variants)) {
    for (case in names(manifest$variants[[variant]]$cases)) {
      if (!grepl("^(array|scalar|string_array)_", case)) {
        next
      }
      store <- zarr_case_store(variant, case)
      info <- paste(variant, case)
      if (case == "array_complex64") {
        expected <- NULL
      } else {
        expected <- h5_case_array(case)
        expect_false(is.null(expected), info = info)
      }
      if (is.null(expected)) {
        expect_error(
          array_read(store, "x"),
          class = "anndata_dtype_error",
          info = info
        )
      } else {
        expect_identical(array_read(store, "x"), expected, info = info)
      }
      checked <- checked + 1L
    }
  }
  expect_gt(checked, 60L)
})

test_that("sparse arrays read as they do from h5ad", {
  # data, indices and indptr are plain arrays of several dtypes
  for (variant in c("v3", "v2")) {
    for (case in c(
      "csr_float64",
      "csc_int8",
      "csr_uint64",
      "csc_indices_int64"
    )) {
      store <- zarr_case_store(variant, case)
      for (part in c("data", "indices", "indptr")) {
        expect_identical(
          array_read(store, paste0("x/", part)),
          h5_case_array(case, paste0("/x/", part)),
          info = paste(variant, case, part)
        )
      }
    }
  }
})

test_that("array information gives class, dtype and rank", {
  # array_info() is what rec-array and scalar reading use to tell arrays apart
  for (variant in c("v3", "v2")) {
    info <- array_info(zarr_case_store(variant, "array_float32"), "x")
    expect_identical(info$dclass, "FLOAT")
    expect_identical(info$dtype, "float32")
    expect_identical(as.integer(info$rank), 1L)
    info <- array_info(zarr_case_store(variant, "array_uint16"), "x")
    expect_identical(c(info$dclass, info$dtype), c("INTEGER", "uint16"))
    info <- array_info(zarr_case_store(variant, "array_bool_2d"), "x")
    expect_identical(c(info$dclass, info$dtype), c("ENUM", "bool"))
    expect_identical(as.integer(info$rank), 2L)
    info <- array_info(zarr_case_store(variant, "string_array_1d"), "x")
    expect_identical(c(info$dclass, info$dtype), c("STRING", "string"))
    info <- array_info(zarr_case_store(variant, "array_complex128"), "x")
    expect_identical(c(info$dclass, info$dtype), c("COMPOUND", "complex128"))
    # A scalar has rank 0, which Rarr cannot tell from one element
    info <- array_info(zarr_case_store(variant, "scalar_float64"), "x")
    expect_identical(as.integer(info$rank), 0L)
    info <- array_info(zarr_case_store(variant, "null"), "x")
    expect_identical(c(info$dclass, as.integer(info$rank)), c("ENUM", "0"))
  }
})

test_that("scalars have no dim and one-element arrays have dim 1", {
  # The distinction decides whether an Element is written back as a scalar
  for (variant in c("v3", "v2")) {
    scalar <- array_read(zarr_case_store(variant, "scalar_int32"), "x")
    expect_null(dim(scalar))
    expect_length(scalar, 1L)
    one <- array_read(zarr_case_store(variant, "array_float64_1elem"), "x")
    expect_null(dim(one))
    expect_equal(as.vector(one), 2.5)
    empty <- array_read(zarr_case_store(variant, "array_float64_0x3"), "x")
    expect_identical(dim(empty), c(0L, 3L))
  }
})

test_that("selections read the same values as subsetting the whole array", {
  # Selections are for backed and lazy reading and must match numpy's x[i, j]
  for (variant in c("v3", "v2")) {
    store <- zarr_case_store(variant, "array_float64_2d")
    whole <- array_read(store, "x")
    part <- array_read(store, "x", list(2L, c(1, 3)))
    expect_equal(as.vector(part), as.vector(whole[2L, c(1, 3)]))
    expect_identical(dim(part), c(1L, 2L))
    rows <- array_read(store, "x", list(NULL, 2L))
    expect_equal(as.vector(rows), as.vector(whole[, 2L]))
    strings <- zarr_case_store(variant, "string_array_2d")
    expect_identical(
      array_read(strings, "x", list(2L, NULL)),
      array_read(strings, "x")[2L, , drop = FALSE]
    )
  }
})

test_that("selections that are sorted ALTREP wrappers read the right cells", {
  # Rarr takes any ALTREP integer for a compact range, so `sort()` results on
  # integers (which lazy seeds pass) read the whole range unless made plain
  for (variant in c("v3", "v2")) {
    store <- zarr_case_store(variant, "array_float64_2d")
    whole <- array_read(store, "x")
    cols <- sort(unique(c(3L, 1L, 1L)))
    expect_true(Rarr:::is.compact(cols))
    part <- array_read(store, "x", list(NULL, cols))
    expect_identical(dim(part), c(2L, 2L))
    expect_equal(as.vector(part), as.vector(whole[, c(1L, 3L)]))
  }
})

test_that("invalid selections are rejected", {
  # A wrong rank, decreasing or out of range indices must raise a classed error
  store <- zarr_case_store("v3", "array_float64_2d")
  expect_error(
    array_read(store, "x", list(1L)),
    class = "anndata_invalid_value_error"
  )
  expect_error(
    array_read(store, "x", list(c(2, 1), NULL)),
    class = "anndata_invalid_value_error"
  )
  expect_error(
    array_read(store, "x", list(9L, NULL)),
    class = "anndata_invalid_value_error"
  )
})

test_that("64-bit values beyond the integer range read as doubles", {
  # Rarr turns them into NA, so they are put together from 16-bit parts.
  # Fixtures hold no such values, so the arrays are written by hand
  big <- 2^40
  for (version in c(3L, 2L)) {
    int64 <- c(1, big, -big, -1)
    # Two's complement little-endian, built from the two 32-bit halves because
    # 2^64 - 1 is not a double
    bytes <- unlist(lapply(int64, function(v) {
      halves <- c(v %% 2^32, floor(v / 2^32) %% 2^32)
      as.raw(floor(rep(halves, each = 4) / 256^(0:3)) %% 256)
    }))
    store <- local_zarr_array(
      version,
      "int64",
      "<i8",
      as.raw(bytes),
      4L,
      environment()
    )
    expect_identical(array_read(store, "x"), set_dtype(int64, "int64"))
    expect_identical(
      array_read(store, "x", list(2:3)),
      set_dtype(c(big, -big), "int64")
    )
  }
  # uint32 above the signed range
  bytes <- as.raw(c(0xff, 0xff, 0xff, 0xff, 1, 0, 0, 0))
  for (version in c(3L, 2L)) {
    store <- local_zarr_array(
      version,
      "uint32",
      "<u4",
      bytes,
      2L,
      environment()
    )
    expect_identical(
      array_read(store, "x"),
      set_dtype(c(2^32 - 1, 1), "uint32")
    )
  }
})

test_that("64-bit values at 2^53 or more raise a precision error", {
  # The policy matches HDF5: a classed error rather than a rounded value
  bytes <- as.raw(c(0, 0, 0, 0, 0, 0, 0x20, 0))
  for (version in c(3L, 2L)) {
    store <- local_zarr_array(
      version,
      "uint64",
      "<u8",
      bytes,
      1L,
      environment()
    )
    expect_error(
      array_read(store, "x"),
      class = "anndata_dtype_overflow_error"
    )
    negative <- as.raw(c(0, 0, 0, 0, 0, 0, 0xe0, 0xff))
    store <- local_zarr_array(
      version,
      "int64",
      "<i8",
      negative,
      1L,
      environment()
    )
    expect_error(
      array_read(store, "x"),
      class = "anndata_dtype_overflow_error"
    )
  }
})

test_that("complex128 arrays read through the split layout", {
  # Rarr has no complex type, so the bytes are read as pairs of float64
  for (variant in c("v3", "v2")) {
    store <- zarr_case_store(variant, "array_complex128")
    expect_identical(array_read(store, "x"), h5_case_array("array_complex128"))
    scalar <- zarr_case_store(variant, "scalar_complex128")
    expect_identical(
      array_read(scalar, "x"),
      h5_case_array("scalar_complex128")
    )
    expect_error(
      array_read(zarr_case_store(variant, "array_complex64"), "x"),
      class = "anndata_dtype_error"
    )
  }
  # A hand-written 2-d array exercises the trailing dimension
  doubles <- c(1, 2, 3, 4, 5, 6, 7, 8)
  store <- local_zarr_array(
    3L,
    "complex128",
    "<c16",
    writeBin(doubles, raw()),
    c(2L, 2L),
    environment()
  )
  expect_identical(
    array_read(store, "x"),
    matrix(complex(real = c(1, 5, 3, 7), imaginary = c(2, 6, 4, 8)), 2, 2)
  )
})

test_that("a zip store raises a classed error suggesting unzipping", {
  # Python adds a note suggesting a ZipStore, the R package asks to unzip
  expect_error(
    zarr_open("store.zarr.zip"),
    class = "anndata_zarr_zip_error"
  )
  expect_error(
    zarr_open("store.zarr.zip"),
    class = "anndata_not_supported_error"
  )
})

test_that("a path that is not a zarr group raises an error", {
  # A missing directory and a directory without metadata are not stores
  expect_error(
    zarr_open(file.path(tempdir(), "missing.zarr")),
    class = "anndata_invalid_value_error"
  )
  expect_error(zarr_open(tempdir()), class = "anndata_invalid_value_error")
})

test_that("layouts the split read cannot handle raise a classed error", {
  # The split read keeps the bytes of a chunk, so it cannot cope with a fill
  # value that is not zero, a transpose codec or big-endian data
  # 2^40 + 1, and still beyond the integer range read big-endian
  bytes <- as.raw(c(1, 0, 0, 0, 0, 1, 0, 0))
  edit <- function(version, change) {
    store <- local_zarr_array(
      version,
      "int64",
      "<i8",
      bytes,
      1L,
      parent.frame()
    )
    file <- file.path(
      store$root,
      "x",
      if (version == 3L) "zarr.json" else ".zarray"
    )
    meta <- jsonlite::fromJSON(file, simplifyVector = FALSE)
    jsonlite::write_json(change(meta), file, auto_unbox = TRUE, null = "null")
    store
  }
  expect_not_supported <- function(store) {
    expect_error(
      array_read(store, "x"),
      class = "anndata_not_supported_error"
    )
  }
  # Sanity: the unedited store reads through the split path
  expect_equal(as.vector(array_read(edit(3L, identity), "x")), 2^40 + 1)
  fill <- function(meta) {
    meta$fill_value <- 5
    meta
  }
  expect_not_supported(edit(3L, fill))
  expect_not_supported(edit(2L, fill))
  expect_not_supported(edit(3L, function(meta) {
    meta$codecs <- c(list(list(name = "transpose")), meta$codecs)
    meta
  }))
  expect_not_supported(edit(3L, function(meta) {
    meta$codecs[[1]]$configuration$endian <- "big"
    meta
  }))
  expect_not_supported(edit(2L, function(meta) {
    meta$dtype <- ">i8"
    meta
  }))
  expect_not_supported(edit(2L, function(meta) {
    meta$order <- "F"
    meta
  }))
})
