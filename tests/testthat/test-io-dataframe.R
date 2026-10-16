# Every dataframe fixture, found from the files so that new cases are covered
dataframe_fixtures <- function() {
  files <- list.files(fixture_path("h5ad"), pattern = "^df_.*\\.h5$")
  sub("\\.h5$", "", files)
}

# Fixtures Python wrote with allow_write_nullable_strings off, which R only
# writes the same way with the setting off too
setting_off_fixtures <- c("df_col_str_allow_nullable_false")

# Calls `fn(name)` for every dataframe fixture, with the setting off for those
# Python wrote with it off, and restored after each call
for_each_fixture <- function(fn) {
  for (name in dataframe_fixtures()) {
    run_fixture_case(name, fn)
  }
}

run_fixture_case <- function(name, fn) {
  if (name %in% setting_off_fixtures) {
    local_anndata_settings(list(allow_write_nullable_strings = FALSE))
  }
  fn(name)
}

# A DataFrame as R holds one, with row names and an optional index name
make_frame <- function(columns, names, index_name = NULL) {
  df <- methods::new(
    "DFrame",
    listData = columns,
    nrows = length(names),
    rownames = names
  )
  if (is.null(index_name)) df else with_index_name(df, index_name)
}

# The group of the Element at `x` of the file written for `value`
written_group_attrs <- function(value) {
  store <- rhdf5::H5Fopen(write_fixture_like(value))
  on.exit(rhdf5::h5closeAll())
  elem <- rhdf5::H5Oopen(store, "x")
  list(
    type = read_elem_attr(elem, "encoding-type"),
    version = read_elem_attr(elem, "encoding-version"),
    index = read_elem_attr(elem, "_index"),
    order = read_attr_strings(elem, "column-order", "/x", NULL),
    members = rhdf5::h5ls(elem, recursive = FALSE)$name
  )
}

# Python -> R: the values and structure of fixtures that are easy to state
test_that("Python-written dataframes read as the expected DataFrame", {
  two <- read_fixture_elem("df_two_columns")
  expect_s4_class(two, "DataFrame")
  expect_identical(rownames(two), c("r0", "r1", "r2"))
  expect_identical(names(two), c("b", "a"))
  expect_identical(two$b, c(1, 2, 3))
  expect_identical(drop_dtype(two$a), c(1, 2, 3))
  expect_identical(get_dtype(two$a), "int64")
  expect_null(frame_index_name(two))

  named <- read_fixture_elem("df_index_named")
  expect_identical(frame_index_name(named), "cell")
  expect_identical(rownames(named), c("r0", "r1", "r2"))

  # NA, duplicate and non-ASCII names are kept as they are
  expect_identical(
    rownames(read_fixture_elem("df_index_na")),
    c("a", NA, "b")
  )
  expect_identical(
    rownames(read_fixture_elem("df_index_duplicates")),
    c("a", "a", "b")
  )
  expect_identical(
    rownames(read_fixture_elem("df_index_nonascii")),
    c("é", "日本", "ß")
  )

  # Integer, range and categorical indexes become string row names
  expect_identical(
    rownames(read_fixture_elem("df_index_range")),
    c("0", "1", "2")
  )
  expect_identical(
    rownames(read_fixture_elem("df_index_int")),
    c("10", "20", "30")
  )
  expect_identical(
    rownames(read_fixture_elem("df_index_categorical")),
    c("a", "b", "a")
  )

  none <- read_fixture_elem("df_no_columns")
  expect_identical(dim(none), c(2L, 0L))
  expect_identical(rownames(none), c("a", "b"))
  expect_identical(
    names(read_fixture_elem("df_columns_order")),
    c("z", "a", "m")
  )
})

test_that("a dataframe reads every column type", {
  df <- read_fixture_elem("df_all_types")
  expect_identical(names(df), c("f", "i", "b", "s", "cat", "ni"))
  expect_identical(df$f, c(1.5, 2.5, 3.5))
  expect_identical(df$b, c(TRUE, FALSE, TRUE))
  expect_s3_class(df$cat, "factor")
  expect_identical(drop_dtype(df$ni), c(1, NA, 3))
  expect_identical(drop_dtype(df$s), c("a", "b", "c"))
})

# R -> R: reading and writing again must not change a value or record
test_that("every dataframe fixture round trips through R", {
  for_each_fixture(function(name) {
    value <- read_fixture_elem(name)
    expect_identical(
      read_written(write_fixture_like(value)),
      value,
      info = name
    )
  })
})

# Python -> R -> Python: R writes the groups, dtypes and attributes Python did
test_that("R rewrites every dataframe fixture equivalently", {
  skip_if_no_python()
  test_env <- environment()
  written <- character()
  originals <- character()
  for_each_fixture(function(name) {
    written[[name]] <<- write_fixture_like(
      read_fixture_elem(name),
      env = test_env
    )
    originals[[name]] <<- fixture_path(file.path("h5ad", paste0(name, ".h5")))
  })
  expect_all_equivalent(written, originals)
})

