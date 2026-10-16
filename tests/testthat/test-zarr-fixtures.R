# Guards the zarr fixtures, the zarr encoding table and the structural
# comparison of zarr stores (ticket zarr-io/03)

# Offline guard: every case in the zarr manifest has its store, so the suite
# works without Python
test_that("every zarr fixture listed in the manifest exists", {
  manifest <- zarr_fixture_manifest()
  expect_equal(manifest$versions$anndata, "0.13.4")
  expect_setequal(
    names(manifest$variants),
    c(
      "v2",
      "v3",
      "v3_unsharded",
      "v3_unconsolidated",
      "v3_zstd",
      "v3_blosc",
      "v3_gzip",
      "v3_none"
    )
  )
  for (variant in names(manifest$variants)) {
    for (case in manifest$variants[[variant]]$cases) {
      expect_true(
        dir.exists(zarr_fixture_path(case$file)),
        info = case$file
      )
    }
  }
})

# Python writes the same cases as v3 and v2 (the format is the only difference),
# and refuses the same ones
test_that("v3 and v2 fixtures cover the same cases and errors", {
  manifest <- zarr_fixture_manifest()
  expect_setequal(
    names(manifest$variants$v3$cases),
    names(manifest$variants$v2$cases)
  )
  expect_setequal(
    names(manifest$variants$v3$errors),
    names(manifest$variants$v2$errors)
  )
  expect_gt(length(manifest$variants$v3$cases), 100L)
})

# The v3 default writes sharded arrays and v2 and the unsharded variant do not,
# so readers and writers are tested on all the layouts Python produces
test_that("fixtures have the layouts Python writes by default", {
  codecs <- function(path) {
    meta <- jsonlite::fromJSON(
      file.path(path, "zarr.json"),
      simplifyVector = FALSE
    )
    vapply(meta$codecs, function(codec) codec$name, character(1))
  }
  expect_true(
    "sharding_indexed" %in%
      codecs(zarr_fixture_path("v3/anndata_full.zarr/X"))
  )
  expect_false(
    "sharding_indexed" %in%
      codecs(zarr_fixture_path("v3_unsharded/anndata_full.zarr/X"))
  )
  expect_true(
    file.exists(zarr_fixture_path("v2/anndata_full.zarr/X/.zarray"))
  )

  consolidated <- function(path) {
    !is.null(
      jsonlite::fromJSON(
        file.path(path, "zarr.json"),
        simplifyVector = FALSE
      )$consolidated_metadata
    )
  }
  expect_true(consolidated(zarr_fixture_path("v3/anndata_full.zarr")))
  expect_false(
    consolidated(zarr_fixture_path("v3_unconsolidated/anndata_full.zarr"))
  )
  expect_true(
    file.exists(zarr_fixture_path("v2/anndata_full.zarr/.zmetadata"))
  )

  # Each compressor variant uses its codec inside the shards of its arrays
  inner_codecs <- function(variant) {
    meta <- jsonlite::fromJSON(
      zarr_fixture_path(file.path(
        variant,
        "csr_float64.zarr",
        "x",
        "data",
        "zarr.json"
      )),
      simplifyVector = FALSE
    )
    vapply(
      meta$codecs[[1]]$configuration$codecs,
      function(codec) codec$name,
      character(1)
    )
  }
  for (name in c("zstd", "blosc", "gzip")) {
    expect_true(name %in% inner_codecs(paste0("v3_", name)), info = name)
  }
  expect_identical(inner_codecs("v3_none"), "bytes")
})

# Guards the zarr encoding table like the h5ad one: its observed block is
# generated from the fixtures, so it must match what regenerating it gives
test_that("the committed zarr encoding table matches the fixtures", {
  skip_if_no_python()
  doc <- testthat::test_path(
    "..",
    "..",
    ".scratch",
    "zarr-io",
    "encoding-table.md"
  )
  skip_if_not(file.exists(doc), "the encoding table is not in the check copy")

  copy <- withr::local_tempfile(fileext = ".md")
  file.copy(doc, copy)
  run_python(
    "zarr_encoding_table.py",
    zarr_fixture_dir(),
    copy
  )

  expect_equal(readLines(copy), readLines(doc))
})

# Guards determinism: regenerating must not change any fixture structurally,
# and the manifests (including the errors Python raises) must be identical
test_that("regenerated zarr fixtures are deterministic and committed", {
  skip_if_no_python()

  first <- withr::local_tempdir()
  second <- withr::local_tempdir()
  run_python("generate_zarr_fixtures.py", first)
  run_python("generate_zarr_fixtures.py", second)

  manifest <- zarr_fixture_manifest()
  expect_equal(
    readLines(file.path(first, "manifest.json")),
    readLines(file.path(second, "manifest.json"))
  )
  expect_equal(
    readLines(file.path(first, "manifest.json")),
    readLines(zarr_fixture_path("manifest.json"))
  )
  files <- unlist(lapply(manifest$variants, function(variant) {
    vapply(variant$cases, function(case) case$file, character(1))
  }))
  expect_all_equivalent(file.path(first, files), file.path(second, files))
  expect_all_equivalent(
    file.path(first, files),
    zarr_fixture_path(files)
  )
})

