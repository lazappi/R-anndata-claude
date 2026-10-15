# Asserts the class of a condition rather than its message text
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