# R -> Python -> R: Python reads what R writes and writes it back unchanged
test_that("Python reads and rewrites the dataframes R writes", {
  skip_if_no_python()
  test_env <- environment()
  values <- list()
  written <- character()
  for_each_fixture(function(name) {
    # rewrite.py uses Python's default setting, which writes nullable strings
    if (name %in% setting_off_fixtures) {
      return(invisible())
    }
    values[[name]] <<- read_fixture_elem(name)
    written[[name]] <<- write_fixture_like(values[[name]], env = test_env)
  })
  rewritten <- python_rewrite(written)
  for (i in seq_along(values)) {
    expect_identical(
      read_written(rewritten[[i]]),
      values[[i]],
      info = names(values)[[i]]
    )
  }
  expect_all_equivalent(rewritten, written)
})

# New frames built in R pick the encodings Python writes for the equivalent
# pandas frame
test_that("a DataFrame built in R is written as Python writes it", {
  df <- make_frame(
    list(
      f = c(1.5, 2),
      i = 1:2,
      l = c(TRUE, FALSE),
      s = c("a", "b"),
      fac = factor(c("u", "v")),
      ni = c(1L, NA),
      ns = c("a", NA)
    ),
    c("r0", "r1")
  )
  store <- rhdf5::H5Fopen(write_fixture_like(df))
  withr::defer(rhdf5::h5closeAll())
  types <- vapply(
    names(df),
    function(name) {
      elem <- rhdf5::H5Oopen(store, paste0("x/", name))
      on.exit(rhdf5::H5Oclose(elem))
      read_elem_attr(elem, "encoding-type")
    },
    character(1)
  )
  expect_identical(
    types,
    c(
      f = "array",
      i = "array",
      l = "array",
      s = "nullable-string-array",
      fac = "categorical",
      ni = "nullable-integer",
      ns = "nullable-string-array"
    )
  )
  expect_identical(h5_dtype(store, "/x/i"), "int32")
  # The index is a nullable string array, as for a pandas 3 string index
  elem <- rhdf5::H5Oopen(store, "x/_index")
  expect_identical(
    read_elem_attr(elem, "encoding-type"),
    "nullable-string-array"
  )
  expect_identical(read_elem_attr(elem, "na-value"), "NaN")
})

test_that("a DataFrame built in R round trips through Python", {
  skip_if_no_python()
  df <- make_frame(
    list(f = c(1.5, NaN), s = c("a", NA), fac = factor(c("u", "v"))),
    c("r0", NA),
    "cell"
  )
  written <- write_fixture_like(df)
  rewritten <- python_rewrite(written)
  expect_identical(read_written(rewritten), read_written(written))
  expect_structurally_equivalent(rewritten, written)
})

# The attributes `_index` and `column-order`
test_that("the index name and column order are written as attributes", {
  df <- make_frame(list(z = 1:2, a = 3:4), c("p", "q"), "cell")
  attrs <- written_group_attrs(df)
  expect_identical(attrs$type, "dataframe")
  expect_identical(attrs$version, "0.2.0")
  expect_identical(attrs$index, "cell")
  expect_identical(attrs$order, c("z", "a"))
  # Datasets are listed alphabetically, only column-order keeps the order
  expect_identical(attrs$members, c("a", "cell", "z"))

  unnamed <- written_group_attrs(make_frame(list(a = 1L), "p"))
  expect_identical(unnamed$index, "_index")
  expect_identical(unnamed$order, "a")
})

test_that("a frame with no columns writes an empty column-order", {
  df <- make_frame(structure(list(), names = character()), c("a", "b"))
  attrs <- written_group_attrs(df)
  expect_identical(attrs$order, character())
  expect_identical(rownames(read_written(write_fixture_like(df))), c("a", "b"))
})

# Decision of 2026-10-15: NULL row names are a RangeIndex
test_that("a data.frame with automatic row names writes a RangeIndex", {
  df <- data.frame(c = c(1, 2, 3))
  value <- read_written(write_fixture_like(df))
  expect_identical(rownames(value), c("0", "1", "2"))
  store <- rhdf5::H5Fopen(write_fixture_like(df))
  withr::defer(rhdf5::h5closeAll())
  expect_identical(h5_dtype(store, "/x/_index"), "int64")
  elem <- rhdf5::H5Oopen(store, "x/_index")
  expect_identical(read_elem_attr(elem, "encoding-type"), "array")
})

test_that("a data.frame with row names and an index name is written", {
  df <- data.frame(c = c(1, 2), row.names = c("a", "b"))
  attr(df, "index_name") <- "cell"
  attrs <- written_group_attrs(df)
  expect_identical(attrs$index, "cell")
  expect_identical(
    rownames(read_written(write_fixture_like(df))),
    c("a", "b")
  )
})

# Python merges a column that repeats the index, but not one that differs
test_that("a column named like the index is written once", {
  same <- make_frame(list(id = c("a", "b")), c("a", "b"), "id")
  expect_identical(written_group_attrs(same)$members, "id")
  different <- make_frame(list(id = c("x", "y")), c("a", "b"), "id")
  err <- expect_anndata_condition(
    write_fixture_like(different),
    "anndata_io_registry_error"
  )
  expect_identical(err$path, "/x")
})

