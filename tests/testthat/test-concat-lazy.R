# An object for the lazy input tests: a dense or sparse X, a layer, an obs
# column and an obsm array, with the given names
concat_lazy_input <- function(obs, var, sparse) {
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

# The dense values of X, a layer or an obsm array, lazy or not
concat_lazy_values <- function(x) {
  as.matrix(if (is_sparse(x)) x else drop_dtype(x))
}

# Why: Python keeps `concat()` of lazily read objects lazy, with values equal
# to the in-memory result, for both axes, joins, dense and sparse X and
# `fill_value`. `obs` and `var` are read into memory (a documented deviation).
test_that("concat of lazy objects is lazy and equals the in-memory result", {
  dir <- withr::local_tempdir()
  cases <- list(
    list(
      names = list(
        list(paste0("a", 1:5), paste0("g", 1:5)),
        list(paste0("b", 1:4), paste0("g", 3:6))
      ),
      args = list(join = "outer", label = "batch", index_unique = "-")
    ),
    list(
      names = list(
        list(paste0("a", 1:5), paste0("g", 1:5)),
        list(paste0("b", 1:4), paste0("g", 3:6))
      ),
      args = list(join = "outer", fill_value = 7)
    ),
    list(
      names = list(
        list(paste0("a", 1:5), paste0("g", 1:5)),
        list(paste0("b", 1:4), paste0("g", 3:6))
      ),
      args = list(join = "inner")
    ),
    list(
      names = list(
        list(paste0("o", 1:4), paste0("a", 1:5)),
        list(paste0("o", 2:6), paste0("b", 1:3))
      ),
      args = list(axis = "var", join = "outer", keys = c("p", "q"))
    )
  )
  for (sparse in c(FALSE, TRUE)) {
    for (i in seq_along(cases)) {
      spec <- cases[[i]]
      memory <- lapply(spec$names, function(n) {
        concat_lazy_input(n[[1L]], n[[2L]], sparse)
      })
      lazy <- lapply(seq_along(memory), function(k) {
        path <- file.path(dir, paste0("c", sparse, i, "-", k, ".h5ad"))
        write_h5ad(memory[[k]], path)
        read_lazy(path)
      })
      expected <- do.call(concat, c(list(memory), spec$args))
      got <- do.call(concat, c(list(lazy), spec$args))

      expect_s4_class(got$X, "DelayedArray")
      expect_s4_class(got$layers[["l"]], "DelayedArray")
      expect_equal(
        concat_lazy_values(got$X),
        concat_lazy_values(expected$X),
        ignore_attr = TRUE
      )
      expect_equal(
        concat_lazy_values(got$layers[["l"]]),
        concat_lazy_values(expected$layers[["l"]]),
        ignore_attr = TRUE
      )
      # obsm is only kept when concatenating along obs
      if (is.null(spec$args$axis)) {
        expect_s4_class(got$obsm[["e"]], "DelayedArray")
        expect_equal(
          concat_lazy_values(got$obsm[["e"]]),
          concat_lazy_values(expected$obsm[["e"]]),
          ignore_attr = TRUE
        )
      } else {
        expect_null(got$obsm[["e"]])
      }
      expect_equal(got$obs_names, expected$obs_names)
      expect_equal(got$var_names, expected$var_names)
      expect_equal(
        as.data.frame(got$obs),
        as.data.frame(expected$obs),
        ignore_attr = TRUE
      )
    }
  }
})

# Why: Python reads lazy inputs into memory when any input is in memory
test_that("concat of lazy and in-memory objects is in memory", {
  path <- withr::local_tempfile(fileext = ".h5ad")
  a <- concat_lazy_input(paste0("a", 1:3), paste0("g", 1:4), FALSE)
  b <- concat_lazy_input(paste0("b", 1:2), paste0("g", 1:4), FALSE)
  write_h5ad(a, path)
  got <- concat(list(read_lazy(path), b))
  expect_false(methods::is(got$X, "DelayedArray"))
  expect_false(methods::is(got$obsm[["e"]], "DelayedArray"))
  expect_equal(got$X, concat(list(a, b))$X)
})

# Why: lazy raw X and lazy alternate-axis mappings must be read, not rejected
test_that("concat of lazy objects with raw and varm works", {
  dir <- withr::local_tempdir()
  make <- function(obs) {
    adata <- concat_lazy_input(obs, paste0("g", 1:3), TRUE)
    adata$varm[["w"]] <- matrix(1, 3, 2)
    adata$raw <- adata
    adata
  }
  memory <- list(make(paste0("a", 1:3)), make(paste0("b", 1:2)))
  lazy <- lapply(seq_along(memory), function(k) {
    path <- file.path(dir, paste0("r", k, ".h5ad"))
    write_h5ad(memory[[k]], path)
    read_lazy(path)
  })
  got <- concat(lazy, merge = "same")
  expected <- concat(memory, merge = "same")
  expect_equal(
    concat_lazy_values(got$raw$X),
    concat_lazy_values(expected$raw$X),
    ignore_attr = TRUE
  )
  expect_equal(
    concat_lazy_values(got$varm[["w"]]),
    concat_lazy_values(expected$varm[["w"]]),
    ignore_attr = TRUE
  )
})
