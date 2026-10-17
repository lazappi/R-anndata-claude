sparse_kinds <- c("csr", "csc")

sparse_reference <- function() {
  matrix(as.numeric(1:12), nrow = 4, byrow = TRUE)
}

# The class Matrix gives a selection of the same format as the file
sparse_class <- function(kind) {
  c(csr = "dgRMatrix", csc = "dgCMatrix")[[kind]]
}

# Opens `X` of a fresh file as a group handle for sparse_dataset()
local_sparse_group <- function(kind, env = parent.frame()) {
  case <- local_backed(kind, "r", env = env)
  case$adata$file$close()
  file <- rhdf5::H5Fopen(case$path, flags = "H5F_ACC_RDONLY")
  group <- rhdf5::H5Gopen(file, "X")
  withr::defer(
    {
      rhdf5::H5Gclose(group)
      rhdf5::H5Fclose(file)
    },
    envir = env
  )
  list(group = group, path = case$path)
}

# Every R index form must select like the same matrix in memory, in the format
# of the file, including the forms Python's sparse handle rejects
test_that("[ on backed sparse X selects like a matrix for every index form", {
  ref <- sparse_reference()
  forms <- list(
    list(1L, 2L),
    list(2:3, 1:2),
    list(c(3L, 1L), c(3L, 1L)),
    list(c(2L, 2L, 4L), 1L),
    list(-1L, -2L),
    list(-(1:2), 2:3),
    list(c(TRUE, FALSE, TRUE, FALSE), c(FALSE, TRUE, TRUE)),
    list(c(TRUE, FALSE), 2L),
    list(integer(0), 1:2),
    list(1:2, integer(0)),
    list(0L, 1:3),
    list(2.9, 1),
    list(4:1, 3:1),
    list(c(1L, 1L), c(3L, 3L, 1L))
  )
  for (kind in sparse_kinds) {
    x <- local_backed(kind, "r")$adata$X
    for (form in forms) {
      for (drop in c(TRUE, FALSE)) {
        values <- x[form[[1]], form[[2]], drop = drop]
        expected <- ref[form[[1]], form[[2]], drop = drop]
        info <- paste(kind, deparse(form), drop)
        if (is.matrix(expected)) {
          expect_s4_class(values, sparse_class(kind))
          expect_equal(
            unname(as.matrix(drop_dtype(values))),
            expected,
            info = info
          )
        } else {
          expect_equal(drop_dtype(values), expected, info = info)
        }
      }
    }
    expect_equal(drop_dtype(x[, 2L]), ref[, 2L])
    expect_equal(drop_dtype(x[3L, ]), ref[3L, ])
    expect_equal(unname(as.matrix(drop_dtype(x[TRUE, TRUE]))), ref)
    expect_equal(unname(as.matrix(drop_dtype(x[]))), ref)
    expect_equal(drop_dtype(x[5L]), ref[5L])
    expect_equal(drop_dtype(x[ref > 6]), ref[ref > 6])
  }
})

# Out-of-range, missing and named indices raise an index error like the other
# subsetting code, and a third index is rejected
test_that("[ on backed sparse X rejects invalid indices", {
  for (kind in sparse_kinds) {
    x <- local_backed(kind, "r")$adata$X
    expect_error(x[5L, ], class = "anndata_index_error")
    expect_error(x[, 4L], class = "anndata_index_error")
    expect_error(x[NA_integer_, ], class = "anndata_index_error")
    expect_error(x["a", ], class = "anndata_index_error")
    expect_error(x[rep(TRUE, 5), ], class = "anndata_index_error")
    expect_error(x[1, 1, 1], class = "anndata_index_error")
  }
})

# Values read from backed X carry the dtype record of data, as in read_h5ad,
# and the whole matrix reads like read_h5ad does
test_that("values read from backed sparse X keep the on-disk dtype", {
  for (kind in sparse_kinds) {
    case <- local_backed(kind, "r")
    x <- case$adata$X
    expect_equal(get_dtype(x[1:2, ]), c(data = "float32"))
    expect_equal(get_dtype(x[3L, 2L]), "float32")
    expect_equal(get_dtype(x[c(2L, 2L), ]), c(data = "float32"))
    expect_equal(get_dtype(as.matrix(x)), "float32")
    in_memory <- read_h5ad(case$path)
    expect_equal(x$to_memory(), in_memory$X)
    expect_equal(get_dtype(x$to_memory()), get_dtype(in_memory$X))
  }
})

