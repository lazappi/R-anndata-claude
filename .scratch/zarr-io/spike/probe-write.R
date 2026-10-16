# Probe how each candidate writes the same small store, for Python to read back.
# Usage: Rscript probe-write.R <candidate> <format 2|3> <store path>
args <- commandArgs(TRUE)
cand <- args[[1]]
fmt <- as.integer(args[[2]])
path <- args[[3]]
unlink(path, recursive = TRUE)

step <- function(label, expr) {
  res <- tryCatch(
    {
      force(expr)
      "ok"
    },
    error = function(e) paste("ERROR", conditionMessage(e))
  )
  cat(sprintf("%-8s %-24s %s\n", cand, label, substr(res, 1, 200)))
}

m <- matrix(c(0.5, 1, NA, 4, 5, 6), 2, 3)
mi <- matrix(0:5, 2, 3)

if (cand == "pizzarr") {
  suppressMessages(library(pizzarr))
  g <- zarr_create_group(path, zarr_format = fmt)
  step(
    "float64 matrix",
    g$create_dataset(
      "f64",
      data = m,
      dtype = "<f8",
      shape = c(2L, 3L),
      chunks = c(2L, 2L)
    )
  )
  step(
    "int32 matrix",
    g$create_dataset("i32", data = mi, dtype = "<i4", shape = c(2L, 3L))
  )
  step(
    "uint8 vector",
    g$create_dataset("u8", data = 1:4, dtype = "|u1", shape = 4L)
  )
  step(
    "int64 vector",
    g$create_dataset(
      "i64",
      data = bit64::as.integer64(1:4),
      dtype = "<i8",
      shape = 4L
    )
  )
  step(
    "bool vector",
    g$create_dataset(
      "bool",
      data = c(TRUE, FALSE, TRUE),
      dtype = "|b1",
      shape = 3L
    )
  )
  step(
    "string vector",
    g$create_dataset(
      "str",
      data = c("a", "bc", "ü€"),
      dtype = "|O",
      shape = 3L,
      object_codec = VLenUtf8Codec$new()
    )
  )
  step(
    "scalar",
    g$create_dataset("scalar", data = 7, dtype = "<f8", shape = integer(0))
  )
  step("group attrs", g$get_attrs()$set_item("encoding-type", "anndata"))
  step(
    "array attrs",
    g$get_item("f64")$get_attrs()$set_item(
      "obj",
      list(a = 1, b = list("x", "y"))
    )
  )
  step(
    "zstd",
    g$create_dataset(
      "zstd",
      data = m,
      dtype = "<f8",
      shape = c(2L, 3L),
      compressor = ZstdCodec$new(level = 3L)
    )
  )
  step(
    "blosc",
    g$create_dataset(
      "blosc",
      data = m,
      dtype = "<f8",
      shape = c(2L, 3L),
      compressor = BloscCodec$new()
    )
  )
} else if (cand == "zarr") {
  suppressMessages(library(zarr))
  if (fmt != 3L) {
    cat("zarr     (v3 only: the array builder requires format 3)\n")
    quit(status = 0)
  }
  z <- create_zarr(path)
  add <- function(name, type, shape, chunks, data, portable = TRUE) {
    b <- define_array(type, shape)
    b$portable <- portable
    if (!is.null(chunks)) {
      b$chunk_shape <- chunks
    }
    a <- z$add_array("/", name, b)
    a$write(data)
    a
  }
  step("float64 matrix", add("f64", "float64", c(2L, 3L), c(2L, 2L), m))
  step("int32 matrix", add("i32", "int32", c(2L, 3L), c(2L, 3L), mi))
  step("uint8 vector", add("u8", "uint8", 4L, 4L, 1:4))
  step("int64 vector", add("i64", "int64", 4L, 4L, 1:4))
  step("bool vector", add("bool", "boolean", 3L, 3L, c(TRUE, FALSE, TRUE)))
  step("string vector", add("str", "string", 3L, 3L, c("a", "bc", "ü€")))
  step("scalar", add("scalar", "float64", integer(0), NULL, 7))
  step("group attrs", z$root$attributes <- list("encoding-type" = "anndata"))
} else if (cand == "Rarr") {
  suppressMessages(library(Rarr))
  if (fmt != 2L) {
    cat("Rarr     (v2 only: no zarr_version argument)\n")
    quit(status = 0)
  }
  dir.create(path, recursive = TRUE)
  step(
    "create",
    create_empty_zarr_array(
      file.path(path, "f64"),
      dim = c(2L, 3L),
      chunk_dim = c(2L, 2L),
      data_type = "<f8",
      compressor = use_zlib()
    )
  )
  step(
    "write float64",
    write_zarr_array(m, file.path(path, "f64"), chunk_dim = c(2L, 2L))
  )
  step(
    "write int32",
    write_zarr_array(mi, file.path(path, "i32"), chunk_dim = c(2L, 3L))
  )
  step(
    "write string",
    write_zarr_array(
      array(c("a", "bc", "ü€"), 3L),
      file.path(path, "str"),
      chunk_dim = 3L
    )
  )
  step(
    "write bool",
    write_zarr_array(
      array(c(TRUE, FALSE, TRUE), 3L),
      file.path(path, "bool"),
      chunk_dim = 3L
    )
  )
  step(
    "write scalar",
    write_zarr_array(array(7), file.path(path, "scalar"), chunk_dim = 1L)
  )
  step("attrs", write_zarr_attributes(file.path(path, "f64"), list(a = 1)))
}
cat(
  "files:",
  paste(list.files(path, recursive = TRUE, all.files = TRUE), collapse = " "),
  "\n"
)
