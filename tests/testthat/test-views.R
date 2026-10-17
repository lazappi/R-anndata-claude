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
