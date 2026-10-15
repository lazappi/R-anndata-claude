# Smoke test that the pinned reference environment is used and reachable
test_that("run_python() runs scripts in the pinned reference environment", {
  skip_if_no_python()

  versions <- jsonlite::fromJSON(paste(
    run_python("versions.py"),
    collapse = ""
  ))

  expect_equal(versions$anndata, "0.13.4")
  expect_equal(
    as.integer(strsplit(versions$pandas, ".", fixed = TRUE)[[1]][1]),
    3L
  )
})

# Guards the skip switch used to run the suite without Python
test_that("skip_if_no_python() skips when ANNDATA_SKIP_PYTHON is true", {
  withr::local_envvar(ANNDATA_SKIP_PYTHON = "true")

  expect_condition(skip_if_no_python(), class = "skip")
})
