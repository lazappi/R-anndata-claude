# Probe Rarr devel dtype handling on write.
# Usage: Rscript probe-rarr-dtypes.R <format 2|3> <store path>
args <- commandArgs(TRUE)
fmt <- as.integer(args[[1]])
path <- args[[2]]
unlink(path, recursive = TRUE)
suppressMessages(library(Rarr))
dir.create(path)
write_zarr_group(path, group = "", zarr_version = fmt)
p <- function(n) file.path(path, n)

mi <- matrix(c(0L, 1L, 300L, 70000L, -5L, 2L), 2, 3)
try_w <- function(label, x, ...) {
  res <- tryCatch(
    {
      write_zarr_array(x, p(label), zarr_version = fmt, ...)
      "ok"
    },
    error = function(e) paste("ERROR", conditionMessage(e))
  )
  cat(sprintf("Rarr v%d %-16s %s\n", fmt, label, substr(res, 1, 160)))
}
try_w("i32_default", mi, chunk_dim = c(2L, 3L))
try_w("i32_explicit", mi, chunk_dim = c(2L, 3L), data_type = "<i4")
try_w("i16", mi[, 1:2], chunk_dim = c(2L, 2L), data_type = "<i2")
try_w("i8", mi[, 1, drop = FALSE], chunk_dim = c(2L, 1L), data_type = "|i1")
try_w("u16", mi[, 2:3] * 0L + 1L, chunk_dim = c(2L, 2L), data_type = "<u2")
try_w("u32", mi[, 2:3] * 0L + 1L, chunk_dim = c(2L, 2L), data_type = "<u4")
try_w("f32", matrix(c(1.5, 2, 3, 4), 2), chunk_dim = c(2L, 2L), data_type = "<f4")
try_w("f64_default", matrix(c(1.5, 2, 3, 4), 2), chunk_dim = c(2L, 2L))
try_w("i64_int", array(1:4, 4L), chunk_dim = 4L, data_type = "<i8")
try_w("i64_dbl", array(as.double(1:4), 4L), chunk_dim = 4L, data_type = "<i8")
try_w("u64_dbl", array(as.double(1:4), 4L), chunk_dim = 4L, data_type = "<u8")
try_w("bool", array(c(TRUE, FALSE, NA), 3L), chunk_dim = 3L)
try_w(
  "str_utf8",
  array(c("a", "", "ü€"), 3L),
  chunk_dim = 3L
)
try_w(
  "str_nchar",
  array(c("a", "", "ü€"), 3L),
  chunk_dim = 3L,
  nchar = 8L
)
# data_type = "|O" (vlen strings) errors on both versions ("vector size cannot
# be NA" in v2, "Unsupported data type" in v3) and leaves a broken zarr.json,
# so it is not part of the written store
try_w("empty_vec", array(integer(0), 0L), chunk_dim = 1L)
