# These tests back the verdicts for Rarr (development version, >= 2.1.48) in
# .scratch/zarr-io/zarr-spike.md, the zarr library chosen for zarr-io (ticket
# zarr-io/01). The tests marked "gap" pin behaviour that Rarr lacks so that an
# upgrade that fixes it shows up here, and the workaround is then not needed.

skip_if_no_python()
skip_if_not_installed("Rarr", "2.1.48")

# Python-written v2 and v3 stores (zarr_spike_fixtures.py), made once per file
fixtures <- local({
  dir <- withr::local_tempdir(.local_envir = testthat::teardown_env())
  run_python("zarr_spike_fixtures.py", dir)
  dir
})

fixture_store <- function(format, name, ...) {
  file.path(fixtures, paste0("v", format), name, ...)
}

# The whole array as R sees it (column-major, with the on-disk shape as dim())
read_array <- function(store) {
  Rarr::read_zarr_array(store)
}

# What Python's zarr sees in a store R wrote (zarr_describe.py), keyed by path
python_describe <- function(store) {
  lines <- run_python("zarr_describe.py", store)
  nodes <- lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)
  unlist(nodes, recursive = FALSE)
}

# An empty group store in the given zarr format
new_store <- function(format, env = parent.frame()) {
  path <- file.path(withr::local_tempdir(.local_envir = env), "r.zarr")
  dir.create(path)
  Rarr::write_zarr_group(path, group = "", zarr_version = format)
  path
}

types_matrix <- matrix(0:5, 2, 3, byrow = TRUE)

# u-umlaut and euro sign, built here because literal non-ASCII text in R files
# gives an R CMD check warning
non_ascii <- intToUtf8(c(0xfc, 0x20ac))

test_that("Rarr reads integers of every width with the on-disk shape", {
  # Verdict: pass. dim() equals the on-disk C-order shape and [i, j] is the same
  # element as numpy's [i, j]. 64-bit types arrive as plain R integers, so
  # values beyond the integer range are not representable
  for (format in 2:3) {
    for (type in c(
      "int8",
      "int16",
      "int32",
      "int64",
      "uint8",
      "uint16",
      "uint32",
      "uint64"
    )) {
      x <- read_array(fixture_store(format, "types.zarr", type))
      expect_identical(dim(x), 2:3, info = paste(format, type))
      expect_equal(
        unname(x),
        types_matrix,
        ignore_attr = TRUE,
        info = paste(format, type)
      )
    }
  }
})

test_that("Rarr reads floats, bool and NaN (v2 and v3)", {
  # Verdict: pass for float32, float64 and bool, NaN and Inf survive
  for (format in 2:3) {
    for (type in c("float32", "float64")) {
      x <- read_array(fixture_store(format, "types.zarr", type))
      expect_identical(dim(x), 2:3)
      expect_identical(unname(x[1, ]), c(0.5, -1.25, NaN))
      expect_identical(unname(x[2, ]), c(Inf, 2, 3.5))
    }
    b <- read_array(fixture_store(format, "types.zarr", "bool"))
    expect_identical(
      unname(b),
      matrix(c(TRUE, FALSE, TRUE, FALSE, FALSE, TRUE), 2, 3, byrow = TRUE),
      ignore_attr = TRUE
    )
  }
})

test_that("Rarr reads variable-length strings, including empty ones", {
  # Verdict: pass for v2 vlen-utf8 and the v3 string type, with empty strings
  # and non-ASCII text intact (pizzarr 0.2.1 read "" as "\005")
  for (format in 2:3) {
    x <- read_array(fixture_store(format, "types.zarr", "string"))
    expect_identical(as.vector(x), c("a", "bc", "", non_ascii))
  }
})

test_that("Rarr reads 0-dimensional arrays as length-1 arrays", {
  # Verdict: pass with a mapping. A scalar arrives with dim() 1, so the caller
  # (not Rarr) must know that the on-disk shape is empty, from the metadata
  for (format in 2:3) {
    expect_identical(
      as.vector(read_array(fixture_store(format, "types.zarr", "scalar_int"))),
      7L
    )
    expect_identical(
      as.vector(
        read_array(fixture_store(format, "types.zarr", "scalar_float"))
      ),
      2.5
    )
    expect_identical(
      as.vector(read_array(fixture_store(format, "types.zarr", "scalar_bool"))),
      TRUE
    )
    expect_identical(
      as.vector(
        read_array(fixture_store(format, "types.zarr", "scalar_string"))
      ),
      "hi"
    )
  }
})

