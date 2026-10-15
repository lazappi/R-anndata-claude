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
  skip_if_no_python()
  doc <- testthat::test_path(
    "..",
    "..",
    ".scratch",
    "h5ad-io",
    "encoding-table.md"
  )
  skip_if_not(file.exists(doc), "the encoding table is not in the check copy")

  copy <- withr::local_tempfile(fileext = ".md")
  file.copy(doc, copy)
  run_python("encoding_table.py", normalizePath(fixture_path(".")), copy)

  expect_equal(readLines(copy), readLines(doc))
})

# Guards determinism: regenerating must not change any fixture structurally
test_that("regenerated fixtures are deterministic and match the committed", {
  skip_if_no_python()

  first <- withr::local_tempdir()
  second <- withr::local_tempdir()
  run_python("generate_fixtures.py", first)
  run_python("generate_fixtures.py", second)

  manifest <- jsonlite::fromJSON(
    fixture_path("manifest.json"),
    simplifyVector = FALSE
  )
  expect_equal(
    readLines(file.path(first, "manifest.json")),
    readLines(file.path(second, "manifest.json"))
  )
  for (case in manifest$cases) {
    expect_structurally_equivalent(
      file.path(first, case$file),
      file.path(second, case$file)
    )
    expect_structurally_equivalent(
      file.path(first, case$file),
      fixture_path(case$file)
    )
  }
})
