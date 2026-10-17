# Evidence for `.scratch/h5ad-io/rhdf5-spike.md`: each verdict there is backed
# by a test here that reads the h5py-written `fixtures/spike_types.h5` or
# writes a file that h5py reads back. The write helpers are the workarounds
# the spike recommends, and h5ad-io/03 onwards will turn them into package
# code.

spike_file <- function() fixture_path("spike_types.h5")

# Reads a dataset the way the spike recommends: R dim() equals the on-disk shape
spike_read <- function(name, ...) {
  as_plain <- function(x) {
    if (length(dim(x)) == 1L) {
      dim(x) <- NULL
    }
    x
  }
  # native = TRUE fails with "INTEGER() can only be applied to a 'integer'"
  # when combined with bit64conversion = "bit64", so those reads are 1-d only
  # (or need a manual aperm() of the reversed-dim result)
  # rhdf5 2.57.12 regression: h5read(native = TRUE) segfaults on scalar
  # (0-d) datasets, native = FALSE works and a scalar has no dims to reverse
  # (the package never calls h5read())
  scalar <- startsWith(name, "scalar_")
  native <- !scalar && !identical(list(...)$bit64conversion, "bit64")
  as_plain(rhdf5::h5read(spike_file(), name, native = native, ...))
}

# The h5py dtype name of a dataset (sign and width), which rhdf5 only exposes
# through h5ls(all = TRUE)
spike_dtype <- function(name) {
  listing <- rhdf5::h5ls(spike_file(), all = TRUE)
  listing$dtype[listing$name == name]
}

# Opens a new HDF5 file and closes it when the calling test ends
spike_create <- function(path, env = parent.frame()) {
  rhdf5::h5createFile(path)
  fid <- rhdf5::H5Fopen(path)
  withr::defer(rhdf5::h5closeAll(), envir = env)
  fid
}

# A variable-length UTF-8 string type, as h5py's `string_dtype()`
spike_vlen_utf8 <- function() {
  tid <- rhdf5::H5Tcopy("H5T_C_S1")
  rhdf5::H5Tset_size(tid, -1L)
  rhdf5::H5Tset_cset(tid, "UTF8")
  tid
}

# An enum of 0 and 1 over int8 named FALSE and TRUE, as h5py's boolean
spike_bool_enum <- function() {
  tid <- rhdf5::H5Tenum_create(dtype_id = "H5T_STD_I8LE")
  rhdf5::H5Tenum_insert(tid, "FALSE", 0L)
  rhdf5::H5Tenum_insert(tid, "TRUE", 1L)
  tid
}

# Writes `value` so that h5py sees shape `dim(value)`. rhdf5 treats dataspace
# dims as R dims and reverses them, so the workaround is to declare the reversed
# dims and write the transposed (row-major) buffer. `memtype` is only needed
# where R's type is not what HDF5 should convert from (enum).
spike_write <- function(
  fid,
  name,
  value,
  dtype,
  scalar = FALSE,
  memtype = NULL,
  dcpl = NULL
) {
  dims <- if (is.null(dim(value))) length(value) else dim(value)
  sid <- if (scalar) {
    rhdf5::H5Screate("H5S_SCALAR")
  } else {
    rhdf5::H5Screate_simple(rev(dims))
  }
  on.exit(rhdf5::H5Sclose(sid), add = TRUE)
  did <- rhdf5::H5Dcreate(fid, name, dtype, sid, dcpl = dcpl)
  on.exit(rhdf5::H5Dclose(did), add = TRUE)
  buf <- if (length(dims) > 1L) aperm(value) else value
  if (is.null(memtype)) {
    rhdf5::H5Dwrite(did, buf)
  } else {
    rhdf5::H5Dwrite(did, buf, h5type = memtype)
  }
  invisible(did)
}

