# Probe Rarr devel (2.1.x) writing a small store, for Python to read back.
# Usage: Rscript probe-write-rarr-devel.R <format 2|3> <store path>
args <- commandArgs(TRUE)
fmt <- as.integer(args[[1]])
path <- args[[2]]
unlink(path, recursive = TRUE)
suppressMessages(library(Rarr))

step <- function(label, expr) {
  res <- tryCatch(
    {
      force(expr)
      "ok"
    },
    error = function(e) paste("ERROR", conditionMessage(e)),
    warning = function(w) paste("WARN", conditionMessage(w))
  )
  cat(sprintf("Rarr v%d %-24s %s\n", fmt, label, substr(res, 1, 200)))
}

m <- matrix(c(0.5, 1, NA, 4, 5, 6), 2, 3)
mi <- matrix(0:5, 2, 3)
p <- function(n) file.path(path, n)

dir.create(path)
step("group", write_zarr_group(path, group = "", zarr_version = fmt))
step(
  "float64 matrix",
  write_zarr_array(m, p("f64"), chunk_dim = c(2L, 2L), zarr_version = fmt)
)
step(
  "int32 matrix",
  write_zarr_array(mi, p("i32"), chunk_dim = c(2L, 3L), zarr_version = fmt)
)
step(
  "uint8 vector",
  write_zarr_array(
    array(1:4, 4L),
    p("u8"),
    chunk_dim = 4L,
    data_type = "|u1",
    zarr_version = fmt
  )
)
step(
  "int64 vector",
  write_zarr_array(
    array(as.double(1:4), 4L),
    p("i64"),
    chunk_dim = 4L,
    data_type = "<i8",
    zarr_version = fmt
  )
)
step(
  "bool vector",
  write_zarr_array(
    array(c(TRUE, FALSE, TRUE), 3L),
    p("bool"),
    chunk_dim = 3L,
    zarr_version = fmt
  )
)
step(
  "string vector",
  write_zarr_array(
    array(c("a", "bc", "ü€"), 3L),
    p("str"),
    chunk_dim = 3L,
    zarr_version = fmt
  )
)
step(
  "scalar (0-d)",
  write_zarr_array(
    array(7, integer(0)),
    p("scalar"),
    chunk_dim = integer(0),
    zarr_version = fmt
  )
)
step(
  "group attrs",
  write_zarr_attributes(
    path,
    list(
      "encoding-type" = "anndata",
      arr = c(1, 2, 3),
      obj = list(a = 1, b = "x")
    ),
    zarr_version = fmt
  )
)
step(
  "array attrs",
  write_zarr_attributes(
    p("f64"),
    list(obj = list(a = 1, b = list("x", "y")), v = c(1L, 2L)),
    zarr_version = fmt
  )
)
step("subgroup", write_zarr_group(path, group = "sub", zarr_version = fmt))
step(
  "nested array",
  write_zarr_array(mi, p("sub/i32"), chunk_dim = c(2L, 3L), zarr_version = fmt)
)
step(
  "blosc",
  write_zarr_array(
    m,
    p("blosc"),
    chunk_dim = c(2L, 3L),
    compressor = use_blosc(),
    zarr_version = fmt
  )
)
step("consolidate", zarr_consolidate_metadata(path))
cat(
  "files:",
  paste(list.files(path, recursive = TRUE, all.files = TRUE), collapse = " "),
  "\n"
)
