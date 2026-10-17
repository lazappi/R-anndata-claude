# Tests of the compound encodings on zarr v3 stores (ticket zarr-io/07): the
# nullable arrays, categorical, dataframe, dict and rec-array.
# The three round-trip directions run over every fixture of these encodings.
# rec-array field dtypes are not kept (ADR 0005), so its Python -> R -> Python
# checks compare values only.

skip_if_not_installed("Rarr", "2.1.48")

compound_zarr_encodings <- c(
  "nullable-integer",
  "nullable-boolean",
  "nullable-string-array",
  "categorical",
  "dataframe",
  "dict",
  "rec-array"
)

# The fixture cases of `variant` whose Element is a compound encoding, as a
# named vector of store paths
compound_zarr_cases <- function(variant = "v3") {
  paths <- zarr_variant_paths(variant)
  keep <- vapply(
    paths,
    function(path) {
      store <- zarr_open(path)
      # Whole AnnData cases have no Element at `x`
      member_exists(store, "x") &&
        read_elem_attr(node_open(store, "x"), "encoding-type") %in%
          compound_zarr_encodings
    },
    logical(1)
  )
  # The int64 field of rec_array_int64_big cannot be read (tested separately)
  paths[keep & !grepl("^anndata_|int64_big", names(paths))]
}

# The R value a rec-array has after a write, which stores logical fields as
# int32 (ADR 0005)
rec_array_as_written <- function(value) {
  if (!inherits(value, "anndata_rec_array")) {
    return(value)
  }
  value[] <- lapply(value, function(field) {
    if (is.logical(field)) as.integer(field) else field
  })
  value
}

# Writes `value` as the Element `x` of a new v3 store and returns its path
write_compound_like <- function(value, dir) {
  path <- tempfile("r", tmpdir = dir, fileext = ".zarr")
  write_elem(zarr_create(path), "x", value)
  path
}

test_that("the compound zarr fixtures are found", {
  # Guards the case filter, so the loops below cannot silently run on nothing
  cases <- compound_zarr_cases()
  expect_gt(length(cases), 10L)
  encodings <- vapply(
    cases,
    function(path) {
      read_elem_attr(node_open(zarr_open(path), "x"), "encoding-type")
    },
    character(1)
  )
  expect_setequal(unique(encodings), compound_zarr_encodings)
})

test_that("Python -> R: compound Elements read as in h5ad", {
  # The zarr and h5ad fixtures of a case hold the same Element, so the HDF5
  # reading is the expected value
  checked <- 0L
  for (variant in c("v3", "v2", "v3_unsharded", "v3_unconsolidated")) {
    cases <- compound_zarr_cases(variant)
    for (case in names(cases)) {
      expected <- h5_case_elem(case)
      if (is.null(expected)) {
        next
      }
      actual <- read_elem(zarr_open(cases[[case]]), "x")
      expect_identical(actual, expected, label = paste(variant, case))
      checked <- checked + 1L
    }
  }
  expect_gt(checked, 10L)
})

test_that("Python -> R -> Python: compound Elements written by R match", {
  skip_if_no_python()
  originals <- compound_zarr_cases()
  dir <- withr::local_tempdir()
  written <- vapply(
    originals,
    function(path) write_compound_like(read_elem(zarr_open(path), "x"), dir),
    character(1)
  )
  # Rec-array field dtypes are exempt (ADR 0005), their values are checked by
  # reading the written store back in R
  expect_all_equivalent(
    unname(written),
    unname(originals),
    rec_array_paths = "/x"
  )
  for (case in grep("^rec_array", names(originals), value = TRUE)) {
    expect_identical(
      read_elem(zarr_open(written[[case]]), "x"),
      rec_array_as_written(read_elem(zarr_open(originals[[case]]), "x")),
      label = case
    )
  }
})

