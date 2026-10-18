# Tests of the dense lazy seed (ticket lazy/04): StoreDenseSeed realises to what
# read_h5ad()/read_zarr() read, on h5ad, zarr v3 and zarr v2.

skip_if_not_installed("Rarr", "2.1.48")

dense_case_names <- sub(
  "\\.h5$",
  "",
  list.files(fixture_path("h5ad"), pattern = "^array_.*\\.h5$")
)
# complex arrays are not numeric seeds
dense_case_names <- setdiff(
  dense_case_names,
  c("array_complex64", "array_complex128")
)

# Opens fixture `case` of `format` and returns its store, closed at test end
dense_fixture_store <- function(case, format, env = parent.frame()) {
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

test_that("dense fixtures are found", {
  # Guards the case list, so the loops below cannot silently run on nothing
  expect_gt(length(dense_case_names), 15L)
})

test_that("a seed realises to the values read_elem() gives", {
  # The acceptance criterion: lazy values equal eager values for every dense
  # fixture on every format, with the On-disk dtype record and the 2^53 error
  for (format in lazy_formats) {
    for (case in dense_case_names) {
      label <- paste(format, case)
      store <- dense_fixture_store(case, format)
      truth <- read_elem(store, "x")
      seed <- store_dense_seed(store, "/x")
      if (case == "array_int32_min") {
        # Documented deviation (spec "Behaviour"): eager reads return double for
        # -2^31 (the NA_integer_ pattern) but a seed's type is fixed, so it
        # raises and suggests an eager read
        expect_error(
          store_dense_values(seed),
          "eagerly",
          class = "anndata_dtype_overflow_error",
          label = label
        )
        next
      }
      expect_identical(store_dense_values(seed), truth, label = label)
      # The type is fixed from the dtype and the DelayedArray agrees
      expect_identical(
        DelayedArray::type(seed),
        typeof(unclass(truth)),
        label = label
      )
      expect_identical(
        unname(as.array(DelayedArray::DelayedArray(seed))),
        unname(array(unclass(drop_dtype(truth)), dim = dim(seed))),
        label = label
      )
    }
  }
})

test_that("block reads with any index form equal subsetting the eager values", {
  # Repeated and unsorted positions follow base arrays, on every format
  for (format in lazy_formats) {
    store <- dense_fixture_store("array_float32", format)
    truth <- unclass(drop_dtype(read_elem(store, "x")))
    seed <- store_dense_seed(store, "/x")
    arr <- DelayedArray::DelayedArray(seed)
    if (is.null(dim(truth))) {
      n <- length(truth)
      i <- c(n, 1L, 1L)
      expect_identical(as.vector(arr[i]), truth[i], label = format)
    } else {
      expect_identical(
        as.matrix(arr[c(2, 1, 2), ]),
        truth[c(2, 1, 2), ],
        label = format
      )
    }
  }
})

test_that("a 2-D block with repeated, unsorted indices matches base", {
  # Uses a written array so the shape is known, on h5ad and both zarr versions
  dir <- withr::local_tempdir()
  values <- matrix(as.numeric(1:60), nrow = 10)
  h5 <- file.path(dir, "m.h5")
  rhdf5::h5createFile(h5)
  fid <- rhdf5::H5Fopen(h5)
  write_elem(fid, "x", values)
  rhdf5::h5closeAll()
  stores <- list(
    h5ad = rhdf5::H5Fopen(h5, flags = "H5F_ACC_RDONLY"),
    zarr_v3 = {
      s <- zarr_create(file.path(dir, "m.zarr"))
      write_elem(s, "x", values)
      s
    }
  )
  withr::defer(rhdf5::h5closeAll())
  for (format in names(stores)) {
    arr <- DelayedArray::DelayedArray(store_dense_seed(stores[[format]], "/x"))
    expect_identical(
      as.matrix(arr[c(9, 3, 3, 10), c(6, 1)]),
      values[c(9, 3, 3, 10), c(6, 1)],
      label = format
    )
    expect_identical(as.matrix(arr[0, ]), values[0, ], label = format)
    expect_identical(as.matrix(arr[, 2:3]), values[, 2:3], label = format)
  }
})

test_that("block reads read only their block", {
  # Lazy means the seed holds no data and a block asks the store for just its
  # sorted unique positions, nothing more
  dir <- withr::local_tempdir()
  s <- zarr_create(file.path(dir, "m.zarr"))
  write_elem(s, "x", matrix(as.numeric(1:60), nrow = 10))
  seed <- store_dense_seed(s, "/x")
  selections <- list()
  testthat::local_mocked_bindings(
    array_read = function(store, path, selection = NULL, call = NULL) {
      selections[length(selections) + 1L] <<- list(selection)
      do.call(
        `[`,
        c(
          list(matrix(as.numeric(1:60), nrow = 10)),
          lapply(selection, function(i) i),
          list(drop = FALSE)
        )
      )
    }
  )
  block <- lazy_dense_block(seed, list(c(5L, 2L, 5L), 3L))
  expect_length(selections, 1L)
  expect_identical(selections[[1L]], list(c(2L, 5L), 3L))
  expect_identical(dim(block), c(3L, 1L))
  # A full dimension is passed as NULL and a full block as no selection
  lazy_dense_block(seed, list(NULL, 2L))
  expect_identical(selections[[2L]], list(NULL, 2L))
  lazy_dense_block(seed, list(NULL, NULL))
  expect_null(selections[[3L]])
})

extract_array_all <- function(seed) {
  DelayedArray::extract_array(seed, lapply(dim(seed), function(n) 1L))
}

test_that("a seed type does not depend on the size of the read", {
  # h5ad selections of int64, uint32 and uint64 are integer, but the seed is
  # double as in read_h5ad()
  for (case in c("array_int64", "array_uint32", "array_uint64")) {
    for (format in lazy_formats) {
      store <- dense_fixture_store(case, format)
      seed <- store_dense_seed(store, "/x")
      expect_identical(
        DelayedArray::type(seed),
        "double",
        label = paste(format, case)
      )
      expect_type(extract_array_all(seed), "double")
    }
  }
})

test_that("chunkdim follows Python's default and explicit chunks", {
  # Rows of the lazy table: contiguous HDF5 gives min(1000, axis), explicit
  # fill NA/-1 with the axis, and zarr uses its own chunk shape
  dir <- withr::local_tempdir()
  values <- matrix(as.numeric(1:12), nrow = 4)
  h5 <- file.path(dir, "m.h5")
  rhdf5::h5createFile(h5)
  fid <- rhdf5::H5Fopen(h5)
  write_elem(fid, "x", values)
  rhdf5::h5closeAll()
  store <- rhdf5::H5Fopen(h5, flags = "H5F_ACC_RDONLY")
  withr::defer(rhdf5::h5closeAll())
  first <- function(row) {
    vapply(row$result$chunks, function(axis) axis[[1L]], numeric(1))
  }
  default <- lazy_row("read_elem_lazy", "dense_float32_default", "h5ad")
  expect_identical(
    DelayedArray::chunkdim(store_dense_seed(store, "/x")),
    as.integer(first(default))
  )
  for (case in c("chunks_2_2", "chunks_minus1_none")) {
    row <- lazy_row("read_elem_lazy", paste0("dense_float32_", case), "h5ad")
    chunks <- switch(case, chunks_2_2 = c(2, 2), chunks_minus1_none = c(-1, NA))
    expect_identical(
      DelayedArray::chunkdim(store_dense_seed(store, "/x", chunks = chunks)),
      as.integer(first(row)),
      label = case
    )
  }
  expect_error(
    store_dense_seed(store, "/x", chunks = 2),
    class = "anndata_invalid_value_error"
  )
  # A tall unchunked array is cut every 1000 rows
  tall <- matrix(0, nrow = 2500, ncol = 4)
  rhdf5::H5Fclose(store)
  fid <- rhdf5::H5Fopen(h5)
  write_elem(fid, "tall", tall)
  rhdf5::h5closeAll()
  store <- rhdf5::H5Fopen(h5, flags = "H5F_ACC_RDONLY")
  expect_identical(
    DelayedArray::chunkdim(store_dense_seed(store, "/tall")),
    c(1000L, 4L)
  )
})

test_that("zarr chunkdim is the on-disk chunk shape", {
  # A zarr array has its own chunks, which the grid uses unless overridden
  dir <- withr::local_tempdir()
  s <- zarr_create(file.path(dir, "m.zarr"))
  write_elem(
    s,
    "x",
    matrix(as.numeric(1:60), nrow = 10),
    dataset_kwargs = list(chunks = c(5, 2))
  )
  expect_identical(DelayedArray::chunkdim(store_dense_seed(s, "/x")), c(5L, 2L))
  expect_identical(
    DelayedArray::chunkdim(store_dense_seed(s, "/x", chunks = c(2, -1))),
    c(2L, 6L)
  )
})

test_that("non-numeric Elements are rejected", {
  # Strings and scalars have no dense numeric seed
  store <- dense_fixture_store("array_float64", "h5ad")
  expect_error(
    store_dense_seed(store, "/x", chunks = c(1, 1, 1)),
    class = "anndata_invalid_value_error"
  )
  dir <- withr::local_tempdir()
  s <- zarr_create(file.path(dir, "s.zarr"))
  write_elem(s, "str", c("a", "b"))
  write_elem(s, "scalar", 1.5)
  expect_error(store_dense_seed(s, "/str"), class = "anndata_dtype_error")
  expect_error(store_dense_seed(s, "/scalar"), class = "anndata_dtype_error")
})