# A dataset creation property list with chunking and one compression filter
spike_dcpl <- function(chunk, filter, level = NULL) {
  pl <- rhdf5::H5Pcreate("H5P_DATASET_CREATE")
  rhdf5::H5Pset_chunk(pl, rev(chunk))
  if (filter == "gzip") {
    rhdf5::H5Pset_deflate(pl, level)
  } else {
    rhdf5::H5Pset_lzf(pl, h5tid = rhdf5::H5Tcopy("H5T_IEEE_F64LE"))
  }
  pl
}

spike_attr <- function(obj, name, value, dtype, scalar = FALSE) {
  sid <- if (scalar) {
    rhdf5::H5Screate("H5S_SCALAR")
  } else {
    rhdf5::H5Screate_simple(length(value))
  }
  on.exit(rhdf5::H5Sclose(sid), add = TRUE)
  attr <- rhdf5::H5Acreate(obj, name, dtype, sid)
  on.exit(rhdf5::H5Aclose(attr), add = TRUE)
  rhdf5::H5Awrite(attr, value)
}

# Writes everything the spike found writable, mirroring the fixture
spike_write_all <- function(path, env = parent.frame()) {
  fid <- spike_create(path, env)
  vlen <- spike_vlen_utf8()
  bool <- spike_bool_enum()

  spike_write(
    fid,
    "vlen_utf8",
    c("a", "bé", "", "日本"),
    vlen
  )
  spike_write(
    fid,
    "vlen_utf8_2d",
    matrix(c("a", "b", "c", "d", "e", "f"), 2, byrow = TRUE),
    vlen
  )
  # The buffer must be raw (1 byte per value) to match the int8 enum memtype
  spike_write(fid, "bool", as.raw(c(1, 0, 1)), bool, memtype = bool)
  spike_write(
    fid,
    "bool_2d",
    matrix(as.raw(c(1, 0, 1, 0, 0, 1)), 2, byrow = TRUE),
    bool,
    memtype = bool
  )
  # Doubles are written for every integer width so that -2^31 and 2^53 survive
  spike_write(fid, "int8", c(-128, 0, 1, 127), "H5T_STD_I8LE")
  spike_write(fid, "int16", c(-32768, 0, 1, 32767), "H5T_STD_I16LE")
  spike_write(fid, "int32", c(-2^31, 0, 1, 2^31 - 1), "H5T_STD_I32LE")
  spike_write(fid, "int64", c(-2^53, 0, 1, 2^53), "H5T_STD_I64LE")
  spike_write(fid, "uint8", as.raw(c(0, 0, 1, 255)), "H5T_STD_U8LE")
  spike_write(fid, "uint16", c(0, 0, 1, 65535), "H5T_STD_U16LE")
  spike_write(fid, "uint32", c(0, 0, 1, 2^32 - 1), "H5T_STD_U32LE")
  spike_write(fid, "uint64", c(0, 0, 1, 2^53), "H5T_STD_U64LE")
  special <- c(1.5, -2.25, NaN, Inf)
  spike_write(fid, "float32", special, "H5T_IEEE_F32LE")
  spike_write(fid, "float64", special, "H5T_IEEE_F64LE")
  spike_write(
    fid,
    "complex128",
    c(1 + 2i, -3.5 + 0.25i),
    rhdf5:::.setDataType(NULL, "complex", NULL, "ASCII")
  )
  spike_write(
    fid,
    "matrix_2x3",
    matrix(0:5, 2, 3, byrow = TRUE),
    "H5T_STD_I32LE"
  )
  spike_write(
    fid,
    "array_2x3x4",
    aperm(array(as.numeric(0:23), c(4, 3, 2))),
    "H5T_IEEE_F64LE"
  )
  spike_write(fid, "scalar_int", 7L, "H5T_STD_I32LE", scalar = TRUE)
  spike_write(fid, "scalar_float", 2.5, "H5T_IEEE_F64LE", scalar = TRUE)
  spike_write(fid, "scalar_str", "héllo", vlen, scalar = TRUE)
  spike_write(
    fid,
    "scalar_bool",
    as.raw(1),
    bool,
    scalar = TRUE,
    memtype = bool
  )
  big <- matrix(as.numeric(0:999), 10, 100, byrow = TRUE)
  spike_write(
    fid,
    "gzip",
    big,
    "H5T_IEEE_F64LE",
    dcpl = spike_dcpl(c(5, 50), "gzip", 4L)
  )
  spike_write(
    fid,
    "lzf",
    big,
    "H5T_IEEE_F64LE",
    dcpl = spike_dcpl(c(5, 50), "lzf")
  )

  group <- rhdf5::H5Gcreate(fid, "attrs")
  rhdf5::h5writeAttribute(
    "héllo",
    group,
    "str",
    encoding = "UTF-8",
    variableLengthString = TRUE,
    asScalar = TRUE
  )
  rhdf5::h5writeAttribute(
    c("a", "b", "c"),
    group,
    "str_array",
    encoding = "UTF-8",
    variableLengthString = TRUE
  )
  spike_attr(group, "int", 5, "H5T_STD_I64LE", scalar = TRUE)
  spike_attr(group, "float", 0.5, "H5T_IEEE_F64LE", scalar = TRUE)
  spike_attr(group, "int_array", 1:3, "H5T_STD_I32LE")
  rhdf5::h5writeAttribute(TRUE, group, "bool", asScalar = TRUE)
  spike_attr(group, "shape", c(2, 3), "H5T_STD_I64LE")
  invisible(path)
}

