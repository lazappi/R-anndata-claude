# Guards the committed lazy operations table against drifting from Python
test_that("the committed lazy operations table matches Python", {
  expect_generator_current("lazy_cases.py")
})

# The table must keep covering every operation the lazy spec lists, so later
# tickets can test each row against its R equivalent
test_that("the lazy operations table covers the operations in the spec", {
  cases <- lazy_cases()
  expect_setequal(
    names(cases),
    c("read_lazy", "read_elem_lazy", "operations", "dask_chunks")
  )
  expect_true(all(
    c(
      "default",
      "load_annotation_index_true",
      "load_annotation_index_false",
      "missing_store",
      "unconsolidated_zarr"
    ) %in%
      names(cases$read_lazy)
  ))
  encodings <- c(
    "dense_float32",
    "dense_bool",
    "csr_float32",
    "csc_float64",
    "categorical",
    "nullable_integer",
    "nullable_boolean",
    "nullable_string",
    "string_array",
    "dataframe_obs",
    "uns_dict",
    "uns_scalar"
  )
  expect_true(all(
    paste0(encodings, "_default") %in% names(cases$read_elem_lazy)
  ))
  expect_true(any(grepl("_chunks_", names(cases$read_elem_lazy))))
  operations <- c(
    "subset_names",
    "subset_slices",
    "view_of_view",
    "to_memory",
    "repr",
    "write_h5ad",
    "write_zarr",
    "write_h5ad_after_to_memory",
    "write_zarr_after_to_memory",
    "write_view_h5ad"
  )
  expect_true(all(operations %in% names(cases$operations)))
  expect_true(all(
    c("tall_csr_f32", "tall_csc_f64", "tall_dense_i64") %in%
      names(cases$dask_chunks)
  ))
})

# Every row records all three formats, so tests can loop over them
test_that("every row of the lazy operations table has all three formats", {
  cases <- lazy_cases()
  for (section in names(cases)) {
    for (operation in names(cases[[section]])) {
      row <- cases[[section]][[operation]]
      if (identical(operation, "unconsolidated_zarr")) {
        expect_named(row, "zarr_v2")
      } else {
        expect_setequal(names(row), lazy_formats)
      }
    }
  }
})