# Structural equivalence must ignore chunk shape, codecs, shard layout and the
# zarr version, because R's defaults need not match Python's
test_that("zarr stores written with different layouts are equivalent", {
  skip_if_no_python()
  v3 <- zarr_variant_paths("v3")
  a <- character()
  b <- character()
  for (variant in setdiff(names(zarr_fixture_manifest()$variants), "v3")) {
    paths <- zarr_variant_paths(variant)
    a <- c(a, v3[names(paths)])
    b <- c(b, paths)
  }
  expect_gt(length(b), 20L)
  expect_all_equivalent(unname(a), unname(b))
})

# Python writes v3 and v2 of every case, which only differ in the zarr format,
# so the whole set checks the zarr tree helper on all encodings
test_that("every case is equivalent in v3 and v2", {
  skip_if_no_python()
  v3 <- zarr_variant_paths("v3")
  v2 <- zarr_variant_paths("v2")[names(v3)]
  expect_all_equivalent(unname(v3), unname(v2))
})

# The comparison must report differences, or an always-passing helper would
# make every later round-trip test meaningless
test_that("zarr stores that differ are reported", {
  skip_if_no_python()
  v3 <- zarr_variant_paths("v3")
  differences <- function(a, b) {
    prefetch_h5_trees(c(a, b))
    h5_tree_differences(h5_tree(a), h5_tree(b))
  }
  expect_match(
    differences(v3[["array_float64_2d"]], v3[["array_int32_2d"]]),
    "dtype differs",
    all = FALSE
  )
  expect_match(
    differences(v3[["scalar_python_str"]], v3[["scalar_str_empty"]]),
    "digest differs",
    all = FALSE
  )
  expect_match(
    differences(v3[["categorical"]], v3[["categorical_ordered"]]),
    "attribute `ordered`",
    all = FALSE
  )

  # A missing group member and an extra attribute are both reported (the
  # unconsolidated store is used, as consolidated metadata would hide edits)
  full <- zarr_variant_paths("v3")[["anndata_full"]]
  edited <- zarr_variant_paths("v3_unconsolidated")[["anndata_full"]]
  broken <- withr::local_tempdir()
  file.copy(edited, broken, recursive = TRUE)
  copy <- file.path(broken, basename(edited))
  unlink(file.path(copy, "obsm"), recursive = TRUE)
  meta_file <- file.path(copy, "uns", "zarr.json")
  meta <- jsonlite::fromJSON(meta_file, simplifyVector = FALSE)
  meta$attributes$extra <- "x"
  writeLines(
    jsonlite::toJSON(meta, auto_unbox = TRUE, null = "null"),
    meta_file
  )
  prefetch_h5_trees(c(full, copy))
  diffs <- h5_tree_differences(h5_tree(full), h5_tree(copy))
  expect_match(diffs, "/obsm: only in the first file", all = FALSE)
  expect_match(diffs, "attribute `extra` only in the second file", all = FALSE)
})

# A zarr store and an h5ad file of the same object are Structurally equivalent,
# which the cross-format tests of later tickets rely on
test_that("zarr stores are equivalent to the h5ad fixtures of the same case", {
  skip_if_no_python()
  manifest <- jsonlite::fromJSON(
    fixture_path("manifest.json"),
    simplifyVector = FALSE
  )
  v3 <- zarr_variant_paths("v3")
  shared <- intersect(names(v3), names(manifest$cases))
  h5 <- vapply(
    manifest$cases[shared],
    function(case) fixture_path(case$file),
    character(1)
  )
  zarr <- unname(v3[shared])
  prefetch_h5_trees(c(h5, zarr))
  for (i in seq_along(shared)) {
    a <- h5_tree(h5[[i]])
    b <- h5_tree(zarr[[i]])
    # rec-arrays keep their field dtypes in zarr and not in HDF5 (ADR 0005)
    is_rec <- vapply(
      b,
      function(node) {
        identical(node$attrs[["encoding-type"]]$value, "rec-array")
      },
      logical(1)
    )
    diffs <- h5_tree_differences(
      a,
      b,
      rec_array_paths = names(b)[is_rec],
      attr_types = FALSE
    )
    # Python writes the missing `raw` of zarr as a `null` Element and skips it
    # in HDF5, so a writer must follow zarr here
    if (!"/raw" %in% names(a) && "/raw" %in% names(b)) {
      expect_identical(
        b[["/raw"]]$attrs[["encoding-type"]]$value,
        "null",
        info = shared[[i]]
      )
      diffs <- setdiff(diffs, "/raw: only in the second file")
    }
    expect_identical(diffs, character(), info = shared[[i]])
  }
})