# Python-side description of a file as a list keyed by "path" or "path@attr"
spike_describe <- function(file) {
  lines <- run_python("spike_describe.py", file)
  nodes <- lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)
  stats::setNames(
    lapply(nodes, function(node) node[[1]]),
    vapply(nodes, function(node) names(node), character(1))
  )
}

# -- Reading: Python-written fixture into R ----------------------------------

# Verdict: variable-length UTF-8 strings read as character with the right shape
test_that("rhdf5 reads variable-length UTF-8 string datasets", {
  expect_identical(
    spike_read("vlen_utf8"),
    c("a", "bé", "", "日本")
  )
  expect_identical(
    spike_read("vlen_utf8_2d"),
    matrix(c("a", "b", "c", "d", "e", "f"), 2, byrow = TRUE)
  )
  expect_identical(spike_read("scalar_str"), "héllo")
})

# Verdict: h5py booleans read as a two-level factor, which must be converted
test_that("rhdf5 reads the boolean enum as a factor that converts to logical", {
  raw <- spike_read("bool")
  expect_s3_class(raw, "factor")
  expect_identical(as.logical(as.character(raw)), c(TRUE, FALSE, TRUE))

  raw_2d <- spike_read("bool_2d")
  expect_identical(dim(raw_2d), c(2L, 3L))
  logical_2d <- array(as.logical(as.character(raw_2d)), dim(raw_2d))
  expect_identical(
    logical_2d,
    matrix(c(TRUE, FALSE, TRUE, FALSE, FALSE, TRUE), 2, byrow = TRUE)
  )
  expect_identical(as.logical(as.character(spike_read("scalar_bool"))), TRUE)
})

# Verdict: signed and 16-bit integers read directly, wider ones need bit64
# conversion, uint8 arrives as raw, and sign and width come from h5ls
test_that("rhdf5 reads every integer width given the right options", {
  expect_identical(spike_read("int8"), c(-128L, 0L, 1L, 127L))
  expect_identical(spike_read("int16"), c(-32768L, 0L, 1L, 32767L))
  expect_identical(spike_read("uint16"), c(0L, 0L, 1L, 65535L))
  expect_identical(spike_read("uint8"), as.raw(c(0, 0, 1, 255)))

  # int32 -2^31 is NA_integer_ in R, which is an unavoidable collision
  utils::capture.output(suppressMessages(int32 <- spike_read("int32")))
  expect_identical(int32, c(NA, 0L, 1L, 2147483647L))

  # Default reads overflow to NA with a warning, so 32 and 64-bit need options
  expect_warning(spike_read("uint32"), "overflow")
  expect_warning(spike_read("int64"), "overflow")
  # The uint32 fixture ends at 2^32 - 1, which only doubles hold exactly
  expect_identical(
    as.vector(spike_read("uint32", bit64conversion = "double")),
    c(0, 0, 1, 2^32 - 1)
  )
})

