#' Read an HDF5 file with a data matrix
#'
#' `read_hdf()` reads the dataset `key` of an HDF5 (`.h5`) file into the X of an
#' [AnnData()] object, as Python's `read_hdf()`.
#' If the file also has the datasets `row_names` and `col_names` they become
#' the `obs` and `var` names.
#'
#' @param filename A path to the HDF5 file.
#' @param key The name of the dataset holding the matrix.
#'   An empty string is an error that lists the datasets in the file.
#' @return An [AnnData()] object.
#' @examples
#' path <- tempfile(fileext = ".h5")
#' rhdf5::h5createFile(path)
#' rhdf5::h5write(matrix(c(0.5, 1.5, 2.5, 3.5), 2), path, "data")
#' read_hdf(path, "data")
#' @export
read_hdf <- function(filename, key) {
  call <- rlang::current_env()
  if (!rlang::is_string(key)) {
    abort_invalid_argument("{.arg key} must be a single string.", call)
  }
  filename <- check_filename(filename, call)
  if (!file.exists(filename)) {
    anndata_abort(
      "The source file does not exist: {.path {filename}}",
      "anndata_file_not_found_error",
      call = call
    )
  }
  store <- rhdf5::H5Fopen(filename, flags = "H5F_ACC_RDONLY")
  on.exit(rhdf5::H5Fclose(store), add = TRUE)
  keys <- group_members(store)
  if (!nzchar(key)) {
    anndata_abort(
      "The file {.file {basename(filename)}} stores the following datasets:
       {.val {keys}}.
       Call {.fn read_hdf} with one of them.",
      "anndata_invalid_value_error",
      call = call
    )
  }
  if (!key %in% keys) {
    abort_key(
      "Unable to open the dataset {.val {key}} in {.file {filename}}.",
      "anndata_key_error",
      call
    )
  }
  X <- read_dataset(store, key, call = call)
  names <- lapply(c("row_names", "col_names"), function(name) {
    if (name %in% keys) string_read(store, name, call)
  })
  frame <- function(index) {
    if (is.null(index)) NULL else frame_from_columns(list(), index)
  }
  AnnData(X, obs = frame(names[[1L]]), var = frame(names[[2L]]))
}
