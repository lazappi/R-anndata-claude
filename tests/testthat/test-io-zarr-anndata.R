# Tests of read_zarr(), write_zarr() and the zarr settings (ticket zarr-io/08).
# The whole-AnnData fixtures (the `anndata_*` cases and the realistic objects)
# run through the three round-trip directions and the cross-format checks.

skip_if_not_installed("Rarr", "2.1.48")

# The zarr fixture cases that hold a whole AnnData, keyed by case name, and the
# h5ad fixtures of the same objects
zarr_adata_cases <- function(variant = "v3") {
  paths <- zarr_variant_paths(variant)
  paths[names(paths) %in% adata_fixture_names]
}

h5ad_adata_cases <- function(names) {
  stats::setNames(
    fixture_path(file.path("h5ad", paste0(names, ".h5ad"))),
    names
  )
}

# The codec names of an array in a store R wrote
zarr_codec_names <- function(path, array) {
  meta <- jsonlite::fromJSON(
    file.path(path, array, "zarr.json"),
    simplifyVector = FALSE
  )
  codecs <- meta$codecs
  # A sharded array holds its codecs inside the sharding codec
  if (identical(codecs[[1]]$name, "sharding_indexed")) {
    codecs <- codecs[[1]]$configuration$codecs
  }
  vapply(codecs, function(codec) codec$name, character(1))
}

# The chunk shape of an array in a store R wrote (inside the shards if sharded)
zarr_inner_chunk_shape <- function(path, array) {
  meta <- jsonlite::fromJSON(file.path(path, array, "zarr.json"))
  sharding <- meta$codecs$configuration$chunk_shape
  if (is.null(sharding)) {
    return(meta$chunk_grid$configuration$chunk_shape)
  }
  sharding[[1]]
}

test_that("the whole-AnnData zarr fixtures are found", {
  # Guards the case filter, so the loops below cannot silently run on nothing
  expect_gt(length(zarr_adata_cases()), 10L)
  expect_true("realistic" %in% names(zarr_adata_cases()))
})

test_that("Python -> R: read_zarr reads the fixtures as read_h5ad does", {
  # The zarr and h5ad fixtures of a case hold the same object. The unsharded
  # and unconsolidated variants are other layouts of the same store.
  checked <- 0L
  for (variant in c("v3", "v2", "v3_unsharded", "v3_unconsolidated")) {
    cases <- zarr_adata_cases(variant)
    for (case in names(cases)) {
      expect_identical(
        adata_parts(read_zarr(cases[[case]])),
        adata_parts(read_adata_fixture(case)),
        label = paste(variant, case)
      )
      checked <- checked + 1L
    }
  }
  expect_gt(checked, 15L)
})

test_that("Python -> R -> Python: write_zarr matches the Python stores", {
  skip_if_no_python()
  # Python's v2 stores are read and rewritten as v3, which is Structurally
  # equivalent (only the format differs)
  v3 <- zarr_adata_cases()
  v2 <- zarr_adata_cases("v2")
  originals <- c(
    stats::setNames(v3, paste0("v3_", names(v3))),
    stats::setNames(v2, paste0("v2_", names(v2)))
  )
  dir <- withr::local_tempdir()
  written <- vapply(
    names(originals),
    function(case) {
      path <- file.path(dir, paste0(case, ".zarr"))
      write_zarr(read_zarr(originals[[case]]), path)
      path
    },
    character(1)
  )
  # The realistic objects hold a rec-array whose field dtypes are exempt
  # (ADR 0005)
  expect_all_equivalent(
    unname(written),
    unname(originals),
    rec_array_paths = "/uns/O_recarray"
  )
  expect_python_equal(unname(written), unname(originals))
})

test_that("R -> Python -> R: Python rewrites the stores R writes", {
  skip_if_no_python()
  # Python's read_zarr drops a Raw with no observations, so those are left out
  built <- r_built_adatas()
  built <- built[names(built) != "raw_zero_obs"]
  dir <- withr::local_tempdir()
  written <- vapply(
    names(built),
    function(label) {
      path <- file.path(dir, paste0(label, ".zarr"))
      write_zarr(built[[label]], path)
      path
    },
    character(1)
  )
  rewritten <- python_rewrite_h5ad(unname(written), ext = ".zarr")
  for (i in seq_along(built)) {
    expect_identical(
      adata_parts(read_zarr(rewritten[[i]])),
      adata_parts(built[[i]]),
      info = names(built)[[i]]
    )
  }
})

