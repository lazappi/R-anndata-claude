defaults <- list(
  remove_unused_categories = TRUE,
  check_uniqueness = TRUE,
  allow_write_nullable_strings = NULL,
  disallow_forward_slash_in_h5ad = TRUE,
  write_csr_csc_indices_with_min_possible_dtype = FALSE,
  restrict_index_types = TRUE,
  zarr_write_format = 3L,
  auto_shard_zarr_v3 = TRUE,
  min_rows_for_chunked_h5_copy = 1000L
)

# Defaults must match Python's anndata.settings
test_that("settings have the Python defaults", {
  withr::local_options(list(anndata.claude.check_uniqueness = NULL))
  anndata_settings$reset()
  for (name in names(defaults)) {
    expect_identical(anndata_settings[[name]], defaults[[name]], info = name)
  }
})

# Values are stored as options so options() and withr work
test_that("setting a value stores the option and reads it back", {
  withr::defer(anndata_settings$reset())
  anndata_settings$check_uniqueness <- FALSE
  expect_false(anndata_settings$check_uniqueness)
  expect_false(getOption("anndata.claude.check_uniqueness"))
  anndata_settings[["restrict_index_types"]] <- FALSE
  expect_false(anndata_settings$restrict_index_types)
})

test_that("options() and withr::local_options() change settings", {
  withr::defer(anndata_settings$reset())
  options(anndata.claude.remove_unused_categories = FALSE)
  expect_false(anndata_settings$remove_unused_categories)
  withr::with_options(list(anndata.claude.check_uniqueness = FALSE), {
    expect_false(anndata_settings$check_uniqueness)
  })
  expect_true(anndata_settings$check_uniqueness)
})

# NULL is a valid value only for the nullable setting
test_that("allow_write_nullable_strings accepts NULL, TRUE and FALSE", {
  withr::defer(anndata_settings$reset())
  anndata_settings$allow_write_nullable_strings <- FALSE
  expect_false(anndata_settings$allow_write_nullable_strings)
  anndata_settings$allow_write_nullable_strings <- TRUE
  expect_true(anndata_settings$allow_write_nullable_strings)
  anndata_settings$allow_write_nullable_strings <- NULL
  expect_null(anndata_settings$allow_write_nullable_strings)
})

# Invalid values must raise a classed error and leave the setting unchanged
test_that("invalid values raise anndata_invalid_setting_error", {
  withr::defer(anndata_settings$reset())
  expect_anndata_condition(
    anndata_settings$check_uniqueness <- "yes",
    "anndata_invalid_setting_error"
  )
  expect_anndata_condition(
    anndata_settings$check_uniqueness <- NA,
    "anndata_invalid_setting_error"
  )
  expect_anndata_condition(
    anndata_settings$check_uniqueness <- c(TRUE, FALSE),
    "anndata_invalid_setting_error"
  )
  expect_anndata_condition(
    anndata_settings$check_uniqueness <- NULL,
    "anndata_invalid_setting_error"
  )
  expect_anndata_condition(
    anndata_settings$allow_write_nullable_strings <- "yes",
    "anndata_invalid_setting_error"
  )
  expect_true(anndata_settings$check_uniqueness)
  expect_error(
    anndata_settings$check_uniqueness <- 1,
    class = "anndata_error"
  )
})

test_that("unknown setting names raise anndata_invalid_setting_error", {
  expect_anndata_condition(
    anndata_settings$not_a_setting <- TRUE,
    "anndata_invalid_setting_error"
  )
  expect_anndata_condition(
    anndata_settings[["not_a_setting"]] <- TRUE,
    "anndata_invalid_setting_error"
  )
  expect_anndata_condition(
    local_anndata_settings(list(not_a_setting = TRUE)),
    "anndata_invalid_setting_error"
  )
})

test_that("reset restores every default", {
  anndata_settings$check_uniqueness <- FALSE
  anndata_settings$allow_write_nullable_strings <- TRUE
  anndata_settings$write_csr_csc_indices_with_min_possible_dtype <- TRUE
  anndata_settings$reset()
  for (name in names(defaults)) {
    expect_identical(anndata_settings[[name]], defaults[[name]], info = name)
  }
})

test_that("with_anndata_settings overrides, restores and returns the value", {
  res <- with_anndata_settings(list(check_uniqueness = FALSE), {
    anndata_settings$check_uniqueness
  })
  expect_false(res)
  expect_true(anndata_settings$check_uniqueness)
})

# Restoring on error is the point of scoped overrides
test_that("with_anndata_settings restores after an error", {
  expect_error(
    with_anndata_settings(list(check_uniqueness = FALSE), stop("boom")),
    "boom"
  )
  expect_true(anndata_settings$check_uniqueness)
})

test_that("nested overrides restore in order", {
  with_anndata_settings(list(check_uniqueness = FALSE), {
    with_anndata_settings(
      list(check_uniqueness = TRUE, restrict_index_types = FALSE),
      {
        expect_true(anndata_settings$check_uniqueness)
        expect_false(anndata_settings$restrict_index_types)
      }
    )
    expect_false(anndata_settings$check_uniqueness)
    expect_true(anndata_settings$restrict_index_types)
  })
  expect_true(anndata_settings$check_uniqueness)
})

# An override must not leave a value behind when the option was unset before
test_that("overrides of the nullable setting restore NULL", {
  with_anndata_settings(list(allow_write_nullable_strings = FALSE), {
    expect_false(anndata_settings$allow_write_nullable_strings)
  })
  expect_null(anndata_settings$allow_write_nullable_strings)
  expect_null(getOption("anndata.claude.allow_write_nullable_strings"))
})

test_that("local_anndata_settings restores at the end of the function", {
  f <- function() {
    local_anndata_settings(list(check_uniqueness = FALSE))
    anndata_settings$check_uniqueness
  }
  expect_false(f())
  expect_true(anndata_settings$check_uniqueness)
})

# Validation happens before any option changes, so a bad entry leaves none set
test_that("a failed override changes no settings", {
  expect_error(
    local_anndata_settings(list(
      check_uniqueness = FALSE,
      restrict_index_types = 1
    )),
    class = "anndata_invalid_setting_error"
  )
  expect_true(anndata_settings$check_uniqueness)
})

test_that("local_anndata_settings requires a named list", {
  expect_anndata_condition(
    local_anndata_settings(list(TRUE)),
    "anndata_invalid_setting_error"
  )
  expect_anndata_condition(
    local_anndata_settings(TRUE),
    "anndata_invalid_setting_error"
  )
})

# The print layout is user facing so it is snapshotted
test_that("printing lists settings, values and descriptions", {
  anndata_settings$reset()
  expect_snapshot(print(anndata_settings))
  with_anndata_settings(
    list(check_uniqueness = FALSE, allow_write_nullable_strings = TRUE),
    expect_snapshot(print(anndata_settings))
  )
})
