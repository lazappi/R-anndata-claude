# Asserts the class of a condition rather than its message text
# Silences only the deprecation warning, for tests of deprecated methods
quiet_deprecated <- function(expr) {
  suppressWarnings(expr, classes = "anndata_deprecated_warning")
}

expect_anndata_condition <- function(expr, class) {
  cnd <- tryCatch(
    {
      expr
      NULL
    },
    condition = identity
  )
  testthat::expect_s3_class(cnd, class)
  invisible(cnd)
}
