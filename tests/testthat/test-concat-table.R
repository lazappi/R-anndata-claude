# Guards the committed concat table against drifting from what Python gives
test_that("the committed concat table matches the generator", {
  expect_generator_current("concat_cases.py")
})

# The table is the reference for every concat ticket, so check it is for the
# pinned Python version and that its rows are well formed
test_that("the concat table is well formed", {
  table <- concat_table()
  expect_identical(table$version, "0.13.4")
  names_out <- vapply(table$cases, function(x) x$name, character(1))
  expect_false(anyDuplicated(names_out) > 0L)
  for (case in table$cases) {
    expect_true(
      xor(is.null(case$error), is.null(case$result)),
      info = case$name
    )
    for (input in case$inputs) {
      expect_true(
        input %in% names(table$inputs) || input == "not_anndata",
        info = case$name
      )
    }
  }
})

# The spec lists what the table must cross, so a missing combination fails here
test_that("the concat table covers every combination in the spec", {
  table <- concat_table()
  args <- lapply(table$cases, function(x) x$args)
  used <- function(arg) {
    unique(unlist(lapply(args, function(a) a[[arg]])))
  }
  expect_setequal(
    used("axis")[used("axis") %in% c("obs", "var")],
    c("obs", "var")
  )
  expect_true(all(c("inner", "outer") %in% used("join")))
  expect_true(
    all(c("same", "unique", "first", "only", "first_fn") %in% used("merge"))
  )
  expect_true(
    all(c("same", "unique", "first", "only", "first_fn") %in% used("uns_merge"))
  )
  for (arg in c("label", "keys", "named", "index_unique", "fill_value")) {
    expect_true(length(used(arg)) > 0L, info = arg)
  }
  expect_setequal(used("pairwise"), c(FALSE, TRUE))

  # Sparse formats and dtypes of the results, NULL X, and warnings and errors
  results <- Filter(Negate(is.null), lapply(table$cases, function(x) x$result))
  x_formats <- unique(vapply(
    results,
    function(r) if (is.null(r$X)) "none" else r$X$format %||% "dense",
    character(1)
  ))
  # Python never returns CSC from concat (CSC inputs come back as CSR), and
  # promotes float32 inputs to float64, so only these appear in results
  expect_setequal(x_formats, c("dense", "csr", "none"))
  x_dtypes <- unique(unlist(lapply(results, function(r) r$X$dtype)))
  expect_true(all(c("float64", "int32", "int8", "bool") %in% x_dtypes))
  expect_true(any(vapply(
    table$cases,
    function(x) length(x$warnings) > 0L,
    logical(1)
  )))
  expect_true(any(vapply(
    table$cases,
    function(x) !is.null(x$error),
    logical(1)
  )))

  # Python 0.13.3 promotes bool annotation columns to nullable boolean when
  # reindexing adds missing values
  col_dtypes <- unlist(lapply(results, function(r) {
    c(
      lapply(r$obs$columns, function(col) col$dtype),
      lapply(r$var$columns, function(col) col$dtype)
    )
  }))
  expect_true("boolean" %in% col_dtypes)
})

# Each row guards a combination of the spec's list that the argument checks
# above cannot see (mixtures, slots, axes crossed with other arguments)
test_that("the concat table crosses the spec's input combinations", {
  table <- concat_table()
  by_name <- table$cases
  names(by_name) <- vapply(by_name, function(x) x$name, character(1))
  input_x <- function(name) table$inputs[[name]]$X
  case_formats <- function(case) {
    vapply(
      case$inputs,
      function(i) {
        x <- input_x(i)
        if (is.null(x)) "none" else x$format %||% "dense"
      },
      character(1)
    )
  }

  # Mixtures of dense, CSR and CSC inputs on both joins
  mixes <- unique(vapply(
    by_name,
    function(case) paste(case_formats(case), collapse = "+"),
    character(1)
  ))
  expect_true(all(
    c(
      "dense+dense",
      "csr+csr",
      "csc+csc",
      "csr+csc",
      "csc+csr",
      "dense+csr"
    ) %in%
      mixes
  ))
  expect_true(all(
    c("dense_obs_outer", "csr_dense_obs_inner", "dense_csc_var_outer") %in%
      names(by_name)
  ))

  # fill_value with dense and sparse inputs, and sparse reindexing
  expect_true(all(
    c("fill_value_dense", "fill_value_csr", "fill_value_var") %in%
      names(by_name)
  ))

  # Missing and differing Slots, on both joins
  expect_true(all(
    c(
      "no_layer_inner",
      "no_layer_outer",
      "no_obsm_outer",
      "bare_outer",
      "extra_obs_column"
    ) %in%
      names(by_name)
  ))

  # index_unique alone and with keys, a named list and label
  expect_true(all(
    c("index_unique", "index_unique_keys", "index_unique_named") %in%
      names(by_name)
  ))

  # pairwise on both axes, missing, and both values
  for (pairwise in c("True", "False")) {
    expect_true(all(
      paste0(
        "pairwise_",
        pairwise,
        "_",
        c("obs", "var", "missing", "outer")
      ) %in%
        names(by_name)
    ))
  }

  # raw on both axes and joins, with raw missing from one object
  expect_true(all(
    c("raw_inner", "raw_outer", "raw_outer_var", "raw_one_missing") %in%
      names(by_name)
  ))

  # uns_merge with every strategy, a custom function and three objects
  expect_true(all(
    paste0(
      "uns_merge_",
      c("same", "unique", "first", "only", "custom", "three")
    ) %in%
      names(by_name)
  ))
})
