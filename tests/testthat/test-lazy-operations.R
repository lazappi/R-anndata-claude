# Tests of operations on lazily read objects (ticket lazy/07, table section
# `operations`): subsetting, Views, to_memory(), printing, copy and writing.

skip_if_not_installed("Rarr", "2.1.48")

# Written once for the whole file, because every test only reads the files
small_paths <- lazy_small_paths(env = testthat::teardown_env())

test_that("subsetting a lazy AnnData gives a lazy View (rows subset_*)", {
  # Row `subset_names`: a View with the selected names in order and values
  # that are still lazy but realise to the selected block
  row <- lazy_row("operations", "subset_names", "h5ad")$result
  expected <- do.call(rbind, lapply(row$X$values, unlist))
  for (path in small_paths) {
    lazy <- read_lazy(path)
    view <- lazy[c("o3", "o1"), c("v2", "v0")]
    expect_true(view$is_view)
    expect_equal(view$obs_names, unlist(row$summary$obs_names))
    expect_equal(view$var_names, unlist(row$summary$var_names))
    expect_s4_class(view$X, "DelayedArray")
    expect_s4_class(view$layers[["csc"]], "DelayedArray")
    expect_s4_class(view$obs, "LazyDFrame")
    expect_equal(as.matrix(view$X), expected, ignore_attr = TRUE)
  }
})

test_that("logical, slice, one-axis and nested subsets agree with eager", {
  # Rows `subset_bool`, `subset_slices`, `subset_obs_only`, `subset_var_only`
  # and `view_of_view`: shapes and values must equal the same subset of the
  # eagerly read object
  for (path in small_paths) {
    lazy <- read_lazy(path)
    eager <- if (grepl("h5ad$", path)) read_h5ad(path) else read_zarr(path)
    cases <- list(
      list(
        lazy[c(TRUE, FALSE, TRUE, FALSE), ],
        eager[c(TRUE, FALSE, TRUE, FALSE), ]
      ),
      list(lazy[2:3, 1:2], eager[2:3, 1:2]),
      list(lazy[c(1, 4), ], eager[c(1, 4), ]),
      list(lazy[, "v1"], eager[, "v1"]),
      list(lazy[c(1, 3), ][2, ], eager[c(1, 3), ][2, ])
    )
    for (case in cases) {
      expect_true(case[[1]]$is_view)
      expect_equal(case[[1]]$shape, case[[2]]$shape)
      expect_equal(case[[1]]$obs_names, case[[2]]$obs_names)
      expect_equal(
        as.matrix(case[[1]]$X),
        as.matrix(case[[2]]$X),
        ignore_attr = TRUE
      )
      expect_equal(
        as.matrix(case[[1]]$layers[["csr"]]),
        as.matrix(case[[2]]$layers[["csr"]]),
        ignore_attr = TRUE
      )
    }
  }
})

test_that("assigning obs of a lazy View warns (view_assign_obs)", {
  # Row `view_assign_obs`: Python adds the column; R follows the Views rule
  # of copy-on-write, so the View becomes an actual object with a warning
  for (path in small_paths) {
    view <- read_lazy(path)[c(1, 3), ]
    expect_warning(
      view$obs[["z"]] <- 1:2,
      class = "anndata_implicit_modification_warning"
    )
    expect_true("z" %in% colnames(view$obs))
  }
})

test_that("assigning obs columns or X on a lazy AnnData (assign_* rows)", {
  # Rows `assign_obs_column` and `assign_X`: a new column is added, and X
  # becomes the assigned in-memory array
  row <- lazy_row("operations", "assign_obs_column", "h5ad")$result
  for (path in small_paths) {
    lazy <- read_lazy(path)
    lazy$obs[["new"]] <- 1:4
    expect_true("new" %in% colnames(lazy$obs))
    expect_setequal(
      setdiff(colnames(lazy$obs), "new"),
      intersect(unlist(row$obs_columns), c("num", "ni", "nb", "cat"))
    )
    lazy$X <- matrix(0, 4, 3)
    expect_equal(as.matrix(lazy$X), matrix(0, 4, 3), ignore_attr = TRUE)
  }
})

