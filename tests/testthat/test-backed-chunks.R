# The rows of a table chunk as a base matrix
chunk_values <- function(chunk) {
  table_matrix(chunk$value)
}

# Why: chunked_X() must give Python's chunks (row `chunked_X_*`) for backed and
# in-memory objects, with the table's 0-based half-open ranges as 1-based
# inclusive rows
test_that("chunked_X() yields the chunks of the table", {
  check_chunks <- function(adata, row, label) {
    chunks <- adata$chunked_X(row$size)
    expect_length(chunks, length(row$result))
    for (i in seq_along(chunks)) {
      expected <- row$result[[i]]
      expect_equal(chunks[[i]]$start, expected$start + 1L, info = label)
      expect_equal(chunks[[i]]$end, expected$end, info = label)
      expect_equal(
        unname(as.matrix(drop_dtype(chunks[[i]]$chunk))),
        unname(chunk_values(expected$chunk)),
        ignore_attr = TRUE,
        info = label
      )
    }
  }
  sizes <- list(
    chunked_X_1 = 1L,
    chunked_X_3 = 3L,
    chunked_X_default = NULL,
    chunked_X_large = 100L,
    chunked_X_negative = -1L
  )
  for (name in names(sizes)) {
    for_each_backed(name, function(case, row, kind) {
      row$size <- sizes[[name]]
      check_chunks(case$adata, row, paste(name, kind))
      # An in-memory object gives the same chunks
      check_chunks(backed_source(kind), row, paste(name, kind, "memory"))
    })
  }
})

# Why: chunks of a sparse X stay sparse in the format of X (the table's chunk
# types), and are read through `[`
test_that("chunked_X() keeps the class of a sparse X", {
  for_each_backed("chunked_X_3", function(case, row, kind) {
    chunk <- case$adata$chunked_X(3L)[[1L]]$chunk
    expect_equal(
      is(chunk, "sparseMatrix"),
      kind != "dense"
    )
  })
})

# Why: rows `chunked_X_zero` and `chunked_X_float` are errors in Python, and a
# closed file is reopened (`chunked_X_closed`)
test_that("chunked_X() rejects bad sizes and reopens a closed file", {
  for_each_backed("chunked_X_zero", function(case, row, kind) {
    expect_equal(row$error$type, "ZeroDivisionError")
    expect_anndata_condition(
      case$adata$chunked_X(0L),
      "anndata_invalid_argument_error"
    )
    expect_anndata_condition(
      case$adata$chunked_X(1.5),
      "anndata_invalid_argument_error"
    )
  })
  for_each_backed("chunked_X_closed", function(case, row, kind) {
    case$adata$file$close()
    chunks <- case$adata$chunked_X(2L)
    expect_length(chunks, length(row$result))
    expect_equal(case$adata$file$is_open, row$state_after$file_is_open)
  })
})

# Why: rows `chunk_X_*` with chosen rows, in the R index forms (1-based), for
# backed and in-memory objects, always a dense matrix
test_that("chunk_X() with chosen rows gives the table's rows", {
  selects <- list(
    chunk_X_list = c(1, 3),
    chunk_X_tuple = c(2, 3),
    chunk_X_range = 1:2,
    chunk_X_array = c(4, 2),
    chunk_X_unsorted_duplicates = c(3, 1, 3),
    chunk_X_negative = I(4),
    chunk_X_closed = c(1, 3)
  )
  for (name in names(selects)) {
    for_each_backed(name, function(case, row, kind) {
      if (name == "chunk_X_closed") {
        case$adata$file$close()
      }
      for (adata in list(case$adata, backed_source(kind))) {
        got <- adata$chunk_X(selects[[name]])
        expect_true(is.matrix(got), info = name)
        expect_equal(
          unname(as.matrix(drop_dtype(got))),
          unname(chunk_values(row$result)),
          ignore_attr = TRUE,
          info = name
        )
      }
    })
  }
})

