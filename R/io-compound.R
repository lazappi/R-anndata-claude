# Compound datasets through the compiled helper (ADR 0008). The helper has its
# own HDF5 instance, so it works on file paths and never shares an id with
# rhdf5.

#' Member names and types of a compound dataset
#'
#' @param path Path of an HDF5 file.
#' @param dataset Path of the compound dataset inside the file.
#' @return A data frame with one row per member: `name`, `class` (`"integer"`,
#'   `"float"`, `"string"`, `"enum"`, `"compound"`, `"vlen"` or `"other"`),
#'   `size` in bytes, `sign` (`"signed"`, `"unsigned"` or `NA`), `order`
#'   (`"LE"` or `"BE"`), `variable` and `utf8` for strings, `enum_names` for
#'   enums and `dims` (the shape of an array-valued member, empty otherwise, in
#'   numpy order).
#' @noRd
compound_members <- function(path, dataset) {
  info <- .Call(c_compound_members, path.expand(path), dataset)
  members <- data.frame(
    name = info$name,
    class = info$class,
    size = info$size,
    sign = info$sign,
    order = info$order,
    variable = info$variable,
    utf8 = info$utf8,
    stringsAsFactors = FALSE
  )
  members$enum_names <- info$enum_names
  members$dims <- info$dims
  members
}

#' A compound field specification
#'
#' The writer builds little-endian integer (1, 2, 4 or 8 bytes), float (4 or 8
#' bytes), bool (FALSE/TRUE enum) and string (fixed or variable length, ASCII or
#' UTF-8) fields, which are the members h5py writes for rec-arrays.
#' Array-valued, big-endian, complex and variable-length members can be read
#' but not written.
#'
#' @param name Field name.
#' @param values Values: integer, double or logical for numbers and bools,
#'   character for strings.
#' @param class One of `"integer"`, `"float"`, `"bool"` and `"string"`.
#' @param size Size in bytes (the fixed length of a fixed-length string).
#' @param signed Whether an integer is signed.
#' @param variable Whether a string is variable length.
#' @param utf8 Whether a string is UTF-8 (ASCII otherwise).
#' @noRd
compound_field <- function(
  name,
  values,
  class,
  size = NA_integer_,
  signed = TRUE,
  variable = FALSE,
  utf8 = FALSE
) {
  list(
    name = name,
    class = class,
    size = as.integer(size),
    signed = signed,
    variable = variable,
    utf8 = utf8,
    values = values
  )
}

#' Write a compound dataset to a new file
#'
#' The file is created (replacing any existing one), holds only the dataset and
#' is closed again, so `rhdf5::H5Ocopy()` can copy it into a store.
#'
#' @param path Path of the file to create.
#' @param dataset Name of the dataset inside the file.
#' @param fields A list of `compound_field()` specifications of equal length.
#' @param level Gzip level, 0 for none.
#' @noRd
compound_write <- function(path, dataset, fields, level = 0L) {
  nrow <- if (length(fields) == 0L) 0L else length(fields[[1L]]$values)
  invisible(.Call(
    c_compound_write,
    path.expand(path),
    dataset,
    unname(fields),
    nrow,
    as.integer(level)
  ))
}

#' Copy a compound dataset written by `compound_write()` into a store
#'
#' @param source Path of the temporary file.
#' @param name Name of the dataset in the temporary file.
#' @param loc An open rhdf5 file or group handle.
#' @param target Name of the dataset to create in `loc`.
#' @noRd
compound_copy <- function(source, name, loc, target) {
  src <- rhdf5::H5Fopen(source, flags = "H5F_ACC_RDONLY")
  on.exit(rhdf5::H5Fclose(src), add = TRUE)
  rhdf5::H5Ocopy(src, name, loc, target)
  invisible(NULL)
}
