# Tests of the basic encodings on zarr v3 stores (ticket zarr-io/06): array,
# string-array, numeric-scalar, string, null, csr_matrix and csc_matrix.
# The three round-trip directions run over every fixture of these encodings.

skip_if_not_installed("Rarr", "2.1.48")

basic_zarr_encodings <- c(
  "array",
  "string-array",
  "numeric-scalar",
  "string",
  "null",
  "csr_matrix",
  "csc_matrix"
)

# The fixture cases of `variant` whose Element is a basic encoding, as a named
# vector of store paths
basic_zarr_cases <- function(variant = "v3") {
  paths <- zarr_variant_paths(variant)
  keep <- vapply(
    paths,
    function(path) {
      store <- zarr_open(path)
      # Whole AnnData cases have no Element at `x`
      member_exists(store, "x") &&
        read_elem_attr(node_open(store, "x"), "encoding-type") %in%
          basic_zarr_encodings
    },
    logical(1)
  )
  # complex64 is not readable, as for h5ad (tested separately)
  # (and `anndata_*` cases hold `X`, which a case-insensitive file system
  # finds as `x`)
  paths[keep & !grepl("complex64|^anndata_", names(paths))]
}

test_that("complex64 arrays raise the dtype error as in h5ad", {
  # Only complex128 is supported, and the zarr and HDF5 backends must agree
  path <- zarr_variant_paths("v3")[["array_complex64"]]
  expect_error(
    read_elem(zarr_open(path), "x"),
    class = "anndata_dtype_error"
  )
})

# The h5ad fixture of a case read with the HDF5 backend, `NULL` when the case
# has no h5ad fixture (both were written by Python from one case)
h5_case_elem <- function(case, env = parent.frame()) {
  file <- fixture_path(file.path("h5ad", paste0(case, ".h5")))
  if (!file.exists(file)) {
    return(NULL)
  }
  store <- rhdf5::H5Fopen(file, flags = "H5F_ACC_RDONLY")
  withr::defer(rhdf5::h5closeAll(), envir = env)
  read_elem(store, "x")
}

# Writes `value` as the Element `x` of a new v3 store and returns its path
write_zarr_like <- function(value, dir) {
  path <- tempfile("r", tmpdir = dir, fileext = ".zarr")
  store <- zarr_create(path)
  write_elem(store, "x", value)
  path
}

test_that("the basic zarr fixtures are found", {
  # Guards the case filter, so the loops below cannot silently run on nothing
  cases <- basic_zarr_cases()
  expect_gt(length(cases), 50L)
  expect_true(all(c("csr_float64", "csc_int8") %in% names(cases)))
})

test_that("Python -> R: basic Elements read as in h5ad", {
  # The zarr and h5ad fixtures of a case hold the same Element, so the HDF5
  # reading is the expected value
  checked <- 0L
  for (variant in c("v3", "v3_unsharded", "v3_unconsolidated")) {
    cases <- basic_zarr_cases(variant)
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
  expect_gt(checked, 50L)
})

test_that("Python -> R -> Python: basic Elements written by R match Python's", {
  # R writes what it read, and the store has the groups, arrays, attributes,
  # dtypes, shapes and values of the original
  skip_if_no_python()
  originals <- basic_zarr_cases()
  dir <- withr::local_tempdir()
  written <- vapply(
    originals,
    function(path) write_zarr_like(read_elem(zarr_open(path), "x"), dir),
    character(1)
  )
  # The original stores hold the Element at `x` of the root, as the new ones do
  expect_all_equivalent(unname(written), unname(originals))
})

test_that("R -> Python -> R: Python reads and rewrites what R wrote", {
  skip_if_no_python()
  originals <- basic_zarr_cases()
  # Python cannot write a complex scalar to zarr, so it cannot rewrite one
  originals <- originals[!grepl("scalar.*complex", names(originals))]
  values <- lapply(originals, function(path) read_elem(zarr_open(path), "x"))
  dir <- withr::local_tempdir()
  written <- vapply(values, write_zarr_like, character(1), dir = dir)
  rewritten <- python_rewrite(unname(written), ext = ".zarr")
  for (i in seq_along(values)) {
    actual <- read_elem(zarr_open(rewritten[[i]]), "x")
    plain <- drop_dtype(values[[i]])
    if (grepl("^scalar_", names(values)[[i]]) && !is.logical(plain)) {
      # Python reads a numeric scalar as a plain int or float (methods.py:1362)
      # and writes it back as int64 or float64, so only the value survives
      expect_equal(drop_dtype(actual), plain, label = names(values)[[i]])
    } else {
      expect_identical(actual, values[[i]], label = names(values)[[i]])
    }
  }
})

test_that("R values round trip through write_elem and read_elem on zarr", {
  # Zarr-specific cases the fixtures do not all cover: variable-length string
  # scalars, empty and 2-d string arrays, bool scalars and empty arrays
  values <- list(
    string_scalar = "text",
    empty_string_scalar = "",
    string_array_2d = matrix(c("a", "b", "", "d"), 2),
    empty_strings = character(),
    bool_scalar = TRUE,
    empty_matrix = matrix(numeric(), 0, 3)
  )
  for (name in names(values)) {
    store <- zarr_create(withr::local_tempdir())
    write_elem(store, "x", values[[name]])
    expect_equal(
      drop_dtype(read_elem(store, "x")),
      values[[name]],
      label = name
    )
  }
})

test_that("zarr member lookup matches the case of names", {
  # A case-insensitive file system would find `x` as `X`
  store <- zarr_create(withr::local_tempdir())
  write_elem(store, "X", c(1, 2))
  expect_true(member_exists(store, "X"))
  expect_false(member_exists(store, "x"))
  expect_error(node_open(store, "x"), class = "anndata_invalid_value_error")
})

test_that("a missing raw is written as a null Element", {
  # Python writes a null where an h5ad file has no group (zarr-io/03 comments)
  store <- zarr_create(withr::local_tempdir())
  write_elem(store, "x", NULL)
  expect_identical(
    read_elem_attr(node_open(store, "x"), "encoding-type"),
    "null"
  )
  expect_null(read_elem(store, "x"))
})
