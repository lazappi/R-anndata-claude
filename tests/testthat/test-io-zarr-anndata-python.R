# Tests of read_zarr() and write_zarr() on the whole-AnnData fixtures (ticket
# zarr-io/08), split from test-io-zarr-anndata.R so the test workers balance.
# The whole-AnnData fixtures (the `anndata_*` cases and the realistic objects)
# run through the three round-trip directions and the cross-format checks.

skip_if_not_installed("Rarr", "2.1.48")

# The zarr fixture cases that hold a whole AnnData, keyed by case name, and the
# h5ad fixtures of the same objects
zarr_adata_cases <- function(variant = "v3") {
  paths <- zarr_variant_paths(variant)
  paths[names(paths) %in% adata_fixture_names]
}

# The cases the AnnData-level write tests use (human decision, ticket
# foundations/10): the realistic object and edge cases of the Slots. Every
# per-encoding store is covered in all three directions by test-io-zarr-basic.R
# and test-io-zarr-compound.R.
zarr_write_cases <- function(variant = "v3") {
  cases <- zarr_adata_cases(variant)
  cases[
    names(cases) %in%
      c(
        "realistic",
        "anndata_full",
        "anndata_empty_slots",
        "anndata_no_x",
        "anndata_0_obs",
        "anndata_raw_own_var",
        "anndata_raw_0_obs"
      )
  ]
}

h5ad_adata_cases <- function(names) {
  stats::setNames(
    fixture_path(file.path("h5ad", paste0(names, ".h5ad"))),
    names
  )
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
  v3 <- zarr_write_cases()
  v2 <- zarr_write_cases("v2")[c("realistic", "anndata_raw_own_var")]
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
  # The realistic objects hold a rec-array, whose field dtypes zarr keeps
  expect_all_equivalent(unname(written), unname(originals))
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
  names <- names(zarr_write_cases())
  h5ad <- h5ad_adata_cases(names)
  dir <- withr::local_tempdir()
  written <- file.path(dir, paste0(names, ".zarr"))
  for (i in seq_along(names)) {
    write_zarr(read_h5ad(h5ad[[i]]), written[[i]])
  }
  converted <- python_rewrite_h5ad(unname(h5ad), ext = ".zarr")
  expect_all_equivalent(written, converted)
})

test_that("cross-format: zarr to h5ad matches Python's conversion", {
  skip_if_no_python()
  # Python's read_zarr drops a Raw with no observations, so it is left out
  zarr <- zarr_write_cases()
  zarr <- zarr[names(zarr) != "anndata_raw_0_obs"]
  dir <- withr::local_tempdir()
  written <- file.path(dir, paste0(names(zarr), ".h5ad"))
  for (i in seq_along(zarr)) {
    write_h5ad(read_zarr(zarr[[i]]), written[[i]])
  }
  converted <- python_rewrite_h5ad(unname(zarr), ext = ".h5ad")
  expect_all_equivalent(written, converted)
})
