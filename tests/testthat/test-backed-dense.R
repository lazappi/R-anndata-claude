dense_reference <- function() {
  drop_dtype(matrix(as.numeric(1:12), nrow = 4, byrow = TRUE))
}

# Every R index form must select like the same matrix in memory, including the
# forms Python's dense handle rejects (unsorted, repeated and negative indices)
test_that("[ on backed dense X selects like a matrix for every index form", {
  case <- local_backed("dense", "r")
  x <- case$adata$X
  ref <- dense_reference()
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
    list(2.9, 1)
  )
  for (form in forms) {
    for (drop in c(TRUE, FALSE)) {
      expect_equal(
        drop_dtype(x[form[[1]], form[[2]], drop = drop]),
        ref[form[[1]], form[[2]], drop = drop],
        info = paste(deparse(form), drop)
      )
    }
  }
  expect_equal(drop_dtype(x[, 2L]), ref[, 2L])
  expect_equal(drop_dtype(x[3L, ]), ref[3L, ])
  expect_equal(drop_dtype(x[TRUE, TRUE]), ref)
  expect_equal(drop_dtype(x[]), ref)
  expect_equal(drop_dtype(x[5L]), ref[5L])
  expect_equal(drop_dtype(x[ref > 6]), ref[ref > 6])
})

# Out-of-range, missing and named indices raise an index error like the other
# subsetting code, and a third index is rejected
test_that("[ on backed dense X rejects invalid indices", {
  case <- local_backed("dense", "r")
  x <- case$adata$X
  expect_error(x[5L, ], class = "anndata_index_error")
  expect_error(x[, 4L], class = "anndata_index_error")
  expect_error(x[NA_integer_, ], class = "anndata_index_error")
  expect_error(x["a", ], class = "anndata_index_error")
  expect_error(x[rep(TRUE, 5), ], class = "anndata_index_error")
  expect_error(x[1, 1, 1], class = "anndata_index_error")
})

# Values read from backed X carry the dtype record of the file, as in read_h5ad
test_that("values read from backed dense X keep the on-disk dtype", {
  case <- local_backed("dense", "r")
  x <- case$adata$X
  expect_equal(get_dtype(x[1:2, ]), "float32")
  expect_equal(get_dtype(x[3L, 2L]), "float32")
  expect_equal(get_dtype(x[c(2L, 2L), ]), "float32")
  expect_equal(get_dtype(as.matrix(x)), "float32")
  in_memory <- read_h5ad(case$path)
  expect_equal(as.matrix(x), in_memory$X)
})

# Reading after close() reopens the file, and the shape is known without
# reading any values
test_that("backed dense X reads after the file was closed", {
  case <- local_backed("dense", "r")
  x <- case$adata$X
  case$adata$file$close()
  expect_equal(dim(x), c(4L, 3L))
  expect_false(case$adata$file$is_open)
  expect_equal(drop_dtype(x[2L, 3L]), 6)
  expect_true(case$adata$file$is_open)
})

# A View of a backed object reads only its subset of X and does not load the
# whole array (the table's view rows)
test_that("a View of a backed object reads its subset of X", {
  case <- local_backed("dense", "r")
  selections <- list()
  original <- array_read
  local_mocked_bindings(
    array_read = function(store, path, selection = NULL, call = NULL) {
      selections[[length(selections) + 1L]] <<- selection
      original(store, path, selection, call)
    }
  )
  view <- case$adata[c("z", "x"), c("r", "p")]
  expect_true(view$is_view)
  expect_equal(drop_dtype(view$X), matrix(c(12, 10, 6, 4), 2, 2, byrow = TRUE))
  expect_equal(dim(view), c(2L, 2L))
  # Only the rows 2 and 4 and columns 1 and 3 were read, in sorted order
  expect_true(length(selections) > 0L)
  for (selection in selections) {
    expect_equal(selection, list(c(2L, 4L), c(1L, 3L)))
  }
})