test_that("Rarr reads zstd, blosc, gzip and uncompressed chunks", {
  # Verdict: pass without the blosc package. The codecs Python writes by
  # default are zstd (v3) and blosc (v2), gzip is the other common one
  expected <- matrix(0:39, 8, 5, byrow = TRUE)
  for (format in 2:3) {
    for (name in c("chunked", "zstd", "blosc", "gzip", "uncompressed")) {
      x <- read_array(fixture_store(format, "layout.zarr", name))
      expect_identical(dim(x), c(8L, 5L))
      expect_equal(unname(x), expected, ignore_attr = TRUE, info = name)
    }
  }
})

test_that("Rarr fills missing chunks with the fill value", {
  # Verdict: pass for integers and a NaN fill value in both formats
  for (format in 2:3) {
    x <- read_array(fixture_store(format, "layout.zarr", "missing"))
    expect_identical(unname(x[1:2, 1:2]), matrix(c(1L, 3L, 2L, 4L), 2, 2))
    expect_true(all(x[3:4, ] == -1L))
    expect_true(all(is.nan(read_array(
      fixture_store(format, "layout.zarr", "fill_nan")
    ))))
  }
})

test_that("Rarr reads slices without reading the whole array", {
  # Verdict: pass. Needed later by `backed` and `lazy`
  for (format in 2:3) {
    part <- Rarr::read_zarr_array(
      fixture_store(format, "layout.zarr", "chunked"),
      index = list(2:4, 1:3)
    )
    expect_equal(
      unname(part),
      matrix(c(5, 6, 7, 10, 11, 12, 15, 16, 17), 3, 3, byrow = TRUE),
      ignore_attr = TRUE
    )
  }
})

test_that("Rarr reads sharded v3 arrays", {
  # Verdict: pass for reading (development version), writing shards is a gap
  x <- read_array(fixture_store(3, "layout.zarr", "sharded"))
  expect_identical(dim(x), c(8L, 5L))
  expect_equal(unname(x), matrix(0:39, 8, 5, byrow = TRUE), ignore_attr = TRUE)
})

test_that("Rarr reads group and array attributes, including objects", {
  # Verdict: pass. Arrays come back as lists, so the caller unlists them
  for (format in 2:3) {
    attrs <- Rarr::read_zarr_attributes(fixture_store(format, "types.zarr"))
    expect_identical(attrs$str, "text")
    expect_identical(attrs$int, 3L)
    expect_identical(unlist(attrs$list), c("a", "b"))
    expect_identical(unlist(attrs$nested$k), c(1L, 2L))
    array_attrs <- Rarr::read_zarr_attributes(
      fixture_store(format, "types.zarr", "int32")
    )
    expect_identical(array_attrs$`encoding-type`, "array")
    expect_identical(unlist(array_attrs$array_attr), 1:3)
    expect_identical(array_attrs$object_attr$a, 1L)
  }
})

test_that("Rarr reads consolidated metadata", {
  # Verdict: pass for reading (v2 .zmetadata and v3 inline), see the write test
  # for consolidating
  for (format in 2:3) {
    meta <- Rarr::read_zarr_consolidated_metadata(
      fixture_store(format, "types.zarr")
    )
    expect_true(all(c("int32", "float64", "string") %in% names(meta)))
  }
})

test_that("Rarr has no zip store", {
  # Verdict: gap. A .zarr.zip is treated as a directory, so Rarr finds no
  # metadata in it
  zip <- fixture_store(3, "types.zarr.zip")
  expect_true(file.exists(zip))
  expect_identical(Rarr::read_zarr_attributes(zip), list())
  expect_error(read_array(zip), "does not contain any metadata files")
})

