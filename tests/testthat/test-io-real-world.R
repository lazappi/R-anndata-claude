pbmc3k_url <- paste0(
  "https://raw.githubusercontent.com/chanzuckerberg/cellxgene/main/",
  "example-dataset/pbmc3k.h5ad"
)

# Downloads the PBMC 3k example file of cellxgene (the processed dataset that
# scanpy's `pbmc3k_processed` is built from), skipping when the network is
# unavailable or the download fails
download_pbmc3k <- function(.local_envir = parent.frame()) {
  testthat::skip_on_cran()
  testthat::skip_if(
    identical(Sys.getenv("ANNDATA_SKIP_NETWORK"), "true"),
    "ANNDATA_SKIP_NETWORK is true"
  )
  # A local copy of the file stands in for the download (used where downloads
  # are not allowed)
  # (git-ignored, found when tests run from the source tree)
  local_copy <- testthat::test_path("../../.ralph/oracle/dl/pbmc3k.h5ad")
  if (file.exists(local_copy)) {
    return(normalizePath(local_copy))
  }
  path <- withr::local_tempfile(fileext = ".h5ad", .local_envir = .local_envir)
  withr::local_options(timeout = 300)
  status <- tryCatch(
    suppressWarnings(
      utils::download.file(pbmc3k_url, path, mode = "wb", quiet = TRUE)
    ),
    error = function(e) 1L
  )
  testthat::skip_if(
    !identical(status, 0L) || !file.exists(path) || file.size(path) == 0,
    "Could not download the PBMC 3k file"
  )
  path
}

# A file written by real-world tools (not our fixtures) must read, and writing
# it again must give a file that is structurally equivalent to the original
# and that Python can read.
# The exceptions are the rank_genes_groups fields and sparse indices stored
# unsorted (ADR 0006)
test_that("the PBMC 3k example file reads and round trips with equivalence", {
  skip_if_no_python()
  # The download is a legacy format (compound `/obsm` and `/varm`) that is read
  # directly, and Python's rewrite of it with the current encodings is the
  # original the written file is compared with
  download <- download_pbmc3k()
  original <- python_rewrite_h5ad(download)

  adata <- quietly_read(function() read_h5ad(download))
  expect_s3_class(adata, "AnnData")
  expect_equal(dim(adata), c(2638L, 1838L))
  expect_named(
    adata$obsm,
    c("X_pca", "X_tsne", "X_umap", "X_draw_graph_fr")
  )
  expect_equal(dim(adata$obsm[["X_pca"]]), c(2638L, 50L))
  expect_named(adata$varm, "PCs")
  expect_equal(dim(adata$varm[["PCs"]]), c(1838L, 50L))
  # Reading the download or Python's rewrite gives the same object
  rewritten <- read_h5ad(original)
  expect_equal(adata$X, rewritten$X)
  expect_equal(adata$raw$X, rewritten$raw$X)
  expect_equal(adata$obsm, rewritten$obsm)
  expect_equal(adata$varm, rewritten$varm)
  expect_equal(adata$obsp, rewritten$obsp)
  # The legacy rank_genes_groups rec-array has fixed-length string fields that
  # R keeps (with a dtype record) and Python's rewrite makes variable-length
  expect_equal(adata$uns, rewritten$uns, ignore_attr = TRUE)
  expect_equal(
    as.data.frame(adata$obs),
    as.data.frame(rewritten$obs),
    ignore_attr = TRUE
  )

  written <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(adata, written)

  # The rank_genes_groups fields stay fixed-length strings (see above)
  expect_all_equivalent(
    written,
    original,
    rec_array_paths = paste0(
      "/uns/rank_genes_groups/",
      c("names", "scores")
    ),
    sorted_paths = c("/raw/X/data", "/raw/X/indices")
  )
  # Python reads the R-written file (the rewrite errors if it cannot)
  expect_length(python_rewrite_h5ad(written), 1L)

  # Reading the R-written file back gives the same object, so `/raw/X` matches
  # the original by value (any other unsorted sparse Element would fail the
  # digest comparison above, as only the `/raw/X` paths are exempt)
  reread <- read_h5ad(written)
  expect_equal(reread, adata)
  expect_equal(reread$raw$X, adata$raw$X)
})