# Reading after close() reopens the file, and the shape is known without
# reading any values
test_that("backed sparse X reads after the file was closed", {
  for (kind in sparse_kinds) {
    case <- local_backed(kind, "r")
    x <- case$adata$X
    case$adata$file$close()
    expect_equal(dim(x), c(4L, 3L))
    expect_false(case$adata$file$is_open)
    expect_equal(drop_dtype(x[2L, 3L]), 6)
    expect_true(case$adata$file$is_open)
  }
})

# A boolean sparse matrix has logical data, and a matrix with no stored values
# in the selection is still a valid sparse matrix
test_that("backed sparse X handles boolean and empty selections", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "bool.h5ad")
  m <- Matrix::sparseMatrix(
    i = c(1, 3),
    j = c(2, 3),
    x = c(TRUE, TRUE),
    dims = c(4, 3)
  )
  write_h5ad(AnnData(methods::as(m, "RsparseMatrix")), path)
  adata <- read_h5ad(path, backed = "r")
  withr::defer(adata$file$close())
  x <- adata$X
  expect_equal(x$dtype, "bool")
  expect_s4_class(x[1:2, ], "lgRMatrix")
  expect_equal(unname(as.matrix(x[c(1, 3), ])), unname(as.matrix(m)[c(1, 3), ]))
  expect_equal(sum(x[2L, , drop = FALSE]), 0)
  expect_equal(as.matrix(x[4L, 1L]), FALSE, ignore_attr = TRUE)
})

# A View of a backed object reads only the data and indices of its rows (or
# columns for CSC) and does not load the whole matrix
test_that("a View of backed sparse X reads only the needed slices", {
  # Rows 2 and 4 hold 3 values each (CSR), and columns 1 and 3 four values
  # each (CSC), which are the only values read. Run per kind so each mock
  # ends with its function.
  check_view <- function(kind, n_values) {
    case <- local_backed(kind, "r")
    reads <- list()
    original <- array_read
    local_mocked_bindings(
      array_read = function(store, path, selection = NULL, call = NULL) {
        reads[[length(reads) + 1L]] <<- list(path = path, selection = selection)
        original(store, path, selection, call)
      }
    )
    view <- case$adata[c("z", "x"), c("r", "p")]
    expect_true(view$is_view)
    expect_equal(
      unname(as.matrix(drop_dtype(view$X))),
      matrix(c(12, 10, 6, 4), 2, 2, byrow = TRUE)
    )
    paths <- vapply(reads, function(read) read$path, character(1))
    data_reads <- reads[endsWith(paths, "X/data")]
    info <- paste(paths, collapse = ", ")
    expect_true(length(data_reads) >= 1L, info = info)
    for (read in data_reads) {
      expect_true(length(read$selection[[1]]) <= n_values, info = info)
    }
  }
  check_view("csr", 6L)
  check_view("csc", 8L)
  # The whole matrix has 12 values, so neither View read it
})

# indptr is read once when cached, and for every selection when it is not
test_that("sparse_dataset caches indptr unless asked not to", {
  group <- local_sparse_group("csr")$group
  counts <- new.env()
  counts$cached <- 0L
  original <- array_read
  local_mocked_bindings(
    array_read = function(store, path, selection = NULL, call = NULL) {
      if (endsWith(path, "indptr")) {
        counts$cached <- counts$cached + 1L
      }
      original(store, path, selection, call)
    }
  )
  handle <- sparse_dataset(group)
  handle[1L, ]
  handle[2L, ]
  expect_equal(counts$cached, 1L)
  counts$cached <- 0L
  uncached <- sparse_dataset(group, should_cache_indptr = FALSE)
  uncached[1L, ]
  uncached[2L, ]
  expect_equal(counts$cached, 2L)
  expect_equal(uncached[3L, ], handle[3L, ])
})

