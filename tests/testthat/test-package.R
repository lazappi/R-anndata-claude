# Placeholder so the testthat 3e setup is exercised until real tests exist
test_that("the package namespace loads", {
  expect_true("anndata.claude" %in% loadedNamespaces())
})
