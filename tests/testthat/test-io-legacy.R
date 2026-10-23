# Reads the Element at `path` of a legacy fixture, returning the value and the
# paths of the old format warnings raised (each is muffled, as Python records
# them without stopping)
read_legacy_elem <- function(file, path, env = parent.frame()) {
  if (endsWith(file, ".zarr")) {
    store <- zarr_open(file.path(legacy_zarr_dir(), file))
  } else {
    store <- rhdf5::H5Fopen(
      fixture_path(file.path("legacy", file)),
      flags = "H5F_ACC_RDONLY"
    )
    withr::defer(rhdf5::h5closeAll(), envir = env)
  }
  warned <- character()
  future <- character()
  value <- withCallingHandlers(
    read_elem(store, path),
    anndata_old_format_warning = function(cnd) {
      warned <<- c(warned, cnd$path)
      rlang::cnd_muffle(cnd)
    },
    anndata_future_warning = function(cnd) {
      future <<- c(future, conditionMessage(cnd))
      rlang::cnd_muffle(cnd)
    }
  )
  list(value = value, warned = sort(warned), future = sort(future))
}

# The paths Python warned about under `prefix` (the Element itself and members)
table_warned <- function(file, prefix) {
  messages <- vapply(
    legacy_table()$fixtures[[file]]$warnings,
    function(w) w$message,
    character(1)
  )
  paths <- sub(
    "^Element '(.*)' was written without encoding metadata[.]$",
    "\\1",
    messages[grepl("^Element '", messages)]
  )
  sort(paths[paths == prefix | startsWith(paths, paste0(prefix, "/"))])
}

# A dense table entry (`values` are rows) as an R array
table_dense <- function(entry) {
  if (length(entry$shape) == 1L) {
    return(unlist(entry$values))
  }
  table_matrix(entry$values)
}

# Why: unencoded Elements are read as `read_basic` does, with values and one
# old format warning per Element equal to what Python 0.13.4 gave for the same
# files (the committed expectation table), for the 0.6.22 and 0.7.8 releases
test_that("unencoded dense Elements read to the values Python reads", {
  values <- legacy_table()$fixtures[["0.6.22-dense.h5ad"]]$values
  cases <- list(
    list("/X", values$X),
    list("/layers/counts", values$layers$counts),
    list("/obsm/X_pca", values$obsm$X_pca),
    list("/varm/PCs", values$varm$PCs),
    list("/uns/arr", values$uns$arr)
  )
  for (case in cases) {
    result <- read_legacy_elem("0.6.22-dense.h5ad", case[[1]])
    expect_equal(
      unname(drop_dtype(result$value)),
      unname(table_dense(case[[2]])),
      tolerance = 1e-6,
      info = case[[1]]
    )
    expect_equal(result$warned, table_warned("0.6.22-dense.h5ad", case[[1]]))
  }
  # float32 on disk is kept
  x <- read_legacy_elem("0.6.22-dense.h5ad", "/X")$value
  expect_equal(get_dtype(x), "float32")
})

# Why: 0.6.22 stores scalars and strings as 1-element arrays, which Python reads
# as arrays (not scalars), so they must keep a dim of 1 to be written back as
# arrays
test_that("1-element arrays of 0.6.22 stay arrays", {
  result <- read_legacy_elem("0.6.22-dense.h5ad", "/uns")
  expect_equal(result$warned, table_warned("0.6.22-dense.h5ad", "/uns"))
  # The `*_categories` members are cleaned up later (legacy-formats/04)
  expect_setequal(
    names(result$value),
    c("arr", "cat_categories", "neighbors", "scalar", "str", "str_categories")
  )
  expect_equal(dim(result$value$scalar), 1L)
  expect_equal(as.vector(result$value$scalar), 3)
  expect_equal(dim(result$value$str), 1L)
  expect_equal(as.vector(result$value$str), "hello")
  n <- result$value$neighbors$params$n
  expect_equal(dim(n), 1L)
  expect_equal(as.vector(n), 3)
  # Python gives its two connectivity matrices as csr_matrix
  expect_s4_class(result$value$neighbors$connectivities, "dgRMatrix")
})

