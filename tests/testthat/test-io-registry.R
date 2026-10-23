# Proves write dispatch on R class and read dispatch on encoding type and
# version, using a trivial encoding
test_that("write_elem and read_elem dispatch through the registry", {
  local_io_registry()
  register_test_encoding()
  store <- local_h5_store()

  write_elem(store, "a", test_elem(3L))

  elem <- rhdf5::H5Oopen(store, "a")
  expect_equal(read_elem_attr(elem, "encoding-type"), "test-elem")
  expect_equal(read_elem_attr(elem, "encoding-version"), "0.1.0")
  expect_equal(read_elem(store, "a"), test_elem(3L))
})

# Python only sets the encoding attributes when the writer has not (setdefault)
test_that("write_elem keeps encoding attributes set by the writer", {
  local_io_registry()
  register_writer(
    "test_elem",
    "test-elem",
    "0.1.0",
    function(store, key, value, dataset_kwargs, path) {
      group <- rhdf5::H5Gcreate(store, key)
      set_elem_attr(group, "encoding-version", "9.9.9")
    }
  )
  store <- local_h5_store()

  write_elem(store, "a", test_elem(1L))

  elem <- rhdf5::H5Oopen(store, "a")
  expect_equal(read_elem_attr(elem, "encoding-type"), "test-elem")
  expect_equal(read_elem_attr(elem, "encoding-version"), "9.9.9")
})

# Writers receive dataset_kwargs and the full path, and replace existing keys
test_that("write_elem passes options and overwrites existing keys", {
  local_io_registry()
  seen <- NULL
  register_writer(
    "test_elem",
    "test-elem",
    "0.1.0",
    function(store, key, value, dataset_kwargs, path) {
      seen <<- list(kwargs = dataset_kwargs, path = path)
      group <- rhdf5::H5Gcreate(store, key)
      rhdf5::h5writeAttribute(value$n, group, "n", asScalar = TRUE)
    }
  )
  register_reader("test-elem", "0.1.0", function(elem, path, store) {
    rhdf5::H5Aread(rhdf5::H5Aopen(elem, "n"))
  })
  store <- local_h5_store()

  write_elem(store, "a", test_elem(1L), dataset_kwargs = list(level = 4L))
  write_elem(store, "a", test_elem(2L))

  expect_equal(seen$path, "/a")
  expect_equal(read_elem(store, "a"), 2L)
  write_elem(store, "a", test_elem(1L), dataset_kwargs = list(level = 4L))
  expect_equal(seen$kwargs, list(level = 4L))
})

# Python allows a key that is an absolute path to a direct child of the group
test_that("write_elem accepts an absolute key under the store", {
  local_io_registry()
  register_test_encoding()
  store <- local_h5_store()
  group <- rhdf5::H5Gcreate(store, "uns")

  write_elem(group, "/uns/a", test_elem(5L))

  expect_equal(read_elem(store, "uns/a"), test_elem(5L))
  expect_anndata_condition(
    write_elem(group, "/other/a", test_elem(5L)),
    "anndata_invalid_key_error"
  )
})

# Python writes into the root with k = "/", clearing it first, and refuses it
# for any other group
test_that("write_elem to '/' clears the root and needs the root group", {
  local_io_registry()
  register_test_encoding()
  store <- local_h5_store()
  write_elem(store, "old", test_elem(1L))
  group <- rhdf5::H5Gcreate(store, "sub")

  expect_anndata_condition(
    write_elem(group, "/", test_elem(1L)),
    "anndata_invalid_key_error"
  )
  write_elem(store, "/", test_elem(7L))

  expect_false(rhdf5::H5Lexists(store, "old"))
  expect_false(rhdf5::H5Lexists(store, "sub"))
  expect_equal(read_elem(store, "/"), test_elem(7L))
})

# Python raises for slashes in keys when the setting is on and only warns
# (FutureWarning) when it is off
test_that("write_elem handles forward slashes in keys by setting", {
  local_io_registry()
  register_test_encoding()
  store <- local_h5_store()
  rhdf5::H5Gcreate(store, "a")

  cnd <- expect_anndata_condition(
    write_elem(store, "a/b", test_elem(1L)),
    "anndata_forward_slash_key_error"
  )
  expect_s3_class(cnd, "anndata_error")

  local_anndata_settings(list(disallow_forward_slash_in_h5ad = FALSE))
  expect_warning(
    write_elem(store, "a/b", test_elem(1L)),
    class = "anndata_future_warning"
  )
  expect_equal(read_elem(store, "a/b"), test_elem(1L))
})

# Python's IORegistryError for a missing writer, with the path and R class
test_that("writing an unencodable value raises a registry error", {
  local_io_registry()
  register_test_encoding()
  store <- local_h5_store()
  group <- rhdf5::H5Gcreate(store, "uns")

  methods::setClass("RegistryTestS4", methods::representation(x = "numeric"))
  withr::defer(methods::removeClass("RegistryTestS4"))
  values <- list(
    `function` = function(x) x,
    environment = new.env(),
    Date = Sys.Date(),
    POSIXct = Sys.time(),
    S4 = methods::new("RegistryTestS4", x = 1),
    S3 = structure(list(a = 1), class = "registry_test_s3")
  )
  for (name in names(values)) {
    cnd <- expect_anndata_condition(
      write_elem(group, "key", values[[name]]),
      "anndata_io_registry_error"
    )
    expect_s3_class(cnd, "anndata_error")
    expect_equal(cnd$path, "/uns/key")
    expect_equal(cnd$r_class, class(values[[name]]))
    expect_match(conditionMessage(cnd), "/uns/key", fixed = TRUE)
    expect_match(
      conditionMessage(cnd),
      class(values[[name]])[[1]],
      fixed = TRUE
    )
  }
  expect_false(rhdf5::H5Lexists(group, "key"))
})

