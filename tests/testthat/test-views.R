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
    c(
      "write",
      "write_h5ad",
      "write_zarr",
      "write_csvs",
      "write_loom",
      "chunked_X"
    ),
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

# Everything about the parent a modification must leave alone
parent_state <- function(parent) {
  list(
    X = parent$X,
    obs = parent$obs,
    var = parent$var,
    uns = parent$uns,
    layers = as.list(parent$layers),
    obsm = as.list(parent$obsm),
    varm = as.list(parent$varm),
    obsp = as.list(parent$obsp),
    varp = as.list(parent$varp),
    raw_X = parent$raw$X,
    raw_var = parent$raw$var,
    obs_names = parent$obs_names,
    var_names = parent$var_names
  )
}

implicit_class <- "anndata_implicit_modification_warning"

# Runs `change(view)` on a fresh View. With `message` it must give Python's
# warning, with `NULL` it must not warn. Then the View must be an independent
# object and the parent unchanged, as in the `is_view_after` and
# `parent_changed` columns of the table. Returns the changed View.
expect_copy_on_write <- function(change, message = NULL, parent = NULL) {
  parent <- parent %||% view_parent()
  view <- view_of(parent)
  expect_true(view$is_view)
  if (is.null(message)) {
    expect_no_warning(change(view))
  } else {
    cnd <- expect_warning(change(view), class = implicit_class)
    expect_match(conditionMessage(cnd), message, fixed = TRUE)
  }
  expect_false(view$is_view)
  expect_equal(parent_state(parent), parent_state(view_parent()))
  invisible(view)
}

set_msg <- function(what) {
  paste0("Setting element `", what, "` of view, initializing view as actual.")
}
modify_msg <- function(what) {
  paste0(
    "Trying to modify attribute `",
    what,
    "` of view, initializing view as actual."
  )
}

# Why: the X rows of the table (X_assign, X_assign_none, X_del, X_item), each
# of which warns and detaches the View with the parent unchanged
test_that("assigning X through a View copies on write", {
  ops <- view_cases()$operations
  expect_equal(ops$X_assign$warnings[[1]]$message, set_msg(".X"))
  view <- expect_copy_on_write(
    function(v) v$X <- matrix(7, 2, 2),
    ops$X_assign$warnings[[1]]$message
  )
  expect_equal(view$X, matrix(7, 2, 2))
  view <- expect_copy_on_write(function(v) v$X <- NULL, set_msg(".X"))
  expect_null(view$X)
  # Python warns "Trying to modify attribute `.X`" for `view.X[0, 0] = -1`, but
  # in R an item assignment is an assignment of X (documented deviation)
  view <- expect_copy_on_write(function(v) v$X[1, 1] <- -1, set_msg(".X"))
  expect_equal(view$X[1, 1], -1)
  expect_equal(view$X[2, 2], 8)
})

# Why: X_assign_wrong_shape and the View of a View rows, where Python raises
# before changing anything, so the View must stay a View
test_that("a failed assignment leaves a View a View", {
  parent <- view_parent()
  view <- view_of(parent)
  expect_error(suppressWarnings(view$X <- matrix(0, 3, 3)))
  expect_error(view$obsm[["new"]] <- matrix(0, 3, 2))
  expect_error(view$obs_names <- c("p", "q", "r"))
  expect_error(view$obs <- data.frame(z = 1:3))
  expect_error(view$rename_categories("cat", "A"))
  expect_true(view$is_view)
  # A View of a View has one row, so every two-row value is the wrong shape
  small <- view[1, ]
  expect_error(suppressWarnings(small$X <- matrix(7, 2, 2)))
  expect_error(small$obs_names <- c("p", "q"))
  expect_error(small$obsm[["new"]] <- matrix(1, 2, 2))
  expect_error(small$obsp[["new"]] <- matrix(1, 2, 2))
  expect_error(small$obs$new <- c(1, 2))
  expect_true(small$is_view)
})