# Why: 0.7.x writes scalars and strings as 0-d datasets, which Python reads as
# a numpy scalar and a str
test_that("0-d datasets of 0.7.8 read as scalars", {
  for (file in c("0.7.8-dense.h5ad", "0.7.8-dense.zarr")) {
    result <- read_legacy_elem(file, "/uns")
    expect_equal(result$warned, table_warned(file, "/uns"), info = file)
    expect_null(dim(result$value$scalar))
    expect_equal(as.vector(result$value$scalar), 3, info = file)
    expect_equal(result$value$str, "hello", info = file)
    expect_equal(as.vector(result$value$neighbors$params$n), 3, info = file)
    expect_equal(as.vector(result$value$arr), 0:2, info = file)
  }
})

# Why: the zarr store of 0.7.8 has the same unencoded Elements as the h5ad file
# and Python warns for the same paths
test_that("unencoded Elements read from a zarr store", {
  values <- legacy_table()$fixtures[["0.7.8-dense.zarr"]]$values
  for (case in list(
    list("/layers/counts", values$layers$counts),
    list("/obsm/X_pca", values$obsm$X_pca)
  )) {
    result <- read_legacy_elem("0.7.8-dense.zarr", case[[1]])
    expect_equal(
      unname(drop_dtype(result$value)),
      unname(table_dense(case[[2]])),
      tolerance = 1e-6,
      info = case[[1]]
    )
    expect_equal(result$warned, table_warned("0.7.8-dense.zarr", case[[1]]))
  }
})

# Why: h5sparse groups (a group with `h5sparse_format` and `h5sparse_shape`)
# are matrices of the stated format, not dicts, and Python warns once for the
# group
test_that("h5sparse groups read to a CSR matrix", {
  values <- legacy_table()$fixtures[["0.6.22-sparse.h5ad"]]$values
  cases <- list(
    list("/X", values$X),
    list("/layers/counts", values$layers$counts),
    list("/uns/neighbors/connectivities", values$obsp$connectivities),
    list("/uns/neighbors/distances", values$obsp$distances)
  )
  for (case in cases) {
    result <- read_legacy_elem("0.6.22-sparse.h5ad", case[[1]])
    expect_s4_class(result$value, "dgRMatrix")
    expect_equal(
      unname(as.matrix(drop_dtype(result$value))),
      unname(table_matrix(case[[2]]$values)),
      tolerance = 1e-6,
      info = case[[1]]
    )
    expect_equal(result$warned, table_warned("0.6.22-sparse.h5ad", case[[1]]))
  }
})

# Why: h5sparse_format picks CSC too, and the group is read for any attribute
# value Python's `sparse_dataset` accepts
test_that("an h5sparse group with a csc format reads to a CSC matrix", {
  path <- withr::local_tempfile(fileext = ".h5")
  rhdf5::h5createFile(path)
  store <- rhdf5::H5Fopen(path)
  withr::defer(rhdf5::h5closeAll())
  m <- methods::as(
    Matrix::Matrix(
      matrix(c(1, 0, 2, 0, 3, 4), nrow = 2),
      sparse = TRUE
    ),
    "CsparseMatrix"
  )
  group <- rhdf5::H5Gcreate(store, "m")
  set_elem_attr(group, "h5sparse_format", "csc")
  attr_write(group, "h5sparse_shape", c(2L, 3L), scalar = FALSE)
  write_dataset(group, "data", m@x)
  write_dataset(group, "indices", m@i)
  write_dataset(group, "indptr", m@p)
  rhdf5::H5Gclose(group)

  warned <- FALSE
  value <- withCallingHandlers(
    read_elem(store, "m"),
    anndata_old_format_warning = function(cnd) {
      warned <<- TRUE
      rlang::cnd_muffle(cnd)
    }
  )
  expect_true(warned)
  expect_s4_class(value, "dgCMatrix")
  expect_equal(unname(as.matrix(drop_dtype(value))), as.matrix(m))
})

