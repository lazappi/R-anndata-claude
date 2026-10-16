# Tests of the compound encodings on zarr v3 stores (ticket zarr-io/07): the
# nullable arrays, categorical, dataframe and dict.
# The three round-trip directions run over every fixture of these encodings.
# rec-array is not here yet, because zarr stores it as a `struct` array that
# needs its own table backend operations (see the ticket).

skip_if_not_installed("Rarr", "2.1.48")

compound_zarr_encodings <- c(
  "nullable-integer",
  "nullable-boolean",
  "nullable-string-array",
  "categorical",
  "dataframe",
  "dict"
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
  paths[keep & !grepl("^anndata_", names(paths))]
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
  for (variant in c("v3", "v3_unsharded", "v3_unconsolidated")) {
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
  expect_all_equivalent(unname(written), unname(originals))
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
    expect_identical(actual, values[[i]], label = names(values)[[i]])
  }
})