test_that("cross-format: h5ad to zarr matches Python's conversion", {
  skip_if_no_python()
  names <- names(zarr_adata_cases())
  h5ad <- h5ad_adata_cases(names)
  dir <- withr::local_tempdir()
  written <- file.path(dir, paste0(names, ".zarr"))
  for (i in seq_along(names)) {
    write_zarr(read_h5ad(h5ad[[i]]), written[[i]])
  }
  converted <- python_rewrite_h5ad(unname(h5ad), ext = ".zarr")
  expect_all_equivalent(
    written,
    converted,
    rec_array_paths = "/uns/O_recarray"
  )
})

test_that("cross-format: zarr to h5ad matches Python's conversion", {
  skip_if_no_python()
  # Python's read_zarr drops a Raw with no observations, so it is left out
  zarr <- zarr_adata_cases()
  zarr <- zarr[names(zarr) != "anndata_raw_0_obs"]
  dir <- withr::local_tempdir()
  written <- file.path(dir, paste0(names(zarr), ".h5ad"))
  for (i in seq_along(zarr)) {
    write_h5ad(read_zarr(zarr[[i]]), written[[i]])
  }
  converted <- python_rewrite_h5ad(unname(zarr), ext = ".h5ad")
  expect_all_equivalent(
    written,
    converted,
    rec_array_paths = "/uns/O_recarray"
  )
})

test_that("write_zarr and read_zarr round trip the R-built objects", {
  # R -> R, with the adata$write_zarr() method
  for (label in names(r_built_adatas())) {
    adata <- r_built_adatas()[[label]]
    path <- withr::local_tempfile(fileext = ".zarr")
    adata$write_zarr(path)
    expect_identical(
      adata_parts(read_zarr(path)),
      adata_parts(adata),
      info = label
    )
  }
})

test_that("write_zarr writes the root attributes and consolidated metadata", {
  adata <- AnnData(matrix(as.numeric(1:6), nrow = 3))
  path <- withr::local_tempfile(fileext = ".zarr")
  write_zarr(adata, path)
  root <- zarr_open(path)
  expect_identical(read_elem_attr(root, "encoding-type"), "anndata")
  expect_identical(read_elem_attr(root, "encoding-version"), "0.1.0")
  meta <- jsonlite::fromJSON(file.path(path, "zarr.json"))
  expect_identical(meta$consolidated_metadata$kind, "inline")
  expect_true("X" %in% names(meta$consolidated_metadata$metadata))
  # A missing raw is a null Element in zarr, as Python writes it
  expect_identical(
    read_elem_attr(node_open(root, "raw"), "encoding-type"),
    "null"
  )
  expect_null(read_zarr(path)$raw)

  plain <- withr::local_tempfile(fileext = ".zarr")
  write_zarr(adata, plain, consolidate_metadata = FALSE)
  meta <- jsonlite::fromJSON(file.path(plain, "zarr.json"))
  expect_null(meta$consolidated_metadata)
  expect_identical(read_zarr(plain)$shape, c(3L, 2L))
})

test_that("write_zarr replaces an existing store", {
  path <- withr::local_tempfile(fileext = ".zarr")
  write_zarr(AnnData(matrix(1, 2, 2), layers = list(a = matrix(1, 2, 2))), path)
  write_zarr(AnnData(matrix(1, 3, 1)), path)
  adata <- read_zarr(path)
  expect_identical(adata$shape, c(3L, 1L))
  expect_length(as.list(adata$layers), 1L)
})

test_that("chunks sets the chunk shape of a dense X only", {
  adata <- AnnData(
    matrix(as.numeric(1:12), nrow = 4),
    layers = list(a = matrix(as.numeric(1:12), nrow = 4))
  )
  path <- withr::local_tempfile(fileext = ".zarr")
  write_zarr(adata, path, chunks = c(2, 3))
  chunk_shape <- function(array) zarr_inner_chunk_shape(path, array)
  expect_identical(chunk_shape("X"), c(2L, 3L))
  expect_false(identical(chunk_shape("layers/a"), c(2L, 3L)))
  expect_identical(adata_parts(read_zarr(path)), adata_parts(adata))
  # A sparse X takes no chunks
  sparse <- AnnData(Matrix::rsparsematrix(4, 3, 0.5))
  write_zarr(sparse, path, chunks = c(2, 3))
  expect_identical(adata_parts(read_zarr(path)), adata_parts(sparse))
})