# Why: a missing shape attribute must be a classed error, not an rhdf5 failure
test_that("an h5sparse group without a shape raises an error", {
  store <- local_h5_store()
  group <- rhdf5::H5Gcreate(store, "m")
  set_elem_attr(group, "h5sparse_format", "csr")
  rhdf5::H5Gclose(group)
  expect_anndata_condition(
    suppressWarnings(read_elem(store, "m")),
    "anndata_io_registry_error"
  )
})

# Why: the warning is a classed condition naming the path, as Python's
# OldFormatWarning does
test_that("the old format warning is classed and names the path", {
  store <- local_h5_store()
  write_elem(store, "d", list(a = 1L))
  rhdf5::H5Adelete(rhdf5::H5Gopen(store, "d"), "encoding-type")
  rhdf5::H5Adelete(rhdf5::H5Gopen(store, "d"), "encoding-version")
  cnd <- expect_warning(
    read_elem(store, "d"),
    class = "anndata_old_format_warning"
  )
  expect_s3_class(cnd, "anndata_warning")
  expect_equal(cnd$path, "/d")
  expect_match(conditionMessage(cnd), "without encoding metadata", fixed = TRUE)
})

# Why: writing always uses the current encodings, so what was read from an
# unencoded Element is written with the encoding of its value
test_that("unencoded Elements are written back with current encodings", {
  value <- read_legacy_elem("0.6.22-dense.h5ad", "/uns")$value
  store <- local_h5_store()
  write_elem(store, "uns", value)
  expect_equal(
    read_elem_attr(rhdf5::H5Gopen(store, "uns"), "encoding-type"),
    "dict"
  )
  back <- read_elem(store, "uns")
  expect_equal(back$arr, value$arr)
  expect_equal(dim(back$scalar), 1L)
})

# The paths Python gave a "very old version" warning for (compound datasets)
table_very_old <- function(file) {
  messages <- vapply(
    legacy_table()$fixtures[[file]]$warnings,
    function(w) w$message,
    character(1)
  )
  old <- messages[grepl("was written with a very old version", messages)]
  sort(sub("^'(.*)' was written.*$", "\\1", old))
}

# The paths under a prefix that warned in R, whichever message Python used
frame_warnings <- function(paths, prefix) {
  sort(paths[paths == prefix | startsWith(paths, paste0(prefix, "/"))])
}

legacy_frame_files <- c(
  "0.6.22-dense.h5ad",
  "0.6.22-sparse.h5ad",
  "0.7.8-dense.h5ad",
  "0.7.8-sparse.h5ad",
  "0.7.8-dense.zarr",
  "0.7.8-sparse.zarr"
)

# Why: obs and var of every legacy layout (a compound dataset in 0.6.22 and a
# dataframe 0.1.0 group in 0.7.8, for h5ad and zarr) must read to the index,
# index name, column order, categories and values Python gave, and Python's
# warnings for the frames and their members must be raised
test_that("legacy obs and var read to the values in the table", {
  for (file in legacy_frame_files) {
    result <- read_legacy_elem(file, "/")
    values <- legacy_table()$fixtures[[file]]$values
    for (name in c("obs", "var")) {
      expect_matches_table_frame(
        result$value[[name]],
        values[[name]],
        paste(file, name)
      )
      expect_identical(
        frame_index_name(result$value[[name]]),
        values[[name]]$index_name,
        info = paste(file, name)
      )
      prefix <- paste0("/", name)
      expected <- sort(c(
        table_warned(file, prefix),
        intersect(table_very_old(file), prefix)
      ))
      expect_equal(
        frame_warnings(result$warned, prefix),
        expected,
        info = paste(file, name)
      )
    }
  }
})

# Why: 0.6.22 kept categories in `uns` and `_clean_uns` removes them, leaving
# the other members as Python does
test_that("categories in uns are removed once they are applied", {
  for (file in c("0.6.22-dense.h5ad", "0.6.22-sparse.h5ad")) {
    uns <- read_legacy_elem(file, "/")$value$uns
    expect_setequal(
      names(uns),
      names(legacy_table()$fixtures[[file]]$values$uns)
    )
    expect_false(any(endsWith(names(uns), "_categories")))
  }
})

