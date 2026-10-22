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

# The input objects of a table row: X, layers and names (the annotations come
# with later tickets)
table_anndata <- function(desc) {
  layers <- desc$layers[names(desc$layers) != "None"]
  layers <- lapply(layers, table_array)
  x <- if (!is.null(desc$X)) table_array(desc$X)
  AnnData(
    X = x,
    obs = S4Vectors::DataFrame(row.names = unlist(desc$obs_names)),
    var = S4Vectors::DataFrame(row.names = unlist(desc$var_names)),
    layers = if (length(layers)) layers,
    shape = if (is.null(x)) unlist(desc$shape)
  )
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
  classes <- character()
  result <- withCallingHandlers(
    do.call(concat, c(list(adatas), case$args)),
    warning = function(w) {
      classes <<- c(classes, class(w))
      rlang::cnd_muffle(w)
    }
  )
  list(result = result, classes = classes)
}
