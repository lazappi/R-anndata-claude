# Skips tests that need the Python reference environment when it is unavailable
skip_if_no_python <- function() {
  testthat::skip_if(
    identical(Sys.getenv("ANNDATA_SKIP_PYTHON"), "true"),
    "ANNDATA_SKIP_PYTHON is true"
  )
  testthat::skip_if(Sys.which("uv") == "", "uv is not on the PATH")
}

# Path to the uv project, found from tests/testthat under both devtools::test()
# and R CMD check (where the tests directory is copied)
python_project <- function() {
  normalizePath(
    testthat::test_path("..", "python"),
    mustWork = TRUE
  )
}

# Runs a script from tests/python in the reference environment and returns its
# stdout lines, failing the test with stderr on a non-zero exit
run_python <- function(script, ...) {
  project <- python_project()
  stderr_file <- withr::local_tempfile()
  args <- c(
    "run",
    "--project",
    project,
    "python",
    "-I",
    file.path(project, script),
    as.character(c(...))
  )
  out <- suppressWarnings(
    system2(
      "uv",
      args,
      stdout = TRUE,
      stderr = stderr_file,
      # uv leaves lock files in TMPDIR, which R CMD check reports as detritus
      env = paste0("TMPDIR=", withr::local_tempdir())
    )
  )
  status <- rlang::`%||%`(attr(out, "status"), 0L)
  if (status != 0L) {
    testthat::fail(paste0(
      "Python script `",
      script,
      "` failed with status ",
      status,
      ":\n",
      paste(readLines(stderr_file, warn = FALSE), collapse = "\n")
    ))
  }
  out
}