# Why: `_clean_uns` only applies categories where every code is in range and
# leaves other keys alone, which is how Python finds the axis they were for
test_that("clean_legacy_uns applies categories only where the codes fit", {
  obs <- S4Vectors::DataFrame(
    a = c(0L, 1L, 2L),
    b = c(0L, 5L, 1L),
    row.names = c("x", "y", "z")
  )
  var <- S4Vectors::DataFrame(a = c(0L, 1L), row.names = c("p", "q"))
  uns <- list(
    a_categories = c("u", "v", "w"),
    b_categories = c("u", "v"),
    other = 1L
  )
  cleaned <- clean_legacy_uns(obs, var, uns, rlang::current_env())
  expect_equal(as.character(cleaned$obs$a), c("u", "v", "w"))
  expect_equal(as.character(cleaned$var$a), c("u", "v"))
  expect_equal(cleaned$obs$b, c(0L, 5L, 1L))
  expect_equal(names(cleaned$uns), c("b_categories", "other"))
})

# Why: Python wraps a single category kept in `uns` in a list
test_that("clean_legacy_uns accepts a single category", {
  obs <- S4Vectors::DataFrame(a = c(0L, 0L), row.names = c("x", "y"))
  cleaned <- clean_legacy_uns(
    obs,
    NULL,
    list(a_categories = "only"),
    rlang::current_env()
  )
  expect_equal(as.character(cleaned$obs$a), c("only", "only"))
  expect_length(cleaned$uns, 0L)
})

# A copy of the 0.7.8 h5ad fixture opened for editing
local_edited_legacy <- function(env = parent.frame()) {
  path <- withr::local_tempfile(fileext = ".h5ad", .local_envir = env)
  file.copy(fixture_path("legacy/0.7.8-dense.h5ad"), path)
  store <- rhdf5::H5Fopen(path)
  withr::defer(rhdf5::h5closeAll(), envir = env)
  store
}

# Why: the `ordered` flag on the categories of a dataframe 0.1.0 column decides
# whether the factor is ordered, as in Python's `read_series`
test_that("dataframe 0.1.0 reads ordered categories", {
  store <- local_edited_legacy()
  node <- rhdf5::H5Oopen(store, "obs/__categories/cat")
  rhdf5::H5Adelete(node, "ordered")
  attr_write(node, "ordered", TRUE)
  rhdf5::H5Oclose(node)
  df <- suppressWarnings(read_elem(store, "/obs"))
  expect_s3_class(df$cat, "ordered")
  expect_false(is.ordered(df$str))
})

# Why: a column that is shorter than the index is a corrupt file and must be a
# classed error naming the dataframe
test_that("dataframe 0.1.0 with a short column raises", {
  store <- local_edited_legacy()
  rhdf5::H5Ldelete(store, "obs/num")
  group <- rhdf5::H5Gopen(store, "obs")
  write_dataset(group, "num", as_array(c(1, 2)))
  rhdf5::H5Gclose(group)
  err <- expect_anndata_condition(
    suppressWarnings(read_elem(store, "/obs")),
    "anndata_io_registry_error"
  )
  expect_identical(err$path, "/obs")
})

# Why: the categories of a dataframe 0.1.0 column are found through an HDF5
# object reference and the `ordered` flag of the categories decides the class
test_that("dataframe 0.1.0 columns read categories through references", {
  result <- read_legacy_elem("0.7.8-dense.h5ad", "/obs")
  cat <- result$value$cat
  expect_s3_class(cat, "factor")
  expect_equal(levels(cat), c("a", "b", "c"))
  expect_false(is.ordered(cat))
  expect_equal(colnames(result$value), c("cat", "num", "str"))
})

legacy_raw_files <- c(
  "0.6.22-dense.h5ad",
  "0.6.22-sparse.h5ad",
  "0.7.8-dense.h5ad",
  "0.7.8-sparse.h5ad",
  "0.7.8-dense.zarr",
  "0.7.8-sparse.zarr"
)