# The sparse X rows of the operations table, as R does them. Row numbers are
# Python's plus one, and results are compared as dense matrices
test_that("the sparse X rows of the operations table match", {
  cases <- list(
    X_col = quote(x[, 2, drop = FALSE]),
    X_colon = quote(x[TRUE, TRUE, drop = FALSE]),
    X_cols_list = quote(x[, c(1, 3), drop = FALSE]),
    X_duplicate_rows = quote(x[c(1, 1), , drop = FALSE]),
    X_ellipsis = quote(x[TRUE, TRUE, drop = FALSE]),
    X_empty_tuple = quote(x[]),
    X_negative_cols_slice = quote(x[, 2:3, drop = FALSE]),
    X_negative_list = quote(x[c(4, 1), , drop = FALSE]),
    X_reverse_slice = quote(x[4:2, , drop = FALSE]),
    X_row = quote(x[2, , drop = FALSE]),
    X_row_colon = quote(x[2, , drop = FALSE]),
    X_rows_bool = quote(x[c(TRUE, FALSE, TRUE, FALSE), , drop = FALSE]),
    X_rows_cols_lists = quote(x[c(1, 3), 1:2, drop = FALSE]),
    X_rows_cols_lists_outer = quote(x[c(4, 1), c(1, 3), drop = FALSE]),
    X_rows_list = quote(x[c(1, 3), , drop = FALSE]),
    X_rows_list_cols_slice = quote(x[c(1, 3), , drop = FALSE]),
    X_slice_rows = quote(x[2:3, , drop = FALSE]),
    X_slices = quote(x[2:3, 1:2, drop = FALSE]),
    X_step_slice = quote(x[c(1, 3), , drop = FALSE]),
    X_unsorted_rows = quote(x[c(3, 1), , drop = FALSE])
  )
  for (name in names(cases)) {
    for_each_backed(
      name,
      function(case, row, kind) {
        x <- case$adata$X
        values <- unname(as.matrix(drop_dtype(eval(cases[[name]]))))
        # Python rejects a few of these for CSC (negative column slice), and
        # R then selects like the matrix
        expected <- if (is.null(row$error)) {
          table_matrix(row$result$value)
        } else {
          unname(as.matrix(eval(cases[[name]], list(x = sparse_reference()))))
        }
        expect_equal(values, expected, info = name)
        expect_s4_class(eval(cases[[name]]), sparse_class(kind))
      },
      kinds = sparse_kinds
    )
  }
  for_each_backed(
    "X_scalar",
    function(case, row, kind) {
      expect_equal(drop_dtype(case$adata$X[2, 3]), row$result$value)
    },
    kinds = sparse_kinds
  )
  for_each_backed(
    "X_asarray",
    function(case, row, kind) {
      expect_equal(
        unname(drop_dtype(as.matrix(case$adata$X))),
        sparse_reference()
      )
    },
    kinds = sparse_kinds
  )
  for_each_backed(
    "X_handle",
    function(case, row, kind) {
      x <- case$adata$X
      expect_equal(dim(x), unlist(row$result$shape))
      expect_equal(x$dtype, row$result$dtype)
      expect_equal(x$format, row$result$format)
      expect_equal(x$backend, "hdf5")
    },
    kinds = sparse_kinds
  )
  # An empty list gives a matrix with no rows and the file is unchanged
  for_each_backed(
    "X_empty_list",
    function(case, row, kind) {
      empty <- case$adata$X[integer(0), , drop = FALSE]
      expect_equal(dim(empty), c(0L, 3L))
      expect_s4_class(empty, sparse_class(kind))
      expect_backed_state(case$adata, row$state_after)
    },
    kinds = sparse_kinds
  )
  # These rows are errors in Python and index errors here too
  errors <- list(
    X_out_of_range_col = quote(x[, 11]),
    X_out_of_range_row = quote(x[11, ]),
    X_string_index = quote(x["a", ]),
    X_three_indices = quote(x[1, 1, 1])
  )
  for (name in names(errors)) {
    for_each_backed(
      name,
      function(case, row, kind) {
        x <- case$adata$X
        expect_equal(row$error$type %in% c("IndexError", "TypeError"), TRUE)
        expect_error(eval(errors[[name]]), class = "anndata_index_error")
      },
      kinds = sparse_kinds
    )
  }
})

# Python's sparse handle rejects negative integers and some other selections
# with a Python-specific error (rows X_negative_int, X_negative_slice and
# X_stop_negative_slice), and R selects them like a matrix
test_that("R selects what Python's sparse handle rejects like a matrix", {
  for_each_backed(
    "X_negative_int",
    function(case, row, kind) {
      # Python gives a TypeError for CSR and the last row for CSC
      expect_equal(is.null(row$error), kind == "csc")
      expect_equal(
        unname(as.matrix(drop_dtype(case$adata$X[-1L, ]))),
        sparse_reference()[-1L, ]
      )
    },
    kinds = sparse_kinds
  )
})

# Python's sparse handle has no len() and no ndim, and R reports shape through
# dim() for every kind of X
test_that("the shape of backed sparse X comes from dim()", {
  for_each_backed(
    "X_len",
    function(case, row, kind) {
      expect_equal(nrow(case$adata$X), 4L)
      expect_equal(length(dim(case$adata$X)), 2L)
    },
    kinds = sparse_kinds
  )
})

