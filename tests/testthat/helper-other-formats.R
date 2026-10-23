other_formats_table <- function() {
  jsonlite::fromJSON(
    fixture_path("other_formats_cases.json"),
    simplifyVector = FALSE
  )
}