# Why: the legacy `raw.X`/`raw.var`/`raw.varm` members of 0.6.22 and the raw
# group of 0.7.8 must give the Raw values of the table, and 0.6.22 must raise
# Python's old format warnings for them
test_that("legacy raw reads to the values in the table", {
  for (file in legacy_raw_files) {
    result <- read_legacy_elem(file, "/")
    expected <- legacy_table()$fixtures[[file]]$values$raw
    raw <- result$value$raw
    expect_false(is.null(raw), info = file)
    expect_equal(dim(raw$X), unlist(expected$shape), info = file)
    expect_equal(
      unname(as.matrix(drop_dtype(raw$X))),
      unname(table_matrix(expected$X$values)),
      tolerance = 1e-6,
      info = file
    )
    expect_equal(
      rownames(raw$var),
      as.character(unlist(expected$var$index)),
      info = file
    )
    expect_equal(
      unname(drop_dtype(raw$var$vnum)),
      unlist(expected$var$columns$vnum$values),
      info = file
    )
    expect_equal(
      unname(drop_dtype(raw$varm$PCs)),
      unname(table_dense(expected$varm$PCs)),
      tolerance = 1e-6,
      info = file
    )
    expect_equal(
      frame_warnings(result$warned, "/raw.var"),
      sort(c(
        table_warned(file, "/raw.var"),
        intersect(table_very_old(file), "/raw.var")
      )),
      info = file
    )
    for (prefix in c("/raw.X", "/raw.varm", "/raw")) {
      expect_equal(
        frame_warnings(result$warned, prefix),
        table_warned(file, prefix),
        info = paste(file, prefix)
      )
    }
  }
})

# Why: a file with a `raw` group and `raw.X` is ambiguous and Python raises
test_that("a store with both legacy and current raw is an error", {
  store <- local_edited_legacy()
  # Python's check looks at any `raw.` key, not only `raw.X`
  group <- rhdf5::H5Gcreate(store, "raw.varm")
  rhdf5::H5Gclose(group)
  expect_anndata_condition(
    suppressWarnings(read_elem(store, "/")),
    "anndata_io_registry_error"
  )
})

# Why: Python only moves 2-D values, so a 1-D `distances` and a `uns` with no
# `neighbors` are left alone without a warning
test_that("move_adjacency_matrices skips values that are not matrices", {
  call <- rlang::current_env()
  slots <- list(uns = list(neighbors = list(distances = 1:3, params = 1L)))
  expect_no_warning(moved <- move_adjacency_matrices(slots, call))
  expect_identical(moved, slots)
  slots <- list(uns = list(a = 1L))
  expect_no_warning(moved <- move_adjacency_matrices(slots, call))
  expect_identical(moved, slots)
})

# Why: adjacency matrices kept in `uns[["neighbors"]]` move to `obsp` with
# Python's FutureWarning, one per matrix, for every release and format
test_that("neighbors matrices move from uns to obsp", {
  files <- c(
    "0.6.22-dense.h5ad",
    "0.6.22-sparse.h5ad",
    "0.7.8-dense.h5ad",
    "0.10.9-neighbors.h5ad",
    "0.10.9-neighbors.zarr"
  )
  for (file in files) {
    result <- read_legacy_elem(file, "/")
    expected <- legacy_table()$fixtures[[file]]$values
    expect_setequal(names(result$value$obsp), names(expected$obsp))
    expect_false(any(
      c("connectivities", "distances") %in% names(result$value$uns$neighbors)
    ))
    for (key in names(expected$obsp)) {
      expect_equal(
        unname(as.matrix(drop_dtype(result$value$obsp[[key]]))),
        unname(table_matrix(expected$obsp[[key]]$values)),
        tolerance = 1e-6,
        info = paste(file, key)
      )
    }
    messages <- vapply(
      legacy_table()$fixtures[[file]]$warnings,
      function(w) if (w$category == "FutureWarning") w$message else "",
      character(1)
    )
    keys <- sub(
      "^Moving element from .uns\\['neighbors'\\]\\['(.*)'\\] to.*$",
      "\\1",
      messages[nzchar(messages)]
    )
    got <- sub(
      "^Moving element from .uns\\['neighbors'\\]\\['(.*)'\\] to.*$",
      "\\1",
      result$future
    )
    expect_setequal(got, keys)
    expect_length(got, length(keys))
  }
})

