# Every successful row of the table, checking the aligned mappings, pairwise
# mappings and raw that Python gave (obsm, varm, obsp, varp, raw), because they
# depend on `join`, `axis`, `merge` and `pairwise` together
test_that("concat gives the aligned mappings and raw of every table row", {
  table <- concat_table()
  cases <- Filter(function(case) is.null(case$error), table$cases)
  expect_gt(length(cases), 120L)
  for (case in cases) {
    out <- run_concat_case(case, table)$result
    expected <- case$result
    for (slot in c("obsm", "varm", "obsp", "varp")) {
      expect_matches_table_mapping(
        out[[slot]],
        expected[[slot]],
        paste(case$name, slot)
      )
    }
    if (is.null(expected$raw)) {
      expect_null(out$raw, info = case$name)
    } else {
      expect_false(is.null(out$raw), info = case$name)
      expect_matches_table_array(
        out$raw$X,
        expected$raw$X,
        paste(case$name, "raw X")
      )
      expect_matches_table_frame(
        out$raw$var,
        expected$raw$var,
        paste(case$name, "raw var")
      )
      expect_matches_table_mapping(
        out$raw$varm,
        expected$raw$varm,
        paste(case$name, "raw varm")
      )
    }
  }
})

# Python warns, and leaves raw out, when only some objects have a raw
test_that("concat warns when only some objects have raw", {
  table <- concat_table()
  for (case in concat_cases_with_args(table, names(formals(concat)))) {
    expected <- any(vapply(
      case$warnings,
      function(w) grepl("Only some AnnData objects have", w$message),
      logical(1)
    ))
    classes <- run_concat_case(case, table)$classes
    expect_identical(
      "anndata_missing_raw_warning" %in% classes,
      expected,
      info = case$name
    )
  }
})

mapping_adata <- function(obs, obsm = NULL, obsp = NULL) {
  AnnData(
    matrix(0, length(obs), 2L),
    obs = S4Vectors::DataFrame(row.names = obs),
    var = S4Vectors::DataFrame(row.names = c("x", "y")),
    obsm = obsm,
    obsp = obsp
  )
}

# An inner join truncates arrays of different widths to the narrowest, and an
# outer join pads them with the fill (Python's range-index reindexers)
test_that("concat aligns aligned mapping arrays of different widths", {
  a <- mapping_adata(c("a", "b"), list(e = matrix(1:4 + 0, 2L, 2L)))
  b <- mapping_adata(c("c"), list(e = matrix(c(5, 6, 7), 1L, 3L)))
  inner <- concat(list(a, b), join = "inner")
  expect_equal(
    unname(inner$obsm[["e"]]),
    rbind(c(1, 3), c(2, 4), c(5, 6))
  )
  outer <- concat(list(a, b), join = "outer")
  expect_equal(
    unname(outer$obsm[["e"]]),
    rbind(c(1, 3, NA), c(2, 4, NA), c(5, 6, 7))
  )
})

# Python fills an element a mapping lacks on an outer join, and drops the key
# on an inner join
test_that("concat fills or drops obsm keys that only some objects have", {
  a <- mapping_adata(c("a", "b"), list(e = matrix(1, 2L, 2L)))
  b <- mapping_adata(c("c"))
  expect_length(as.list(concat(list(a, b), join = "inner")$obsm), 0L)
  out <- concat(list(a, b), join = "outer", fill_value = -1)
  expect_equal(
    unname(out$obsm[["e"]]),
    rbind(c(1, 1), c(1, 1), c(-1, -1))
  )
})

# Data frames in a mapping are concatenated like annotation frames, on their
# columns, and cannot be mixed with arrays
test_that("concat combines data frame elements of obsm", {
  frame <- function(obs, ...) {
    S4Vectors::DataFrame(..., row.names = obs)
  }
  a <- mapping_adata(
    c("a", "b"),
    list(f = frame(c("a", "b"), p = c(1, 2), q = c("u", "v")))
  )
  b <- mapping_adata(
    "c",
    list(f = frame("c", p = 3, r = "w"))
  )
  inner <- concat(list(a, b))$obsm[["f"]]
  expect_identical(colnames(inner), "p")
  expect_identical(rownames(inner), c("a", "b", "c"))
  outer <- concat(list(a, b), join = "outer")$obsm[["f"]]
  expect_identical(colnames(outer), c("p", "q", "r"))
  expect_identical(outer$q, c("u", "v", NA))
  mixed <- mapping_adata("c", list(f = matrix(1, 1L, 2L)))
  expect_anndata_condition(
    concat(list(a, mixed)),
    "anndata_unsupported_value_error"
  )
})

# Pairwise mappings form a block diagonal, and an object without the key adds
# an empty block on an outer join
test_that("concat builds block diagonal pairwise mappings", {
  a <- mapping_adata(
    c("a", "b"),
    obsp = list(g = matrix(c(1, 2, 3, 4), 2L, 2L))
  )
  b <- mapping_adata("c")
  out <- concat(list(a, b), join = "outer", pairwise = TRUE)
  expect_true(is_csr(out$obsp[["g"]]))
  expect_equal(
    unname(as.matrix(out$obsp[["g"]])),
    rbind(c(1, 3, 0), c(2, 4, 0), c(0, 0, 0))
  )
  expect_length(
    as.list(concat(list(a, b), join = "inner", pairwise = TRUE)$obsp),
    0L
  )
  expect_length(as.list(concat(list(a, b), join = "outer")$obsp), 0L)
})

# `merge` selects the varm entries of the other axis after reindexing their
# rows, and rows of new variables are NaN
test_that("concat merges varm with the merge strategy", {
  varm_adata <- function(var, value) {
    AnnData(
      matrix(0, 1L, length(var)),
      obs = S4Vectors::DataFrame(row.names = value),
      var = S4Vectors::DataFrame(row.names = var),
      varm = list(load = matrix(seq_along(var) + 0, length(var), 1L))
    )
  }
  a <- varm_adata(c("x", "y"), "a")
  b <- varm_adata(c("y", "z"), "b")
  expect_length(as.list(concat(list(a, b), join = "outer")$varm), 0L)
  first <- concat(list(a, b), join = "outer", merge = "first")
  expect_equal(unname(first$varm[["load"]]), cbind(c(1, 2, NA)))
  only <- concat(list(a, b), join = "outer", merge = "only")
  expect_length(as.list(only$varm), 0L)
})
