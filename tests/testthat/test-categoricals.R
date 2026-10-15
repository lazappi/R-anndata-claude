cases <- function() {
  jsonlite::fromJSON(
    fixture_path("categorical_cases.json"),
    simplifyVector = FALSE
  )
}

null_to_na <- function(x) {
  vapply(x, function(v) if (is.null(v)) NA_character_ else as.character(v), "")
}

# Guards the committed expectations against drifting from what Python gives
test_that("the committed categorical expectations match Python", {
  skip_if_no_python()
  fresh <- withr::local_tempfile(fileext = ".json")
  run_python("categorical_cases.py", fresh)
  expect_equal(
    readLines(fresh),
    readLines(fixture_path("categorical_cases.json"))
  )
})

# Python's conversion rules (string columns, fewer unique values than rows,
# natural level order, NA kept) and info messages are the reference
test_that("strings_to_categoricals matches the Python expectations", {
  for (label in names(cases()$convert)) {
    case <- cases()$convert[[label]]
    n <- length(case$values)
    values <- lapply(case$values, function(v) if (is.null(v)) NA else v)
    obs <- data.frame(row.names = paste0("o", seq_len(n)))
    obs$col <- unlist(values)
    if (label == "mixed") {
      # R columns are typed, so a mix of strings and numbers can't exist
      next
    }
    adata <- AnnData(matrix(0, n, 1), obs = obs)
    messages <- character()
    withCallingHandlers(
      adata$strings_to_categoricals(),
      anndata_info_message = function(cnd) {
        messages <<- c(messages, conditionMessage(cnd))
      }
    )
    if (is.null(case$result)) {
      expect_false(is.factor(adata$obs$col), label = label)
      expect_equal(messages, character(), label = label)
    } else {
      expect_s3_class(adata$obs$col, "factor")
      expect_false(is.ordered(adata$obs$col))
      expect_equal(levels(adata$obs$col), unlist(case$result$categories))
      expect_equal(
        as.character(adata$obs$col),
        null_to_na(case$result$values)
      )
      expect_equal(unlist(case$messages), messages, label = label)
    }
  }
})

# Python skips a single-row frame because categories can't be fewer than rows
test_that("strings_to_categoricals skips a single row", {
  adata <- AnnData(
    matrix(0, 1, 1),
    obs = data.frame(col = "a", row.names = "o")
  )
  adata$strings_to_categoricals()
  expect_false(is.factor(adata$obs$col))
})

# Python's default processes both obs and var, and returns None
test_that("strings_to_categoricals converts obs and var in place", {
  adata <- AnnData(
    matrix(0, 4, 4),
    obs = data.frame(g = c("a", "b", "a", "b"), row.names = paste0("o", 1:4)),
    var = data.frame(h = c("p", "p", "q", "q"), row.names = paste0("v", 1:4))
  )
  expect_identical(adata$strings_to_categoricals(), adata)
  expect_s3_class(adata$obs$g, "factor")
  expect_s3_class(adata$var$h, "factor")
})

# Python can convert a frame that is passed in and leaves obs and var alone
test_that("strings_to_categoricals converts only a given data frame", {
  adata <- AnnData(
    matrix(0, 4, 1),
    obs = data.frame(g = c("a", "b", "a", "b"), row.names = paste0("o", 1:4))
  )
  df <- adata$strings_to_categoricals(data.frame(z = c("a", "a", "b")))
  expect_s3_class(df$z, "factor")
  expect_false(is.factor(adata$obs$g))
  expect_anndata_condition(
    adata$strings_to_categoricals(1),
    "anndata_invalid_argument_error"
  )
})

# Python renames by position, tries obs before var and returns None
test_that("rename_categories matches the Python expectations", {
  for (label in c("obs", "var", "both_prefers_obs", "swap_names")) {
    case <- cases()$rename[[label]]
    adata <- AnnData(
      matrix(0, 6, 3),
      obs = data.frame(
        s = factor(c("a", "b", "c", "a", "b", "c")),
        both = factor(c("u", "v", "u", "v", "u", "v")),
        row.names = paste0("o", 1:6)
      ),
      var = data.frame(
        g = factor(c("p", "q", "p")),
        both = factor(c("k", "l", "k")),
        row.names = c("x", "y", "z")
      )
    )
    key <- c(
      obs = "s",
      var = "g",
      both_prefers_obs = "both",
      swap_names = "s"
    )[[label]]
    new <- switch(
      label,
      obs = c("W", "X", "Y"),
      var = c("P", "Q"),
      both_prefers_obs = c("A", "B"),
      swap_names = c("c", "a", "b")
    )
    expect_identical(adata$rename_categories(key, new), adata)
    for (col in c("s", "both")) {
      expect_equal(
        levels(adata$obs[[col]]),
        unlist(case$obs[[col]]$categories),
        label = paste(label, "obs", col)
      )
      expect_equal(
        as.character(adata$obs[[col]]),
        null_to_na(case$obs[[col]]$values),
        label = paste(label, "obs", col)
      )
    }
    for (col in c("g", "both")) {
      expect_equal(
        levels(adata$var[[col]]),
        unlist(case$var[[col]]$categories),
        label = paste(label, "var", col)
      )
    }
  }
})

# Python raises ValueError for a missing key, a mapping, wrong length and
# duplicates, and AttributeError for a column that is not categorical
test_that("rename_categories errors by class", {
  adata <- AnnData(
    matrix(0, 3, 1),
    obs = data.frame(
      s = factor(c("a", "b", "c")),
      plain = c("a", "b", "c"),
      row.names = paste0("o", 1:3)
    )
  )
  expect_anndata_condition(
    adata$rename_categories("nope", "a"),
    "anndata_key_error"
  )
  expect_anndata_condition(
    adata$rename_categories("plain", c("a", "b", "c")),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    adata$rename_categories("s", c("a", "b")),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    adata$rename_categories("s", c("a", "b", "c", "d")),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    adata$rename_categories("s", c("a", "a", "b")),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    adata$rename_categories("s", list(a = "A")),
    "anndata_invalid_argument_error"
  )
  expect_equal(levels(adata$obs$s), c("a", "b", "c"))
})

# Python's natsort puts digit runs in numeric order and uppercase first
test_that("natural_order sorts like natsort", {
  x <- c("c10", "c2", "c1", "10a", "2a", "a", "B", "A", "b", "a1", "a1b")
  expect_equal(
    x[natural_order(x)],
    c("2a", "10a", "A", "B", "a", "a1", "a1b", "b", "c1", "c2", "c10")
  )
})
