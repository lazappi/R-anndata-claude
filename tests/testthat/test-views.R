view_cases <- function() {
  jsonlite::fromJSON(fixture_path("view_cases.json"), simplifyVector = FALSE)
}

# Guards the committed View operations table against drifting from Python
test_that("the committed View operations table matches Python", {
  skip_if_no_python()
  fresh <- withr::local_tempfile(fileext = ".json")
  run_python("view_cases.py", fresh)
  expect_equal(readLines(fresh), readLines(fixture_path("view_cases.json")))
})

# The table must keep covering every operation the views spec lists, so later
# tickets can test each row against its R equivalent
test_that("the View operations table covers the operations in the spec", {
  cases <- view_cases()
  operations <- names(cases$operations)
  expected <- c(
    # Slots: reading, assigning, modifying nested and deleting
    paste0(
      "read_",
      c(
        "X",
        "obs",
        "var",
        "layers",
        "obsm",
        "varm",
        "obsp",
        "varp",
        "uns",
        "raw"
      )
    ),
    c("X_assign", "X_item", "layers_set", "layers_item", "layers_del"),
    c("obs_assign", "obs_col_set", "obs_col_item", "obs_col_del"),
    c("var_assign", "var_col_set", "var_col_del"),
    c("obsm_set", "obsm_item", "obsm_del", "varm_set", "varm_del"),
    c("obsp_set", "obsp_del", "varp_set", "varp_del"),
    c("uns_set", "uns_modify", "uns_nested", "uns_del", "uns_assign"),
    c("raw_assign", "raw_del", "obs_names_set", "var_names_set"),
    # Whole-object operations and the other public methods
    c(
      "copy",
      "transpose",
      "T",
      "to_memory",
      "to_df",
      "obs_vector",
      "var_vector"
    ),
    c("strings_to_categoricals", "rename_categories"),
    c("obs_names_make_unique", "var_names_make_unique"),
    c("write_h5ad", "write_zarr", "write_csvs", "write_loom", "chunked_X"),
    # Views of Views and a changing parent
    c("subset_rows", "view_of_view_parent"),
    paste0(
      "parent_",
      c("X_new", "X_item", "obs_col", "uns", "raw", "layer_item")
    )
  )
  expect_in(expected, operations)
  # Views of Views repeat every row except those about the parent changing
  expect_in(
    expected[
      !startsWith(expected, "parent_") &
        !expected %in% c("subset_rows", "view_of_view_parent")
    ],
    names(cases$view_of_view)
  )
  expect_true(cases$composition$ref_is_parent)
})

# Python's mix of lazy and snapshot parts is the core of the View decision, so
# the table must show it (X follows the parent, obs does not)
test_that("the View operations table records lazy and snapshot parts", {
  ops <- view_cases()$operations
  expect_equal(ops$parent_X_new$view_after$X, list(list(0, 0), list(0, 0)))
  expect_null(ops$parent_obs_col$view_after)
  expect_true(ops$parent_X_new$is_view_after)
  expect_false(ops$X_assign$is_view_after)
  expect_equal(
    ops$X_assign$warnings[[1]]$category,
    "ImplicitModificationWarning"
  )
})

# R version of `make_parent()` in view_cases.py, and helpers to read the table
view_parent <- function() {
  x <- matrix(as.numeric(0:11), nrow = 4, byrow = TRUE)
  obs <- data.frame(
    num = c(1, 2, 3, 4),
    cat = factor(c("a", "b", "c", "a"), levels = c("a", "b", "c")),
    row.names = c("o0", "o1", "o2", "o3")
  )
  var <- data.frame(gene = c(10, 20, 30), row.names = c("v0", "v1", "v2"))
  adata <- AnnData(
    x,
    obs = obs,
    var = var,
    layers = list(
      counts = x * 10,
      sparse = as(as(x + 1, "generalMatrix"), "CsparseMatrix")
    ),
    obsm = list(pca = matrix(as.numeric(0:7), nrow = 4, byrow = TRUE)),
    varm = list(pcs = matrix(as.numeric(0:5), nrow = 3, byrow = TRUE)),
    obsp = list(conn = matrix(as.numeric(0:15), nrow = 4, byrow = TRUE)),
    varp = list(corr = matrix(as.numeric(0:8), nrow = 3, byrow = TRUE)),
    uns = list(
      u = 1,
      nested = list(k = c(1, 2, 3)),
      cat_colors = c("red", "green", "blue")
    )
  )
  adata$raw <- adata
  adata
}

