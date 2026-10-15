# Writes the tiny a, same and changed h5ad files from Python into a temp dir
smoke_files <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  run_python("write_smoke.py", dir)
  list(
    a = file.path(dir, "a.h5ad"),
    same = file.path(dir, "same.h5ad"),
    changed = file.path(dir, "changed.h5ad"),
    different = file.path(dir, "different.h5ad")
  )
}

# Identical files must pass, or every comparison would be a false failure
test_that("expect_structurally_equivalent() passes for identical files", {
  skip_if_no_python()
  files <- smoke_files()

  expect_success(expect_structurally_equivalent(files$a, files$same))
})

# A changed dtype must be caught, and the message must name the path
test_that("expect_structurally_equivalent() fails and names the path", {
  skip_if_no_python()
  files <- smoke_files()

  expect_failure(
    expect_structurally_equivalent(files$a, files$changed),
    "/X: dtype differs"
  )
})

# Guards the readability of the failure message
test_that("expect_structurally_equivalent() failure message is readable", {
  skip_if_no_python()
  files <- smoke_files()

  result <- tryCatch(
    expect_structurally_equivalent(files$a, files$changed),
    expectation_failure = function(cnd) conditionMessage(cnd)
  )
  expect_snapshot(cat(result))
})

# expect_python_equal() must accept files Python reads as equal
test_that("expect_python_equal() passes for identical files", {
  skip_if_no_python()
  files <- smoke_files()

  expect_success(expect_python_equal(files$a, files$same))
})

# expect_python_equal() must fail when the files differ in content
test_that("expect_python_equal() fails for different files", {
  skip_if_no_python()
  files <- smoke_files()

  expect_failure(
    expect_python_equal(files$a, files$different),
    "Python reads the files as different"
  )
})

# fixture_path() must point inside the testthat fixtures directory
test_that("fixture_path() returns a path under fixtures", {
  expect_equal(basename(dirname(fixture_path("x.h5ad"))), "fixtures")
})
