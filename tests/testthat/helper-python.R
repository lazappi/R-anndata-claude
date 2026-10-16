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

# Runs a script from tests/python in the reference environment and returns
# its stdout lines, stderr text and exit status without judging the result
run_python_raw <- function(script, ...) {
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
  list(
    stdout = as.character(out),
    stderr = paste(readLines(stderr_file, warn = FALSE), collapse = "\n"),
    status = rlang::`%||%`(attr(out, "status"), 0L)
  )
}

# Runs a script from tests/python in the reference environment and returns its
# stdout lines, failing the test with stderr on a non-zero exit
run_python <- function(script, ...) {
  result <- run_python_raw(script, ...)
  if (result$status != 0L) {
    testthat::fail(paste0(
      "Python script `",
      script,
      "` failed with status ",
      result$status,
      ":\n",
      result$stderr
    ))
  }
  result$stdout
}

# Path to a committed fixture under tests/testthat/fixtures/
fixture_path <- function(name) {
  testthat::test_path("fixtures", name)
}

# Reads the h5_tree.py description of a file as a list of nodes keyed by path
h5_tree <- function(file) {
  nodes <- jsonlite::fromJSON(
    paste(run_python("h5_tree.py", file), collapse = ""),
    simplifyVector = FALSE
  )
  stats::setNames(nodes, vapply(nodes, function(node) node$path, character(1)))
}

# Lists every path and property that differs between two h5_tree() results
#
# `rec_array_paths` are datasets whose field dtypes are exempt (ADR 0005), so
# their `dtype` and `digest` are not compared, and nothing else is relaxed
h5_tree_differences <- function(a, b, rec_array_paths = character()) {
  diffs <- character()
  note <- function(...) diffs <<- c(diffs, paste0(...))
  show <- function(x) jsonlite::toJSON(x, auto_unbox = TRUE, null = "null")

  for (path in setdiff(names(a), names(b))) {
    note(path, ": only in the first file")
  }
  for (path in setdiff(names(b), names(a))) {
    note(path, ": only in the second file")
  }
  for (path in intersect(names(a), names(b))) {
    x <- a[[path]]
    y <- b[[path]]
    props <- c("kind", "dtype", "shape", "digest")
    if (path %in% rec_array_paths) {
      props <- c("kind", "shape")
    }
    for (prop in props) {
      if (!identical(x[[prop]], y[[prop]])) {
        note(
          path,
          ": ",
          prop,
          " differs (",
          show(x[[prop]]),
          " vs ",
          show(y[[prop]]),
          ")"
        )
      }
    }
    for (attr in setdiff(names(x$attrs), names(y$attrs))) {
      note(path, ": attribute `", attr, "` only in the first file")
    }
    for (attr in setdiff(names(y$attrs), names(x$attrs))) {
      note(path, ": attribute `", attr, "` only in the second file")
    }
    for (attr in intersect(names(x$attrs), names(y$attrs))) {
      for (prop in c("value", "type")) {
        if (!identical(x$attrs[[attr]][[prop]], y$attrs[[attr]][[prop]])) {
          note(
            path,
            ": attribute `",
            attr,
            "` ",
            prop,
            " differs (",
            show(x$attrs[[attr]][[prop]]),
            " vs ",
            show(y$attrs[[attr]][[prop]]),
            ")"
          )
        }
      }
    }
  }
  diffs
}

# Expects two HDF5 files to have the same groups, datasets, attributes, dtypes,
# shapes and values, listing each difference on failure
expect_structurally_equivalent <- function(
  a,
  b,
  rec_array_paths = character()
) {
  diffs <- h5_tree_differences(h5_tree(a), h5_tree(b), rec_array_paths)
  testthat::expect(
    length(diffs) == 0L,
    paste0(
      "Files are not structurally equivalent:\n",
      paste0("* ", diffs, collapse = "\n")
    )
  )
  invisible(a)
}

# The field names, order and values of a rec-array dataset, as Python sees them
rec_array_values <- function(file, name) {
  jsonlite::fromJSON(
    paste(run_python("rec_array_values.py", file, name), collapse = ""),
    simplifyVector = FALSE
  )
}

# Expects the rec-arrays at `name` in two files to have the same field names,
# order and values, which is all ADR 0005 promises
expect_rec_array_values_equal <- function(a, b, name = "/x") {
  x <- rec_array_values(a, name)
  y <- rec_array_values(b, name)
  same_values <- identical(names(x$fields), names(y$fields)) &&
    all(mapply(
      function(p, q) {
        p <- unlist(p)
        q <- unlist(q)
        if (is.character(p) || is.character(q)) {
          identical(as.character(p), as.character(q))
        } else {
          isTRUE(all.equal(as.double(p), as.double(q), tolerance = 0))
        }
      },
      x$fields,
      y$fields
    ))
  testthat::expect(
    identical(x$names, y$names) && same_values,
    paste0(
      "Rec-arrays differ:\n",
      jsonlite::toJSON(x, auto_unbox = TRUE),
      "\nvs\n",
      jsonlite::toJSON(y, auto_unbox = TRUE)
    )
  )
  invisible(a)
}

# Expects two h5ad files to read as equal AnnData objects in Python
expect_python_equal <- function(a, b) {
  result <- run_python_raw("compare.py", a, b)
  testthat::expect(
    result$status == 0L,
    paste0("Python reads the files as different:\n", result$stderr)
  )
  invisible(a)
}