# The table stores matrices as lists of rows
table_matrix <- function(rows) {
  do.call(rbind, lapply(rows, function(row) as.numeric(unlist(row))))
}

view_of <- function(parent) parent[c(1, 3), c(1, 3)]

# Why: a View must report itself as one and say so in its print() prefix, as
# `repr` does in Python
test_that("subsetting gives a View, and only subsetting does", {
  parent <- view_parent()
  view <- view_of(parent)
  expect_false(parent$is_view)
  expect_true(view$is_view)
  expect_false(parent$copy()$is_view)
  expect_false(AnnData(view)$is_view)
  expect_equal(format(view), view_cases()$operations$repr$result)
  expect_match(format(view), "^View of AnnData object")
  expect_no_match(format(parent), "View of")
})

# Why: the reading rows of the table, so a View shows the same values as Python
# and reading never warns or copies
test_that("reading a View matches the Python table without warnings", {
  tbl <- view_cases()$view
  parent <- view_parent()
  view <- view_of(parent)
  expect_no_warning({
    expect_equal(view$X, table_matrix(tbl$X))
    expect_equal(
      as.matrix(view$layers[["counts"]]),
      table_matrix(tbl$layers$counts)
    )
    expect_equal(
      as.matrix(view$layers[["sparse"]]),
      table_matrix(tbl$layers$sparse)
    )
    expect_equal(view$layers[[NA]], view$X)
    expect_equal(view$obsm[["pca"]], table_matrix(tbl$obsm$pca))
    expect_equal(view$varm[["pcs"]], table_matrix(tbl$varm$pcs))
    expect_equal(view$obsp[["conn"]], table_matrix(tbl$obsp$conn))
    expect_equal(view$varp[["corr"]], table_matrix(tbl$varp$corr))
    expect_equal(view$obs_names, unlist(tbl$obs_names))
    expect_equal(view$var_names, unlist(tbl$var_names))
    expect_equal(view$shape, unlist(tbl$shape))
    expect_equal(
      as.numeric(view$obs$num),
      as.numeric(unlist(tbl$obs$columns$num$values))
    )
    expect_equal(view$raw$X, table_matrix(tbl$raw$X))
    expect_equal(view$uns$cat_colors, unlist(tbl$uns$cat_colors))
  })
  # Unused categories are removed when the View is created
  expect_equal(
    levels(view$obs$cat),
    unique(unlist(tbl$obs$columns$cat$values))
  )
  expect_true(view$is_view)
  expect_equal(parent$shape, c(4L, 3L))
})

# Why: Python's lazy parts follow the parent and its snapshot parts do not
# (rows parent_* of the table), which is the core of the View decision
test_that("a View follows later changes to the lazy parts of its parent", {
  ops <- view_cases()$operations
  parent <- view_parent()
  view <- view_of(parent)

  parent$X <- matrix(0, 4, 3)
  expect_equal(view$X, table_matrix(ops$parent_X_new$view_after$X))
  expect_equal(view$layers[[NA]], view$X)

  parent$X[1, 1] <- -99
  expect_equal(view$X[1, 1], -99)

  parent$layers[["counts"]][1, 1] <- -99
  expect_equal(
    view$layers[["counts"]],
    table_matrix(ops$parent_layer_item$view_after$layers$counts)
  )
  parent$layers[["counts"]] <- matrix(0, 4, 3)
  expect_equal(
    view$layers[["counts"]],
    table_matrix(ops$parent_layer_set$view_after$layers$counts)
  )

  parent$obsm[["pca"]][1, 1] <- -99
  expect_equal(
    view$obsm[["pca"]],
    table_matrix(ops$parent_obsm_item$view_after$obsm$pca)
  )
  parent$obsm[["pca"]] <- matrix(0, 4, 2)
  expect_equal(
    view$obsm[["pca"]],
    table_matrix(ops$parent_obsm_new$view_after$obsm$pca)
  )
  parent$obsp[["conn"]][1, 1] <- -99
  expect_equal(
    view$obsp[["conn"]],
    table_matrix(ops$parent_obsp_item$view_after$obsp$conn)
  )
  expect_true(view$is_view)
})

