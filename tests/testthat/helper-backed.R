# The backed operations table written by tests/python/backed_cases.py
backed_cases <- function() {
  jsonlite::fromJSON(fixture_path("backed_cases.json"), simplifyVector = FALSE)
}

backed_kinds <- c("dense", "csr", "csc")
backed_modes <- c("r", "r+")

# The table row of an operation for one kind of X and one mode
backed_row <- function(operation, kind, mode, table = "operations") {
  backed_cases()[[table]][[operation]][[kind]][[mode]]
}

# Python's record of the object's state after an operation, which R mirrors
expect_backed_state <- function(adata, state) {
  expect_equal(adata$isbacked, state$isbacked)
  expect_equal(basename(adata$filename %||% ""), state$filename %||% "")
  expect_equal(adata$file$is_open, state$file_is_open)
  expect_equal(adata$file$filemode, state$file_mode)
}

# The 4 x 3 matrix the table's files hold, from a list of rows
table_matrix <- function(rows) {
  do.call(rbind, lapply(rows, unlist))
}

# The AnnData of tests/python/backed_cases.py: a 4 x 3 float32 X (1 to 12 by
# row) as dense, csr or csc, an obs column `g` and a layer `l`
backed_source <- function(kind, raw = FALSE) {
  x <- matrix(as.numeric(1:12), nrow = 4, byrow = TRUE)
  csc <- methods::as(x, "CsparseMatrix")
  x <- switch(
    kind,
    dense = set_dtype(x, "float32"),
    csr = set_dtype(methods::as(csc, "RsparseMatrix"), c(data = "float32")),
    csc = set_dtype(csc, c(data = "float32"))
  )
  adata <- AnnData(
    x,
    obs = data.frame(
      g = c("a", "b", "a", "b"),
      row.names = c("w", "x", "y", "z")
    ),
    var = data.frame(row.names = c("p", "q", "r")),
    layers = list(l = x)
  )
  if (raw) {
    adata$raw <- adata
  }
  adata
}

# Writes `backed_source()` to `orig.h5ad` in a fresh directory and reads it
# back in backed `mode`. The file is closed when the calling test ends.
local_backed <- function(kind, mode = "r", raw = FALSE, env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  path <- file.path(dir, "orig.h5ad")
  write_h5ad(backed_source(kind, raw), path)
  adata <- read_h5ad(path, backed = mode)
  withr::defer(adata$file$close(), envir = env)
  list(adata = adata, path = path, dir = dir)
}

# Runs `code(case, row, kind)` for every kind of X (or `kinds`) and mode, with
# the table row of `operation` and the backed object, to check R against it
for_each_backed <- function(
  operation,
  code,
  ...,
  table = "operations",
  kinds = backed_kinds
) {
  for (kind in kinds) {
    for (mode in backed_modes) {
      case <- local_backed(kind, mode, ...)
      row <- backed_row(operation, kind, mode, table)
      code(case, row, kind)
    }
  }
}

# Whether the file can be opened read-write, which fails while this process
# holds it open read-only
file_is_free <- function(path) {
  handle <- tryCatch(
    rhdf5::H5Fopen(path, flags = "H5F_ACC_RDWR"),
    error = function(e) NULL
  )
  if (is.null(handle)) {
    return(FALSE)
  }
  rhdf5::H5Fclose(handle)
  TRUE
}
