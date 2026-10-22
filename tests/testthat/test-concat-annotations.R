# The arguments of the rows this ticket covers
annotation_case_args <- c(
  "axis",
  "join",
  "fill_value",
  "merge",
  "uns_merge",
  "label",
  "keys",
  "named",
  "index_unique"
)

# Every row of the table about obs, var, uns, labels, keys and merge
# strategies: the columns, dtypes, categories, index and merged values must be
# what Python gives
test_that("concat gives the annotations of every table row", {
  table <- concat_table()
  cases <- concat_cases_with_args(table, annotation_case_args)
  expect_gt(length(cases), 120L)
  for (case in cases) {
    out <- run_concat_case(case, table)$result
    expected <- case$result
    expect_identical(
      out$obs_names,
      as.character(unlist(expected$obs_names)),
      info = case$name
    )
    expect_matches_table_frame(out$obs, expected$obs, paste(case$name, "obs"))
    expect_matches_table_frame(out$var, expected$var, paste(case$name, "var"))
    expect_equal(
      out$uns,
      expected$uns,
      ignore_attr = TRUE,
      info = paste(case$name, "uns")
    )
  }
})

# Python warns when the concatenated names are not unique, and R must too
test_that("concat warns about non-unique names like Python", {
  table <- concat_table()
  cases <- concat_cases_with_args(table, annotation_case_args)
  for (case in cases) {
    expected <- any(vapply(
      case$warnings,
      function(w) grepl("names are not unique", w$message),
      logical(1)
    ))
    classes <- run_concat_case(case, table)$classes
    expect_identical(
      "anndata_names_not_unique_warning" %in% classes,
      expected,
      info = case$name
    )
  }
})

# Python's argument errors have accidental messages, so R raises its own
# classes for the rows of the table that fail
test_that("concat rejects bad merge strategies, keys and labels", {
  table <- concat_table()
  failing <- Filter(
    function(case) {
      case$name %in% c("keys_wrong_length", "merge_bad", "uns_merge_bad")
    },
    table$cases
  )
  expect_length(failing, 3L)
  for (case in failing) {
    expect_anndata_condition(
      run_concat_case(case, table),
      "anndata_invalid_argument_error"
    )
  }
  a <- AnnData(matrix(1, 2, 2))
  expect_anndata_condition(
    concat(list(a, a), label = c("a", "b")),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    concat(list(a, a), index_unique = 1),
    "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    concat(list(a, a), keys = c("x", "x")),
    "anndata_invalid_argument_error"
  )
  # Python refuses a mapping together with keys
  expect_anndata_condition(
    concat(list(x = a, y = a), keys = c("x", "y")),
    "anndata_invalid_argument_error"
  )
})

# Python makes an object column of mixed values, which cannot be written, so R
# refuses types it cannot hold in one column
test_that("concat refuses columns of types that do not combine", {
  frame <- function(column, names) {
    frame_from_columns(list(col = column), names)
  }
  a <- AnnData(obs = frame(c(1, 2), c("a", "b")), shape = c(2L, 1L))
  b <- AnnData(obs = frame(c("x", "y"), c("c", "d")), shape = c(2L, 1L))
  expect_anndata_condition(
    concat(list(a, b), join = "inner"),
    "anndata_unsupported_value_error"
  )
  d <- AnnData(obs = frame(c(TRUE, FALSE), c("e", "f")), shape = c(2L, 1L))
  expect_anndata_condition(
    concat(list(a, d), join = "inner"),
    "anndata_unsupported_value_error"
  )
})