# Why: R index forms beyond Python's (names, logical, negative) and `I()` for a
# single row, which a bare number cannot express as it means a count
test_that("chunk_X() accepts the R index forms", {
  adata <- backed_source("csr")
  expected <- as.matrix(drop_dtype(adata$X))
  expect_equal(
    unname(adata$chunk_X(c("z", "w"))),
    unname(expected[c(4, 1), ]),
    ignore_attr = TRUE
  )
  expect_equal(
    unname(adata$chunk_X(c(TRUE, FALSE, TRUE, FALSE))),
    unname(expected[c(1, 3), ]),
    ignore_attr = TRUE
  )
  expect_equal(
    unname(adata$chunk_X(c(-1, -2))),
    unname(expected[3:4, ]),
    ignore_attr = TRUE
  )
  expect_equal(
    unname(adata$chunk_X(I(2))),
    unname(expected[2, , drop = FALSE]),
    ignore_attr = TRUE
  )
  expect_equal(nrow(adata$chunk_X(integer())), 0L)
})

# Why: rows `chunk_X_int*` are random in Python so only the sizes and
# membership are compared. A count above n_obs is capped, and without
# replacement it is a permutation
test_that("chunk_X() with a count samples rows", {
  for_each_backed("chunk_X_int", function(case, row, kind) {
    adata <- case$adata
    x <- as.matrix(drop_dtype(backed_source(kind)$X))
    as_keys <- function(m) apply(unname(m), 1L, paste, collapse = ",")
    got <- adata$chunk_X(2L)
    expect_equal(dim(got), c(2L, 3L))
    expect_true(all(as_keys(got) %in% as_keys(x)))
    expect_equal(nrow(adata$chunk_X(10L)), 4L)
    all_rows <- adata$chunk_X(10L, replace = FALSE)
    expect_setequal(as_keys(all_rows), as_keys(x))
    expect_equal(nrow(all_rows), 4L)
    expect_equal(nrow(adata$chunk_X(0L)), 0L)
  })
})

# Why: rows `chunk_X_negative_int`, `chunk_X_float`, `chunk_X_none`,
# `chunk_X_string` are errors in Python
test_that("chunk_X() rejects invalid selections", {
  adata <- backed_source("dense")
  for (select in list(-1L, 1.5, NA_real_)) {
    expect_anndata_condition(
      adata$chunk_X(select),
      "anndata_invalid_argument_error"
    )
  }
  expect_anndata_condition(
    adata$chunk_X(NULL),
    "anndata_invalid_argument_error"
  )
  for (select in list(list(1), c(1, 99), c("a", "b"), c(-1, 2))) {
    expect_anndata_condition(adata$chunk_X(select), "anndata_index_error")
  }
})

# Why: a View of a backed object reads only its rows through the backing file
test_that("chunks of a View of a backed object come from the file", {
  for_each_backed("view", function(case, row, kind) {
    view <- case$adata[c(1, 3), c(1, 3)]
    chunks <- view$chunked_X(1L)
    expect_length(chunks, 2L)
    expect_equal(
      unname(as.matrix(chunks[[2L]]$chunk)),
      unname(matrix(c(7, 9), nrow = 1L)),
      ignore_attr = TRUE
    )
  })
})

# The file and expected values behind a table of `read_elem_partial`
partial_case <- function(kind, env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  path <- file.path(dir, "partial.h5ad")
  write_h5ad(backed_source(kind), path)
  file <- rhdf5::H5Fopen(path, flags = "H5F_ACC_RDONLY")
  withr::defer(rhdf5::H5Fclose(file), envir = env)
  file
}

# Why: read_elem_partial() must select like Python's (rows `X_*`, `layer_rows`)
test_that("read_elem_partial() reads arrays and sparse matrices partially", {
  cases <- list(
    X_default = list("X"),
    X_rows = list("X", rows = 2:3),
    X_bare_slice = list("X", rows = 2:3),
    X_slices = list("X", rows = 2:3, cols = 1:2),
    X_list_rows = list("X", rows = c(1, 3)),
    X_list_cols = list("X", cols = c(1, 3)),
    X_bool = list("X", rows = c(TRUE, FALSE, TRUE, FALSE)),
    layer_rows = list("layers/l", rows = 1:2)
  )
  for (kind in backed_kinds) {
    file <- partial_case(kind)
    table <- backed_cases()$read_elem_partial[[kind]]
    for (name in names(cases)) {
      args <- cases[[name]]
      got <- do.call(
        read_elem_partial,
        c(list(file, args[[1L]]), args[-1L])
      )
      expect_equal(
        unname(as.matrix(drop_dtype(got))),
        unname(table_matrix(table[[name]]$result$value)),
        ignore_attr = TRUE,
        info = paste(kind, name)
      )
      expect_equal(is(got, "sparseMatrix"), kind != "dense")
    }
  }
})

