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

# A hash of a generator script, its extra inputs (other scripts it depends on)
# and the uv lock file. `scripts/write-generator-hashes.R` stores it next to the
# generated fixtures, so freshness tests compare hashes, not run Python
generator_hash <- function(
  script,
  extra = character(),
  dir = python_project()
) {
  files <- file.path(dir, c(script, extra, "uv.lock"))
  hashes <- unname(tools::md5sum(files))
  combined <- tempfile()
  on.exit(unlink(combined))
  writeLines(hashes, combined)
  unname(tools::md5sum(combined))
}

# The generators whose output is committed, and the extra inputs of each
generator_inputs <- function() {
  list(
    "encoding_table.py" = "generate_fixtures.py",
    "zarr_encoding_table.py" = "generate_zarr_fixtures.py",
    "backed_cases.py" = character(),
    "unwriteable_cases.py" = character(),
    "view_cases.py" = character(),
    "categorical_cases.py" = character(),
    "make_unique_cases.py" = character(),
    "repr_cases.py" = character()
  )
}

# Fails when a generator script (or uv.lock) changed since its committed output
# was last regenerated with `scripts/regenerate-fixtures.sh`
expect_generator_current <- function(script) {
  stored <- jsonlite::fromJSON(fixture_path("generator-hashes.json"))
  expect_identical(
    stored[[script]],
    generator_hash(script, generator_inputs()[[script]]),
    info = paste0(
      "`",
      script,
      "` or uv.lock changed, run scripts/regenerate-fixtures.sh"
    )
  )
}

# The interpreter of the uv environment, found once per test process because
# `uv run` costs a few hundred milliseconds on every call (uv still creates and
# syncs the environment on the first one)
python_interpreter <- local({
  path <- NULL
  function() {
    if (is.null(path)) {
      out <- system2(
        "uv",
        c(
          "run",
          "--project",
          python_project(),
          "python",
          "-I",
          "-c",
          shQuote("import sys; print(sys.executable)")
        ),
        stdout = TRUE,
        stderr = FALSE,
        env = paste0("TMPDIR=", withr::local_tempdir())
      )
      if (length(out) == 0L) {
        stop("`uv run` did not print the Python interpreter path")
      }
      path <<- out[[length(out)]]
    }
    path
  }
})