# Why: an unencoded root is how every 0.6 and 0.7 file starts, and Python
# reads it without a warning for the root itself, but a root with no obs gives
# nothing to build an AnnData from
test_that("an unencoded root without obs is a legacy error", {
  path <- withr::local_tempfile(fileext = ".h5ad")
  rhdf5::h5createFile(path)
  expect_error(read_h5ad(path), class = "anndata_legacy_format_error")
})

# Old scanpy wrote `obsm` and `varm` as compound datasets with array-valued
# fields, which Python's constructor turns into a mapping of the fields
test_that("compound obsm and varm read as a mapping of matrices", {
  skip_if_no_python()
  path <- withr::local_tempfile(fileext = ".h5ad")
  run_python("write_compound_obsm.py", path)
  adata <- quietly_read(function() read_h5ad(path))
  expect_named(adata$obsm, c("X_pca", "X_umap"))
  expect_equal(
    as.vector(t(drop_dtype(adata$obsm[["X_pca"]]))),
    as.numeric(0:5)
  )
  expect_equal(dim(adata$obsm[["X_umap"]]), c(3L, 3L))
  expect_equal(adata$obsm[["X_umap"]][2, 3], 2.5, ignore_attr = TRUE)
  # float32 is recorded when the compound size determines the field widths
  expect_identical(get_dtype(adata$obsm[["X_pca"]]), "float32")
  expect_named(adata$varm, "PCs")
  expect_equal(dim(adata$varm[["PCs"]]), c(2L, 2L))
})

# The other layouts of unencoded datasets that Python's `read_dataset` handles,
# read from the `uns` of the file above (the 2^60 field is read on its own)
test_that("unencoded strings and compound datasets read as Python does", {
  skip_if_no_python()
  path <- withr::local_tempfile(fileext = ".h5ad")
  run_python("write_compound_obsm.py", path)
  uns <- quietly_read(function() read_h5ad(path))$uns
  # Old datasets have a fixed-length string as a one element array, which
  # Python reads as a scalar (variable-length strings and longer arrays stay)
  expect_null(dim(uns$one_fixed))
  expect_identical(as.vector(uns$one_fixed), "abc")
  expect_identical(dim(uns$one_vlen), 1L)
  expect_identical(as.vector(uns$three_fixed), c("a", "b", "c"))
  # A compound without array fields is a rec-array
  expect_s3_class(uns$plain, "data.frame")
  expect_named(uns$plain, c("a", "b"))
  # Array fields give matrices and the other fields stay vectors
  expect_equal(dim(uns$mixed$m), c(2L, 2L))
  expect_length(uns$mixed$s, 2L)
  # Widths that the compound size does not determine leave no dtype record
  expect_null(get_dtype(uns$ambiguous$p))
  expect_equal(dim(uns$ambiguous$p), c(2L, 2L))
  # Too many fields to try every width
  expect_null(compound_float_widths(NULL, "/x", rep(1L, 13L)))
  # Complex numbers are the compound of `r` and `i`
  expect_identical(as.vector(uns$complex), c(1 + 2i, 3 + 4i))
})

# A 64-bit field of a compound with array fields is checked for precision as
# in the other readers
test_that("a compound int64 field beyond 2^53 is an error", {
  skip_if_no_python()
  path <- withr::local_tempfile(fileext = ".h5ad")
  big <- withr::local_tempfile(fileext = ".h5")
  run_python("write_compound_obsm.py", path, big)
  store <- rhdf5::H5Fopen(big, flags = "H5F_ACC_RDONLY")
  withr::defer(rhdf5::H5Fclose(store))
  expect_anndata_condition(
    read_unencoded_compound(store, "/big", rlang::current_env()),
    "anndata_dtype_overflow_error"
  )
})
