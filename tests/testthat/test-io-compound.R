# The compiled helper of ADR 0008, which rhdf5 cannot replace: it reads the
# member types of compound datasets and writes compound datasets whose types
# h5py then sees exactly.

# What `compound_members()` should say for one field, from h5py's own report
# (`compound_types.py`), so expectations are never guessed
expected_member <- function(field) {
  dtype <- field$dtype
  if (!is.null(field$string)) {
    return(list(
      class = "string",
      variable = is.null(field$string$length),
      utf8 = field$string$encoding == "utf-8",
      # a variable-length string is a pointer, 8 bytes
      size = field$string$length %||% 8L
    ))
  }
  # h5py reports a FALSE/TRUE enum as numpy bool
  if (dtype == "bool") {
    return(list(class = "enum", size = 1L))
  }
  # numpy names native types by bits ("int32") and byte-ordered ones by bytes
  size <- as.integer(gsub("\\D", "", dtype))
  if (grepl("^(u?int|float)", dtype)) {
    size <- size %/% 8L
  }
  if (grepl("f", dtype)) {
    return(list(class = "float", size = size))
  }
  list(
    class = "integer",
    size = size,
    sign = if (grepl("u", dtype)) "unsigned" else "signed"
  )
}

h5py_compound <- function(file, dataset) {
  out <- run_python("compound_types.py", file, dataset)
  jsonlite::fromJSON(paste(out, collapse = ""), simplifyVector = FALSE)
}

# Reads: every Python-written rec-array fixture gives the member names, classes,
# sizes, signs and string kinds that h5py reports
test_that("compound_members() reads the member types of Python rec-arrays", {
  skip_if_no_python()
  cases <- c(
    "rec_array_basic",
    "rec_array_widths",
    "rec_array_rank_genes_groups",
    "rec_array_object_field",
    "rec_array_int64_big"
  )
  for (case in cases) {
    file <- fixture_path(file.path("h5ad", paste0(case, ".h5")))
    members <- compound_members(file, "/x")
    py <- h5py_compound(file, "/x")
    expect_equal(members$name, vapply(py$fields, `[[`, "", "name"), info = case)
    for (i in seq_along(py$fields)) {
      want <- expected_member(py$fields[[i]])
      expect_equal(members$class[[i]], want$class, info = case)
      expect_equal(members$size[[i]], want$size, info = case)
      if (!is.null(want$sign)) {
        expect_equal(members$sign[[i]], want$sign, info = case)
      }
      if (want$class == "string") {
        expect_equal(members$variable[[i]], want$variable, info = case)
        expect_equal(members$utf8[[i]], want$utf8, info = case)
      }
      expect_length(members$dims[[i]], 0L)
    }
  }
})

# Spot checks that do not depend on h5py's report: float32 stays float32 (what
# rhdf5 cannot say) and a bool is an enum of FALSE and TRUE
test_that("compound_members() tells float32, unsigned and bool apart", {
  members <- compound_members(
    fixture_path("h5ad/rec_array_widths.h5"),
    "/x"
  )
  expect_equal(members$name, c("u1", "i2", "u4", "i8", "f4", "b"))
  expect_equal(members$class, c(rep("integer", 4), "float", "enum"))
  expect_equal(members$size, c(1L, 2L, 4L, 8L, 4L, 1L))
  expect_equal(members$sign[1:4], c("unsigned", "signed", "unsigned", "signed"))
  expect_equal(members$enum_names[[6]], c("FALSE", "TRUE"))
})

# Legacy obsm is a compound of array-valued members, whose shape is needed to
# read them (the PBMC file is git-ignored, so skip when absent)
test_that("compound_members() reports array shapes of PBMC /obsm", {
  path <- testthat::test_path(
    "..",
    "..",
    ".ralph",
    "oracle",
    "dl",
    "pbmc3k.h5ad"
  )
  skip_if_not(file.exists(path), "the PBMC 3k file is not downloaded")
  members <- compound_members(path, "/obsm")
  expect_gt(nrow(members), 0L)
  expect_true(all(lengths(members$dims) >= 1L))
  expect_true(all(members$class == "float"))
  py <- h5py_compound(path, "/obsm")
  expect_equal(members$name, vapply(py$fields, `[[`, "", "name"))
})

test_that("compound_members() refuses non-compound datasets and bad paths", {
  file <- fixture_path("h5ad/rec_array_widths.h5")
  expect_error(compound_members(file, "/missing"), "cannot open the dataset")
  expect_error(compound_members("/no/such.h5", "/x"), "cannot open the file")
  expect_error(
    compound_members(fixture_path("trivial.h5ad"), "/X"),
    "not a compound"
  )
})

# HDF5 locking would refuse a second open of a file rhdf5 holds, so the helper
# must read while rhdf5 has the same file open read-only
test_that("compound_members() reads a file rhdf5 holds open", {
  file <- fixture_path("h5ad/rec_array_widths.h5")
  handle <- rhdf5::H5Fopen(file, flags = "H5F_ACC_RDONLY")
  withr::defer(rhdf5::H5Fclose(handle))
  expect_equal(compound_members(file, "/x")$name[[1]], "u1")
})