# The rows of sparse_dataset() in the table that do not append, which is
# tested with the writing tickets
test_that("sparse_dataset gives a handle like Python's", {
  table <- backed_cases()$sparse_dataset
  for (kind in sparse_kinds) {
    rows <- table[[kind]]
    handle <- sparse_dataset(local_sparse_group(kind)$group)
    expect_s3_class(handle, "backed_sparse")
    expect_equal(dim(handle), unlist(rows$shape$result$value))
    expect_equal(handle$format, rows$format$result$value)
    expect_equal(handle$backend, rows$backend$result$value)
    expect_equal(handle$dtype, rows$dtype$result$value)
    expect_output(print(handle), rows$repr$result$value, fixed = TRUE)
    expect_equal(
      unname(as.matrix(drop_dtype(handle$to_memory()))),
      table_matrix(rows$to_memory$result$value)
    )
    expect_equal(
      unname(as.matrix(drop_dtype(handle[]))),
      table_matrix(rows$all$result$value)
    )
    expect_equal(
      unname(as.matrix(drop_dtype(handle[2:3, , drop = FALSE]))),
      table_matrix(rows$rows$result$value)
    )
    expect_equal(drop_dtype(handle[2, 3]), rows$cell$result$value)
    expect_equal(
      unname(as.matrix(drop_dtype(handle[c(4, 1), c(1, 3), drop = FALSE]))),
      table_matrix(rows$outer$result$value)
    )
    expect_equal(dim(handle[integer(0), , drop = FALSE]), c(0L, 3L))
    expect_equal(rows$to_memory_indices$result$value$indices, "int32")
    expect_equal(rows$len$error$type, "TypeError")
    expect_equal(
      rows$no_cache$result$value,
      paste0("_", toupper(kind), "Dataset")
    )
  }
})

# Python's handle has no setter for shape and group (rows set_shape and
# set_group, an AttributeError), so assigning a field is a read-only error
test_that("a backed sparse handle is read-only", {
  handle <- sparse_dataset(local_sparse_group("csr")$group)
  expect_error(handle$shape <- c(1L, 1L), class = "anndata_read_only_error")
  expect_error(handle[["path"]] <- "Y", class = "anndata_read_only_error")
  expect_equal(dim(handle), c(4L, 3L))
})

# Rows Python rejects with its own errors (X_out_of_range_slice, an IndexError,
# and X_none_index) or selects differently from R (X_negative_slice and
# X_stop_negative_slice are slices, which R spells as positions)
test_that("slice rows of the table have R equivalents", {
  for_each_backed(
    "X_out_of_range_slice",
    function(case, row, kind) {
      # CSR raises an IndexError and CSC gives an empty matrix
      expect_equal(is.null(row$error), kind == "csc")
      expect_error(case$adata$X[10:20, ], class = "anndata_index_error")
    },
    kinds = sparse_kinds
  )
  for (name in c("X_negative_slice", "X_stop_negative_slice")) {
    for_each_backed(
      name,
      function(case, row, kind) {
        rows <- if (name == "X_negative_slice") 2:4 else 1:3
        expect_equal(
          unname(as.matrix(drop_dtype(case$adata$X[rows, ]))),
          sparse_reference()[rows, ]
        )
      },
      kinds = sparse_kinds
    )
  }
  # numpy's newaxis has no R meaning, and NULL selects no rows as for a matrix
  for_each_backed(
    "X_none_index",
    function(case, row, kind) {
      expect_equal(dim(case$adata$X[NULL, , drop = FALSE]), c(0L, 3L))
    },
    kinds = sparse_kinds
  )
})

# Python's sparse_dataset() takes should_cache_indptr by name only (row
# positional), and rejects groups that are not sparse matrices (rows
# not_sparse), here as invalid arguments
test_that("sparse_dataset rejects other arguments and Elements", {
  group <- local_sparse_group("csr")$group
  expect_error(
    sparse_dataset(group, TRUE),
    class = "anndata_invalid_argument_error"
  )
  expect_error(sparse_dataset(1:3), class = "anndata_invalid_argument_error")
  expect_error(sparse_dataset(list()), class = "anndata_invalid_argument_error")
  dir <- withr::local_tempdir()
  path <- file.path(dir, "dense.h5ad")
  write_h5ad(AnnData(matrix(0, 4, 3), uns = list(d = list(a = 1L))), path)
  file <- rhdf5::H5Fopen(path, flags = "H5F_ACC_RDONLY")
  withr::defer(rhdf5::H5Fclose(file))
  for (key in c("X", "uns/d")) {
    elem <- rhdf5::H5Oopen(file, key)
    expect_error(sparse_dataset(elem), class = "anndata_invalid_argument_error")
    rhdf5::H5Oclose(elem)
  }
})