# Verdict: dtype (sign and width) of a dataset is readable through h5ls only
test_that("h5ls(all = TRUE) reports the on-disk dtype of numeric datasets", {
  expect_identical(
    vapply(
      c(
        "int8",
        "int16",
        "int32",
        "int64",
        "uint8",
        "uint16",
        "uint32",
        "uint64",
        "float32",
        "float64"
      ),
      spike_dtype,
      character(1),
      USE.NAMES = FALSE
    ),
    c(
      "H5T_STD_I8LE",
      "H5T_STD_I16LE",
      "H5T_STD_I32LE",
      "H5T_STD_I64LE",
      "H5T_STD_U8LE",
      "H5T_STD_U16LE",
      "H5T_STD_U32LE",
      "H5T_STD_U64LE",
      "H5T_IEEE_F32LE",
      "H5T_IEEE_F64LE"
    )
  )
})

# Verdict: int64 recommendation. Read as integer64, then use doubles when every
# value is within 2^53 and keep integer64 (or raise a classed error) otherwise
test_that("64-bit integers read exactly through bit64 conversion", {
  small <- spike_read("int64", bit64conversion = "bit64")
  expect_s3_class(small, "integer64")
  expect_identical(
    as.character(small),
    c("-9007199254740992", "0", "1", "9007199254740992")
  )
  # as.double() warns at exactly 2^53 so the safe range check stays in bit64
  expect_true(all(abs(small) <= bit64::as.integer64("9007199254740992")))

  big <- spike_read("int64_big", bit64conversion = "bit64")
  expect_identical(
    as.character(big),
    c("9007199254740993", "-4611686018427387904")
  )
  expect_true(any(abs(big) > bit64::as.integer64("9007199254740992")))

  # double conversion is lossy beyond 2^53, which is why bit64 is the first read
  expect_warning(
    spike_read("int64_big", bit64conversion = "double"),
    "precision lost"
  )
})

# Verdict: uint64 above 2^63 cannot be held by integer64, so a classed error is
# the only exact option
test_that("uint64 values above 2^63 are unreadable as integers", {
  expect_warning(
    utils::capture.output(suppressMessages(
      big <- spike_read("uint64_big", bit64conversion = "bit64")
    )),
    "overflow"
  )
  expect_true(any(is.na(big)))
})

# Verdict: floats of both widths read as double with NaN and Inf kept
test_that("rhdf5 reads float32 and float64 including NaN and Inf", {
  expect_identical(spike_read("float32"), c(1.5, -2.25, NaN, Inf))
  expect_identical(spike_read("float64"), c(1.5, -2.25, NaN, Inf))
})

# Verdict: complex128 passes, complex64 is a gap that reads garbage, but its
# 8-byte type size makes it detectable so the reader can raise a classed error
test_that("complex128 reads correctly and complex64 is detectable", {
  expect_identical(spike_read("complex128"), c(1 + 2i, -3.5 + 0.25i))

  type_size <- function(name) {
    fid <- rhdf5::H5Fopen(spike_file(), flags = "H5F_ACC_RDONLY")
    withr::defer(rhdf5::H5Fclose(fid))
    did <- rhdf5::H5Dopen(fid, name)
    withr::defer(rhdf5::H5Dclose(did))
    rhdf5::H5Tget_size(rhdf5::H5Dget_type(did))
  }
  expect_identical(type_size("complex128"), 16L)
  expect_identical(type_size("complex64"), 8L)
  expect_false(isTRUE(all.equal(
    spike_read("complex64"),
    c(1 + 2i, -3.5 + 0.25i)
  )))
})

