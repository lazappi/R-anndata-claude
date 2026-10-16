# Probe pizzarr details beyond the read matrix: scalars, attributes, slices,
# stores, consolidated metadata and writing.
# Usage: Rscript probe-pizzarr.R <fixture dir (out/)> <scratch dir>
suppressMessages(library(pizzarr))
args <- commandArgs(TRUE)
out <- args[[1]]
tmp <- args[[2]]

section <- function(x) cat("\n==", x, "\n")
try_do <- function(label, expr) {
  res <- tryCatch(
    paste(utils::capture.output(print(force(expr))), collapse = " | "),
    error = function(e) paste("ERROR", conditionMessage(e))
  )
  cat(sprintf("%-26s %s\n", label, substr(res, 1, 220)))
}

section("scalars (v2 and v3)")
for (v in c("v2", "v3")) {
  for (a in c("scalar_int", "scalar_float", "scalar_bool", "scalar_string")) {
    z <- tryCatch(
      zarr_open(file.path(out, v, "types.zarr", a)),
      error = function(e) e
    )
    if (inherits(z, "error")) {
      cat(v, a, "open ERROR", conditionMessage(z), "\n")
      next
    }
    try_do(paste(v, a, "shape"), z$get_shape())
    try_do(paste(v, a, "item"), z$get_item("..."))
  }
}

section("attributes")
for (v in c("v2", "v3")) {
  g <- zarr_open(file.path(out, v, "types.zarr"))
  try_do(paste(v, "group attrs"), g$get_attrs()$to_list())
  a <- g$get_item("int32")
  try_do(paste(v, "array attrs"), a$get_attrs()$to_list())
  try_do(paste(v, "listing"), g$get_store()$listdir(""))
}

section("slices and chunks")
for (v in c("v2", "v3")) {
  a <- zarr_open(file.path(out, v, "layout.zarr", "chunked"))
  try_do(paste(v, "shape"), a$get_shape())
  try_do(paste(v, "chunks"), a$get_chunks())
  try_do(paste(v, "slice"), a$get_item(list(slice(2, 4), slice(1, 3)))$data)
  try_do(paste(v, "fill_value"), a$get_fill_value())
}

section("consolidated metadata")
for (v in c("v2", "v3")) {
  try_do(paste(v, "open consolidated"), {
    g <- zarr_open_group(file.path(out, v, "types.zarr"), mode = "r")
    g$get_item("int32")$get_shape()
  })
}
try_do(
  "fn consolidate",
  exists("zarr_consolidate_metadata") || exists("consolidate_metadata")
)
print(grep(
  "consol|zip|Zip|v3|shard",
  ls("package:pizzarr"),
  value = TRUE,
  ignore.case = TRUE
))

section("zip store")
for (v in c("v2", "v3")) {
  try_do(paste(v, "zip"), {
    z <- zarr_open(file.path(out, v, "types.zarr.zip"))
    z$get_item("int32")$get_item("...")$data
  })
}

section("write v2 and v3")
for (v in c(2, 3)) {
  p <- file.path(tmp, paste0("r-written-v", v, ".zarr"))
  unlink(p, recursive = TRUE)
  try_do(paste("write", v), {
    g <- zarr_create_group(p, zarr_format = v)
    m <- matrix(as.numeric(1:6), 2, 3)
    a <- g$create_dataset(
      "m",
      data = m,
      dtype = "<f8",
      shape = c(2L, 3L),
      chunks = c(2L, 3L)
    )
    ai <- g$create_dataset(
      "i",
      data = matrix(1:6, 2, 3),
      dtype = "<i4",
      shape = c(2L, 3L)
    )
    g$get_attrs()$set_item("encoding-type", "anndata")
    a$get_attrs()$set_item("lst", list(a = 1, b = "x"))
    list.files(p, recursive = TRUE)
  })
}