test_that("unwritable frames raise io registry errors with the path", {
  reserved <- make_frame(list(`_index` = 1:2), c("a", "b"))
  err <- expect_anndata_condition(
    write_fixture_like(reserved),
    "anndata_io_registry_error"
  )
  expect_identical(err$path, "/x")

  repeated <- data.frame(a = 1:2, a = 3:4, check.names = FALSE)
  err <- expect_anndata_condition(
    write_fixture_like(repeated),
    "anndata_io_registry_error"
  )
  expect_identical(err$path, "/x")

  # A column no encoding exists for is reported at its own path
  err <- expect_anndata_condition(
    write_fixture_like(data.frame(d = as.Date(c("2020-01-01", "2020-01-02")))),
    "anndata_io_registry_error"
  )
  expect_identical(err$path, "/x/d")

  err <- expect_anndata_condition(
    write_fixture_like(data.frame(m = I(matrix(1:4, 2)))),
    "anndata_io_registry_error"
  )
  expect_identical(err$path, "/x/m")
})

# A length-1 column would be a scalar without as_array()
test_that("a frame with one row writes array columns", {
  df <- make_frame(list(a = 1.5, s = "x"), "r0")
  value <- read_written(write_fixture_like(df))
  expect_identical(value$a, 1.5)
  expect_identical(drop_dtype(value$s), "x")
  expect_identical(rownames(value), "r0")
  none <- make_frame(list(a = numeric(0), s = character(0)), character(0))
  expect_identical(dim(read_written(write_fixture_like(none))), c(0L, 2L))
})

# Decision for ticket 09: the setting applies to string columns and the index
test_that("allow_write_nullable_strings FALSE writes string-array or raises", {
  local_anndata_settings(list(allow_write_nullable_strings = FALSE))
  df <- make_frame(list(s = c("a", "b")), c("r0", "r1"))
  store <- rhdf5::H5Fopen(write_fixture_like(df))
  withr::defer(rhdf5::h5closeAll())
  for (member in c("x/s", "x/_index")) {
    elem <- rhdf5::H5Oopen(store, member)
    expect_identical(read_elem_attr(elem, "encoding-type"), "string-array")
  }

  missing_value <- make_frame(list(s = c("a", NA)), c("r0", "r1"))
  err <- expect_anndata_condition(
    write_fixture_like(missing_value),
    "anndata_nullable_strings_error"
  )
  expect_identical(err$path, "/x/s")
  missing_name <- make_frame(list(c = 1:2), c("r0", NA))
  err <- expect_anndata_condition(
    write_fixture_like(missing_name),
    "anndata_nullable_strings_error"
  )
  expect_identical(err$path, "/x/_index")
})

test_that("a string-array column keeps its encoding when read and written", {
  df <- read_fixture_elem("df_col_str_allow_nullable_false")
  store <- rhdf5::H5Fopen(write_fixture_like(df))
  withr::defer(rhdf5::h5closeAll())
  for (member in c("x/c", "x/_index")) {
    elem <- rhdf5::H5Oopen(store, member)
    expect_identical(read_elem_attr(elem, "encoding-type"), "string-array")
  }
})

# The index source is only reused while the row names still match it
test_that("an integer index is written as it was only while names match", {
  df <- read_fixture_elem("df_index_int")
  expect_identical(get_dtype(S4Vectors::metadata(df)$index_source), "int64")
  expect_identical(
    h5_dtype(rhdf5::H5Fopen(write_fixture_like(df)), "/x/_index"),
    "int64"
  )
  rhdf5::h5closeAll()

  renamed <- with_frame_names(df, c("p", "q", "r"))
  store <- rhdf5::H5Fopen(write_fixture_like(renamed))
  withr::defer(rhdf5::h5closeAll())
  elem <- rhdf5::H5Oopen(store, "x/_index")
  expect_identical(
    read_elem_attr(elem, "encoding-type"),
    "nullable-string-array"
  )
})

# Legacy layouts have their own classed error from the registry
test_that("a dataframe 0.1.0 group raises the legacy error", {
  store <- local_h5_store()
  make_encoded_group(store, "x", "dataframe", "0.1.0")
  err <- expect_anndata_condition(
    read_elem(store, "x"),
    "anndata_legacy_format_error"
  )
  expect_identical(err$path, "/x")
})

test_that("a dataframe missing its attributes or with a short column raises", {
  store <- local_h5_store()
  make_encoded_group(store, "x", "dataframe", "0.2.0")
  err <- expect_anndata_condition(
    read_elem(store, "x"),
    "anndata_io_registry_error"
  )
  expect_identical(err$path, "/x")

  # Column c has 2 values but the index has 3
  df <- make_frame(list(c = c(1, 2, 3)), c("a", "b", "c"))
  write_elem(store, "y", df)
  rhdf5::H5Ldelete(store, "y/c")
  write_elem(rhdf5::H5Gopen(store, "y"), "c", as_array(c(1, 2)))
  err <- expect_anndata_condition(
    read_elem(store, "y"),
    "anndata_io_registry_error"
  )
  expect_identical(err$path, "/y")
})
