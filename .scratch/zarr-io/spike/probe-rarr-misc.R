# Probe Rarr devel: partial reads, attributes, consolidated metadata, zip.
# Usage: Rscript probe-rarr-misc.R <fixture dir (out/)>
out <- commandArgs(TRUE)[[1]]
suppressMessages(library(Rarr))
say <- function(label, expr) {
  res <- tryCatch(
    paste(utils::capture.output(print(expr)), collapse = " | "),
    error = function(e) paste("ERROR", conditionMessage(e))
  )
  cat(sprintf("%-26s %s\n", label, substr(res, 1, 230)))
}
for (v in c("v2", "v3")) {
  lay <- file.path(out, v, "layout.zarr")
  say(
    paste(v, "partial rows 2:3, cols 2:3"),
    read_zarr_array(file.path(lay, "chunked"), index = list(2:3, 2:3))
  )
  say(
    paste(v, "partial NULL cols"),
    read_zarr_array(file.path(lay, "chunked"), index = list(1:2, NULL))
  )
  say(paste(v, "overview"), zarr_overview(file.path(lay, "chunked"), as_data_frame = TRUE))
  say(paste(v, "group attrs"), read_zarr_attributes(file.path(out, v, "types.zarr")))
  say(paste(v, "consolidated"), names(read_zarr_consolidated_metadata(file.path(out, v, "types.zarr"))))
}
for (z in list.files(out, pattern = "zip$", recursive = TRUE, full.names = TRUE)) {
  say(paste("zip", basename(z)), read_zarr_attributes(z))
  say(paste("zip array", basename(z)), read_zarr_array(file.path(z, "x")))
}
