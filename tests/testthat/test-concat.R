# The cases for this ticket use only these arguments (annotations and the
# other arguments come with later tickets)
array_case_args <- c("axis", "join", "fill_value")

# Every row of the table about X, layers and names: the sparse format, On-disk
# dtype, fill and reindexing of the arrays must be what Python gives
test_that("concat gives the arrays of every table row", {
  table <- concat_table()
  cases <- concat_cases_with_args(table, array_case_args)
  expect_gt(length(cases), 80L)
  for (case in cases) {
    out <- run_concat_case(case, table)$result
    expected <- case$result
    info <- case$name
    expect_identical(
      out$obs_names,
      as.character(unlist(expected$obs_names)),
      info = info
    )
    expect_identical(
      out$var_names,
      as.character(unlist(expected$var_names)),
      info = info
    )
    expect_identical(out$shape, unlist(expected$shape), info = info)
    expected_layers <- expected$layers[names(expected$layers) != "None"]
    expect_setequal(
      names(out$layers)[!is.na(names(out$layers))],
      names(expected_layers)
    )
    for (key in names(expected_layers)) {
      expect_matches_table_array(
        out$layers[[key]],
        expected_layers[[key]],
        paste(case$name, key)
      )
    }
    if (is.null(expected$X)) {
      expect_null(out$X, info = info)
    } else {
      expect_matches_table_array(out$X, expected$X, paste(case$name, "X"))
    }
  }
})

# Python warns about dropped Xs only when `join` is left at its default
test_that("concat warns when only some objects have X and join is implicit", {
  table <- concat_table()
  cases <- concat_cases_with_args(table, array_case_args)
  for (case in cases) {
    expected <- any(vapply(
      case$warnings,
      function(w) grepl("Some Xs are None", w$message),
      logical(1)
    ))
    classes <- run_concat_case(case, table)$classes
    expect_identical(
      "anndata_missing_x_warning" %in% classes,
      expected,
      info = case$name
    )
  }
})

# Python's argument errors, which R raises as its own classes
test_that("concat rejects bad arguments", {
  a <- AnnData(matrix(1, 2, 2))
  expect_anndata_condition(
    concat(list(a, a), axis = "rows"),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    concat(list(a, a), join = "left"),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    concat(list(), join = "inner"),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    concat(list(a, "not an AnnData"), join = "inner"),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    concat(list(a, a), fill_value = "x"),
    "anndata_invalid_argument_error"
  )
})

# Python treats a NaN fill as non-zero, so sparse inputs get explicit NaN
# entries (a review found R crashing on the comparison with zero)
test_that("concat fills with NA, also for sparse inputs", {
  a <- AnnData(
    Matrix::sparseMatrix(1:2, 1:2, x = c(1, 2), dims = c(2, 2), repr = "R"),
    obs = S4Vectors::DataFrame(row.names = c("a", "b")),
    var = S4Vectors::DataFrame(row.names = c("x", "y"))
  )
  b <- AnnData(
    Matrix::sparseMatrix(1:2, 1:2, x = c(3, 4), dims = c(2, 2), repr = "R"),
    obs = S4Vectors::DataFrame(row.names = c("c", "d")),
    var = S4Vectors::DataFrame(row.names = c("y", "z"))
  )
  out <- concat(list(a, b), join = "outer", fill_value = NA_real_)
  expect_equal(
    unname(as.matrix(out$X)),
    rbind(c(1, 0, NA), c(0, 2, NA), c(NA, 3, 0), c(NA, 0, 4))
  )
  expect_true(is_csr(out$X))
  dense <- concat(
    list(
      AnnData(as.matrix(a$X), obs = a$obs, var = a$var),
      AnnData(as.matrix(b$X), obs = b$obs, var = b$var)
    ),
    join = "outer",
    fill_value = NA_real_
  )
  expect_false(is_sparse(dense$X))
})

# Objects with no observations or no shared variables hit the zero-size
# branches of the reindexing, which numpy and scipy handle by broadcasting
test_that("concat handles zero-size inputs", {
  empty <- AnnData(
    matrix(numeric(), 0, 2),
    obs = S4Vectors::DataFrame(row.names = character()),
    var = S4Vectors::DataFrame(row.names = c("x", "y"))
  )
  full <- AnnData(
    matrix(1, 2, 2),
    obs = S4Vectors::DataFrame(row.names = c("a", "b")),
    var = S4Vectors::DataFrame(row.names = c("y", "z"))
  )
  out <- concat(list(empty, full), join = "outer")
  expect_identical(out$shape, c(2L, 3L))
  expect_equal(unname(out$X[, 1L]), c(NA_real_, NA_real_))
  none <- concat(list(empty, full), join = "inner")
  expect_identical(none$shape, c(2L, 1L))
})

# numpy's promotion rules decide the dtype of every result, so check them
# directly, including the unsigned and float32 corners the table does not hit
test_that("promote_dtype follows numpy", {
  expect_identical(promote_dtype("int32", "float32"), "float64")
  expect_identical(promote_dtype("int16", "float32"), "float32")
  expect_identical(promote_dtype("uint8", "int8"), "int16")
  expect_identical(promote_dtype("uint32", "int16"), "int64")
  expect_identical(promote_dtype("uint64", "int8"), "float64")
  expect_identical(promote_dtype("int8", "uint8"), "int16")
  expect_identical(promote_dtype("bool", "int8"), "int8")
  expect_identical(promote_dtype("float32", "bool"), "float32")
  expect_identical(promote_dtype("int64", "uint16"), "int64")
})
