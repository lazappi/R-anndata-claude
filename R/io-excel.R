#' Read an Excel sheet with a data matrix
#'
#' `read_excel()` reads a sheet of an `.xlsx` file into an [AnnData()] object
#' with a dense X, as Python's `read_excel()`.
#' The first column holds the `obs` names and the first row the `var` names,
#' and the name in the corner becomes the `obs` index name.
#' It needs the readxl package.
#'
#' Every other cell must be a number (or empty, which gives `NA`).
#' X has the dtype `"int64"` when the whole sheet holds whole numbers and
#' `"float64"` otherwise.
#' Python gives an `object` array when the first column is text and ignores
#' `dtype`, so R gives doubles whatever the cells hold and also ignores it.
#' Names are always strings, even with the setting `restrict_index_types` off
#' (Python then keeps the type of the labels).
#'
#' @section Deviations from Python:
#' Python's `object` X (text in the first column) has no R form, so X is
#' numeric, and names are always strings.
#' See `vignette("deviations")` for the full list.
#'
#' @param filename A path to the `.xlsx` file.
#' @param sheet The name of the sheet, or its position as a zero-based whole
#'   number (as Python).
#' @param dtype Ignored, kept for compatibility with Python.
#' @return An [AnnData()] object.
#' @examples
#' \dontrun{
#' read_excel("counts.xlsx", sheet = "counts")
#' }
#' @export
read_excel <- function(filename, sheet, dtype = "float32") {
  call <- rlang::current_env()
  rlang::check_installed("readxl", "to read Excel files.")
  filename <- check_filename(filename, call)
  if (!file.exists(filename)) {
    anndata_abort(
      "The source file does not exist: {.path {filename}}",
      "anndata_file_not_found_error",
      call = call
    )
  }
  sheet <- excel_sheet_name(filename, sheet, call)
  cells <- readxl::read_excel(
    filename,
    sheet = sheet,
    col_names = FALSE,
    col_types = "list",
    .name_repair = "minimal"
  )
  if (!nrow(cells) || !ncol(cells)) {
    text_error("The sheet has no data.", call)
  }
  columns <- lapply(cells, function(column) column[-1L])
  labels <- function(values) {
    vapply(values, excel_label, character(1), USE.NAMES = FALSE)
  }
  header <- labels(lapply(cells, `[[`, 1L))
  data <- lapply(columns[-1L], excel_numbers, call = call)
  X <- matrix(
    as.double(unlist(data)),
    nrow = nrow(cells) - 1L,
    ncol = length(data)
  )
  first <- columns[[1L]]
  whole <- all(vapply(first, is.numeric, NA)) &&
    !anyNA(X) &&
    all(X == round(X)) &&
    all(vapply(first, function(v) !is.na(v) && v == round(v), NA))
  if (whole) {
    X <- typed_dense(X, "int64")
  }
  index_name <- if (is.na(cells[[1L]][[1L]][[1L]])) NULL else header[[1L]]
  AnnData(
    X,
    obs = with_index_name(
      frame_from_columns(list(), labels(first)),
      index_name
    ),
    var = frame_from_columns(list(), header[-1L])
  )
}

# The zero-based position or name of a sheet as the name readxl needs
excel_sheet_name <- function(filename, sheet, call) {
  sheets <- readxl::excel_sheets(filename)
  if (rlang::is_string(sheet)) {
    if (!sheet %in% sheets) {
      text_error(paste0("Worksheet named '", sheet, "' not found"), call)
    }
    return(sheet)
  }
  if (!is.numeric(sheet) || length(sheet) != 1L || is.na(sheet)) {
    abort_invalid_argument(
      "{.arg sheet} must be a sheet name or a position.",
      call
    )
  }
  if (sheet < 0 || sheet >= length(sheets) || sheet != round(sheet)) {
    text_error(
      paste0(
        "Worksheet index ",
        format(sheet),
        " is invalid, ",
        length(sheets),
        " worksheets found"
      ),
      call
    )
  }
  sheets[[sheet + 1L]]
}

# A cell value as a name, whole numbers without a decimal point as pandas
excel_label <- function(value) {
  value <- value[[1L]]
  if (is.character(value)) {
    return(value)
  }
  if (is.numeric(value) && !is.na(value)) {
    return(format(value, digits = 15L, scientific = FALSE, trim = TRUE))
  }
  as.character(value)
}

# A column of cells as doubles, `NA` for an empty cell
excel_numbers <- function(cells, call) {
  vapply(
    cells,
    function(value) {
      if (!(is.numeric(value) || (is.logical(value) && is.na(value)))) {
        text_error("The cells of the data must be numbers.", call)
      }
      as.double(value)
    },
    double(1),
    USE.NAMES = FALSE
  )
}