test_that("a chunk larger than the array is cut to its shape", {
  # Documented in write_zarr(), and the store must stay readable
  adata <- AnnData(matrix(as.numeric(1:6), nrow = 3))
  path <- withr::local_tempfile(fileext = ".zarr")
  write_zarr(adata, path, chunks = c(100, 100))
  expect_identical(zarr_inner_chunk_shape(path, "X"), c(3L, 2L))
  expect_identical(adata_parts(read_zarr(path)), adata_parts(adata))
})

test_that("convert_strings_to_categoricals converts in place as in h5ad", {
  # Python converts obs, var and raw.var before writing (zarr.py:99-102)
  make <- function() {
    obs <- data.frame(
      g = c("a", "b", "a", "b"),
      row.names = paste0("c", 1:4)
    )
    var <- data.frame(h = c("x", "x", "y"), row.names = paste0("g", 1:3))
    adata <- AnnData(matrix(0, 4, 3), obs = obs, var = var)
    adata$raw <- adata
    adata
  }
  adata <- make()
  path <- withr::local_tempfile(fileext = ".zarr")
  write_zarr(adata, path)
  expect_true(is.factor(adata$obs$g))
  expect_true(is.factor(adata$raw$var$h))
  back <- read_zarr(path)
  expect_true(is.factor(back$obs$g))
  expect_true(is.factor(back$var$h))
  expect_true(is.factor(back$raw$var$h))

  plain <- make()
  write_zarr(plain, path, convert_strings_to_categoricals = FALSE)
  expect_type(plain$obs$g, "character")
  expect_type(read_zarr(path)$obs$g, "character")
})

test_that("invalid chunks raise anndata_invalid_argument_error", {
  adata <- AnnData(matrix(1, 2, 2))
  path <- withr::local_tempfile(fileext = ".zarr")
  for (chunks in list("a", 0, c(1.5, 1), NA_real_)) {
    expect_anndata_condition(
      write_zarr(adata, path, chunks = chunks),
      "anndata_invalid_argument_error"
    )
  }
  # One value for each dimension of X
  expect_anndata_condition(
    write_zarr(adata, path, chunks = 1),
    "anndata_invalid_argument_error"
  )
})

test_that("write_zarr checks its arguments", {
  adata <- AnnData(matrix(1, 2, 2))
  path <- withr::local_tempfile(fileext = ".zarr")
  expect_anndata_condition(
    write_zarr(1, path),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    write_zarr(adata, c("a", "b")),
    "anndata_invalid_argument_error"
  )
  big <- AnnData(matrix(1, 2, 2))
  suppressWarnings(big$X <- array(1, c(2, 2, 2)))
  expect_error(
    suppressWarnings(write_zarr(big, path)),
    class = "anndata_non_2d_error"
  )
})

test_that("compressors sets the codec of every array and round trips", {
  # Python's compressors dataset argument (zstd, gzip, blosc, none), applied to
  # arrays, strings and scalars, with Python reading what R wrote
  adata <- AnnData(
    matrix(as.numeric(1:6), nrow = 3),
    uns = list(n = 2.5, s = "text", big = c(2^40, 1))
  )
  specs <- list(
    zstd = list("zstd", list(name = "zstd", level = 3)),
    gzip = list("gzip", list(name = "gzip", level = 5)),
    blosc = list("blosc", list(name = "blosc", cname = "zstd", clevel = 3)),
    gzip_name = list("gzip", "gzip"),
    none = list(character(), NULL)
  )
  paths <- character()
  for (case in names(specs)) {
    path <- withr::local_tempfile(fileext = ".zarr")
    paths[[case]] <- path
    write_zarr(adata, path, compressors = specs[[case]][[2]])
    expected <- c("bytes", specs[[case]][[1]])
    expect_identical(zarr_codec_names(path, "X"), expected, info = case)
    expect_identical(
      zarr_codec_names(path, "uns/s"),
      c("vlen-utf8", specs[[case]][[1]]),
      info = case
    )
    expect_identical(zarr_codec_names(path, "uns/n"), expected, info = case)
    # The `null` Element ignores the argument, as in Python
    expect_identical(
      zarr_codec_names(path, "raw"),
      c("bytes", "zstd"),
      info = case
    )
    back <- read_zarr(path)
    expect_identical(back$X, adata$X, info = case)
    expect_identical(back$uns[["n"]], 2.5, info = case)
    expect_identical(back$uns[["s"]], "text", info = case)
    expect_identical(as.vector(back$uns[["big"]]), c(2^40, 1), info = case)
  }
  skip_if_no_python()
  # Python must decode the chunks too (R's gzip is not Rarr's zlib)
  for (case in names(paths)) {
    nodes <- run_python("zarr_describe.py", paths[[case]])
    for (key in c("X", "uns/big", "uns/n", "uns/s")) {
      line <- nodes[grepl(paste0("^\\{\"/", key, "\""), nodes)]
      node <- jsonlite::fromJSON(line, simplifyVector = FALSE)[[1]]
      expect_null(node$error, info = case)
      expect_true(!is.null(node$value), info = case)
    }
  }
})