test_that("to_memory() realises every slot (rows to_memory*)", {
  # Rows `to_memory`, `to_memory_copy_false` and `to_memory_view`: the result
  # is not lazy, is not a View and has the values of the eager read
  for (path in small_paths) {
    lazy <- read_lazy(path)
    eager <- if (grepl("h5ad$", path)) read_h5ad(path) else read_zarr(path)
    for (mem in list(
      lazy$to_memory(),
      lazy$to_memory(copy = FALSE)
    )) {
      expect_false(mem$is_view)
      expect_false(methods::is(mem$X, "DelayedArray"))
      expect_false(methods::is(mem$obs, "LazyDFrame"))
      expect_equal(as.matrix(mem$X), as.matrix(eager$X), ignore_attr = TRUE)
      expect_equal(mem$obs_names, eager$obs_names)
      expect_equal(mem$obs$num, eager$obs$num)
      expect_equal(mem$obs$cat, eager$obs$cat)
      for (key in names(eager$layers)) {
        expect_false(methods::is(mem$layers[[key]], "DelayedArray"))
        expect_equal(
          as.matrix(mem$layers[[key]]),
          as.matrix(eager$layers[[key]]),
          ignore_attr = TRUE
        )
      }
    }
    view <- lazy[c(1, 3), ]$to_memory()
    expect_false(view$is_view)
    expect_equal(
      as.matrix(view$X),
      as.matrix(eager[c(1, 3), ]$X),
      ignore_attr = TRUE
    )
    expect_equal(view$obs$num, eager$obs$num[c(1, 3)])
  }
})

test_that("printing a lazy AnnData matches its in-memory form (repr)", {
  # Row `repr`: the summary lists slots the same way as for an eager object
  for (path in small_paths) {
    lazy <- read_lazy(path)
    expect_equal(format(lazy), format(lazy$to_memory()))
    expect_output(print(lazy), "AnnData object with n_obs", fixed = TRUE)
  }
})

test_that("copy() and transpose of a lazy AnnData stay lazy (rows)", {
  # Row `copy` keeps the lazy classes. Python's `.T` of a lazy AnnData fails
  # with a ValueError ("Invalid mode"), a Python bug, so R transposes lazily
  for (path in small_paths) {
    lazy <- read_lazy(path)
    copied <- lazy$copy()
    expect_s4_class(copied$X, "DelayedArray")
    expect_s4_class(copied$obs, "LazyDFrame")
    expect_false(copied$is_view)
    tr <- t(lazy)
    expect_equal(unname(tr$shape), c(3L, 4L))
    expect_equal(as.matrix(tr$X), t(as.matrix(lazy$X)), ignore_attr = TRUE)
  }
})

test_that("writing a lazy AnnData raises like Python (write_* rows)", {
  # Rows `write_h5ad`, `write_zarr` and `write_view_*`: NotImplementedError
  # that points to to_memory(), which does write
  dir <- withr::local_tempdir()
  for (path in small_paths) {
    lazy <- read_lazy(path)
    for (obj in list(lazy, lazy[c(1, 3), ])) {
      expect_anndata_condition(
        write_h5ad(obj, file.path(dir, "o.h5ad")),
        "anndata_not_implemented_error"
      )
      expect_anndata_condition(
        write_zarr(obj, file.path(dir, "o.zarr")),
        "anndata_not_implemented_error"
      )
    }
    mem <- lazy$to_memory()
    write_h5ad(mem, file.path(dir, "mem.h5ad"))
    back <- read_h5ad(file.path(dir, "mem.h5ad"))
    expect_equal(as.matrix(back$X), as.matrix(mem$X), ignore_attr = TRUE)
    write_zarr(mem, file.path(dir, "mem.zarr"))
    back <- read_zarr(file.path(dir, "mem.zarr"))
    expect_equal(as.matrix(back$X), as.matrix(mem$X), ignore_attr = TRUE)
  }
})

test_that("tall sparse layers subset lazily (subset_tall_csr)", {
  # Row `subset_tall_csr`: a View of a tall CSR layer is still lazy and
  # realises to the right rows
  dir <- withr::local_tempdir()
  csr <- methods::as(
    methods::as(
      Matrix::sparseMatrix(
        i = c(1, 3, 2500),
        j = c(1, 2, 4),
        x = c(1, 2, 3),
        dims = c(2500, 4)
      ),
      "generalMatrix"
    ),
    "RsparseMatrix"
  )
  adata <- AnnData(X = csr)
  path <- file.path(dir, "tall.h5ad")
  write_h5ad(adata, path)
  view <- read_lazy(path)[c(3, 2500), ]
  expect_s4_class(view$X, "DelayedArray")
  expect_equal(
    as.matrix(view$X),
    as.matrix(csr[c(3, 2500), ]),
    ignore_attr = TRUE
  )
})

