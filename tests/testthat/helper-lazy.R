# The lazy operations table written by tests/python/lazy_cases.py
lazy_cases <- function() {
  jsonlite::fromJSON(fixture_path("lazy_cases.json"), simplifyVector = FALSE)
}

lazy_formats <- c("h5ad", "zarr_v3", "zarr_v2")

# The 4 x 3 AnnData of the lazy operations table, written to h5ad and zarr v3
# (R cannot write v2) in a directory removed at the end of the test
lazy_small_paths <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  x <- matrix(as.numeric(0:11), nrow = 4, byrow = TRUE)
  mask <- x %% 3 == 0
  adata <- AnnData(
    X = x,
    obs = data.frame(
      num = c(1, 2, 3, 4),
      ni = set_nullable(c(1L, NA, 3L, 4L)),
      nb = set_nullable(c(TRUE, NA, FALSE, TRUE)),
      cat = factor(c("a", "b", "a", NA), levels = c("a", "b", "c")),
      row.names = paste0("o", 0:3)
    ),
    var = data.frame(g = c(1, 2, 3), row.names = paste0("v", 0:2)),
    layers = list(
      dense_i = array(as.integer(x), dim = dim(x)),
      dense_bool = mask,
      csr = methods::as(
        methods::as(x * mask, "generalMatrix"),
        "RsparseMatrix"
      ),
      csc = methods::as(methods::as(x * mask, "generalMatrix"), "CsparseMatrix")
    )
  )
  h5ad <- file.path(dir, "small.h5ad")
  zarr <- file.path(dir, "small.zarr")
  write_h5ad(adata, h5ad)
  write_zarr(adata, zarr)
  list(h5ad = h5ad, zarr_v3 = zarr)
}

# The table row of an operation for one format
lazy_row <- function(section, operation, format) {
  lazy_cases()[[section]][[operation]][[format]]
}
