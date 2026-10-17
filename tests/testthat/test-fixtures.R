# Guards the committed fixtures: every case in the manifest must have its file,
# and this runs offline so the suite works without Python
test_that("every fixture listed in the manifest exists", {
  manifest <- jsonlite::fromJSON(
    fixture_path("manifest.json"),
    simplifyVector = FALSE
  )

  expect_equal(manifest$versions$anndata, "0.13.4")
  expect_gt(length(manifest$cases), 0L)
  for (case in manifest$cases) {
    expect_true(file.exists(fixture_path(case$file)), info = case$file)
  }
})

# Guards the encoding table: its observed block is generated from the fixtures,
# so it must match what regenerating it now gives
test_that("the committed encoding table matches the fixtures", {
  expect_generator_current("encoding_table.py")
})

# Guards determinism: regenerating must not change any fixture structurally
# (generated once, as a second run would only repeat the comparison)
test_that("regenerated fixtures are deterministic and match the committed", {
  skip_if_no_python()

  first <- withr::local_tempdir()
  run_python("generate_fixtures.py", first)

  manifest <- jsonlite::fromJSON(
    fixture_path("manifest.json"),
    simplifyVector = FALSE
  )
  expect_equal(
    readLines(file.path(first, "manifest.json")),
    readLines(fixture_path("manifest.json"))
  )
  files <- vapply(manifest$cases, function(case) case$file, character(1))
  expect_all_equivalent(
    file.path(first, files),
    fixture_path(files)
  )
})
