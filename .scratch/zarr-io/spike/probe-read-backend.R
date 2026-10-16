# What Rarr returns for the fixture arrays, for the zarr read backend (zarr-io/04)
# Usage: Rscript probe-read-backend.R <unpacked fixture dir>
dir <- commandArgs(TRUE)[[1]]
cases <- c(
  "array_bool", "array_bool_2d", "array_complex128", "array_complex64",
  "array_float64_0x3", "array_float64_1elem", "array_float64_empty",
  "array_int32_min", "array_int64", "array_uint32", "array_uint64",
  "array_uint8", "array_int8", "scalar_int64", "scalar_str_empty",
  "scalar_python_str", "scalar_bool", "scalar_complex128", "scalar_uint64",
  "string_array_1d", "string_array_2d", "string_array_empty", "null",
  "string_array_1elem"
)
for (v in c("v3", "v2")) {
  for (case in cases) {
    p <- file.path(dir, v, paste0(case, ".zarr"), "x")
    out <- tryCatch(
      {
        x <- Rarr::read_zarr_array(p)
        paste(class(x), typeof(x), paste(dim(x), collapse = "x"),
          paste(utils::head(as.vector(x), 4), collapse = ","))
      },
      error = function(e) paste("ERROR", conditionMessage(e))
    )
    cat(v, case, ":", out, "\n")
  }
}
x <- Rarr::read_zarr_attributes(file.path(dir, "v3", "df_two_columns.zarr", "x"))
str(x)
x <- Rarr::read_zarr_attributes(file.path(dir, "v2", "df_two_columns.zarr", "x"))
str(x)
