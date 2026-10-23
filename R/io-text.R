#' Read text and csv files
#'
#' `read_text()` reads a delimited text file (`.txt`, `.tab`, `.data`) into an
#' [AnnData()] object and `read_csv()` is the same with the delimiter `","`, as
#' in Python's `read_text()` and `read_csv()`.
#' Blank lines are skipped and lines starting with `#` are comments.
#' If the first line holds names (its last field is not a number) they become
#' the `var` names, otherwise the last comment line is used or the names are
#' `"0"`, `"1"` and so on.
#' If a line starts with a field that is not a number (or `first_column_names`
#' is `TRUE`) the first column holds the `obs` names, and double quotes around
#' names are removed.
#' A first line with one name fewer than the second line's values is read as
#' integer names for both axes.
#'
#' @param filename A path (a `.gz` or `.bz2` suffix is decompressed), a
#'   connection, or a character vector of lines.
#'   A single line is passed as `I("...")`, because a single string is a path.
#' @param delimiter The field delimiter.
#'   With `NULL` lines are split at any run of white space, which differs from
#'   `" "`.
#' @param first_column_names Whether the first column stores the `obs` names,
#'   detected when `NULL`.
#' @param dtype A numpy dtype string for X, such as `"float32"` (the default),
#'   `"float64"` or `"int32"`.
#'   The values are R doubles or integers that carry the On-disk dtype.
#' @return An [AnnData()] object with a dense X.
#' @examples
#' lines <- c("cell,g1,g2", "c1,1,2", "c2,3,4")
#' read_csv(lines)
#' @export
read_text <- function(
  filename,
  delimiter = NULL,
  first_column_names = NULL,
  dtype = "float32"
) {
  call <- rlang::current_env()
  read_delimited(filename, delimiter, first_column_names, dtype, call)
}

#' @rdname read_text
#' @export
read_csv <- function(
  filename,
  delimiter = ",",
  first_column_names = NULL,
  dtype = "float32"
) {
  call <- rlang::current_env()
  read_delimited(filename, delimiter, first_column_names, dtype, call)
}

read_delimited <- function(
  filename,
  delimiter,
  first_column_names,
  dtype,
  call
) {
  if (
    !is.null(delimiter) && !(rlang::is_string(delimiter) && nzchar(delimiter))
  ) {
    abort_invalid_argument(
      "{.arg delimiter} must be a non-empty string or {.code NULL}.",
      call
    )
  }
  if (!is.null(first_column_names) && !rlang::is_bool(first_column_names)) {
    abort_invalid_argument(
      "{.arg first_column_names} must be {.code TRUE}, {.code FALSE} or
       {.code NULL}.",
      call
    )
  }
  if (!rlang::is_string(dtype) || !dtype %in% numeric_dtypes) {
    abort_invalid_argument(
      "{.arg dtype} must be one of {.val {numeric_dtypes}}.",
      call
    )
  }
  lines <- text_lines(filename, call)
  text_to_anndata(lines, delimiter, first_column_names, dtype, call)
}

# The non-empty lines without line breaks (Python's `_iter_lines`)
text_lines <- function(filename, call) {
  if (inherits(filename, "connection")) {
    lines <- readLines(filename, warn = FALSE, encoding = "UTF-8")
  } else if (
    is.character(filename) &&
      !inherits(filename, "AsIs") &&
      length(filename) == 1L
  ) {
    path <- path.expand(filename)
    if (!file.exists(path)) {
      anndata_abort(
        "Cannot read {.path {filename}}, the file does not exist.",
        "anndata_file_not_found_error",
        call = call
      )
    }
    con <- if (endsWith(path, ".gz")) {
      gzfile(path, "rt", encoding = "UTF-8")
    } else if (endsWith(path, ".bz2")) {
      bzfile(path, "rt", encoding = "UTF-8")
    } else {
      file(path, "rt", encoding = "UTF-8")
    }
    on.exit(close(con))
    lines <- readLines(con, warn = FALSE)
  } else if (is.character(filename)) {
    lines <- as.character(filename)
  } else {
    abort_invalid_argument(
      "{.arg filename} must be a path, a connection or a character vector of
       lines, not {.obj_type_friendly {filename}}.",
      call
    )
  }
  lines <- sub("[\r\n]+$", "", lines)
  lines[nzchar(lines)]
}

text_whitespace <- "[ \t\n\r\f\v]"

# `str.split(delimiter)` of Python, which keeps empty fields
text_split <- function(line, delimiter) {
  if (is.null(delimiter)) {
    line <- trimws(line, whitespace = text_whitespace)
    if (!nzchar(line)) {
      return(character())
    }
    return(strsplit(line, paste0(text_whitespace, "+"))[[1L]])
  }
  parts <- strsplit(line, delimiter, fixed = TRUE)[[1L]]
  if (endsWith(line, delimiter)) {
    parts <- c(parts, "")
  }
  parts
}

# Python's `float(string)` succeeds
is_py_float <- function(x) {
  grepl(
    paste0(
      "^",
      text_whitespace,
      "*[+-]?(([0-9]+[.]?[0-9]*|[.][0-9]+)",
      "([eE][+-]?[0-9]+)?|inf(inity)?|nan)",
      text_whitespace,
      "*$"
    ),
    x,
    ignore.case = TRUE
  )
}