# Why: dense reads need increasing positions and sparse reads do not
# (rows `X_unsorted`, `X_outer_lists`, `X_out_of_range_int`)
test_that("read_elem_partial() orders and bounds as Python does", {
  for (kind in backed_kinds) {
    file <- partial_case(kind)
    table <- backed_cases()$read_elem_partial[[kind]]
    if (kind == "dense") {
      expect_equal(table$X_unsorted$error$type, "TypeError")
      expect_anndata_condition(
        read_elem_partial(file, "X", rows = c(3, 1)),
        "anndata_index_error"
      )
      expect_anndata_condition(
        read_elem_partial(file, "X", rows = c(3, 1), cols = c(2, 3)),
        "anndata_index_error"
      )
    } else {
      got <- read_elem_partial(file, "X", rows = c(3, 1), cols = c(2, 3))
      expect_equal(
        unname(as.matrix(drop_dtype(got))),
        unname(table_matrix(table$X_outer_lists$result$value)),
        ignore_attr = TRUE
      )
    }
    expect_anndata_condition(
      read_elem_partial(file, "X", rows = 11),
      "anndata_index_error"
    )
  }
})

# Why: dataframes take rows and `items`, categoricals and indexes rows only
# (rows `obs_*`, `var_rows`)
test_that("read_elem_partial() reads data frames and vectors", {
  file <- partial_case("dense")
  table <- backed_cases()$read_elem_partial$dense
  obs <- read_elem_partial(file, "obs", rows = 2:3)
  expect_equal(rownames(obs), unlist(table$obs_rows$result$value$index))
  expect_equal(as.character(obs$g), c("b", "a"))
  expect_equal(
    rownames(read_elem_partial(file, "obs", rows = c(1, 3))),
    unlist(table$obs_list$result$value$index)
  )
  # Items select columns and unknown items are ignored
  expect_equal(
    names(read_elem_partial(file, "obs", items = "g", rows = 2:3)),
    "g"
  )
  expect_length(read_elem_partial(file, "obs", items = "zz", rows = 2:3), 0L)
  expect_length(
    read_elem_partial(file, "obs", items = character(), rows = 2:3),
    0L
  )
  expect_equal(
    nrow(read_elem_partial(file, "obs", items = "zz", rows = 2:3)),
    2L
  )
  expect_equal(
    rownames(read_elem_partial(file, "var", rows = 1:2)),
    unlist(table$var_rows$result$value$index)
  )
  expect_anndata_condition(
    read_elem_partial(file, "obs", rows = c(3, 1)),
    "anndata_index_error"
  )
  index <- read_elem_partial(file, "obs/_index", rows = 2:3)
  expect_equal(as.vector(index), unlist(table$obs_index$result$value))
  categorical <- read_elem_partial(file, "obs/g", rows = 2:3)
  expect_equal(as.character(categorical), c("b", "a"))
  expect_equal(levels(categorical), c("a", "b"))
})

# Why: arrays above 2-D stay in memory when backed, and a flat row subset
# of one would be silently wrong, so the partial read refuses them
test_that("read_elem_partial() refuses arrays with more than two dimensions", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "a3.h5ad")
  # X must be 2-D to be written, so the array is kept in uns
  adata <- AnnData(
    matrix(1, 2, 2),
    uns = list(a = array(as.numeric(1:8), c(2, 2, 2)))
  )
  write_h5ad(adata, path)
  file <- rhdf5::H5Fopen(path, flags = "H5F_ACC_RDONLY")
  withr::defer(rhdf5::H5Fclose(file))
  expect_anndata_condition(
    read_elem_partial(file, "uns/a", rows = 1),
    "anndata_partial_read_error"
  )
})

# Why: Elements without a partial reader raise a registry error in Python
# (rows `uns_dict`, `root`, `other/*`)
test_that("read_elem_partial() has no reader for other Elements", {
  file <- partial_case("dense")
  for (path in c("uns", "/")) {
    expect_anndata_condition(
      read_elem_partial(file, path),
      "anndata_io_registry_error"
    )
  }
  expect_equal(
    backed_cases()$read_elem_partial$dense$uns_dict$error$type,
    "IORegistryError"
  )
})