# Combining columns follows `unify_dtypes()` and pandas, which the table only
# samples, so check the other pairings directly
test_that("combine_columns follows pandas dtype rules", {
  ns <- c(2L, 2L)
  dtype_of <- function(...) column_dtype(combine_columns(list(...), ns, NULL))
  # integers with missing values become float64, and float32 stays
  int <- typed_dense(c(1, 2), "int32")
  out <- combine_columns(list(int, NULL), ns, NULL)
  expect_identical(column_dtype(out), "float64")
  expect_identical(as.double(out), c(1, 2, NA, NA))
  expect_identical(dtype_of(typed_dense(c(1, 2), "float32"), NULL), "float32")
  # integers promote like numpy
  expect_identical(dtype_of(typed_dense(c(1, 2), "int16"), int), "int32")
  # nullable integers stay nullable with missing values
  nullable <- set_nullable(typed_dense(c(1, 2), "int32"), TRUE)
  expect_identical(dtype_of(nullable, NULL), "nullable-int32")
  # bool with boolean is boolean, bool alone is bool
  expect_identical(
    dtype_of(c(TRUE, NA), set_nullable(c(FALSE, TRUE), TRUE)),
    "boolean"
  )
  expect_identical(dtype_of(c(TRUE, FALSE), c(FALSE, TRUE)), "bool")
  # strings stay str only when all are str
  str <- set_nullable(c("a", "b"), "NaN")
  expect_identical(dtype_of(str, str), "str")
  expect_identical(dtype_of(str, c("c", "d")), "object")
  # categorical with strings is a string column, with its values kept
  mixed <- combine_columns(list(factor(c("u", "v")), c("w", "x")), ns, NULL)
  expect_identical(mixed, c("u", "v", "w", "x"))
})

# Ordered categoricals keep their order only when every object agrees,
# otherwise Python makes an object column
test_that("combine_columns handles ordered categoricals", {
  ns <- c(2L, 2L)
  levels_abc <- c("lo", "mid", "hi")
  ordered_a <- factor(c("lo", "hi"), levels = levels_abc, ordered = TRUE)
  ordered_b <- factor(c("mid", "lo"), levels = levels_abc, ordered = TRUE)
  same <- combine_columns(list(ordered_a, ordered_b), ns, NULL)
  expect_true(is.ordered(same))
  expect_identical(levels(same), levels_abc)
  other <- factor(c("hi", "lo"), levels = c("hi", "lo"), ordered = TRUE)
  expect_identical(
    combine_columns(list(ordered_a, other), ns, NULL),
    c("lo", "hi", "hi", "lo")
  )
  # one ordered and one unordered also gives strings
  plain <- factor(c("lo", "hi"))
  expect_type(combine_columns(list(ordered_a, plain), ns, NULL), "character")
  # unordered categories take the natural-order union
  a <- factor(c("g10", "g2"))
  b <- factor(c("g1", "g2"))
  expect_identical(
    levels(combine_columns(list(a, b), ns, NULL)),
    c("g1", "g2", "g10")
  )
})

# Python's `equal()` treats missing values as equal and compares arrays,
# categoricals, sparse matrices and nested values
test_that("concat_equal compares like Python's equal", {
  expect_true(concat_equal(c(1, NA), c(1, NA)))
  expect_false(concat_equal(c(1, NA), c(1, 2)))
  expect_true(concat_equal(1L, 1))
  expect_false(concat_equal(1, "1"))
  expect_false(concat_equal(1:2, 1:3))
  expect_true(concat_equal(NULL, NULL))
  expect_false(concat_equal(NULL, 1))
  expect_true(concat_equal(factor(c("a", "b")), factor(c("a", "b"))))
  expect_false(concat_equal(factor(c("a", "b")), c("a", "b")))
  expect_false(concat_equal(factor("a", levels = c("a", "b")), factor("a")))
  expect_false(concat_equal(
    factor("a", ordered = TRUE),
    factor("a", ordered = FALSE)
  ))
  expect_true(concat_equal(list(a = 1, b = "x"), list(a = 1, b = "x")))
  expect_false(concat_equal(list(a = 1), list(b = 1)))
  expect_false(concat_equal(list(a = 1), 1))
  expect_true(concat_equal(
    Matrix::Matrix(c(0, 1, 0, 0), 2, sparse = TRUE),
    matrix(c(0, 1, 0, 0), 2)
  ))
  expect_false(concat_equal(matrix(1:4, 2), matrix(1:4, 1)))
  expect_false(concat_equal(
    typed_dense(1, "int32"),
    typed_dense(1, "float64"),
    same_type = TRUE
  ))
  expect_true(concat_equal(typed_dense(1, "int32"), typed_dense(1, "float64")))
  expect_true(concat_equal(
    S4Vectors::DataFrame(x = 1),
    S4Vectors::DataFrame(x = 1)
  ))
})