# Verdict: the default read reverses dim(), native = TRUE restores the on-disk
# shape with row-major meaning, so dim() equals the shape Python sees
test_that("native = TRUE makes R dim() equal the on-disk shape", {
  expect_identical(dim(rhdf5::h5read(spike_file(), "matrix_2x3")), c(3L, 2L))
  expect_identical(
    spike_read("matrix_2x3"),
    matrix(0:5, 2, 3, byrow = TRUE)
  )
  expect_identical(dim(spike_read("array_2x3x4")), c(2L, 3L, 4L))
  expect_identical(spike_read("array_2x3x4")[2, 3, 4], 23)
  expect_identical(spike_read("array_2x3x4")[1, 2, 3], 6)
  expect_identical(dim(spike_read("gzip")), c(10L, 100L))
})

# Verdict: scalar datasets read as length-1 vectors with no dim, and h5ls tells
# them apart from 1-element arrays
test_that("0-dimensional datasets read as detectable length-1 vectors", {
  expect_identical(spike_read("scalar_int"), 7L)
  expect_identical(spike_read("scalar_float"), 2.5)
  listing <- rhdf5::h5ls(spike_file(), all = TRUE)
  expect_identical(
    listing$stype[listing$name == "scalar_int"],
    "SCALAR"
  )
  expect_identical(listing$stype[listing$name == "int8"], "SIMPLE")
})

# Verdict: gzip and lzf datasets read transparently
test_that("rhdf5 reads gzip and lzf compressed datasets", {
  expect_true("lzf" %in% rhdf5filters::available_filters())
  expected <- matrix(as.numeric(0:999), 10, 100, byrow = TRUE)
  expect_identical(spike_read("gzip"), expected)
  expect_identical(spike_read("lzf"), expected)
})

# Verdict: attributes read with the right R types, scalars as length-1 vectors
test_that("rhdf5 reads string, numeric, boolean and array attributes", {
  attrs <- rhdf5::h5readAttributes(spike_file(), "attrs", native = TRUE)
  expect_identical(attrs$str, "héllo")
  expect_identical(as.vector(attrs$str_array), c("a", "b", "c"))
  expect_identical(attrs$int, 5L)
  expect_identical(attrs$float, 0.5)
  expect_identical(as.vector(attrs$int_array), 1:3)
  expect_identical(attrs$bool, TRUE)
  expect_identical(as.vector(attrs$shape), 2:3)
})

# Verdict: compound datasets read as data.frames whose values are right, but
# member widths and fixed or variable string types are not introspectable
test_that("rec-array compounds read values but lose member dtypes", {
  rec <- spike_read("rec")
  expect_s3_class(rec, "data.frame")
  expect_identical(names(rec), c("i", "f", "fixed", "v"))
  expect_identical(as.vector(rec$fixed), c("ab", "c"))
  expect_identical(as.vector(rec$v), c("x", "yé"))

  # Every integer member reads as integer, so u1/i2/u4/i8 cannot be told apart
  expect_warning(
    widths <- spike_read("rec_widths"),
    "overflow"
  )
  expect_identical(typeof(widths$u1), "raw")
  expect_identical(typeof(widths$i2), "integer")
  expect_identical(typeof(widths$u4), "integer")
  expect_identical(typeof(widths$i8), "integer")

  member_functions <- c(
    "H5Tget_member_type",
    "H5Tget_member_name",
    "H5Tget_sign"
  )
  expect_false(any(member_functions %in% getNamespaceExports("rhdf5")))
})

# -- Writing: R file read back by Python -------------------------------------

# Verdict: everything except the gaps writes identically to h5py, checked by
# comparing the R-written file to the Python-written fixture node by node
test_that("R-written file is structurally equivalent to the h5py fixture", {
  skip_if_no_python()
  skip_if_not_installed("jsonlite")

  path <- withr::local_tempfile(fileext = ".h5")
  spike_write_all(path)
  rhdf5::h5closeAll()

  gaps <- c("/complex64", "/int64_big", "/rec", "/rec_widths", "/uint64_big")
  diffs <- h5_tree_differences(h5_tree(path), h5_tree(spike_file()))
  expect_identical(
    sort(diffs),
    sort(paste0(gaps, ": only in the second file"))
  )
})

