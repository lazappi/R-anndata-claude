plain_raw_x <- function(x) unname(as.matrix(drop_dtype(as.matrix(x))))

# Python's Raw.X has no setter, so replacing a backed raw X fails and the
# object stays backed (rows raw_X_assign in raw_operations)
test_that("a backed raw X cannot be replaced", {
  for_each_backed(
    "raw_X_assign",
    function(case, row, kind) {
      expect_anndata_condition(
        case$adata$raw$X <- matrix(0, 4, 3),
        class = "anndata_not_supported_error"
      )
      expect_backed_state(case$adata, row$state_after)
      expect_true(inherits(case$adata$raw$X, "backed_x"))
    },
    raw = TRUE,
    table = "raw_operations"
  )
})

# Without a raw, `raw$X <- v` fails too (row raw_X_assign in operations)
test_that("assigning raw X without a raw fails", {
  for_each_backed("raw_X_assign", function(case, row, kind) {
    expect_anndata_condition(
      case$adata$raw$X <- matrix(0, 4, 3),
      class = "anndata_invalid_argument_error"
    )
    expect_backed_state(case$adata, row$state_after)
  })
})

# Python's Raw refuses an X when the parent is backed, with or without a raw
# (rows raw_assign)
test_that("assigning a backed object as its raw fails", {
  for (raw in c(FALSE, TRUE)) {
    for_each_backed(
      "raw_assign",
      function(case, row, kind) {
        expect_anndata_condition(
          case$adata$raw <- case$adata,
          class = "anndata_invalid_argument_error"
        )
        expect_backed_state(case$adata, row$state_after)
      },
      raw = raw,
      table = if (raw) "raw_operations" else "operations"
    )
  }
})

# Nested assignment hands the same placeholder back and must not fail
test_that("nested assignment into a backed raw keeps it backed", {
  case <- local_backed("dense", "r", raw = TRUE)
  expect_no_error(case$adata$raw$var$s <- 3:1)
  expect_true(inherits(case$adata$raw$X, "backed_x"))
})

# `raw$X[i, j] <- v` assigns the placeholder back to the setter, which must
# accept it, whatever the outcome of the item assignment itself
test_that("item assignment into a backed raw X does not hit the setter error", {
  for (kind in backed_kinds) {
    for (mode in backed_modes) {
      case <- local_backed(kind, mode, raw = TRUE)
      result <- tryCatch(
        {
          case$adata$raw$X[1, 1] <- 5
          NULL
        },
        error = function(e) e
      )
      expect_false(
        inherits(result, "anndata_not_supported_error") &&
          grepl("cannot be replaced", conditionMessage(result))
      )
      expect_true(inherits(case$adata$raw$X, "backed_x"))
    }
  }
})

# Python loses raw X when filename is set to NULL (None afterwards), R reads it
# into memory instead (row filename_none in raw_operations)
test_that("setting filename to NULL loads a backed raw X", {
  for_each_backed(
    "filename_none",
    function(case, row, kind) {
      expected <- plain_raw_x(case$adata$raw$X)
      case$adata$filename <- NULL
      expect_backed_state(case$adata, row$result$state)
      expect_false(inherits(case$adata$raw$X, "backed_x"))
      expect_equal(plain_raw_x(case$adata$raw$X), expected)
    },
    raw = TRUE,
    table = "raw_operations"
  )
})

# Editing obs then writing without a filename updates the file in place (row
# write_obs_edit)
test_that("an obs edit is written to the backing file", {
  for_each_backed("write_obs_edit", function(case, row, kind) {
    case$adata$obs$n <- c(1, 2, 3, 4)
    case$adata$write()
    expect_backed_state(case$adata, row$state_after)
    expect_equal(read_h5ad(case$path)$obs$n, c(1, 2, 3, 4))
    written <- row$result$written
    expect_equal(
      unname(plain_raw_x(read_h5ad(case$path)$X)),
      table_matrix(written$X$value)
    )
    expect_equal(rownames(read_h5ad(case$path)$obs), unlist(written$obs_names))
  })
})
