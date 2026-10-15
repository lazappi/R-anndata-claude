# The generic wrapper must add the base class, the subclass and rlang's class
test_that("anndata_abort adds anndata_error, the subclass and rlang_error", {
  f_abort <- function() {
    anndata_abort("Something {.val {1}} failed", "anndata_test_error")
  }
  cnd <- expect_error(f_abort(), class = "anndata_test_error")
  expect_s3_class(cnd, "anndata_error")
  expect_s3_class(cnd, "rlang_error")
  expect_s3_class(cnd, "error")
})

# Callers rely on the reported call being the raising function, not the wrapper
test_that("anndata_abort reports the calling function", {
  f_abort <- function() anndata_abort("x", "anndata_test_error")
  cnd <- expect_error(f_abort())
  expect_equal(rlang::call_name(cnd$call), "f_abort")
})

# Python errors need an explicit way to report a different frame
test_that("anndata_abort passes a custom call through", {
  g <- function() {
    anndata_abort("x", "anndata_test_error", call = quote(custom()))
  }
  cnd <- expect_error(g())
  expect_equal(rlang::call_name(cnd$call), "custom")
})

# cli markup must be interpolated from the caller's environment
test_that("anndata_abort interpolates in the caller environment", {
  h <- function() {
    n <- 3
    anndata_abort("Got {n} things", "anndata_test_error")
  }
  expect_error(h(), "Got 3 things", class = "anndata_test_error")
})

# The warning wrapper mirrors the error wrapper
test_that("anndata_warn adds anndata_warning, the subclass and rlang_warning", {
  f_warn <- function() anndata_warn("Something", "anndata_test_warning")
  cnd <- expect_warning(f_warn(), class = "anndata_test_warning")
  expect_s3_class(cnd, "anndata_warning")
  expect_s3_class(cnd, "rlang_warning")
  expect_s3_class(cnd, "warning")
  expect_equal(rlang::call_name(cnd$call), "f_warn")
})

test_that("anndata_warn passes a custom call through", {
  g <- function() {
    anndata_warn("x", "anndata_test_warning", call = quote(custom()))
  }
  cnd <- expect_warning(g())
  expect_equal(rlang::call_name(cnd$call), "custom")
})

# Each named constructor maps a Python category to its documented R class
test_that("named error constructors use the documented classes", {
  expect_anndata_condition(
    abort_dimension("Bad shape"),
    "anndata_dimension_error"
  )
  expect_anndata_condition(
    abort_io_registry("No reader"),
    "anndata_io_registry_error"
  )
  expect_anndata_condition(
    abort_not_supported("Not yet"),
    "anndata_not_supported_error"
  )
  for (fn in list(abort_dimension, abort_io_registry, abort_not_supported)) {
    expect_error(fn("x"), class = "anndata_error")
  }
})

test_that("named warning constructors use the documented classes", {
  cnd <- expect_warning(
    warn_implicit_modification("Transforming"),
    class = "anndata_implicit_modification_warning"
  )
  expect_s3_class(cnd, "anndata_warning")
  cnd <- expect_warning(
    warn_future("Changing"),
    class = "anndata_future_warning"
  )
  expect_s3_class(cnd, "anndata_warning")
})

# Constructors must report the calling function, like the generic wrappers
test_that("named constructors report the calling function", {
  f <- function() abort_dimension("Bad shape")
  cnd <- expect_error(f())
  expect_equal(rlang::call_name(cnd$call), "f")
  w <- function() warn_future("Changing")
  cnd <- expect_warning(w())
  expect_equal(rlang::call_name(cnd$call), "w")
})

# Constructors must interpolate from the caller, not from their own frame
test_that("named constructors interpolate in the caller environment", {
  f <- function() {
    shape <- "2x3"
    abort_dimension("Shape {shape} is wrong")
  }
  expect_error(f(), "Shape 2x3 is wrong")
})

# The helper must fail when the class differs, else tests using it prove nothing
test_that("expect_anndata_condition checks the class", {
  expect_anndata_condition(abort_dimension("x"), "anndata_dimension_error")
  expect_failure(
    expect_anndata_condition(abort_dimension("x"), "anndata_io_registry_error")
  )
})
