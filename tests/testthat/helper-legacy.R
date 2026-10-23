legacy_table <- function() {
  jsonlite::fromJSON(
    fixture_path("legacy_cases.json"),
    simplifyVector = FALSE
  )
}
