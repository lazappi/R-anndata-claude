pkgload::load_all(quiet = TRUE)
for (n in c(2^12, 2^13, 2^14)) {
  values <- matrix(2^40 + seq_len(n * 3), n, 3)
  store <- zarr_create(file.path(tempfile(), "r.zarr"))
  write_dataset(store, "x", set_dtype(values, "int64"))
  array <- zarr_array_meta(store, "/x")
  dir <- zarr_dir(array$node)
  t1 <- system.time(
    r <- withCallingHandlers(
      zarr_rarr_read(dir, array$shape, NULL),
      warning = function(w) rlang::cnd_muffle(w)
    )
  )
  t2 <- system.time(parts <- zarr_split_read(array, "uint16", 4L, NULL))
  t3 <- system.time(zarr_wide_read(array, NULL, "/x", NULL))
  cat(n, "rarr", t1[[3]], "split", t2[[3]], "wide", t3[[3]], "\n")
}
