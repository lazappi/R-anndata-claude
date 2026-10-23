csv_text <- function(path) {
  rawToChar(readBin(path, "raw", file.size(path)))
}

csvs_adata <- function(desc) {
  column <- function(values) {
    values <- unlist(values)
    if (is.character(values)) {
      values
    } else if (is.integer(values)) {
      set_dtype(as.double(values), "int64")
    } else {
      as.double(values)
    }
  }
  uns_value <- function(item) {
    value <- item$value
    switch(
      item$kind,
      scalar = if (is.character(value)) {
        value
      } else if (is.integer(value)) {
        set_dtype(as.double(value), "int64")
      } else {
        value
      },
      vector = column(value),
      matrix = do.call(rbind, lapply(value, unlist)),
      # `Matrix()` would give a diagonal class for the identity
      sparse = methods::as(
        methods::as(do.call(rbind, lapply(value, unlist)), "generalMatrix"),
        "CsparseMatrix"
      ),
      array3 = aperm(
        array(unlist(value), c(2L, 2L, 2L)),
        c(3L, 2L, 1L)
      ),
      dict = lapply(value, function(v) {
        if (is.list(v)) {
          lapply(v, function(w) set_dtype(as.double(w), "int64"))
        } else if (is.integer(v)) {
          set_dtype(as.double(v), "int64")
        } else {
          v
        }
      })
    )
  }
  rows <- function(values) do.call(rbind, lapply(values, unlist))
  names_obs <- unlist(desc$obs_names)
  names_var <- unlist(desc$var_names)
  make_frame <- function(columns, index) {
    frame_from_columns(lapply(columns, column), index)
  }
  mapping <- function(items) lapply(items, function(v) rows(v))
  x <- desc$X
  x_value <- if (is.null(x)) {
    NULL
  } else if (identical(x$kind, "dense")) {
    typed_dense(rows(x$values), "float32")
  } else {
    set_dtype(
      methods::as(
        Matrix::Matrix(rows(x$values), sparse = TRUE),
        "RsparseMatrix"
      ),
      c(data = "float32")
    )
  }
  AnnData(
    X = x_value,
    obs = make_frame(desc$obs, names_obs),
    var = make_frame(desc$var, names_var),
    obsm = mapping(desc$obsm),
    varm = mapping(desc$varm),
    uns = lapply(desc$uns, uns_value),
    shape = if (is.null(x_value)) c(length(names_obs), length(names_var))
  )
}

# Runs `write_csvs()` for a table case and gathers the write warnings
run_csvs_case <- function(case, adata, root) {
  messages <- character()
  args <- list(adata, file.path(root, case$dirname))
  args$skip_data <- case$args$skip_data
  args$sep <- case$args$sep
  withCallingHandlers(
    do.call(write_csvs, args),
    anndata_write_warning = function(w) {
      messages <<- c(messages, cli::ansi_strip(conditionMessage(w)))
      invokeRestart("muffleWarning")
    }
  )
  messages
}

# Why: every `write_csvs` row of the table, the files written (names and
# contents) and the warnings must be Python's. Equal text means pandas reads
# the same values back, which is the acceptance criterion.
test_that("write_csvs() writes the files Python writes", {
  table <- other_formats_table()$write_csvs
  adatas <- lapply(table$adatas, csvs_adata)
  for (case in table$cases) {
    root <- withr::local_tempdir()
    messages <- run_csvs_case(case, adatas[[case$adata]], root)
    expect_equal(
      messages,
      vapply(case$warnings, function(w) w$message, ""),
      info = case$name
    )
    written <- list.files(root, recursive = TRUE)
    expect_setequal(written, names(case$files))
    for (path in written) {
      expect_identical(
        csv_text(file.path(root, path)),
        case$files[[path]]$text,
        info = paste(case$name, path)
      )
    }
  }
})

# Why: pandas shortens floats with `repr`, so R must pick the same digits,
# switch to exponents at the same points and keep `.0` on whole numbers
test_that("format_float() matches Python's repr", {
  expect_identical(
    format_float(c(
      0.1,
      1e16,
      1e-5,
      1.2345678901234568e17,
      5e-324,
      1 / 3,
      100,
      -2.5,
      1e15,
      0,
      -0,
      0.0001,
      NA,
      Inf,
      -Inf,
      NaN
    )),
    c(
      "0.1",
      "1e+16",
      "1e-05",
      "1.2345678901234568e+17",
      "5e-324",
      "0.3333333333333333",
      "100.0",
      "-2.5",
      "1000000000000000.0",
      "0.0",
      "-0.0",
      "0.0001",
      "",
      "inf",
      "-inf",
      ""
    )
  )
  # float32 values are the shortest digits that round trip in float32
  expect_identical(
    format_float(to_float32(c(0.1, 16777216, 3.4028235e38)), float32 = TRUE),
    c("0.1", "16777216.0", "3.4028235e+38")
  )
})