all_fields <- function(n) {
  list(
    compound_field("u1", rep_len(c(1L, 255L), n), "integer", 1, FALSE),
    compound_field("i2", rep_len(c(-2L, 7L), n), "integer", 2, TRUE),
    compound_field("u4", rep_len(c(3, 4e9), n), "integer", 4, FALSE),
    compound_field("i8", rep_len(c(4, -9), n), "integer", 8, TRUE),
    compound_field("f4", rep_len(c(0.5, 1.5), n), "float", 4),
    compound_field("f8", rep_len(c(2.25, -1), n), "float", 8),
    compound_field("b", rep_len(c(TRUE, FALSE), n), "bool", 1),
    compound_field("fixed", rep_len(c("ab", "c"), n), "string", 3),
    compound_field(
      "vl_ascii",
      rep_len(c("x", "yz"), n),
      "string",
      variable = TRUE
    ),
    compound_field(
      "vl_utf8",
      rep_len(c("é", "bé"), n),
      "string",
      variable = TRUE,
      utf8 = TRUE
    )
  )
}

# Writes through the temporary file and H5Ocopy() into a store, as encodings
# will, and returns the store path
write_copied <- function(n, level = 0L, envir = parent.frame()) {
  tmp <- withr::local_tempfile(fileext = ".h5", .local_envir = envir)
  compound_write(tmp, "x", all_fields(n), level = level)
  store <- withr::local_tempfile(fileext = ".h5", .local_envir = envir)
  loc <- rhdf5::H5Fcreate(store)
  compound_copy(tmp, "x", loc, "x")
  rhdf5::H5Fclose(loc)
  store
}

# Writes: h5py sees the exact types and values after the temporary-file and
# H5Ocopy() route, with and without compression
test_that("a copied compound dataset has the exact types in h5py", {
  skip_if_no_python()
  for (level in c(0L, 4L)) {
    store <- write_copied(3L, level)
    py <- h5py_compound(store, "/x")
    dtypes <- vapply(py$fields, `[[`, "", "dtype")
    expect_equal(
      unname(dtypes[1:7]),
      c("uint8", "int16", "uint32", "int64", "float32", "float64", "bool")
    )
    expect_equal(dtypes[[8]], "|S3")
    expect_identical(py$fields[[8]]$string$length, 3L)
    expect_null(py$fields[[9]]$string$length)
    expect_equal(py$fields[[9]]$string$encoding, "ascii")
    expect_equal(py$fields[[10]]$string$encoding, "utf-8")
    expect_equal(py$compression, if (level > 0L) "gzip" else NULL)
    expect_equal(py$shape, list(3L))
    expect_equal(unlist(py$fields[[10]]$values), c("é", "bé", "é"))
    expect_equal(unlist(py$fields[[3]]$values), c(3, 4e9, 3))
    expect_equal(unlist(py$fields[[7]]$values), c(TRUE, FALSE, TRUE))
    expect_equal(
      compound_members(store, "/x")$name,
      vapply(
        all_fields(1L),
        `[[`,
        "",
        "name"
      )
    )
  }
})

# A compound with no rows (which rhdf5's own writer cannot make) keeps its
# types, plain and compressed
test_that("a compound dataset with zero rows is written", {
  skip_if_no_python()
  for (level in c(0L, 4L)) {
    store <- write_copied(0L, level)
    py <- h5py_compound(store, "/x")
    expect_equal(py$shape, list(0L))
    expect_length(py$fields, 10L)
    expect_equal(py$fields[[1]]$dtype, "uint8")
    expect_equal(py$compression, if (level > 0L) "gzip" else NULL)
  }
})

test_that("compound_write() rejects values it cannot store", {
  tmp <- withr::local_tempfile(fileext = ".h5")
  # Out-of-range and fractional values would wrap silently in C
  for (bad in list(
    list(-1, 1, FALSE),
    list(256, 1, FALSE),
    list(128, 1, TRUE),
    list(1.5, 1, TRUE),
    list(2^64, 8, FALSE),
    list(2^63, 8, TRUE)
  )) {
    expect_error(
      compound_write(
        tmp,
        "x",
        list(compound_field("i", bad[[1]], "integer", bad[[2]], bad[[3]]))
      ),
      "does not fit"
    )
  }
  expect_no_error(compound_write(
    tmp,
    "x",
    list(compound_field("i", c(-2^63, 2^63 - 1025), "integer", 8, TRUE))
  ))
  expect_error(
    compound_write(tmp, "x", list(compound_field("s", "abcd", "string", 2))),
    "longer than its fixed field"
  )
  expect_error(
    compound_write(
      tmp,
      "x",
      list(compound_field("s", NA_character_, "string", 2))
    ),
    "missing values"
  )
  expect_error(
    compound_write(
      tmp,
      "x",
      list(compound_field("i", NA_integer_, "integer", 4))
    ),
    "missing values"
  )
  expect_error(
    compound_write(tmp, "x", list(compound_field("i", 1L, "integer", 3))),
    "size of 1, 2, 4 or 8"
  )
  expect_error(
    compound_write(
      tmp,
      "x",
      list(
        compound_field("a", 1:2, "integer", 4),
        compound_field("b", 1L, "integer", 4)
      )
    ),
    "one value per row"
  )
})