# The recursive strategies on nested lists, including lists that merge to
# nothing, which Python leaves out
test_that("merge strategies work recursively on lists", {
  a <- list(x = 1, nested = list(p = 1, q = 2), only_a = "a")
  b <- list(x = 1, nested = list(p = 1, q = 3), only_b = "b")
  same <- resolve_merge_strategy("same", "m")
  expect_identical(same(list(a, b)), list(x = 1, nested = list(p = 1)))
  unique <- resolve_merge_strategy("unique", "m")
  expect_identical(
    unique(list(a, b)),
    list(x = 1, nested = list(p = 1), only_a = "a", only_b = "b")
  )
  first <- resolve_merge_strategy("first", "m")
  expect_identical(first(list(a, b))$nested, list(p = 1, q = 2))
  only <- resolve_merge_strategy("only", "m")
  expect_identical(only(list(a, b)), list(only_a = "a", only_b = "b"))
  expect_identical(resolve_merge_strategy(NULL, "m")(list(a, b)), list())
  # NULL values are kept
  expect_identical(first(list(list(k = NULL), list(k = 1))), list(k = NULL))
  # The intersection follows the order of the last list
  expect_identical(
    names(same(list(list(p = 1, q = 2), list(q = 2, p = 1)))),
    c("q", "p")
  )
})

# A function in place of a strategy gets the reindexed annotation frames
test_that("concat passes reindexed frames to a custom merge function", {
  a <- AnnData(
    obs = frame_from_columns(list(), "o1"),
    var = frame_from_columns(list(g = c("a1", "a2")), c("v1", "v2")),
    shape = c(1L, 2L)
  )
  b <- AnnData(
    obs = frame_from_columns(list(), "o2"),
    var = frame_from_columns(list(g = c("b2", "b3")), c("v2", "v3")),
    shape = c(1L, 2L)
  )
  seen <- NULL
  out <- concat(
    list(a, b),
    join = "outer",
    merge = function(values) {
      # Python also calls the function for the varm mappings
      if (!methods::is(values[[1L]], "DataFrame")) {
        return(list())
      }
      seen <<- values
      list(g = values[[2L]][["g"]])
    }
  )
  expect_identical(nrow(seen[[1L]]), 3L)
  expect_identical(seen[[1L]][["g"]], c("a1", "a2", NA))
  expect_identical(out$var[["g"]], c(NA, "b2", "b3"))
  expect_identical(out$var_names, c("v1", "v2", "v3"))
})

# Python rejects repeated column names it could not tell apart
test_that("concat refuses duplicated column names", {
  dup <- methods::new(
    "DFrame",
    listData = list(x = 1, x = 2),
    nrows = 1L,
    rownames = "o1"
  )
  a <- AnnData(obs = dup, shape = c(1L, 1L))
  expect_anndata_condition(
    concat(list(a, a), join = "inner"),
    "anndata_invalid_argument_error"
  )
})

# Taking rows of a column fills with NA and changes bool and integer dtypes
# as pandas' reindex does
test_that("take_column follows pandas reindexing", {
  dtype_of <- function(x, positions) column_dtype(take_column(x, positions))
  expect_identical(dtype_of(c(TRUE, FALSE), c(1L, NA)), "boolean")
  expect_identical(dtype_of(c(TRUE, FALSE), 1:2), "bool")
  expect_identical(
    dtype_of(typed_dense(c(1, 2), "int64"), c(1L, NA)),
    "float64"
  )
  expect_identical(
    dtype_of(typed_dense(c(1, 2), "float32"), c(1L, NA)),
    "float32"
  )
  expect_identical(
    levels(take_column(factor(c("a", "b")), c(2L, NA))),
    c("a", "b")
  )
  expect_identical(
    get_nullable(take_column(set_nullable(c("a", "b"), "NaN"), c(2L, NA))),
    "NaN"
  )
})
