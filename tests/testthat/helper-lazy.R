# The lazy operations table written by tests/python/lazy_cases.py
lazy_cases <- function() {
  jsonlite::fromJSON(fixture_path("lazy_cases.json"), simplifyVector = FALSE)
}

lazy_formats <- c("h5ad", "zarr_v3", "zarr_v2")

# The table row of an operation for one format
lazy_row <- function(section, operation, format) {
  lazy_cases()[[section]][[operation]][[format]]
}