# Why: obs, var, uns and raw are snapshots, so changing the parent leaves them
# alone (parent_obs_col, parent_var_col, parent_uns, parent_raw,
# parent_obs_names and the R side of parent_uns_nested)
test_that("a View keeps snapshots of obs, var, uns and raw", {
  ops <- view_cases()$operations
  expect_null(ops$parent_obs_col$view_after)
  parent <- view_parent()
  view <- view_of(parent)
  obs <- view$obs
  var <- view$var
  uns <- view$uns
  raw_x <- view$raw$X
  names <- view$obs_names

  parent$obs$num <- c(-1, -2, -3, -4)
  parent$var$gene <- c(-1, -2, -3)
  parent$uns$u <- 99
  # Python's nested uns is shared with the parent, R values cannot be
  # (documented deviation, see the Views vignette)
  parent$uns$nested$k <- c(parent$uns$nested$k, 99)
  parent$obs_names <- c("a", "b", "c", "d")
  parent$raw <- NULL

  expect_equal(view$obs, obs)
  expect_equal(view$var, var)
  expect_equal(view$uns, uns)
  expect_equal(view$raw$X, raw_x)
  expect_equal(view$obs_names, names)
  expect_true(view$is_view)
})

# Why: a View of a View refers to the original parent with composed positions
# (the `composition` and `view_of_view_parent` rows), for every R index form
test_that("Views of Views compose indices against the original parent", {
  tbl <- view_cases()
  parent <- view_parent()
  chain <- parent[c(4, 3, 2, 1), ][c(2, 4), ][2, c(3, 1)]
  expect_true(chain$is_view)
  expect_identical(.subset2(chain, "view_info")()$parent, parent)
  expect_equal(chain$obs_names, unlist(tbl$composition$obs_names))
  expect_equal(chain$var_names, unlist(tbl$composition$var_names))
  expect_equal(chain$X, table_matrix(tbl$composition$X))

  view <- view_of(parent)
  # Name, logical, negative and positive indices give the same View of a View
  forms <- list(view[2, ], view["o2", ], view[c(FALSE, TRUE), ], view[-1, ])
  for (sub in forms) {
    expect_true(sub$is_view)
    expect_identical(.subset2(sub, "view_info")()$parent, parent)
    expect_equal(sub$obs_names, "o2")
    expect_equal(sub$X, parent$X[3, c(1, 3), drop = FALSE])
  }
  cols <- list(view[, "v2"], view[, c(FALSE, TRUE)], view[, -1], view[, 2])
  for (sub in cols) {
    expect_equal(sub$var_names, "v2")
    expect_equal(sub$X, parent$X[c(1, 3), 3, drop = FALSE])
  }
  # Repeated and reordered positions compose too
  both <- view[c(2, 1, 2), ]
  expect_equal(both$obs_names, c("o2", "o0", "o2"))
  expect_equal(both$X, parent$X[c(3, 1, 3), c(1, 3)])
})