# Why: layers_set, layers_item, layers_del and layers_assign rows
test_that("changing layers through a View copies on write", {
  ops <- view_cases()$operations
  view <- expect_copy_on_write(
    function(v) v$layers[["new"]] <- matrix(1, 2, 2),
    ops$layers_set$warnings[[1]]$message
  )
  expect_equal(view$layers[["new"]], matrix(1, 2, 2))
  # Python's message for an item assignment says "modify attribute", R sees an
  # assignment of the key (documented deviation)
  view <- expect_copy_on_write(
    function(v) v$layers[["counts"]][1, 1] <- -1,
    set_msg(".layers['counts']")
  )
  expect_equal(view$layers[["counts"]][1, 1], -1)
  view <- expect_copy_on_write(
    function(v) v$layers[["counts"]] <- NULL,
    ops$layers_del$warnings[[1]]$message
  )
  expect_null(view$layers[["counts"]])
  expect_equal(view$layers[["sparse"]][1, 1], 1)
  # Assigning the whole mapping warns about X only, not about the View
  parent <- view_parent()
  view <- view_of(parent)
  expect_warning(
    view$layers <- list(only = matrix(1, 2, 2)),
    class = "anndata_future_warning"
  )
  expect_false(view$is_view)
  expect_equal(view$layers$keys(), c("only", NA))
  expect_equal(parent_state(parent), parent_state(view_parent()))
})

# Why: the obs and var rows. Python is silent for assigning the whole frame and
# for deleting a column, which R cannot tell from a nested assignment, so R
# always warns as Python does for a column (documented deviation)
test_that("changing obs and var through a View copies on write", {
  ops <- view_cases()$operations
  expect_equal(ops$obs_col_set$warnings[[1]]$message, modify_msg(".obs"))
  view <- expect_copy_on_write(
    function(v) v$obs$new <- c(1, 2),
    modify_msg(".obs")
  )
  expect_equal(view$obs$new, c(1, 2))
  view <- expect_copy_on_write(
    function(v) v$obs$num[1] <- -1,
    modify_msg(".obs")
  )
  expect_equal(view$obs$num, c(-1, 3))
  view <- expect_copy_on_write(
    function(v) v$obs$num <- NULL,
    modify_msg(".obs")
  )
  expect_false("num" %in% colnames(view$obs))
  view <- expect_copy_on_write(
    function(v) {
      v$obs <- data.frame(z = c(1, 2), row.names = v$obs_names)
    },
    modify_msg(".obs")
  )
  expect_equal(colnames(view$obs), "z")

  expect_equal(ops$var_col_set$warnings[[1]]$message, modify_msg(".var"))
  view <- expect_copy_on_write(
    function(v) v$var$new <- c(1, 2),
    modify_msg(".var")
  )
  expect_equal(view$var$new, c(1, 2))
  view <- expect_copy_on_write(
    function(v) v$var$gene <- NULL,
    modify_msg(".var")
  )
  expect_equal(ncol(view$var), 0L)
  view <- expect_copy_on_write(
    function(v) {
      v$var <- data.frame(z = c(1, 2), row.names = v$var_names)
    },
    modify_msg(".var")
  )
  expect_equal(colnames(view$var), "z")
})

# Why: the aligned mapping rows (obsm_*, varm_*, obsp_*, varp_*) for setting,
# item modification, deleting and assigning the mapping
test_that("changing aligned mappings through a View copies on write", {
  ops <- view_cases()$operations
  for (attr in c("obsm", "varm", "obsp", "varp")) {
    row <- ops[[paste0(attr, "_set")]]
    expect_equal(
      row$warnings[[1]]$message,
      set_msg(paste0(".", attr, "['new']"))
    )
    view <- expect_copy_on_write(
      function(v) v[[attr]][["new"]] <- matrix(1, 2, 2),
      row$warnings[[1]]$message
    )
    expect_equal(view[[attr]][["new"]], matrix(1, 2, 2))
  }
  # Deleting a key
  key <- c(obsm = "pca", varm = "pcs", obsp = "conn", varp = "corr")
  for (attr in names(key)) {
    row <- ops[[paste0(attr, "_del")]]
    view <- expect_copy_on_write(
      function(v) v[[attr]][[key[[attr]]]] <- NULL,
      row$warnings[[1]]$message
    )
    expect_null(view[[attr]][[key[[attr]]]])
  }
  # Item assignment (the message says "modify attribute" in Python)
  view <- expect_copy_on_write(
    function(v) v$obsm[["pca"]][1, 1] <- -1,
    set_msg(".obsm['pca']")
  )
  expect_equal(view$obsm[["pca"]][1, 1], -1)
  # Python assigns a whole mapping silently
  view <- expect_copy_on_write(
    function(v) v$obsm <- list(only = matrix(1, 2, 2))
  )
  expect_equal(view$obsm$keys(), "only")
  # Other Slots of the View are loaded from the parent before it detaches
  expect_equal(view$varm[["pcs"]], table_matrix(view_cases()$view$varm$pcs))
})

