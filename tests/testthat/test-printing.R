repr_cases <- function() {
  jsonlite::fromJSON(fixture_path("repr_cases.json"), simplifyVector = FALSE)
}

repr_frame <- function(n, columns, prefix) {
  df <- data.frame(row.names = paste0(prefix, seq_len(n) - 1L))
  for (column in columns) {
    df[[column]] <- as.numeric(seq_len(n) - 1L)
  }
  df
}

repr_objects <- function() {
  m <- function(r, c) matrix(0, r, c)
  with_raw <- function(adata) {
    adata$raw <- adata
    adata
  }
  list(
    empty = AnnData(m(3, 2)),
    obs_var = AnnData(
      m(3, 2),
      obs = repr_frame(3, c("a", "b"), "o"),
      var = repr_frame(2, "gene", "v")
    ),
    uns = AnnData(m(3, 2), uns = list(first = 1, second = "x", a = c(1, 2))),
    obsm_varm = AnnData(
      m(3, 2),
      obsm = list(X_pca = m(3, 2), X_umap = m(3, 2)),
      varm = list(PCs = m(2, 2))
    ),
    obsp_varp = AnnData(
      m(3, 2),
      obsp = list(connectivities = m(3, 3)),
      varp = list(corr = m(2, 2))
    ),
    layers = AnnData(
      m(3, 2),
      layers = list(counts = m(3, 2), logcounts = m(3, 2))
    ),
    layers_only_counts = AnnData(m(3, 2), layers = list(counts = m(3, 2))),
    raw = with_raw(AnnData(m(3, 2), obs = repr_frame(3, "a", "o"))),
    all_slots = with_raw(AnnData(
      m(3, 2),
      obs = repr_frame(3, c("a", "b"), "o"),
      var = repr_frame(2, "gene", "v"),
      uns = list(u = 1),
      obsm = list(X_pca = m(3, 2)),
      varm = list(PCs = m(2, 2)),
      obsp = list(c = m(3, 3)),
      varp = list(d = m(2, 2)),
      layers = list(counts = m(3, 2))
    )),
    quotes = AnnData(
      m(3, 2),
      obs = repr_frame(3, c("it's", "say \"hi\"", "plain"), "o"),
      uns = list("a'b" = 1)
    ),
    # Control, non-printable and non-ASCII characters are escaped as repr does
    escapes = AnnData(
      m(3, 2),
      obs = repr_frame(
        3,
        c(
          "new\nline",
          "tab\there",
          "back\\slash",
          paste0("caf", intToUtf8(0xE9)),
          "\001"
        ),
        "o"
      ),
      uns = stats::setNames(
        as.list(1:6),
        c(
          "both'\"",
          paste0("nbsp", intToUtf8(0xA0), "x"),
          paste0("zero", intToUtf8(0x200B), "width"),
          paste0("emoji", intToUtf8(0x1F600)),
          "it's\n",
          "a\"b"
        )
      )
    ),
    no_x = AnnData(
      obs = repr_frame(3, "a", "o"),
      var = repr_frame(2, "gene", "v")
    )
  )
}

# Guards the committed expectations against drifting from what Python gives
test_that("the committed repr expectations match Python", {
  skip_if_no_python()
  fresh <- withr::local_tempfile(fileext = ".json")
  run_python("repr_cases.py", fresh)
  expect_equal(readLines(fresh), readLines(fixture_path("repr_cases.json")))
})

# format() must reproduce Python's repr for objects covering every Slot,
# including Python's key order and quoting
test_that("format() matches the Python repr", {
  expected <- repr_cases()
  objects <- repr_objects()
  expect_setequal(names(objects), names(expected))
  for (label in names(expected)) {
    expect_identical(
      format(objects[[label]]),
      expected[[label]]$repr,
      label = label
    )
  }
})

# print() writes the format and returns the object invisibly
test_that("print() outputs the format and returns the object", {
  adata <- repr_objects()$all_slots
  expect_output(print(adata), format(adata), fixed = TRUE)
  expect_invisible(print(adata))
  expect_identical(withVisible(print(adata))$value, adata)
})
