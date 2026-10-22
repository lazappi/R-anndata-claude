# An object for the input tests: a dense or sparse X, a layer, an obs column
# and an obsm array, with the given names
concat_input <- function(obs, var, sparse) {
  x <- matrix(seq_len(length(obs) * length(var)) + 0, length(obs))
  if (sparse) {
    x[x %% 3 == 0] <- 0
    x <- methods::as(methods::as(x, "generalMatrix"), "CsparseMatrix")
  }
  AnnData(
    x,
    obs = data.frame(
      g = factor(rep(c("u", "v"), length.out = length(obs))),
      n = seq_along(obs) + 0,
      row.names = obs
    ),
    var = data.frame(k = seq_along(var) + 0, row.names = var),
    layers = list(l = x * 2),
    obsm = list(e = matrix(seq_along(obs) + 0, length(obs), 2L))
  )
}

# Why: Python concatenates Views and backed objects as their in-memory
# equivalents (backed ones are read into memory), so the result must be
# Structurally equivalent to the in-memory result and to Python's own, for both
# axes and joins
test_that("concat of Views and backed objects matches memory and Python", {
  dir <- withr::local_tempdir()
  cases <- list(
    list(
      names = list(
        list(paste0("a", 1:5), paste0("g", 1:5)),
        list(paste0("b", 1:4), paste0("g", 3:6))
      ),
      args = list(
        join = "outer",
        label = "batch",
        index_unique = "-",
        merge = "first"
      )
    ),
    list(
      names = list(
        list(paste0("o", 1:4), paste0("a", 1:5)),
        list(paste0("o", 2:6), paste0("b", 1:3))
      ),
      args = list(axis = "var", label = "batch", keys = c("p", "q"))
    )
  )
  sparse <- c(FALSE, TRUE)
  mine <- character()
  theirs <- character()
  jobs <- list()
  for (i in seq_along(cases)) {
    spec <- cases[[i]]
    # Each parent is a bigger object whose View holds the rows and columns
    # the in-memory copy holds
    parents <- Map(
      function(n, s) concat_input(c(n[[1L]], "x1", "x2"), c(n[[2L]], "y1"), s),
      spec$names,
      sparse
    )
    views <- Map(
      function(parent, n) parent[n[[1L]], n[[2L]]],
      parents,
      spec$names
    )
    memory <- lapply(views, function(view) view$copy())
    files <- file.path(dir, paste0("in", i, "-", seq_along(memory), ".h5ad"))
    for (j in seq_along(memory)) {
      write_h5ad(memory[[j]], files[[j]])
    }
    backed <- lapply(files, read_h5ad, backed = "r")
    withr::defer(
      for (b in backed) {
        b$file$close()
      }
    )
    inputs <- list(memory = memory, view = views, backed = backed)
    for (kind in names(inputs)) {
      out <- file.path(dir, paste0("out", i, "-", kind, ".h5ad"))
      result <- do.call(concat, c(list(inputs[[kind]]), spec$args))
      expect_false(result$is_view)
      expect_false(result$isbacked)
      write_h5ad(result, out)
      mine <- c(mine, out)
      theirs <- c(theirs, file.path(dir, paste0("py", i, ".h5ad")))
    }
    jobs[[i]] <- list(
      inputs = files,
      out = file.path(dir, paste0("py", i, ".h5ad")),
      kwargs = spec$args
    )
  }
  jobs_file <- file.path(dir, "jobs.json")
  jsonlite::write_json(jobs, jobs_file, auto_unbox = TRUE)
  run_python("concat_files.py", jobs_file)
  expect_all_equivalent(mine, theirs)
  expect_python_equal(mine, theirs)
})

# Why: a backed object's raw X is a placeholder too, and concat must read it
# into memory like X, for dense and sparse files
test_that("concat reads the raw X of backed objects into memory", {
  for (kind in c("dense", "csr")) {
    first <- local_backed(kind, raw = TRUE)$adata
    second <- local_backed(kind, raw = TRUE)$adata
    expected <- concat(
      list(first$to_memory(), second$to_memory()),
      index_unique = "-"
    )
    result <- concat(list(first, second), index_unique = "-")
    expect_equal(as.matrix(result$raw$X), as.matrix(expected$raw$X))
    expect_equal(as.matrix(result$X), as.matrix(expected$X))
    expect_identical(array_dtype(result$raw$X), array_dtype(expected$raw$X))
  }
})
