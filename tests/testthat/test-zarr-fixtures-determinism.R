# Guards the zarr fixtures against drift (ticket zarr-io/03), split from
# test-zarr-fixtures.R because the generator takes about 50s and the test
# workers stay balanced with it in its own file

# Guards determinism: regenerating must not change any fixture structurally,
# and the manifests (including the errors Python raises) must be identical
test_that("regenerated zarr fixtures are deterministic and committed", {
  skip_if_no_python()

  # Generated once (about 50s), a second run would only repeat the comparison
  first <- withr::local_tempdir()
  run_python("generate_zarr_fixtures.py", first)

  manifest <- zarr_fixture_manifest()
  expect_equal(
    readLines(file.path(first, "manifest.json")),
    readLines(zarr_fixture_path("manifest.json"))
  )
  files <- unlist(lapply(manifest$variants, function(variant) {
    vapply(variant$cases, function(case) case$file, character(1))
  }))
  expect_all_equivalent(
    file.path(first, files),
    zarr_fixture_path(files)
  )
})
