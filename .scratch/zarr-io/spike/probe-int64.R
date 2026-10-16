# How Rarr reads 64-bit values beyond the R integer range (zarr-io/04)
dir <- tempfile()
dir.create(file.path(dir, "c"), recursive = TRUE)
meta <- function(type) {
  sprintf(
    '{"zarr_format":3,"node_type":"array","shape":[3],"data_type":"%s","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[3]}},"chunk_key_encoding":{"name":"default","configuration":{"separator":"/"}},"fill_value":0,"codecs":[{"name":"bytes","configuration":{"endian":"little"}}]}',
    type
  )
}
for (type in c("int64", "uint64", "uint32")) {
  d <- file.path(dir, type)
  dir.create(file.path(d, "c"), recursive = TRUE)
  writeLines(meta(type), file.path(d, "zarr.json"))
  con <- file(file.path(d, "c", "0"), "wb")
  if (type == "uint32") {
    writeBin(as.raw(c(0xff, 0xff, 0xff, 0xff, 1, 0, 0, 0, 0, 0, 0, 0x80)), con)
  } else {
    # 1, 2^40, 2^63 + 5 (little-endian)
    writeBin(as.raw(c(1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0x80)), con)
  }
  close(con)
  r <- tryCatch(Rarr::read_zarr_array(d), error = function(e) conditionMessage(e), warning = function(w) paste("W", conditionMessage(w)))
  cat(type, ":", class(r), typeof(r), format(r, digits = 17), "\n")
}
