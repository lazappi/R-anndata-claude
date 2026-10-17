make_named <- function(names) {
  adata <- AnnData(matrix(0, nrow = length(names), ncol = length(names)))
  suppressWarnings(adata$obs_names <- names)
  suppressWarnings(adata$var_names <- names)
  adata
}

# Guards the committed expectations against drifting from what Python gives
test_that("the committed make_unique expectations match Python", {
  expect_generator_current("make_unique_cases.py")
})

# Python's make_index_unique results are the reference (committed JSON), so
# the R results for collisions, NA and custom joins must equal them
test_that("make_unique matches the Python expectations", {
  cases <- jsonlite::fromJSON(
    fixture_path("make_unique_cases.json"),
    simplifyVector = FALSE
  )
  for (label in names(cases)) {
    case <- cases[[label]]
    names_in <- vapply(
      case$names,
      function(x) if (is.null(x)) NA_character_ else x,
      character(1)
    )
    expected <- vapply(
      case$result,
      function(x) if (is.null(x)) NA_character_ else x,
      character(1)
    )
    for (attr in c("obs", "var")) {
      adata <- make_named(names_in)
      method <- paste0(attr, "_names_make_unique")
      if (length(case$warnings)) {
        cnd <- expect_warning(
          adata[[method]](case$join),
          class = "anndata_names_collision_warning",
          info = label
        )
        # Python lists the examples at the end of its message
        listing <- sub(".*: \\[", "[", case$warnings[[1]])
        listed <- regmatches(listing, gregexpr("'[^']*'", listing))[[1]]
        expect_identical(
          cnd$examples,
          gsub("'", "", listed, fixed = TRUE),
          info = label
        )
        expect_length(case$warnings, 1L)
      } else {
        expect_no_warning(adata[[method]](case$join), message = label)
      }
      expect_identical(adata[[paste0(attr, "_names")]], expected, info = label)
    }
  }
})

# Python warns with the colliding names, and R keeps them as condition fields
test_that("the collision warning names example collisions", {
  adata <- make_named(c("a", "a", "a-1"))
  cnd <- expect_warning(
    adata$obs_names_make_unique(),
    class = "anndata_names_collision_warning"
  )
  expect_identical(cnd$examples, "a-1")
  expect_identical(cnd$join, "-")
})

# The method is in place and the other axis is untouched
test_that("make_unique changes only its own axis", {
  adata <- make_named(c("a", "a"))
  adata$obs_names_make_unique()
  expect_identical(adata$obs_names, c("a", "a-1"))
  expect_identical(adata$var_names, c("a", "a"))
  expect_false(anyNA(adata$obs_names))
})

# Python goes through the names setter so obsm frames follow the rename
test_that("make_unique renames data frames in obsm and varm", {
  adata <- AnnData(matrix(0, 2, 2), obs = list(obs_names = c("a", "b")))
  adata$obsm[["df"]] <- data.frame(k = 1:2, row.names = c("a", "b"))
  suppressWarnings(adata$obs_names <- c("a", "a"))
  adata$obs_names_make_unique()
  expect_identical(rownames(adata$obsm[["df"]]), c("a", "a-1"))
})

# Python takes a string join, so anything else is rejected
test_that("join must be a single string", {
  adata <- make_named(c("a", "a"))
  expect_anndata_condition(
    adata$obs_names_make_unique(1),
    "anndata_invalid_argument_error"
  )
})