# Python's IORegistryError for an unknown encoding type or version, which must
# name the path, type and version
test_that("reading an unknown type or version raises a registry error", {
  local_io_registry()
  register_test_encoding()
  store <- local_h5_store()
  make_encoded_group(store, "unknown_type", "no-such-type", "0.1.0")
  make_encoded_group(store, "unknown_version", "test-elem", "7.0.0")

  cnd <- expect_anndata_condition(
    read_elem(store, "unknown_type"),
    "anndata_io_registry_error"
  )
  expect_s3_class(cnd, "anndata_error")
  expect_equal(cnd$path, "/unknown_type")
  expect_equal(cnd$encoding_type, "no-such-type")
  expect_equal(cnd$encoding_version, "0.1.0")
  expect_match(conditionMessage(cnd), "/unknown_type", fixed = TRUE)
  expect_match(conditionMessage(cnd), "no-such-type", fixed = TRUE)

  cnd <- expect_anndata_condition(
    read_elem(store, "unknown_version"),
    "anndata_io_registry_error"
  )
  expect_equal(cnd$encoding_version, "7.0.0")
  expect_match(conditionMessage(cnd), "7.0.0", fixed = TRUE)
})

# Legacy dataframes are not read yet (legacy-formats/04), so reading one must
# fail with a classed error naming the path rather than a registry error
# (unencoded Elements are read, see test-io-legacy.R)
test_that("reading legacy elements raises a not-supported error", {
  local_io_registry()
  register_test_encoding()
  store <- local_h5_store()
  make_encoded_group(store, "old_dataframe", "dataframe", "0.1.0")

  for (name in c("old_dataframe")) {
    cnd <- expect_anndata_condition(
      read_elem(store, name),
      "anndata_legacy_format_error"
    )
    expect_s3_class(cnd, "anndata_not_supported_error")
    expect_s3_class(cnd, "anndata_error")
    expect_equal(cnd$path, paste0("/", name))
    expect_match(conditionMessage(cnd), paste0("/", name), fixed = TRUE)
    expect_match(conditionMessage(cnd), "not yet supported", fixed = TRUE)
  }
  # The message names the layout without leftover cli markup
  cnd <- expect_anndata_condition(
    read_elem(store, "old_dataframe"),
    "anndata_legacy_format_error"
  )
  expect_match(conditionMessage(cnd), "dataframe", fixed = TRUE)
  expect_match(conditionMessage(cnd), "0.1.0", fixed = TRUE)
  expect_no_match(conditionMessage(cnd), "{", fixed = TRUE)
})

# Old categorical storage is detected inside the dataframe reader (ticket 09),
# which calls this helper
test_that("the old categorical helper raises a legacy error naming the path", {
  cnd <- expect_anndata_condition(
    abort_legacy_categorical("/obs/cell_type"),
    "anndata_legacy_format_error"
  )
  expect_s3_class(cnd, "anndata_not_supported_error")
  expect_match(conditionMessage(cnd), "/obs/cell_type", fixed = TRUE)
  expect_match(conditionMessage(cnd), "not yet supported", fixed = TRUE)
})

# awkward-array belongs to the experimental sub-project
test_that("reading an awkward-array raises a not-supported error", {
  local_io_registry()
  store <- local_h5_store()
  make_encoded_group(store, "ragged", "awkward-array", "0.1.0")

  cnd <- expect_anndata_condition(
    read_elem(store, "ragged"),
    "anndata_awkward_array_error"
  )
  expect_s3_class(cnd, "anndata_not_supported_error")
  expect_equal(cnd$path, "/ragged")
  expect_match(conditionMessage(cnd), "not yet supported", fixed = TRUE)
})

# Python refuses to change the encoding already recorded for a type
test_that("registering a writer with a different encoding is an error", {
  local_io_registry()
  register_test_encoding()

  expect_anndata_condition(
    register_writer("test_elem", "test-elem", "0.2.0", function(...) NULL),
    "anndata_io_registry_error"
  )
  expect_no_error(
    register_writer("test_elem", "test-elem", "0.1.0", function(...) NULL)
  )
})

# Named package functions are looked up at call time so covr can instrument
# them, while anonymous, test-local and primitive functions are kept as given
test_that("late_bound looks named package functions up at call time", {
  local_io_registry()
  fn <- late_bound(quote(spec_key), spec_key)
  expect_equal(fn("a", "b"), spec_key("a", "b"))
  local_mocked_bindings(spec_key = function(...) "mocked")
  expect_equal(fn("a", "b"), "mocked")

  anon <- function(...) NULL
  expect_identical(late_bound(quote(function(...) NULL), anon), anon)
  expect_identical(late_bound(quote(anon), anon), anon)
  expect_identical(late_bound(quote(sum), sum), sum)
  expect_identical(late_bound(quote(not_a_function), spec_key), spec_key)
})
