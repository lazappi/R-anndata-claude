#' Read a umi_tools count table
#'
#' `read_umi_tools()` reads a (optionally gzipped) tab-separated condensed
#' count matrix from umi_tools, with the columns `gene`, `cell` and `count`,
#' into an [AnnData()] object with a sparse (CSR) X, as Python's
#' `read_umi_tools()`.
#' The `obs` and `var` names are the sorted unique cells and genes (Python's
#' category order), with the index names `"cell"` and `"gene"`.
#' Repeated cell and gene pairs are summed and other columns are ignored.
#'
#' @param filename A path (a `.gz` or `.bz2` suffix is decompressed).
#' @param dtype A numpy dtype string for X, such as `"float32"`.
#'   With `NULL` the dtype of the counts is used (`"int64"` for whole numbers,
#'   otherwise `"float64"`).
#' @return An [AnnData()] object with a sparse (CSR) X.
#' @examples
#' path <- tempfile(fileext = ".tsv")
#' writeLines(
#'   c("gene\tcell\tcount", "g2\tc2\t3", "g1\tc1\t1", "g3\tc1\t2"),
#'   path
#' )
#' read_umi_tools(path)
#' @export
read_umi_tools <- function(filename, dtype = NULL) {
  call <- rlang::current_env()
  if (
    !is.null(dtype) && (!rlang::is_string(dtype) || !dtype %in% numeric_dtypes)
  ) {
    abort_invalid_argument(
      "{.arg dtype} must be one of {.val {numeric_dtypes}} or {.code NULL}.",
      call
    )
  }
  if (!rlang::is_string(filename) || inherits(filename, "AsIs")) {
    abort_invalid_argument("{.arg filename} must be a path.", call)
  }
  lines <- text_lines(filename, call)
  table <- umi_table(lines, call)
  cells <- sort(unique(table$cell), method = "radix")
  genes <- sort(unique(table$gene), method = "radix")
  counts <- table$count
  if (is.null(dtype)) {
    dtype <- if (table$integer) "int64" else "float64"
  }
  X <- mtx_sparse(
    list(
      i = match(table$cell, cells) - 1,
      j = match(table$gene, genes) - 1,
      x = counts,
      shape = c(length(cells), length(genes))
    ),
    dtype
  )
  AnnData(
    X,
    obs = with_index_name(frame_from_columns(list(), cells), "cell"),
    var = with_index_name(frame_from_columns(list(), genes), "gene")
  )
}

# The `gene`, `cell` and `count` columns of the table in `lines`
umi_table <- function(lines, call) {
  if (!length(lines)) {
    text_error("No columns to parse from file", call)
  }
  header <- strsplit(lines[[1L]], "\t", fixed = TRUE)[[1L]]
  missing <- setdiff(c("gene", "cell", "count"), header)
  if (length(missing)) {
    text_error(paste0("'", missing[[1L]], "'"), call)
  }
  if (length(lines) == 1L) {
    text_error("cannot infer dimensions from zero sized index arrays", call)
  }
  fields <- strsplit(lines[-1L], "\t", fixed = TRUE)
  if (any(lengths(fields) < length(header))) {
    text_error("Missing fields in a umi_tools data line.", call)
  }
  column <- function(name) {
    vapply(fields, `[[`, "", match(name, header))
  }
  count <- column("count")
  if (!all(is_py_float(count))) {
    text_error("The umi_tools counts must be numbers.", call)
  }
  list(
    gene = column("gene"),
    cell = column("cell"),
    count = as.double(trimws(tolower(count), whitespace = text_whitespace)),
    # pandas gives int64 only if every value is an integer literal
    integer = all(grepl(
      "^[+-]?[0-9]+$",
      trimws(count, whitespace = text_whitespace)
    ))
  )
}