# The table's dense X rows, as R does them. Row numbers are Python's plus one
# and results are compared as matrices
test_that("the dense X rows of the operations table match", {
  for_each_backed(
    "X_asarray",
    function(case, row, kind) {
      expect_equal(
        unname(drop_dtype(as.matrix(case$adata$X))),
        table_matrix(row$result$value)
      )
    },
    kinds = "dense"
  )
  for_each_backed(
    "X_empty_tuple",
    function(case, row, kind) {
      expect_equal(
        unname(drop_dtype(case$adata$X[])),
        table_matrix(row$result$value)
      )
    },
    kinds = "dense"
  )
  slices <- list(
    X_row = quote(x[2, ]),
    X_col = quote(x[, 2]),
    X_slices = quote(x[2:3, 1:2])
  )
  for (name in names(slices)) {
    for_each_backed(
      name,
      function(case, row, kind) {
        x <- case$adata$X
        expected <- unlist(row$result$value)
        values <- unname(drop_dtype(eval(slices[[name]])))
        if (is.list(row$result$value[[1]])) {
          expected <- table_matrix(row$result$value)
        }
        expect_equal(values, expected, info = name)
      },
      kinds = "dense"
    )
  }
  for_each_backed(
    "X_len",
    function(case, row, kind) {
      expect_equal(nrow(case$adata$X), row$result)
    },
    kinds = "dense"
  )
  for_each_backed(
    "X_ndim",
    function(case, row, kind) {
      expect_equal(length(dim(case$adata$X)), row$result)
    },
    kinds = "dense"
  )
  for_each_backed(
    "X_handle",
    function(case, row, kind) {
      x <- case$adata$X
      expect_equal(dim(x), unlist(row$result$shape))
      expect_equal(x$dtype, row$result$dtype)
      expect_null(row$result$format)
    },
    kinds = "dense"
  )
  # Python returns an empty array and nothing about the file changes
  for_each_backed(
    "X_empty_list",
    function(case, row, kind) {
      empty <- case$adata$X[integer(0), , drop = FALSE]
      expect_length(empty, 0L)
      expect_equal(dim(empty), c(0L, 3L))
      expect_backed_state(case$adata, row$state_after)
    },
    kinds = "dense"
  )
})

# Python's dense handle rejects unsorted, repeated and negative lists (rows
# X_duplicate_rows and X_negative_list, a TypeError). R accepts them and
# selects like a matrix, as the spec asks for every R index form
test_that("R accepts the lists Python's dense handle rejects", {
  for_each_backed(
    "X_duplicate_rows",
    function(case, row, kind) {
      expect_equal(row$error$type, "TypeError")
      expect_equal(
        unname(drop_dtype(case$adata$X[c(1, 1), ])),
        rbind(1:3, 1:3)
      )
    },
    kinds = "dense"
  )
  for_each_backed(
    "X_negative_list",
    function(case, row, kind) {
      expect_equal(row$error$type, "TypeError")
      expect_equal(
        unname(drop_dtype(case$adata$X[c(4, 1), ])),
        rbind(10:12, 1:3)
      )
    },
    kinds = "dense"
  )
})

# Printing a backed array shows its shape and dtype without reading values
test_that("printing backed dense X does not read the array", {
  case <- local_backed("dense", "r")
  local_mocked_bindings(
    array_read = function(...) stop("values were read")
  )
  expect_output(
    print(case$adata$X),
    "Backed dense array, shape (4, 3)",
    fixed = TRUE
  )
})

# x[i] is a vector index, which reads the whole array (documented in
# R/backed-dense.R), and it matches a matrix
test_that("vector indexing of backed dense X matches a matrix", {
  x <- local_backed("dense", "r")$adata$X
  ref <- dense_reference()
  expect_equal(drop_dtype(x[c(1, 12)]), ref[c(1, 12)])
  expect_equal(drop_dtype(x[-1]), ref[-1])
})