# Verdict: dtype of every written dataset and attribute is what h5py writes
test_that("Python reads the R-written dtypes, shapes and compression", {
  skip_if_no_python()
  skip_if_not_installed("jsonlite")

  path <- withr::local_tempfile(fileext = ".h5")
  spike_write_all(path)
  rhdf5::h5closeAll()

  written <- spike_describe(path)
  expect_identical(written[["/vlen_utf8"]]$dtype, "string(variable, utf-8)")
  # h5py maps the FALSE/TRUE enum to numpy bool
  expect_identical(written[["/bool"]]$dtype, "bool")
  expect_identical(written[["/bool"]]$value, list(TRUE, FALSE, TRUE))
  expect_identical(written[["/scalar_bool"]]$shape, list())
  expect_identical(written[["/complex128"]]$dtype, "complex128")
  expect_identical(written[["/matrix_2x3"]]$shape, list(2L, 3L))
  expect_identical(
    written[["/matrix_2x3"]]$value,
    list(list(0L, 1L, 2L), list(3L, 4L, 5L))
  )
  expect_identical(written[["/gzip"]]$compression, "gzip")
  expect_identical(written[["/gzip"]]$compression_opts, 4L)
  expect_identical(written[["/lzf"]]$compression, "lzf")
  expect_null(written[["/int8"]]$compression)
  expect_identical(written[["/attrs@str"]]$shape, list())
  expect_identical(written[["/attrs@shape"]]$dtype, "int64")
  expect_identical(written[["/attrs@int"]]$shape, list())
  expect_false(any(grepl("rhdf5-NA.OK|storage.mode", names(written))))
})

# Verdict: 64-bit integers beyond 2^53 cannot be written, because H5Dwrite
# reinterprets an integer64 buffer as doubles, so only doubles are accepted
test_that("integer64 buffers are not written correctly by rhdf5", {
  skip_if_no_python()
  skip_if_not_installed("jsonlite")

  path <- withr::local_tempfile(fileext = ".h5")
  fid <- spike_create(path)
  big <- bit64::as.integer64(c("9007199254740993", "-4611686018427387904"))
  spike_write(fid, "int64_big", big, "H5T_STD_I64LE")
  rhdf5::h5closeAll()

  written <- spike_describe(path)[["/int64_big"]]$value
  expect_false(identical(written, list(9007199254740993, -4611686018427387904)))
  expect_identical(written, list(0L, -2L))
})

# Verdict: data.frame compounds write, but only as int32, float64 and
# fixed-length strings with no compression, never h5py's variable-length type
test_that("rec-array compounds are written with fixed-length strings only", {
  skip_if_no_python()
  skip_if_not_installed("jsonlite")

  path <- withr::local_tempfile(fileext = ".h5")
  fid <- spike_create(path)
  rhdf5::h5writeDataset(
    data.frame(
      i = 1:2,
      f = c(1.5, 2.5),
      fixed = c("ab", "c"),
      v = c("x", "yé")
    ),
    fid,
    "rec",
    level = 0L,
    chunk = 2L
  )
  rhdf5::h5closeAll()

  written <- spike_describe(path)[["/rec"]]
  expect_identical(
    written$dtype,
    paste0(
      "compound(i:int32, f:float64, fixed:string(fixed 2, ascii), ",
      "v:string(fixed 3, ascii))"
    )
  )
  expect_identical(
    written$value,
    list(list(1L, 1.5, "ab", "x"), list(2L, 2.5, "c", "yé"))
  )
  expected <- spike_describe(spike_file())[["/rec"]]$dtype
  expect_false(identical(written$dtype, expected))
})