# Python rejects nothing here, but R must refuse 64-bit values it cannot hold
test_that("an int64 rec-array field of 2^53 or more raises on read", {
  path <- zarr_variant_paths("v3")[["rec_array_int64_big"]]
  expect_anndata_condition(
    read_elem(zarr_open(path), "x"),
    "anndata_dtype_overflow_error"
  )
})

test_that("R -> Python -> R: Python reads and rewrites what R wrote", {
  skip_if_no_python()
  originals <- compound_zarr_cases()
  # Python's default settings rewrite the plain strings of these cases as
  # nullable ones, which changes the record (as for h5ad)
  originals <- originals[!grepl("allow_nullable_false", names(originals))]
  values <- lapply(originals, function(path) read_elem(zarr_open(path), "x"))
  dir <- withr::local_tempdir()
  written <- vapply(values, write_compound_like, character(1), dir = dir)
  rewritten <- python_rewrite(unname(written), ext = ".zarr")
  for (i in seq_along(values)) {
    actual <- read_elem(zarr_open(rewritten[[i]]), "x")
    expect_identical(
      actual,
      rec_array_as_written(values[[i]]),
      label = names(values)[[i]]
    )
  }
})

# A copy of the v2 `rec_array_widths` store whose array metadata is edited by
# `edit`, returning the store
local_v2_rec_array <- function(edit, env = parent.frame()) {
  source <- zarr_variant_paths("v2")[["rec_array_widths"]]
  dir <- withr::local_tempdir(.local_envir = env)
  file.copy(source, dir, recursive = TRUE)
  path <- file.path(dir, basename(source))
  file <- file.path(path, "x", ".zarray")
  meta <- jsonlite::read_json(file)
  jsonlite::write_json(
    edit(meta, file.path(path, "x")),
    file,
    auto_unbox = TRUE,
    null = "null",
    digits = NA
  )
  zarr_open(path)
}

test_that("v2 rec-arrays that are uncompressed or have a missing chunk read", {
  # Python writes blosc by default, so the other compressor and fill-value
  # paths need an edited copy of a fixture
  expected <- read_elem(
    zarr_open(zarr_variant_paths("v2")[["rec_array_widths"]]),
    "x"
  )
  plain <- local_v2_rec_array(function(meta, dir) {
    chunk <- file.path(dir, "0")
    bytes <- zarr_v2_unpack(chunk, 2L * 20L, meta)
    writeBin(bytes, chunk)
    meta$compressor <- NULL
    meta
  })
  expect_identical(read_elem(plain, "x"), expected)
  missing <- local_v2_rec_array(function(meta, dir) {
    unlink(file.path(dir, "0"))
    meta
  })
  zeros <- read_elem(missing, "x")
  expect_equal(nrow(zeros), 2L)
  expect_true(all(unlist(zeros[names(zeros) != "b"]) == 0))
})

test_that("v2 rec-arrays the reader cannot decode raise classed errors", {
  # Big-endian, Fortran order, filters and unknown field types must not be
  # read as if they were plain little-endian records
  big <- local_v2_rec_array(function(meta, dir) {
    meta$dtype[[2L]][[2L]] <- ">i2"
    meta
  })
  expect_anndata_condition(
    read_elem(big, "x"),
    "anndata_not_supported_error"
  )
  fortran <- local_v2_rec_array(function(meta, dir) {
    meta$order <- "F"
    meta
  })
  expect_anndata_condition(
    read_elem(fortran, "x"),
    "anndata_not_supported_error"
  )
  filtered <- local_v2_rec_array(function(meta, dir) {
    meta$filters <- list(list(id = "delta", dtype = "|u1"))
    meta
  })
  expect_anndata_condition(
    read_elem(filtered, "x"),
    "anndata_not_supported_error"
  )
  unknown <- local_v2_rec_array(function(meta, dir) {
    meta$dtype[[2L]][[2L]] <- "<c8"
    meta
  })
  expect_anndata_condition(read_elem(unknown, "x"), "anndata_dtype_error")
})
