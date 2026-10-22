concat_table <- function() {
  jsonlite::fromJSON(
    fixture_path("concat_cases.json"),
    simplifyVector = FALSE
  )
}

# The rows of a table array description as an R matrix, with JSON null as NA
concat_table_matrix <- function(desc) {
  rows <- desc$values
  n_col <- desc$shape[[2L]]
  out <- matrix(NA_real_, length(rows), n_col)
  for (i in seq_along(rows)) {
    for (j in seq_len(n_col)) {
      value <- rows[[i]][[j]]
      if (!is.null(value)) {
        out[i, j] <- as.double(value)
      }
    }
  }
  out
}

# An input array from its table description, with the On-disk dtype of Python
table_array <- function(desc) {
  values <- concat_table_matrix(desc)
  dtype <- desc$dtype
  if (identical(desc$kind, "dense")) {
    return(typed_dense(values, dtype))
  }
  keep <- which(values != 0, arr.ind = TRUE)
  data <- if (dtype == "bool") rep(TRUE, nrow(keep)) else values[keep]
  matrix <- Matrix::sparseMatrix(
    i = keep[, 1L],
    j = keep[, 2L],
    x = data,
    dims = dim(values),
    repr = if (desc$format == "csr") "R" else "C"
  )
  if (dtype %in% c("bool", "float64")) {
    matrix
  } else {
    set_dtype(matrix, c(data = dtype))
  }
}

# An annotation column from its table description, with the pandas dtype as
# the record: `str` is a nullable string, `object` a plain string and
# `boolean` a nullable logical
table_column <- function(col) {
  na_or <- function(convert, empty) {
    vapply(col$values, function(v) if (is.null(v)) empty else convert(v), empty)
  }
  switch(
    col$dtype,
    category = factor(
      na_or(as.character, NA_character_),
      levels = unlist(col$categories),
      ordered = isTRUE(col$ordered)
    ),
    str = set_nullable(na_or(as.character, NA_character_), "NaN"),
    object = na_or(as.character, NA_character_),
    bool = na_or(as.logical, NA),
    boolean = set_nullable(na_or(as.logical, NA), TRUE),
    typed_dense(na_or(as.double, NA_real_), col$dtype)
  )
}

table_frame <- function(desc) {
  frame_from_columns(
    lapply(desc$columns, table_column),
    as.character(unlist(desc$index))
  )
}

# The elements of an aligned mapping from their table descriptions
table_mapping <- function(desc) {
  lapply(desc, function(d) {
    if (identical(d$kind, "dataframe")) table_frame(d) else table_array(d)
  })
}

# The input objects of a table row: X, layers, obs, var, uns, the aligned
# mappings and raw
table_anndata <- function(desc) {
  layers <- desc$layers[names(desc$layers) != "None"]
  layers <- lapply(layers, table_array)
  x <- if (!is.null(desc$X)) table_array(desc$X)
  raw <- if (!is.null(desc$raw)) {
    list(
      X = table_array(desc$raw$X),
      var = table_frame(desc$raw$var),
      varm = table_mapping(desc$raw$varm)
    )
  }
  AnnData(
    X = x,
    obs = table_frame(desc$obs),
    var = table_frame(desc$var),
    uns = desc$uns,
    obsm = table_mapping(desc$obsm),
    varm = table_mapping(desc$varm),
    obsp = table_mapping(desc$obsp),
    varp = table_mapping(desc$varp),
    layers = if (length(layers)) layers,
    raw = raw,
    shape = if (is.null(x)) unlist(desc$shape)
  )
}

# What Python gave for an aligned mapping: keys and each element
expect_matches_table_mapping <- function(actual, expected, info) {
  actual <- as.list(actual)
  expect_setequal(
    names(actual) %||% character(),
    names(expected) %||% character()
  )
  for (key in names(expected)) {
    element <- expected[[key]]
    label <- paste(info, key)
    if (identical(element$kind, "dataframe")) {
      expect_matches_table_frame(actual[[key]], element, label)
    } else {
      expect_matches_table_array(actual[[key]], element, label)
    }
  }
}

# What Python gave for an annotation frame: index, column order, dtypes (as
# `column_dtype()` names them), categories and values
expect_matches_table_frame <- function(actual, desc, info) {
  expect_identical(
    rownames(actual),
    as.character(unlist(desc$index)),
    info = info
  )
  expect_identical(
    colnames(actual),
    names(desc$columns) %||% character(),
    info = info
  )
  for (name in names(desc$columns)) {
    expected <- desc$columns[[name]]
    column <- actual[[name]]
    label <- paste(info, name)
    expect_identical(column_dtype(column), expected$dtype, info = label)
    values <- vapply(
      expected$values,
      function(v) if (is.null(v)) NA_character_ else as.character(v),
      character(1)
    )
    expect_identical(as.character(drop_dtype(column)), values, info = label)
    if (identical(expected$dtype, "category")) {
      expect_identical(
        levels(column),
        unlist(expected$categories),
        info = label
      )
      expect_identical(is.ordered(column), expected$ordered, info = label)
    }
  }
}

# What Python gave for an array: sparse format, On-disk dtype and values
expect_matches_table_array <- function(actual, desc, info) {
  expect_identical(array_dtype(actual), desc$dtype, info = info)
  if (identical(desc$kind, "sparse")) {
    expect_true(is_csr(actual), info = info)
  } else {
    expect_false(is_sparse(actual), info = info)
  }
  expect_equal(
    unname(matrix(as.double(as.matrix(actual)), nrow(actual), ncol(actual))),
    concat_table_matrix(desc),
    info = info
  )
}

# Rows of the table whose arguments are all in `allowed` and that succeed
concat_cases_with_args <- function(table, allowed) {
  keep <- vapply(
    table$cases,
    function(case) {
      is.null(case$error) && all(names(case$args) %in% allowed)
    },
    logical(1)
  )
  table$cases[keep]
}

# Runs a table row, returning the result and the classes of the warnings
run_concat_case <- function(case, table) {
  adatas <- lapply(case$inputs, function(i) table_anndata(table$inputs[[i]]))
  args <- case$args
  # `named` is a list input whose names are the keys
  if (!is.null(args$named)) {
    names(adatas) <- unlist(args$named)
    args$named <- NULL
  }
  if (!is.null(args$keys)) {
    args$keys <- unlist(args$keys)
  }
  # The table's custom merge function is "the first value"
  for (arg in c("merge", "uns_merge")) {
    if (identical(args[[arg]], "first_fn")) {
      args[[arg]] <- function(values) values[[1L]]
    }
  }
  classes <- character()
  result <- withCallingHandlers(
    do.call(concat, c(list(adatas), args)),
    warning = function(w) {
      classes <<- c(classes, class(w))
      rlang::cnd_muffle(w)
    }
  )
  list(result = result, classes = classes)
}
