# What X holds as a plain matrix, whatever its class
assigned_x <- function(x) unname(as.matrix(drop_dtype(as.matrix(x))))

# The 4 x 3 matrix every backed file starts with (1 to 12 by row)
original_x <- matrix(as.numeric(1:12), nrow = 4, byrow = TRUE)

# The new X of the table (0 to 55 by 5) as the class of `kind`
new_x <- function(kind) {
  x <- matrix(seq(0, 55, by = 5), nrow = 4, byrow = TRUE)
  switch(
    kind,
    dense = x,
    csr = methods::as(methods::as(x, "CsparseMatrix"), "RsparseMatrix"),
    csc = methods::as(x, "CsparseMatrix")
  )
}

# Assigning X to a backed object keeps the file and its mode but ends backed
# mode, and the file is left as it was (rows X_assign_dense, X_assign_csr and
# X_assign_csc, with the assigned class not depending on the file's)
test_that("assigning X ends backed mode and leaves the file alone", {
  for (operation in c("X_assign_dense", "X_assign_csr", "X_assign_csc")) {
    assigned <- sub("X_assign_", "", operation)
    for_each_backed(operation, function(case, row, kind) {
      adata <- case$adata
      adata$X <- new_x(assigned)
      expect_backed_state(adata, row$state_after)
      expect_false(adata$isbacked)
      expect_equal(assigned_x(adata$X), table_matrix(row$result$X$value))
      expect_equal(assigned_x(read_h5ad(case$path)$X), original_x)
    })
  }
})

# Shapes that Python reshapes, fills or warns about still end backed mode
# (rows X_assign_reshape, X_assign_flat, X_assign_scalar and X_assign_3d),
# while a size that cannot be reshaped fails and leaves X on disk
# (row X_assign_small)
test_that("assigning other shapes to a backed X follows Python", {
  values <- list(
    X_assign_reshape = matrix(0, nrow = 3, ncol = 4),
    X_assign_flat = as.numeric(0:11),
    X_assign_scalar = 1,
    X_assign_3d = array(0, c(4, 3, 2))
  )
  for (operation in names(values)) {
    for_each_backed(operation, function(case, row, kind) {
      expect_warning(case$adata$X <- values[[operation]])
      expect_backed_state(case$adata, row$state_after)
      expect_false(case$adata$isbacked)
    })
  }
  for_each_backed("X_assign_small", function(case, row, kind) {
    expect_error(
      suppressWarnings(case$adata$X <- matrix(0, nrow = 2, ncol = 2))
    )
    expect_backed_state(case$adata, row$state_after)
    expect_true(case$adata$isbacked)
  })
})

# Removing X changes nothing on a backed object, because X lives in the file
# (rows X_assign_none and X_del)
test_that("assigning NULL to a backed X is a no-op", {
  for (operation in c("X_assign_none", "X_del")) {
    for_each_backed(operation, function(case, row, kind) {
      adata <- case$adata
      adata$X <- NULL
      expect_backed_state(adata, row$state_after)
      expect_equal(assigned_x(adata$X), original_x)
      expect_equal(assigned_x(read_h5ad(case$path)$X), original_x)
    })
  }
})

# Removing an X that was assigned reads X from the file again, as Python does
# because its X is only in the layers while it is in memory
test_that("removing an assigned X makes the object backed again", {
  case <- local_backed("csr", "r+")
  adata <- case$adata
  adata$X <- new_x("dense")
  expect_false(adata$isbacked)
  adata$X <- NULL
  expect_true(adata$isbacked)
  expect_equal(assigned_x(adata$X), original_x)
})

# The X layer key is the same slot as X (row layers_none_assign)
test_that("assigning layers[[NA]] ends backed mode like X", {
  for_each_backed("layers_none_assign", function(case, row, kind) {
    adata <- case$adata
    adata$layers[[NA]] <- new_x(kind)
    expect_backed_state(adata, row$state_after)
    expect_false(adata$isbacked)
  })
})

# After X was assigned there is no backing file to write to, so write()
# without a filename fails (row write_after_X_assign)
test_that("write() after assigning X asks for a filename", {
  for_each_backed("write_after_X_assign", function(case, row, kind) {
    case$adata$X <- new_x(kind)
    expect_anndata_condition(
      case$adata$write(),
      class = "anndata_invalid_argument_error"
    )
    expect_equal(assigned_x(read_h5ad(case$path)$X), original_x)
  })
})

# Item assignment on dense X writes into the file in "r+" mode, fails in "r"
# mode, and sparse X has none (row X_item)
test_that("X[i, j] <- value writes to a backed dense X in r+ mode", {
  for_each_backed("X_item", function(case, row, kind) {
    adata <- case$adata
    if (kind != "dense") {
      expect_anndata_condition(
        adata$X[1, 1] <- 99,
        class = "anndata_not_supported_error"
      )
    } else if (identical(row$error$type, "OSError")) {
      expect_anndata_condition(
        adata$X[1, 1] <- 99,
        class = "anndata_read_only_error"
      )
    } else {
      adata$X[1, 1] <- 99
      expect_true(adata$isbacked)
      expected <- table_matrix(row$original_after$X$value)
      expect_equal(assigned_x(adata$X), expected)
      expect_equal(assigned_x(read_h5ad(case$path)$X), expected)
      return(invisible(NULL))
    }
    expect_equal(assigned_x(read_h5ad(case$path)$X), original_x)
  })
})