# Why: copy() of a View is independent, and so is a View after it is modified
# (copy-on-write itself and its warnings are tested with ticket views/03)
test_that("a copy and a modified View are independent of the parent", {
  parent <- view_parent()
  view <- view_of(parent)
  copy <- view$copy()
  expect_false(copy$is_view)
  expect_equal(copy$X, view$X)
  copy$X[1, 1] <- -1
  expect_equal(parent$X[1, 1], 0)

  view$X <- matrix(7, 2, 2)
  expect_false(view$is_view)
  expect_equal(parent$X, matrix(as.numeric(0:11), nrow = 4, byrow = TRUE))
  parent$X <- matrix(0, 4, 3)
  expect_equal(view$X, matrix(7, 2, 2))

  other <- view_of(parent)
  other$layers[["new"]] <- matrix(1, 2, 2)
  expect_false(other$is_view)
  expect_null(parent$layers[["new"]])
  expect_equal(other$layers[["new"]], matrix(1, 2, 2))
  expect_equal(
    other$layers[["counts"]],
    parent$layers[["counts"]][c(1, 3), c(1, 3)]
  )
})

# Why: the remaining reading and creation rows (keys, to_df, uns colours, copy,
# repeated subsetting) compared with the table
test_that("the other reading rows of the table hold for a View", {
  ops <- view_cases()$operations
  tbl <- view_cases()$view
  view <- view_of(view_parent())
  quiet_deprecated({
    expect_equal(view$obs_keys(), unlist(ops$obs_keys$result))
    expect_equal(view$var_keys(), unlist(ops$var_keys$result))
    expect_equal(view$obsm_keys(), unlist(ops$obsm_keys$result))
    expect_equal(view$varm_keys(), unlist(ops$varm_keys$result))
    expect_equal(sort(view$uns_keys()), sort(unlist(ops$uns_keys$result)))
  })
  expect_equal(length(view), ops$len$result)
  expect_equal(dim(view), as.integer(unlist(ops$shape$result)))
  expect_equal(unname(as.matrix(view$to_df())), table_matrix(tbl$X))
  expect_equal(
    unname(as.matrix(view$to_df("counts"))),
    table_matrix(tbl$layers$counts)
  )
  # Unused categories drop their uns colours at creation
  expect_equal(view$uns$cat_colors, unlist(tbl$uns$cat_colors))
  # copy() has the values of the View
  copy <- view$copy()
  expect_equal(copy$X, table_matrix(ops$copy$result$copy$X))
  expect_equal(copy$obs_names, unlist(ops$copy$result$copy$obs_names))
  # A View from a View by name and by logical index (rows of the table)
  by_name <- view["o2", "v0"]
  expect_equal(by_name$X, table_matrix(ops$subset_by_name$result$by_name$X))
  by_bool <- view[c(TRUE, FALSE), ]
  expect_equal(
    by_bool$X,
    table_matrix(ops$subset_by_bool$result$by_bool$X)
  )
})

# Why: edge cases of lazy reading (sparse and missing X, errors when composing)
test_that("lazy reading handles sparse and missing X and bad indices", {
  sparse <- AnnData(as(matrix(c(1, 0, 0, 2, 3, 0), 3), "CsparseMatrix"))
  view <- sparse[2:3, ]
  expect_s4_class(view$X, "sparseMatrix")
  sparse$X <- as(matrix(1, 3, 2), "CsparseMatrix")
  expect_equal(as.matrix(view$X), matrix(1, 2, 2), ignore_attr = TRUE)

  empty <- AnnData(shape = c(3, 2))
  view <- empty[1:2, ]
  expect_null(view$X)
  expect_true(view$is_view)
  empty$X <- matrix(5, 3, 2)
  expect_equal(view$X, matrix(5, 2, 2))

  view <- view_of(view_parent())
  expect_error(view[3, ], class = "anndata_index_error")
  expect_error(view["o1", ], class = "anndata_index_error")
  expect_true(view$is_view)
})

# Why: the documented deviation, an extracted value is a plain R value so
# changing it does not change the View (Python's `x = view.X; x[0, 0] = 1` does)
test_that("an extracted value does not affect the View", {
  parent <- view_parent()
  view <- view_of(parent)
  x <- view$X
  x[1, 1] <- -1
  expect_true(view$is_view)
  expect_equal(view$X[1, 1], 0)
})