# Why: the uns rows. Python's `uns_assign` and `uns_del` do not warn, and
# `uns_nested` changes the parent, which R values cannot do (documented
# deviation), so R warns for any change of uns and never shares it
test_that("changing uns through a View copies on write", {
  ops <- view_cases()$operations
  expect_equal(ops$uns_set$warnings[[1]]$message, modify_msg("._uns"))
  view <- expect_copy_on_write(
    function(v) v$uns[["new"]] <- 5,
    modify_msg("._uns")
  )
  expect_equal(view$uns$new, 5)
  view <- expect_copy_on_write(
    function(v) v$uns[["u"]] <- 2,
    modify_msg("._uns")
  )
  expect_equal(view$uns$u, 2)
  view <- expect_copy_on_write(
    function(v) v$uns$nested$k <- 9,
    modify_msg("._uns")
  )
  expect_equal(view$uns$nested$k, 9)
  view <- expect_copy_on_write(
    function(v) v$uns[["u"]] <- NULL,
    modify_msg("._uns")
  )
  expect_null(view$uns$u)
  view <- expect_copy_on_write(
    function(v) v$uns <- list(only = 1),
    modify_msg("._uns")
  )
  expect_equal(view$uns, list(only = 1))
})

# Why: raw and names rows, which Python changes silently and detaches
test_that("changing raw and names through a View copies silently", {
  view <- expect_copy_on_write(function(v) v$raw <- v)
  expect_equal(view$raw$X, view$X)
  view <- expect_copy_on_write(function(v) v$raw <- NULL)
  expect_null(view$raw)
  view <- expect_copy_on_write(function(v) v$obs_names <- c("p", "q"))
  expect_equal(view$obs_names, c("p", "q"))
  expect_equal(rownames(view$obsm[["pca"]]), NULL)
  view <- expect_copy_on_write(function(v) v$var_names <- c("p", "q"))
  expect_equal(view$var_names, c("p", "q"))
  view <- expect_copy_on_write(function(v) {
    v$obs_names <- c("p", "p")
    v$obs_names_make_unique()
  })
  expect_equal(view$obs_names, c("p", "p-1"))
  view <- expect_copy_on_write(function(v) {
    v$var_names <- c("p", "p")
    v$var_names_make_unique()
  })
  expect_equal(view$var_names, c("p", "p-1"))
})

# Why: the raw rows of Python (no warning, stays a View, parent's raw
# unchanged), because the View's Raw is its own object
test_that("modifying the Raw of a View leaves the View and the parent alone", {
  parent <- view_parent()
  view <- view_of(parent)
  expect_no_warning({
    view$raw$X[1, 1] <- -1
    view$raw$var$c <- c(1, 2, 3)
    view$raw$varm[["k"]] <- matrix(1, 3, 2)
  })
  expect_true(view$is_view)
  expect_equal(view$raw$X[1, 1], -1)
  expect_equal(colnames(view$raw$var), c("gene", "c"))
  expect_equal(parent_state(parent), parent_state(view_parent()))
})

# Why: strings_to_categoricals and rename_categories rows. Python only detaches
# when something changes
test_that("methods that change a View copy on write", {
  parent <- view_parent()
  parent$obs$s <- c("x", "y", "x", "x")
  fresh <- view_parent()
  fresh$obs$s <- c("x", "y", "x", "x")
  view <- view_of(parent)
  expect_warning(
    view$strings_to_categoricals(),
    modify_msg(".obs"),
    fixed = TRUE,
    class = implicit_class
  )
  expect_false(view$is_view)
  expect_s3_class(view$obs$s, "factor")
  expect_type(parent$obs$s, "character")
  expect_equal(parent_state(parent), parent_state(fresh))

  # Nothing to convert, so nothing warns and the View stays a View
  plain <- view_of(view_parent())
  expect_no_warning(plain$strings_to_categoricals())
  expect_true(plain$is_view)

  view <- expect_copy_on_write(
    function(v) v$rename_categories("cat", c("A", "C")),
    modify_msg(".obs")
  )
  expect_equal(levels(view$obs$cat), c("A", "C"))
})

