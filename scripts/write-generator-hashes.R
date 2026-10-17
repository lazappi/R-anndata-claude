# Writes tests/testthat/fixtures/generator-hashes.json, the hashes of the Python
# generators that the freshness tests compare (see `generator_hash()` in
# tests/testthat/helper-python.R). Run by scripts/regenerate-fixtures.sh.
source("tests/testthat/helper-python.R")

dir <- file.path("tests", "python")
inputs <- generator_inputs()
hashes <- lapply(names(inputs), function(script) {
  generator_hash(script, inputs[[script]], dir = dir)
})
names(hashes) <- names(inputs)
jsonlite::write_json(
  hashes,
  file.path("tests", "testthat", "fixtures", "generator-hashes.json"),
  auto_unbox = TRUE,
  pretty = TRUE
)
