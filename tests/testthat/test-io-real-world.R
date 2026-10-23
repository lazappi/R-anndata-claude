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
# The exceptions are the rec-array field dtypes (ADR 0005, so Python's own
# comparison would fail on them) and sparse indices stored unsorted (ADR 0006)
test_that("the PBMC 3k example file reads and round trips with equivalence", {
  skip_if_no_python()
  # The download uses a legacy format (its compound `/obsm` is not yet
  # supported, see legacy-formats/06), so Python rewrites it with the current
  # encodings and that file is the original
  original <- python_rewrite_h5ad(download_pbmc3k())

  adata <- read_h5ad(original)
  expect_s3_class(adata, "AnnData")
  expect_equal(dim(adata), c(2638L, 1838L))

  written <- withr::local_tempfile(fileext = ".h5ad")
  write_h5ad(adata, written)

  rank_genes <- paste0("/uns/rank_genes_groups/", c("names", "scores"))
  expect_all_equivalent(
    written,
    original,
    rec_array_paths = rank_genes,
    sorted_paths = c("/raw/X/data", "/raw/X/indices")
  )
  for (name in rank_genes) {
    expect_rec_array_values_equal(written, original, name)
  }
  # Python reads the R-written file (the rewrite errors if it cannot)
  expect_length(python_rewrite_h5ad(written), 1L)

  # Reading the R-written file back gives the same object, so `/raw/X` matches
  # the original by value (any other unsorted sparse Element would fail the
  # digest comparison above, as only the `/raw/X` paths are exempt)
  reread <- read_h5ad(written)
  expect_equal(reread, adata)
  expect_equal(reread$raw$X, adata$raw$X)
})