# The values of `parts` as `np.array(parts, dtype=dtype)`, with Python's errors
text_numbers <- function(parts, dtype, call) {
  if (grepl("^u?int", dtype)) {
    ok <- grepl(
      paste0("^", text_whitespace, "*[+-]?[0-9]+", text_whitespace, "*$"),
      parts
    )
    if (!all(ok)) {
      text_error(
        paste0(
          "invalid literal for int() with base 10: '",
          parts[!ok][[1L]],
          "'"
        ),
        call
      )
    }
    values <- as.double(parts)
    limits <- dtype_limits[[dtype]]
    outside <- values < limits[[1L]] | values >= limits[[2L]]
    if (any(outside)) {
      text_error(
        paste0(
          "Python integer ",
          trimws(parts[outside][[1L]], whitespace = text_whitespace),
          " out of bounds for ",
          dtype
        ),
        call
      )
    }
    return(values)
  }
  ok <- is_py_float(parts)
  if (!all(ok)) {
    text_error(
      paste0("could not convert string to float: '", parts[!ok][[1L]], "'"),
      call
    )
  }
  values <- as.double(trimws(tolower(parts), whitespace = text_whitespace))
  if (dtype == "float32") to_float32(values) else values
}

# Python's `ValueError` (message copied from Python, so braces are escaped)
text_error <- function(message, call) {
  anndata_abort(
    gsub("}", "}}", gsub("{", "{{", message, fixed = TRUE), fixed = TRUE),
    "anndata_invalid_value_error",
    call = call
  )
}

text_no_data <- function(call) {
  anndata_abort(
    "The text has no data lines.",
    "anndata_invalid_value_error",
    call = call
  )
}

# Port of `_read_text`, the lines are already cleaned
text_to_anndata <- function(
  lines,
  delimiter,
  first_column_names,
  dtype,
  call
) {
  comments <- character()
  data <- list()
  col_names <- character()
  row_names <- character()
  pos <- 1L
  n_lines <- length(lines)
  # read the header and column names
  while (pos <= n_lines) {
    line <- lines[[pos]]
    pos <- pos + 1L
    if (startsWith(line, "#")) {
      comment <- sub("^[# ]+", "", line)
      if (nzchar(comment)) {
        comments <- c(comments, comment)
      }
      next
    }
    if (!is.null(delimiter) && !grepl(delimiter, line, fixed = TRUE)) {
      text_error(
        paste0("Did not find delimiter '", delimiter, "' in first line."),
        call
      )
    }
    parts <- text_split(line, delimiter)
    if (!length(parts)) {
      text_no_data(call)
    }
    # the first column might be row names, so check the last
    if (!is_py_float(parts[[length(parts)]])) {
      col_names <- parts
    } else if (!is_py_float(parts[[1L]]) || isTRUE(first_column_names)) {
      first_column_names <- TRUE
      row_names <- c(row_names, parts[[1L]])
      data <- c(data, list(text_numbers(parts[-1L], dtype, call)))
    } else {
      data <- c(data, list(text_numbers(parts, dtype, call)))
    }
    break
  }
  if (!length(col_names)) {
    if (length(comments)) {
      # the last comment line stores the variable names
      col_names <- text_split(comments[[length(comments)]], NULL)
    } else if (length(data)) {
      col_names <- as.character(seq_along(data[[1L]]) - 1L)
    } else {
      text_no_data(call)
    }
  }
  # read another line to check if the first column contains row names
  first_column_names <- isTRUE(first_column_names)
  if (pos <= n_lines) {
    parts <- text_split(lines[[pos]], delimiter)
    pos <- pos + 1L
    if (!length(parts)) {
      text_no_data(call)
    }
    if (first_column_names || !is_py_float(parts[[1L]])) {
      first_column_names <- TRUE
      row_names <- c(row_names, parts[[1L]])
      data <- c(data, list(text_numbers(parts[-1L], dtype, call)))
    } else {
      data <- c(data, list(text_numbers(parts, dtype, call)))
    }
  }
  # integer names: the first row holds the column names
  if (length(data) > 1L && length(data[[1L]]) != length(data[[2L]])) {
    first_column_names <- TRUE
    col_names <- as.character(as.integer(data[[1L]]))
    row_names <- c(row_names, as.character(as.integer(data[[2L]][[1L]])))
    data <- list(data[[2L]][-1L])
  }
  while (pos <= n_lines) {
    parts <- text_split(lines[[pos]], delimiter)
    pos <- pos + 1L
    if (!length(parts)) {
      text_no_data(call)
    }
    if (first_column_names) {
      row_names <- c(row_names, parts[[1L]])
      data <- c(data, list(text_numbers(parts[-1L], dtype, call)))
    } else {
      data <- c(data, list(text_numbers(parts, dtype, call)))
    }
  }
  if (!length(data)) {
    text_no_data(call)
  }
  first <- length(data[[1L]])
  last <- length(data[[length(data)]])
  if (first != last) {
    text_error(
      paste0(
        "Length of first line (",
        first,
        ") is different from length of ",
        "last line (",
        last,
        ")."
      ),
      call
    )
  }
  values <- typed_dense(
    matrix(unlist(data), nrow = length(data), ncol = first, byrow = TRUE),
    dtype
  )
  if (!length(row_names)) {
    row_names <- as.character(seq_along(data) - 1L)
  }
  row_names <- gsub('^"+|"+$', "", row_names)
  if (length(col_names) > ncol(values)) {
    col_names <- col_names[-1L]
  }
  col_names <- gsub('^"+|"+$', "", col_names)
  AnnData(
    values,
    obs = frame_from_columns(list(), row_names),
    var = frame_from_columns(list(), col_names)
  )
}
