# Tests of lazy obs and var (ticket lazy/06): a LazyDFrame subsets, prints and
# realises to what read_h5ad()/read_zarr() read, on h5ad, zarr v3 and zarr v2.

skip_if_not_installed("Rarr", "2.1.48")

frame_case_names <- sub(
  "\\.h5$",
  "",
  list.files(fixture_path("h5ad"), pattern = "^df_.*\\.h5$")
)

# Opens fixture `case` of `format`, closed at the end of the test
frame_fixture_store <- function(case, format, env = parent.frame()) {
  if (format == "h5ad") {
    withr::defer(rhdf5::h5closeAll(), envir = env)
    return(rhdf5::H5Fopen(
      fixture_path(file.path("h5ad", paste0(case, ".h5"))),
      flags = "H5F_ACC_RDONLY"
    ))
  }
  variant <- if (format == "zarr_v3") "v3" else "v2"
  zarr_open(zarr_variant_paths(variant)[[case]])
}

test_that("dataframe fixtures are found", {
  # Guards the case list, so the loops below cannot silently run on nothing
  expect_gt(length(frame_case_names), 30L)
})

test_that("a lazy frame realises to the frame read_elem() gives", {
  # The acceptance criterion: every dataframe fixture, on every format and with
  # both values of load_annotation_index
  for (format in lazy_formats) {
    for (case in frame_case_names) {
      label <- paste(format, case)
      store <- frame_fixture_store(case, format)
      truth <- read_elem(store, "x")
      for (load in c(TRUE, FALSE)) {
        lazy <- lazy_dataframe(store, "/x", load_annotation_index = load)
        expect_s4_class(lazy, "LazyDFrame")
        expect_identical(
          lazy_dataframe_realise(lazy),
          truth,
          label = paste(label, "load", load)
        )
      }
    }
  }
})

test_that("a lazy frame keeps its columns lazy", {
  # Reading is metadata only, so no column is a plain vector
  store <- frame_fixture_store("df_all_types", "h5ad")
  lazy <- lazy_dataframe(store, "/x")
  lazy_kinds <- vapply(
    as.list(lazy),
    function(col) {
      methods::is(col, "DelayedArray") ||
        methods::is(col, "LazyCategorical") ||
        methods::is(col, "LazyNullable")
    },
    logical(1)
  )
  expect_true(all(lazy_kinds))
  expect_gt(length(lazy_kinds), 3L)
})

test_that("row and column subsets realise to the eager subsets", {
  # Subsetting a lazy frame (also with a lazy index) follows DataFrame, with
  # repeated and unsorted rows
  for (format in lazy_formats) {
    for (case in c("df_all_types", "df_index_named", "df_col_categorical")) {
      label <- paste(format, case)
      store <- frame_fixture_store(case, format)
      truth <- read_elem(store, "x")
      rows <- c(2L, 1L, 2L)
      for (load in c(TRUE, FALSE)) {
        lazy <- lazy_dataframe(store, "/x", load_annotation_index = load)
        got <- lazy_dataframe_realise(lazy[rows, , drop = FALSE])
        # Eager row subsetting drops the dtype records the lazy columns keep
        expect_identical(
          lapply(as.list(got), drop_dtype),
          lapply(as.list(truth[rows, , drop = FALSE]), drop_dtype),
          label = label
        )
        expect_identical(
          rownames(got),
          rownames(truth[rows, , drop = FALSE]),
          label = label
        )
      }
      lazy <- lazy_dataframe(store, "/x")
      expect_identical(
        lazy_dataframe_realise(lazy[, 1, drop = FALSE]),
        truth[, 1, drop = FALSE],
        label = label
      )
    }
  }
})

test_that("column subsets follow an unloaded index", {
  # The lazy index must survive column subsetting and a following row subset
  for (format in lazy_formats) {
    store <- frame_fixture_store("df_all_types", format)
    truth <- read_elem(store, "x")
    lazy <- lazy_dataframe(store, "/x", load_annotation_index = FALSE)
    got <- lazy_dataframe_realise(lazy[, c("ni", "s", "cat")][c(3L, 1L), ])
    expect_identical(colnames(got), c("ni", "s", "cat"), label = format)
    expect_identical(
      rownames(got),
      rownames(truth)[c(3L, 1L)],
      label = format
    )
    expect_identical(
      lapply(as.list(got), drop_dtype),
      lapply(as.list(truth[c(3L, 1L), c("ni", "s", "cat")]), drop_dtype),
      label = format
    )
  }
})

test_that("lazy_column rejects an array that is not 1-d", {
  # Columns are 1-d, a matrix Element is not a column
  store <- frame_fixture_store("array_float64_2d", "h5ad")
  expect_error(
    lazy_column(store, "/x"),
    "dimensions",
    class = "anndata_io_registry_error"
  )
})

test_that("an unloaded index is NULL row names and realises on demand", {
  # Python's dummy range index when load_annotation_index is FALSE
  store <- frame_fixture_store("df_index_named", "h5ad")
  truth <- read_elem(store, "x")
  lazy <- lazy_dataframe(store, "/x", load_annotation_index = FALSE)
  expect_null(rownames(lazy))
  expect_identical(nrow(lazy), nrow(truth))
  expect_identical(
    rownames(lazy_dataframe_realise(lazy)),
    rownames(truth)
  )
})

test_that("lazy frames print and convert to data frames", {
  # Printing shows the first rows and as.data.frame() realises every column
  store <- frame_fixture_store("df_all_types", "zarr_v3")
  truth <- read_elem(store, "x")
  lazy <- lazy_dataframe(store, "/x")
  out <- capture.output(show(lazy))
  expect_true(any(grepl("LazyDFrame", out)))
  # Categorical and nullable cells are shown through showAsCell()
  expect_true(any(grepl(as.character(truth$cat[1]), out, fixed = TRUE)))
  unloaded <- lazy_dataframe(store, "/x", load_annotation_index = FALSE)
  expect_true(any(grepl(
    "LazyDFrame",
    capture.output(show(unloaded))
  )))
  expect_identical(as.data.frame(lazy), as.data.frame(truth))
})

test_that("lazy columns subset and print", {
  # The small classes define length, [ and show like the spec asks
  store <- frame_fixture_store("df_all_types", "h5ad")
  col <- lazy_column(store, "/x/cat")
  expect_s4_class(col, "LazyCategorical")
  truth <- read_elem(store, "x")[["cat"]]
  expect_identical(length(col), length(truth))
  expect_identical(as.vector(col[2:1]), truth[2:1])
  expect_output(show(col), "LazyCategorical")
  expect_error(
    lazy_column(store, "/x"),
    class = "anndata_io_registry_error"
  )
})