# Why: the parent must stay independent of a detached View in both directions
test_that("a detached View no longer follows its parent", {
  parent <- view_parent()
  view <- view_of(parent)
  suppressWarnings(view$obs$num <- c(5, 6))
  parent$X <- matrix(0, 4, 3)
  parent$obsm[["pca"]] <- matrix(0, 4, 2)
  expect_equal(view$X, matrix(c(0, 2, 6, 8), 2, byrow = TRUE))
  expect_equal(view$obsm[["pca"]], matrix(c(0, 1, 4, 5), 2, byrow = TRUE))
  view$X[1, 1] <- 100
  expect_equal(parent$X[1, 1], 0)
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

# Why: the transpose and T rows, Python refuses to transpose a View (also a View
# of a View) and leaves it a View, while a copy can be transposed
test_that("transposing a View raises Python's error", {
  ops <- view_cases()$operations
  expect_equal(ops$transpose$error$type, "ValueError")
  expect_equal(ops$T$error$type, "ValueError")
  view <- view_of(view_parent())
  expect_error(view$transpose(), class = "anndata_view_transpose_error")
  expect_error(t(view), class = "anndata_view_transpose_error")
  expect_error(view[1, ]$transpose(), class = "anndata_view_transpose_error")
  expect_true(view$is_view)
  expect_equal(view$copy()$transpose()$shape, c(2L, 2L))
})

# Why: the write_h5ad and write_zarr rows, a View is written as its subset and
# the file reads back with the values Python records for the same View
test_that("writing a View writes the subset", {
  ops <- view_cases()$operations
  view <- view_of(view_parent())
  for (format in c("h5ad", "zarr")) {
    path <- withr::local_tempfile(fileext = paste0(".", format))
    if (format == "h5ad") {
      view$write_h5ad(path)
      back <- read_h5ad(path)
    } else {
      view$write_zarr(path)
      back <- read_zarr(path)
    }
    expected <- ops[[paste0("write_", format)]]$result$written
    expect_false(back$is_view)
    expect_equal(back$obs_names, unlist(expected$obs_names))
    expect_equal(back$var_names, unlist(expected$var_names))
    expect_equal(back$X, table_matrix(expected$X))
    expect_equal(
      back$layers[["counts"]],
      table_matrix(expected$layers$counts)
    )
    expect_equal(back$obsm[["pca"]], table_matrix(expected$obsm$pca))
    expect_equal(
      levels(back$obs$cat),
      unique(unlist(expected$obs$columns$cat$values))
    )
    expect_equal(back$raw$X, table_matrix(expected$raw$X))
  }
  expect_true(view$is_view)
})

# Why: the `write` row, Python's `write` is an alias of `write_h5ad`, so a View
# written through it reads back as the subset the table records
test_that("write() on a View is an alias of write_h5ad()", {
  expected <- view_cases()$operations$write$result$written
  view <- view_of(view_parent())
  path <- withr::local_tempfile(fileext = ".h5ad")
  view$write(path)
  back <- read_h5ad(path)
  expect_false(back$is_view)
  expect_equal(back$obs_names, unlist(expected$obs_names))
  expect_equal(back$X, table_matrix(expected$X))
  expect_true(view$is_view)
})

# Why: the Structural equivalence criterion, a View written by R has the same
# nodes, dtypes and attributes as Python writing the same View of the same
# parent (one Python process per step, see CLAUDE.md)
test_that("a written View is Structurally equivalent to Python's", {
  parent <- view_parent()
  view <- view_of(parent)
  dir <- withr::local_tempdir()
  formats <- c("h5ad", "zarr")
  parents <- file.path(dir, paste0("parent.", formats))
  mine <- file.path(dir, paste0("mine.", formats))
  theirs <- file.path(dir, paste0("theirs.", formats))
  parent$write_h5ad(parents[[1]])
  parent$write_zarr(parents[[2]])
  view$write_h5ad(mine[[1]])
  view$write_zarr(mine[[2]])
  run_python(
    "rewrite_view.py",
    c("0,2", "0,2", as.vector(rbind(parents, theirs)))
  )
  expect_all_equivalent(mine, theirs)
  expect_python_equal(mine, theirs)
})

# Why: rows of the operations table for methods R does not have yet are
# deferred (human decision, views/04). Each names the sub-project that owns
# it, which must pass the row when it adds the method. The test keeps the rows
# in the table and fails once a method appears, as a reminder to test its row
# and update this list
test_that("table rows for methods owned by later sub-projects are deferred", {
  deferred <- list(
    to_memory = "backed",
    chunked_X = "backed",
    chunk_X = "backed",
    write_csvs = "other-formats",
    write_loom = "other-formats"
  )
  ops <- view_cases()$operations
  view <- view_of(view_parent())
  for (name in names(deferred)) {
    expect_true(name %in% names(ops), info = name)
    expect_false(is.function(.subset2(view, name)), info = name)
  }
})