# Item assignment takes every R index form and writes only those cells, so a
# non-square selection checks that the values land in the right place
test_that("X[i, j] <- value takes R index forms", {
  case <- local_backed("dense", "r+")
  adata <- case$adata
  adata$X[c(4, 2), 2:3] <- matrix(c(1, 2, 3, 4), nrow = 2)
  expected <- original_x
  expected[c(4, 2), 2:3] <- matrix(c(1, 2, 3, 4), nrow = 2)
  expect_equal(assigned_x(read_h5ad(case$path)$X), expected)
  # Recycled values, a missing index and negative positions
  adata$X[, -1] <- 0
  expected[, -1] <- 0
  adata$X[3, ] <- c(7, 8, 9)
  expected[3, ] <- c(7, 8, 9)
  expect_equal(assigned_x(read_h5ad(case$path)$X), expected)
  # A repeated position keeps the last value, as for a matrix
  adata$X[c(1, 1), 1] <- c(5, 6)
  expected[c(1, 1), 1] <- c(5, 6)
  expect_equal(assigned_x(adata$X), expected)
  # A vector index has no rows and columns
  expect_anndata_condition(adata$X[1] <- 0, class = "anndata_index_error")
  expect_anndata_condition(
    adata$X[5, 1] <- 0,
    class = "anndata_index_error"
  )
})

# A View of a backed object that gets a new X becomes an independent object
# with that X and no file, and the parent is untouched (row view_X_assign)
test_that("assigning X to a View of a backed object makes it actual", {
  for_each_backed("view_X_assign", function(case, row, kind) {
    view <- case$adata[c(1, 3), c(1, 3)]
    expect_warning(
      view$X <- matrix(0, nrow = 2, ncol = 2),
      class = "anndata_implicit_modification_warning"
    )
    expect_backed_state(view, row$result$view)
    expect_false(view$is_view)
    expect_equal(assigned_x(view$X), matrix(0, nrow = 2, ncol = 2))
    expect_backed_state(case$adata, row$result$parent)
    expect_equal(assigned_x(case$adata$X), original_x)
  })
})

# Any other change to a View of a backed object warns then fails, because
# Python cannot copy a backed object without a filename, and the View stays a
# View (rows view_obs_assign, view_layers_set and view_obs_names_set)
test_that("modifying a View of a backed object fails like Python", {
  changes <- list(
    view_obs_assign = function(v) v$obs$n <- c(1, 2),
    view_layers_set = function(v) v$layers[["n"]] <- matrix(0, 2, 2),
    view_obs_names_set = function(v) v$obs_names <- c("p", "q")
  )
  for (operation in names(changes)) {
    for_each_backed(operation, function(case, row, kind) {
      view <- case$adata[c(1, 3), c(1, 3)]
      expect_anndata_condition(
        suppressWarnings(changes[[operation]](view)),
        class = "anndata_invalid_argument_error"
      )
      expect_true(view$is_view)
      expect_backed_state(case$adata, row$state_after)
    })
  }
  # The warning comes first, as in Python, when the change has one
  case <- local_backed("dense", "r")
  view <- case$adata[c(1, 3), c(1, 3)]
  expect_warning(
    try(view$obs$n <- c(1, 2), silent = TRUE),
    class = "anndata_implicit_modification_warning"
  )
})

# R does not wrap the accessor in a View, so `view$X[1, 1] <- 5` is an
# assignment of X to the View and not a silent no-op as in Python (row
# view_X_item, deviation documented in the Views help)
test_that("item assignment to a backed View's X makes it actual", {
  case <- local_backed("dense", "r+")
  view <- case$adata[c(1, 3), c(1, 3)]
  expect_warning(
    view$X[1, 1] <- 5,
    class = "anndata_implicit_modification_warning"
  )
  expect_false(view$is_view)
  expect_equal(assigned_x(read_h5ad(case$path)$X), original_x)
})

# Bool and integer dense X are written with their own HDF5 types, and the
# file keeps its dtype after an item assignment
test_that("X[i, j] <- value keeps the dtype of bool and integer X", {
  for (x in list(
    matrix(c(TRUE, FALSE, TRUE, TRUE, FALSE, FALSE), nrow = 2),
    set_dtype(matrix(1:6, nrow = 2), "int32")
  )) {
    path <- withr::local_tempfile(fileext = ".h5ad")
    write_h5ad(AnnData(x), path)
    adata <- read_h5ad(path, backed = "r+")
    withr::defer(adata$file$close())
    before <- attr(read_h5ad(path)$X, "anndata_dtype")
    new <- if (is.logical(x)) !x[2, 3] else 42L
    adata$X[2, 3] <- new
    after <- read_h5ad(path)$X
    expect_equal(attr(after, "anndata_dtype"), before)
    expected <- unclass(drop_dtype(x))
    expected[2, 3] <- new
    expect_equal(unname(as.matrix(drop_dtype(after))), unname(expected))
  }
})

# A View of an object whose X was assigned is not backed any more, so it
# behaves as a View of an in-memory object and becomes actual on a change
test_that("a View of a backed object with assigned X is an ordinary View", {
  case <- local_backed("dense", "r+")
  case$adata$X <- new_x("dense")
  view <- case$adata[c(1, 3), c(1, 3)]
  expect_warning(
    view$obs$n <- c(1, 2),
    class = "anndata_implicit_modification_warning"
  )
  expect_false(view$is_view)
})

# Other slots of a View of a backed object fail the same way
test_that("changing uns or obsm of a backed View fails", {
  case <- local_backed("dense", "r")
  view <- case$adata[c(1, 3), c(1, 3)]
  expect_anndata_condition(
    suppressWarnings(view$uns[["a"]] <- 1),
    class = "anndata_invalid_argument_error"
  )
  expect_anndata_condition(
    suppressWarnings(view$obsm[["m"]] <- matrix(0, 2, 2)),
    class = "anndata_invalid_argument_error"
  )
})
