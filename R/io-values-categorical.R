#' Categorical arrays
#'
#' Reads and writes the Element `categorical` (version 0.2.0), a group with the
#' boolean attribute `ordered` and the members `codes` and `categories`.
#'
#' A `factor` is written as an unordered and an `ordered` factor as an ordered
#' categorical.
#' R levels are always strings, so non-string categories (Python's integer,
#' float and boolean categories) are read as the string form of the category
#' and the original categories are kept in the `anndata_categories` attribute
#' of the factor.
#' They are written back with their own dtype as long as the levels still match
#' them, and as strings otherwise (so subsetting a factor with `[` writes
#' string categories).
#'
#' Codes use the smallest signed integer dtype pandas picks for the number of
#' categories, whatever dtype the file had.
#' `NA` is the code -1 and unused levels are kept.
#'
#' @inheritParams io-registry
#'
#' @name io-categorical
#' @keywords internal
NULL

categories_attr <- "anndata_categories"

# pandas picks int8, int16 or int32 from the number of categories
code_dtype <- function(n_categories) {
  if (n_categories < 127) {
    "int8"
  } else if (n_categories < 32767) {
    "int16"
  } else {
    "int32"
  }
}

# The levels R holds for categories of any dtype
categories_as_levels <- function(categories) {
  values <- drop_dtype(categories)
  dim(values) <- NULL
  out <- as.character(values)
  if (is.double(values)) {
    # `as.character()` gives 1e+05 for 100000
    whole <- is.finite(values) & values == trunc(values)
    out[whole] <- sprintf("%.0f", values[whole])
  }
  out
}

#' @rdname io-categorical
write_factor <- function(store, key, value, dataset_kwargs, path) {
  call <- rlang::caller_env()
  group <- group_create(store, key)
  on.exit(node_close(group), add = TRUE)
  attr_write(group, "ordered", is.ordered(value))

  levels <- levels(value)
  codes <- as.integer(value) - 1L
  codes[is.na(codes)] <- -1L
  codes <- record_dtype(codes, code_dtype(length(levels)))
  write_elem(group, "codes", as_array(codes), dataset_kwargs, call)

  categories <- attr(value, categories_attr, exact = TRUE)
  stored <- !is.null(categories) &&
    identical(categories_as_levels(categories), levels)
  if (!stored) {
    categories <- levels
  }
  write_elem(group, "categories", as_array(categories), dataset_kwargs, call)
  invisible(NULL)
}

# The factor of `codes` and `categories` as read from the Element at `path`,
# shared by eager and lazy reads
categorical_from_parts <- function(codes, categories, ordered, path, call) {
  levels <- categories_as_levels(categories)
  codes <- as.integer(drop_dtype(codes))
  if (anyDuplicated(levels) > 0L) {
    abort_io_registry(
      "Cannot read {.path {path}}, its categories are not unique.",
      path = path,
      call = call
    )
  }
  if (any(codes < -1L | codes >= length(levels), na.rm = TRUE)) {
    abort_io_registry(
      "Cannot read {.path {path}}, its codes must be between -1 and
       {length(levels) - 1L}.",
      path = path,
      call = call
    )
  }
  codes[codes == -1L] <- NA_integer_

  factor <- structure(
    codes + 1L,
    levels = levels,
    class = if (ordered) c("ordered", "factor") else "factor"
  )
  if (!is.character(categories)) {
    dim(categories) <- NULL
    attr(factor, categories_attr) <- categories
  }
  factor
}

read_categorical_elem <- function(elem, path, store) {
  categorical_from_parts(
    read_elem(store, paste0(path, "/codes")),
    read_elem(store, paste0(path, "/categories")),
    identical(read_elem_attr(elem, "ordered"), "TRUE"),
    path,
    rlang::caller_env()
  )
}

register_writer("factor", "categorical", "0.2.0", write_factor)
register_reader("categorical", "0.2.0", read_categorical_elem)