test_that("lazy obs subsets keep columns and rows (obs_* rows)", {
  # Rows `obs_column_subset`, `obs_row_subset` and `obs_columns_realised`:
  # a column subset keeps the named columns, a row subset the rows in order,
  # and each column realises to the table's values. Row `obs_loc` is a Python
  # AttributeError (no `.loc` on Dataset2D), R indexes by row name instead
  cols <- lazy_row("operations", "obs_column_subset", "h5ad")$result$obs
  rows <- lazy_row("operations", "obs_row_subset", "h5ad")$result
  real <- lazy_row("operations", "obs_columns_realised", "h5ad")$result
  for (path in small_paths) {
    obs <- read_lazy(path)$obs
    sub <- obs[, unlist(cols$columns)]
    expect_s4_class(sub, "LazyDFrame")
    expect_setequal(colnames(sub), unlist(cols$columns))
    sub_rows <- obs[c(1, 3), ]
    expect_s4_class(sub_rows, "LazyDFrame")
    expect_equal(rownames(sub_rows), unlist(rows$index))
    expect_equal(
      as.data.frame(sub_rows)$num,
      unlist(rows$columns_detail$num$values)
    )
    expect_equal(rownames(obs[c("o3", "o1"), ]), c("o3", "o1"))
    frame <- as.data.frame(obs)
    expect_equal(frame$num, unlist(real$num$values))
    expect_equal(as.character(frame$cat), c("a", "b", "a", NA))
    expect_equal(
      as.integer(frame$ni),
      as.integer(unlist(lapply(real$ni$values, function(v) v %||% NA)))
    )
  }
})

test_that("lazy raw, obsm and obsp realise or stay lazy as asked", {
  # Covers memory_copy(): to_memory() reads raw and the aligned mappings,
  # copy() keeps them lazy
  dir <- withr::local_tempdir()
  x <- matrix(as.numeric(1:6), nrow = 3)
  adata <- AnnData(
    X = x,
    obsm = list(pca = x),
    obsp = list(graph = matrix(as.numeric(1:9), nrow = 3))
  )
  adata$raw <- adata
  paths <- c(file.path(dir, "r.h5ad"), file.path(dir, "r.zarr"))
  write_h5ad(adata, paths[[1]])
  write_zarr(adata, paths[[2]])
  for (path in paths) {
    lazy <- read_lazy(path)
    kept <- lazy$copy()
    expect_s4_class(kept$raw$X, "DelayedArray")
    expect_s4_class(kept$obsm[["pca"]], "DelayedArray")
    mem <- lazy$to_memory()
    expect_false(methods::is(mem$raw$X, "DelayedArray"))
    expect_false(methods::is(mem$obsm[["pca"]], "DelayedArray"))
    expect_false(methods::is(mem$obsp[["graph"]], "DelayedArray"))
    expect_equal(as.matrix(mem$raw$X), x, ignore_attr = TRUE)
    expect_equal(as.matrix(mem$obsm[["pca"]]), x, ignore_attr = TRUE)
  }
})

test_that("a View of a lazy AnnData writes once in memory (write_view_*)", {
  # Rows `write_*_after_to_memory`: to_memory() of a lazy object or View gives
  # something that writes, and the error message points to to_memory()
  dir <- withr::local_tempdir()
  for (path in small_paths) {
    view <- read_lazy(path)[c(1, 3), ]
    cnd <- expect_anndata_condition(
      write_h5ad(view, file.path(dir, "v.h5ad")),
      "anndata_not_implemented_error"
    )
    expect_match(conditionMessage(cnd), "to_memory", fixed = TRUE)
    mem <- view$to_memory()
    write_zarr(mem, file.path(dir, "v.zarr"))
    back <- read_zarr(file.path(dir, "v.zarr"))
    expect_equal(back$obs_names, c("o0", "o2"))
  }
})

test_that("delayed_in_memory() gives the on-disk class for pristine seeds", {
  # Pristine seeds keep the sparse class and dtype of read_elem(), subsets and
  # other operations give a plain Matrix or array
  paths <- small_paths
  lazy <- read_lazy(paths$h5ad)
  csr <- delayed_in_memory(lazy$layers[["csr"]])
  expect_true(methods::is(csr, "sparseMatrix"))
  expect_true(methods::is(
    delayed_in_memory(lazy$layers[["csr"]][1:2, ]),
    "sparseMatrix"
  ))
  dense <- delayed_in_memory(lazy$layers[["dense_i"]])
  expect_equal(dim(dense), c(4L, 3L))
  expect_equal(dim(delayed_in_memory(lazy$X[1:2, ] + 1)), c(2L, 3L))
  expect_s4_class(realise_lazy_value(lazy$obs), "DFrame")
  expect_false(methods::is(realise_lazy_value(lazy$obs), "LazyDFrame"))
})