# Runs a script from tests/python in the reference environment and returns
# its stdout lines, stderr text and exit status without judging the result
run_python_raw <- function(script, ...) {
  project <- python_project()
  stderr_file <- withr::local_tempfile()
  args <- c(
    "-I",
    file.path(project, script),
    as.character(c(...))
  )
  out <- suppressWarnings(
    system2(
      python_interpreter(),
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

# The zarr fixture stores are committed as one archive (R CMD check notes the
# hidden files and long paths of a zarr directory tree), unpacked once per test
# process into a temporary directory that is removed at the end
zarr_fixture_dir <- local({
  dir <- NULL
  function() {
    if (is.null(dir)) {
      dir <<- withr::local_tempdir(.local_envir = testthat::teardown_env())
      utils::untar(fixture_path("zarr-fixtures.tar.gz"), exdir = dir)
    }
    dir
  }
})

# Path to a zarr fixture (a manifest or a store) in the unpacked archive
zarr_fixture_path <- function(name) {
  file.path(zarr_fixture_dir(), name)
}

# The manifest of the zarr fixtures: the variants and the cases of each
zarr_fixture_manifest <- function() {
  jsonlite::fromJSON(
    zarr_fixture_path("manifest.json"),
    simplifyVector = FALSE
  )
}

# The fixture store paths of a variant, keyed by case name
zarr_variant_paths <- function(variant) {
  cases <- zarr_fixture_manifest()$variants[[variant]]$cases
  vapply(
    cases,
    function(case) zarr_fixture_path(case$file),
    character(1)
  )
}

name_h5_nodes <- function(nodes) {
  stats::setNames(nodes, vapply(nodes, function(node) node$path, character(1)))
}

# Trees computed ahead by `prefetch_h5_trees()`, keyed by file path
h5_tree_cache <- new.env(parent = emptyenv())

# Computes the h5_tree() of many files with one Python process, because starting
# Python for each file dominates the run time of the comparison tests
#
# Each tree is used (and dropped) by the next `h5_tree()` of that path, so the
# files must not change in between
prefetch_h5_trees <- function(files) {
  # A path listed n times is used n times, because a fixture is often compared
  # with several files
  files <- as.character(files)
  uses <- table(files)
  files <- unique(files)
  uses <- stats::setNames(as.integer(uses[files]), files)
  # A zarr store is a directory and is described by zarr_tree.py in the same
  # shape, so HDF5 files and zarr stores can be compared with each other
  is_store <- dir.exists(files)
  for (script in c("h5_tree.py", "zarr_tree.py")) {
    group <- files[is_store == (script == "zarr_tree.py")]
    if (length(group) == 0L) {
      next
    }
    # Big batches are split over two Python processes that run side by side
    # (R CMD check allows no more), as reading a store takes about 0.4s
    n_parts <- min(2L, ceiling(length(group) / 8L))
    parts <- split(group, rep_len(seq_len(n_parts), length(group)))
    results <- parallel::mclapply(
      parts,
      function(part) run_python_raw(script, part),
      mc.cores = n_parts
    )
    trees <- list()
    for (i in seq_along(parts)) {
      if (!identical(results[[i]]$status, 0L)) {
        testthat::fail(paste0(
          "Python script `",
          script,
          "` failed:\n",
          results[[i]]$stderr
        ))
        next
      }
      # One file prints its own list of nodes, several print a list per file
      part_trees <- jsonlite::fromJSON(
        paste(results[[i]]$stdout, collapse = ""),
        simplifyVector = FALSE
      )
      if (length(parts[[i]]) == 1L) {
        part_trees <- list(part_trees)
      }
      trees[match(parts[[i]], group)] <- part_trees
    }
    for (i in seq_along(group)) {
      assign(
        group[[i]],
        list(tree = name_h5_nodes(trees[[i]]), uses = uses[[group[[i]]]]),
        envir = h5_tree_cache
      )
    }
  }
  invisible()
}

# Reads the h5_tree.py description of a file as a list of nodes keyed by path
h5_tree <- function(file) {
  if (exists(file, envir = h5_tree_cache, inherits = FALSE)) {
    entry <- get(file, envir = h5_tree_cache, inherits = FALSE)
    if (entry$uses > 1L) {
      entry$uses <- entry$uses - 1L
      assign(file, entry, envir = h5_tree_cache)
    } else {
      rm(list = file, envir = h5_tree_cache)
    }
    return(entry$tree)
  }
  prefetch_h5_trees(file)
  h5_tree(file)
}

# Python's rewrite (read then write with `anndata.io`) of many files in one
# Python process, returning the paths of the rewritten files (in the temporary
# directory of the calling test)
python_rewrite <- function(files, ext = ".h5", .local_envir = parent.frame()) {
  out_dir <- withr::local_tempdir(.local_envir = .local_envir)
  rewritten <- file.path(out_dir, paste0(seq_along(files), ext))
  run_python("rewrite.py", as.vector(rbind(files, rewritten)))
  rewritten
}

# Lists every path and property that differs between two h5_tree() results
#
# `rec_array_paths` are datasets whose field dtypes are exempt (ADR 0005), so
# their `dtype` and `digest` are not compared, and nothing else is relaxed
#
# `sorted_paths` are sparse `data` and `indices` datasets that may be stored
# unsorted in the second file (ADR 0006), so only their `digest` is skipped
#
# `attr_types = FALSE` skips the attribute `type`, which an HDF5 file and a zarr
# store describe differently (zarr only stores JSON)
h5_tree_differences <- function(
  a,
  b,
  rec_array_paths = character(),
  sorted_paths = character(),
  attr_types = TRUE
) {
  found <- new.env(parent = emptyenv())
  found$diffs <- character()
  note <- function(...) found$diffs <- c(found$diffs, paste0(...))
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
    if (path %in% sorted_paths) {
      props <- setdiff(props, "digest")
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
      for (prop in c("value", if (attr_types) "type")) {
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
  found$diffs
}

# Expects two HDF5 files or zarr stores (or one of each) to have the same
# groups, datasets, attributes, dtypes, shapes and values, listing each
# difference on failure
#
# Chunk shape, codecs and shard layout are never compared
expect_structurally_equivalent <- function(
  a,
  b,
  rec_array_paths = character(),
  sorted_paths = character()
) {
  diffs <- h5_tree_differences(
    h5_tree(a),
    h5_tree(b),
    rec_array_paths,
    sorted_paths,
    attr_types = dir.exists(a) == dir.exists(b)
  )
  testthat::expect(
    length(diffs) == 0L,
    paste0(
      "Files are not structurally equivalent:\n",
      paste0("* ", diffs, collapse = "\n")
    )
  )
  invisible(a)
}

# Runs `expect_structurally_equivalent(a[[i]], b[[i]])` for every pair, reading
# all the files with one Python process
expect_all_equivalent <- function(
  a,
  b,
  rec_array_paths = character(),
  sorted_paths = character()
) {
  stopifnot(length(a) == length(b))
  prefetch_h5_trees(c(a, b))
  for (i in seq_along(a)) {
    expect_structurally_equivalent(
      a[[i]],
      b[[i]],
      rec_array_paths,
      sorted_paths
    )
  }
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

# Expects pairs of h5ad files (`a[i]` and `b[i]`) to read as equal AnnData
# objects in Python, using one Python process for all the pairs
expect_python_equal <- function(a, b) {
  stopifnot(length(a) == length(b))
  result <- run_python_raw("compare.py", as.vector(rbind(a, b)))
  testthat::expect(
    result$status == 0L,
    paste0("Python reads the files as different:\n", result$stderr)
  )
  invisible(a)
}

# Python's read and write of many h5ad files in one Python process, returning
# the paths of the rewritten files (in the temporary directory of the caller)
python_rewrite_h5ad <- function(
  files,
  ext = ".h5ad",
  .local_envir = parent.frame()
) {
  out_dir <- withr::local_tempdir(.local_envir = .local_envir)
  rewritten <- file.path(out_dir, paste0(seq_along(files), ext))
  run_python("rewrite_h5ad.py", as.vector(rbind(files, rewritten)))
  rewritten
}