# Why: the csv quoting rules (delimiter, quote and newline, and a lone empty
# field) and the cell formats of each column type, as pandas writes them
test_that("write_csvs() quotes fields and formats column types like pandas", {
  obs <- frame_from_columns(
    list(
      text = c("a,b", "say \"hi\"", NA, "line\nbreak"),
      flag = c(TRUE, FALSE, NA, TRUE),
      level = factor(c("x", NA, "y", "x")),
      count = set_dtype(c(1, 2, NA, 4), "int64")
    ),
    c("c1", "c2", "c3", "c4")
  )
  adata <- AnnData(
    X = matrix(0, 4, 1),
    obs = obs,
    var = frame_from_columns(list(), "g1")
  )
  dir <- withr::local_tempdir()
  adata$write_csvs(dir)
  expect_identical(
    csv_text(file.path(dir, "obs.csv")),
    paste0(
      ",text,flag,level,count\n",
      "c1,\"a,b\",True,x,1\n",
      "c2,\"say \"\"hi\"\"\",False,,2\n",
      "c3,,,y,\n",
      "c4,\"line\nbreak\",True,x,4\n"
    )
  )
})

# Why: Python calls `to_df()` on obsm, so frames and matrices give columns
# named by key and 1-based position, and integer matrices stay integers
test_that("write_csvs() names obsm columns by key and position", {
  adata <- AnnData(
    X = matrix(0, 2, 1),
    obs = frame_from_columns(list(), c("c1", "c2")),
    obsm = list(
      a = matrix(c(1L, 2L, 3L, 4L), 2, 2),
      b = frame_from_columns(list(u = c("p", "q")), c("c1", "c2"))
    )
  )
  dir <- withr::local_tempdir()
  write_csvs(adata, dir)
  expect_identical(
    csv_text(file.path(dir, "obsm.csv")),
    "a1,a2,b1\n1,3,p\n2,4,q\n"
  )
})

# Why: the dict cell is Python's `repr`, including the numpy repr of arrays
# inside it (the Views table's parent holds one)
test_that("write_csvs() writes dicts as Python's repr", {
  adata <- AnnData(
    X = matrix(0, 1, 1),
    uns = list(
      d = list(
        a = c(1, 2.5),
        b = "it's",
        c = c("x", "yy"),
        e = list(f = TRUE),
        g = c(1, 10)
      )
    )
  )
  dir <- withr::local_tempdir()
  write_csvs(adata, dir)
  expect_identical(
    csv_text(file.path(dir, "uns", "d.csv")),
    paste0(
      "\"{'a': array([1. , 2.5]), 'b': \"\"it's\"\", ",
      "'c': array(['x', 'yy'], dtype='<U2'), 'e': {'f': True}, ",
      "'g': array([ 1., 10.])}\"\n"
    )
  )
})

# Why: arrays too long for numpy's one-line repr would wrap, which is not
# reproduced, so they must fail loudly rather than write a different cell
test_that("write_csvs() rejects dicts with arrays it cannot represent", {
  adata <- AnnData(
    X = matrix(0, 1, 1),
    uns = list(d = list(a = as.double(1:40)))
  )
  expect_error(
    write_csvs(adata, withr::local_tempdir()),
    class = "anndata_not_supported_error"
  )
})

# Why: Python removes a `.csv` suffix, creates parents, signals the info log
# and the method is a shortcut for the function
test_that("write_csvs() handles the directory and the method", {
  adata <- AnnData(X = matrix(0, 1, 1))
  root <- withr::local_tempdir()
  messages <- character()
  withCallingHandlers(
    adata$write_csvs(file.path(root, "a", "b.csv")),
    anndata_info_message = function(m) {
      messages <<- c(messages, conditionMessage(m))
    }
  )
  expect_true(file.exists(file.path(root, "a", "b", "obs.csv")))
  expect_true(dir.exists(file.path(root, "a", "b", "uns")))
  expect_match(messages, "writing .csv files to .*b$")
})

# Why: argument checks fail with classed errors before touching the disk
test_that("write_csvs() checks its arguments", {
  adata <- AnnData(X = matrix(0, 1, 1))
  dir <- withr::local_tempdir()
  expect_error(write_csvs(1, dir), class = "anndata_invalid_argument_error")
  expect_error(write_csvs(adata, 1), class = "anndata_invalid_argument_error")
  expect_error(
    write_csvs(adata, dir, skip_data = NA),
    class = "anndata_invalid_argument_error"
  )
  expect_error(
    write_csvs(adata, dir, sep = ";;"),
    class = "anndata_invalid_argument_error"
  )
})

# Why: Python writes only the first 2 dimensions of X and layers, so a 3-D X
# is refused as for the other writers
test_that("write_csvs() refuses 3-D X", {
  adata <- AnnData(X = matrix(0, 2, 2))
  suppressWarnings(adata$X <- array(0, c(2, 2, 2)))
  expect_error(
    write_csvs(adata, withr::local_tempdir()),
    class = "anndata_non_2d_error"
  )
})

# Why: dict cells with values whose Python repr is not reproduced must fail
# rather than write a different cell
test_that("write_csvs() rejects dict values it cannot represent", {
  for (value in list(1i, list(1, 2))) {
    adata <- AnnData(X = matrix(0, 1, 1), uns = list(d = list(a = value)))
    expect_error(
      write_csvs(adata, withr::local_tempdir()),
      class = "anndata_not_supported_error"
    )
  }
})
