library(Rarr)
p <- file.path(tempdir(), "a")
write_zarr_group(p, group = "")
x <- matrix(1:6, 2)
write_zarr_array(
  x,
  file.path(p, "m"),
  chunk_dim = c(2, 3),
  data_type = "<i4",
  order = "C",
  fill_value = 0L
)
write_zarr_array(
  array(c(1.5, 2, 3), 3L),
  file.path(p, "v"),
  chunk_dim = 3,
  data_type = "<f8",
  order = "C",
  fill_value = 0
)
write_zarr_attributes(file.path(p, "v"), list(a = 1, b = list(1, 2), s = "x"))
write_zarr_attributes(p, list(encoding = "x"))
for (f in c("m/zarr.json", "v/zarr.json", "zarr.json")) {
  cat("##", f, "\n")
  cat(readLines(file.path(p, f)), sep = "\n")
}
print(list.files(p, recursive = TRUE))
print(read_zarr_array(file.path(p, "m")))
