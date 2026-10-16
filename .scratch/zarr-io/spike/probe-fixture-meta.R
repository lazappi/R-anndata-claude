out <- file.path(tempdir(), "zfx")
dir.create(out)
utils::untar("tests/testthat/fixtures/zarr-fixtures.tar.gz", exdir = out)
cases <- list.files(file.path(out, "v3"))
print(grep("scalar|string|null|bytes", cases, value = TRUE))
show <- function(case) {
  files <- list.files(file.path(out, "v3", case), recursive = TRUE, all.files = TRUE)
  for (f in files) {
    path <- file.path(out, "v3", case, f)
    cat("##", case, f, "\n")
    if (basename(f) == "zarr.json") {
      cat(gsub("\\s+", " ", paste(readLines(path), collapse = " ")), "\n")
    } else {
      cat(paste(as.character(readBin(path, "raw", 64)), collapse = ""), "\n")
    }
  }
}
for (case in c("scalar_python_str.zarr", "scalar_complex128.zarr", "string_array_2d.zarr", "string_array_empty.zarr", "df_col_str_allow_nullable_true.zarr")) {
  if (case %in% cases) show(case)
}