test_that("compressed arrays with several chunks are read by R and Python", {
  # Every chunk file must be compressed (the recursive walk of the gzip step)
  withr::local_options(anndata.zarr_chunk_limit = 4)
  adata <- AnnData(
    matrix(as.numeric(1:30), nrow = 10),
    uns = list(big = matrix(c(2^40, 1:11), nrow = 6))
  )
  for (name in c("gzip", "blosc")) {
    path <- withr::local_tempfile(fileext = ".zarr")
    # Unsharded, so that every chunk is a file of its own
    write_zarr(adata, path, compressors = name, shards = NULL)
    expect_gt(
      length(list.files(file.path(path, "X", "c"), recursive = TRUE)),
      1
    )
    expect_identical(read_zarr(path)$X, adata$X)
    # Sharded, the chunks are compressed inside the shard files
    write_zarr(adata, path, compressors = name)
    back <- read_zarr(path)
    expect_identical(back$X, adata$X, info = name)
    expect_identical(
      as.vector(back$uns[["big"]]),
      as.vector(adata$uns[["big"]]),
      info = name
    )
    skip_if_no_python()
    nodes <- run_python("zarr_describe.py", path)
    for (key in c("X", "uns/big")) {
      line <- nodes[grepl(paste0("^\\{\"/", key, "\""), nodes)]
      node <- jsonlite::fromJSON(line, simplifyVector = FALSE)[[1]]
      expect_null(node$error, info = name)
    }
  }
})

test_that("compressor is Python's older name for compressors", {
  # zarr_v3_compressor_compat renames it, and it wins when both are given
  adata <- AnnData(matrix(as.numeric(1:6), nrow = 3))
  path <- withr::local_tempfile(fileext = ".zarr")
  write_zarr(adata, path, compressor = "gzip")
  expect_identical(zarr_codec_names(path, "X"), c("bytes", "gzip"))
  # Python drops `compressor` for scalars (_remove_scalar_compression_args)
  adata$uns[["n"]] <- 2.5
  write_zarr(adata, path, compressor = "gzip")
  expect_identical(zarr_codec_names(path, "uns/n"), c("bytes", "zstd"))
  write_zarr(adata, path, compressors = "gzip")
  expect_identical(zarr_codec_names(path, "uns/n"), c("bytes", "gzip"))
  write_zarr(adata, path, compressors = "gzip", compressor = NULL)
  expect_identical(zarr_codec_names(path, "X"), "bytes")
  expect_identical(adata_parts(read_zarr(path)), adata_parts(adata))
})

test_that("invalid dataset arguments raise classed errors", {
  # Python raises TypeError for h5py keywords and unknown names
  adata <- AnnData(matrix(1, 2, 2))
  path <- withr::local_tempfile(fileext = ".zarr")
  for (args in list(
    list(compression = "gzip"),
    list(foo = 1),
    list("gzip"),
    list(compressors = "lzma"),
    list(compressors = list(name = "zstd", level = 99)),
    list(compressors = list(name = "gzip", cname = "lz4")),
    list(compressors = list(name = "blosc", cname = "nope")),
    list(compressors = 1)
  )) {
    expect_anndata_condition(
      do.call(write_zarr, c(list(adata, path), args)),
      "anndata_invalid_argument_error"
    )
  }
})

