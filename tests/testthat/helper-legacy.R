legacy_zarr_dir <- local({
  dir <- NULL
  function() {
    if (is.null(dir)) {
      dir <<- tempfile("legacy-zarr")
      dir.create(dir)
      utils::untar(fixture_path("legacy-zarr-fixtures.tar.gz"), exdir = dir)
    }
    dir
  }
})

# Reads a legacy file with `read_fun`, muffling the old format and future
# warnings that Python records without stopping
quietly_read <- function(read_fun) {
  withCallingHandlers(
    read_fun(),
    anndata_old_format_warning = function(cnd) rlang::cnd_muffle(cnd),
    anndata_future_warning = function(cnd) rlang::cnd_muffle(cnd)
  )
}

legacy_table <- function() {
  jsonlite::fromJSON(
    fixture_path("legacy_cases.json"),
    simplifyVector = FALSE
  )
}