test_that("Python reads the groups, arrays and attributes Rarr writes", {
  # Verdict: pass for numeric, bool and nested groups, attributes (including
  # objects) and consolidated metadata, in both formats
  for (format in 2:3) {
    path <- new_store(format)
    p <- function(name) file.path(path, name)
    m <- matrix(c(0.5, 1, NA, 4, 5, 6), 2, 3)
    Rarr::write_zarr_array(
      m,
      p("f64"),
      chunk_dim = c(2L, 2L),
      data_type = "<f8",
      zarr_version = format
    )
    Rarr::write_zarr_array(
      matrix(0:5, 2, 3),
      p("i32"),
      chunk_dim = c(2L, 3L),
      data_type = "<i4",
      zarr_version = format
    )
    Rarr::write_zarr_array(
      array(c(TRUE, FALSE, TRUE), 3L),
      p("bool"),
      chunk_dim = 3L,
      data_type = "|b1",
      zarr_version = format
    )
    Rarr::write_zarr_group(path, group = "sub", zarr_version = format)
    Rarr::write_zarr_array(
      array(1:4, 4L),
      p("sub/u8"),
      chunk_dim = 4L,
      data_type = "|u1",
      zarr_version = format
    )
    Rarr::write_zarr_attributes(
      path,
      list("encoding-type" = "anndata", arr = c(1, 2, 3)),
      zarr_version = format
    )
    Rarr::write_zarr_attributes(
      p("f64"),
      list(obj = list(a = 1, b = list("x", "y"))),
      zarr_version = format
    )
    Rarr::zarr_consolidate_metadata(path)

    # Consolidated metadata is written where Python looks for it
    if (format == 2) {
      expect_true(file.exists(file.path(path, ".zmetadata")))
    } else {
      root_meta <- jsonlite::read_json(file.path(path, "zarr.json"))
      expect_identical(root_meta$consolidated_metadata$kind, "inline")
      expect_true("f64" %in% names(root_meta$consolidated_metadata$metadata))
    }
    expect_true("f64" %in% names(Rarr::read_zarr_consolidated_metadata(path)))

    nodes <- python_describe(path)
    expect_identical(nodes[["/"]]$format, format)
    expect_identical(nodes[["/"]]$attrs$`encoding-type`, "anndata")
    expect_identical(nodes[["/"]]$attrs$arr, list(1L, 2L, 3L))
    expect_identical(nodes[["/f64"]]$shape, list(2L, 3L))
    expect_identical(nodes[["/f64"]]$chunks, list(2L, 2L))
    expect_identical(
      nodes[["/f64"]]$value,
      list(list(0.5, "nan", 5), list(1, 4, 6))
    )
    expect_identical(nodes[["/f64"]]$attrs$obj$b, list("x", "y"))
    expect_identical(nodes[["/i32"]]$dtype, "int32")
    expect_identical(
      nodes[["/i32"]]$value,
      list(list(0L, 2L, 4L), list(1L, 3L, 5L))
    )
    expect_identical(nodes[["/bool"]]$value, list(TRUE, FALSE, TRUE))
    expect_identical(nodes[["/sub"]]$kind, "group")
    expect_identical(nodes[["/sub/u8"]]$value, list(1L, 2L, 3L, 4L))
  }
})

test_that("Rarr picks the smallest integer type unless data_type is given", {
  # Verdict: workaround. matrix(0:5) is written as uint8, so the writer must
  # always pass data_type to keep int32 on disk
  path <- new_store(3)
  Rarr::write_zarr_array(
    matrix(0:5, 2, 3),
    file.path(path, "i"),
    chunk_dim = c(2L, 3L)
  )
  expect_identical(python_describe(path)[["/i"]]$dtype, "uint8")
})

test_that("Rarr writes strings as fixed-width bytes, not vlen-utf8 (gap)", {
  # Verdict: gap. The width is the character count (3), so the 5 UTF-8 bytes of
  # the last string are cut to 3 and Python sees a bytes dtype (|S3), so the
  # writer needs its own string path
  for (format in 2:3) {
    path <- new_store(format)
    Rarr::write_zarr_array(
      array(c("a", "bc", non_ascii), 3L),
      file.path(path, "str"),
      chunk_dim = 3L,
      zarr_version = format
    )
    node <- python_describe(path)[["/str"]]
    expect_identical(node$dtype, "|S3")
    expect_identical(
      node$value,
      list("a", "bc", paste0(intToUtf8(0xfc), intToUtf8(0xfffd)))
    )
  }
})

test_that("Rarr cannot write 0-dimensional arrays (gap)", {
  # Verdict: gap. Scalars (anndata `numeric-scalar`, `string`) need their own
  # writer
  for (format in 2:3) {
    path <- new_store(format)
    expect_error(
      Rarr::write_zarr_array(
        array(7, integer(0)),
        file.path(path, "scalar"),
        chunk_dim = integer(0),
        zarr_version = format
      ),
      # R 4.6 says "'dim' cannot be", older versions "'dims' cannot be"
      "dims?"
    )
  }
})

test_that("Rarr cannot write 64-bit integers from doubles (gap)", {
  # Verdict: gap. data_type "<i8" accepts R integers but errors for doubles,
  # and an R double has no other way to hold values above 2^31
  path <- new_store(3)
  expect_error(
    Rarr::write_zarr_array(
      array(as.double(1:4), 4L),
      file.path(path, "i64"),
      chunk_dim = 4L,
      data_type = "<i8",
      zarr_version = 3
    ),
    "REAL"
  )
})