test_that("shards = NULL writes unsharded arrays and a shape shards them", {
  # NULL switches off the automatic sharding as in Python, and an explicit
  # shape must round trip through R
  adata <- AnnData(matrix(as.numeric(1:12), 4, 3))
  path <- withr::local_tempfile(fileext = ".zarr")
  has_sharding <- function() {
    meta <- jsonlite::fromJSON(file.path(path, "X", "zarr.json"))
    "sharding_indexed" %in% meta$codecs$name
  }
  write_zarr(adata, path, shards = NULL)
  expect_false(has_sharding())
  expect_identical(adata_parts(read_zarr(path)), adata_parts(adata))
  write_zarr(adata, path)
  expect_true(has_sharding())
  expect_identical(adata_parts(read_zarr(path)), adata_parts(adata))
  local_anndata_settings(list(auto_shard_zarr_v3 = FALSE))
  write_zarr(adata, path)
  expect_false(has_sharding())
})

test_that("an invalid shards argument is rejected", {
  # The shard shape needs one whole number per dimension
  adata <- AnnData(matrix(1, 2, 2))
  path <- withr::local_tempfile(fileext = ".zarr")
  for (shards in list(c(2, 2, 2), c(0, 2), c(1.5, 2), "auto")) {
    expect_anndata_condition(
      write_zarr(adata, path, shards = shards),
      "anndata_invalid_argument_error"
    )
  }
})

test_that("write_zarr refuses a directory that is not a zarr store", {
  # The write clears the directory, so it must not clear unrelated files
  dir <- withr::local_tempdir()
  writeLines("data", file.path(dir, "notes.txt"))
  expect_anndata_condition(
    write_zarr(AnnData(matrix(1, 2, 2)), dir),
    "anndata_invalid_value_error"
  )
  expect_true(file.exists(file.path(dir, "notes.txt")))
  # An empty directory is fine
  empty <- withr::local_tempdir()
  write_zarr(AnnData(matrix(1, 2, 2)), empty)
  expect_identical(read_zarr(empty)$shape, c(2L, 2L))
})

test_that("zarr_write_format 2 is not yet supported", {
  local_anndata_settings(list(zarr_write_format = 2L))
  expect_anndata_condition(
    write_zarr(AnnData(matrix(1, 2, 2)), withr::local_tempfile()),
    "anndata_not_supported_error"
  )
})

test_that("read_zarr raises classed errors", {
  expect_anndata_condition(read_zarr(1), "anndata_invalid_argument_error")
  expect_anndata_condition(
    read_zarr(file.path(withr::local_tempdir(), "missing.zarr")),
    "anndata_file_not_found_error"
  )
  zip <- withr::local_tempfile(fileext = ".zarr.zip")
  writeLines("x", zip)
  expect_anndata_condition(read_zarr(zip), "anndata_zarr_zip_error")
  # A directory that is not a zarr group
  expect_anndata_condition(
    read_zarr(withr::local_tempdir()),
    "anndata_invalid_value_error"
  )
})

test_that("read_zarr raises the legacy error for a legacy layout", {
  # Legacy layouts are out of scope (as for h5ad), `raw.X` is the old raw
  path <- withr::local_tempfile(fileext = ".zarr")
  write_zarr(AnnData(matrix(1, 2, 2)), path)
  store <- zarr_open(path)
  write_elem(store, "raw.X", matrix(1, 2, 2))
  expect_anndata_condition(read_zarr(path), "anndata_legacy_format_error")
})

test_that("unwriteable accepts the zarr store type", {
  adata <- AnnData(matrix(1, 2, 2))
  expect_false(adata$unwriteable(store_type = "zarr"))
  adata$uns[["f"]] <- function() 1
  expect_true(adata$unwriteable(store_type = "zarr"))
})

test_that("the zarr settings validate their values", {
  withr::defer(anndata_settings$reset())
  expect_identical(anndata_settings$zarr_write_format, 3L)
  expect_true(anndata_settings$auto_shard_zarr_v3)
  anndata_settings$auto_shard_zarr_v3 <- FALSE
  expect_false(anndata_settings$auto_shard_zarr_v3)
  anndata_settings$zarr_write_format <- 2
  expect_identical(anndata_settings$zarr_write_format, 2)
  expect_anndata_condition(
    anndata_settings$zarr_write_format <- 4,
    "anndata_invalid_setting_error"
  )
  expect_anndata_condition(
    anndata_settings$auto_shard_zarr_v3 <- "yes",
    "anndata_invalid_setting_error"
  )
})
