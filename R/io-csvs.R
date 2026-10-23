#' Write annotations and uns to csv files
#'
#' Writes `obs`, `var`, `obsm`, `varm` and `uns` (and X when `skip_data` is
#' `FALSE`) to csv files in a directory, as Python's `write_csvs()` does.
#' `obs.csv` and `var.csv` have a header and their names as the first column,
#' `obsm.csv` and `varm.csv` have one column per column of each matrix (named
#' by the key and the 1-based column number) and no names, and `X.csv` and
#' `uns/<key>.csv` have neither header nor names.
#' Numbers are written as pandas does, so reading the files with pandas gives
#' the same values whichever language wrote them.
#'
#' Sparse `uns` values are omitted with one `anndata_write_warning`, and so is
#' any `uns` value with more than 2 dimensions.
#' A named list in `uns` (a dict) is written as one cell holding Python's
#' `repr` of the dict, which supports strings, scalars and nested dicts.
#' A View is written as its subset and stays a View.
#'
#' @param adata An [AnnData()] object.
#' @param dirname Directory to write to, created if needed.
#'   A `.csv` suffix is removed.
#' @param skip_data Whether to leave out X.
#' @param sep The field separator.
#' @return `NULL`, invisibly.
#' @examples
#' adata <- AnnData(X = matrix(c(1, 2, 3, 4), 2, 2))
#' dir <- tempfile("csvs")
#' write_csvs(adata, dir, skip_data = FALSE)
#' list.files(dir, recursive = TRUE)
#' unlink(dir, recursive = TRUE)
#' @export
write_csvs <- function(adata, dirname, skip_data = TRUE, sep = ",") {
  call <- rlang::current_env()
  if (!inherits(adata, "AnnData")) {
    abort_invalid_argument(
      "{.arg adata} must be an {.cls AnnData}, not
       {.obj_type_friendly {adata}}.",
      call
    )
  }
  if (!rlang::is_string(dirname)) {
    abort_invalid_argument("{.arg dirname} must be a single string.", call)
  }
  if (!rlang::is_bool(skip_data)) {
    abort_invalid_argument(
      "{.arg skip_data} must be {.code TRUE} or {.code FALSE}.",
      call
    )
  }
  if (!rlang::is_string(sep) || nchar(sep) != 1L) {
    abort_invalid_argument("{.arg sep} must be a single character.", call)
  }
  check_x_and_layers_are_2d(adata, call)
  dirname <- sub("\\.csv$", "", sub("/+$", "", dirname))
  rlang::signal(
    paste0("writing .csv files to ", dirname),
    class = "anndata_info_message"
  )
  dir_uns <- file.path(dirname, "uns")
  dir.create(dir_uns, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(dir_uns)) {
    anndata_abort(
      "Cannot create the directory {.path {dir_uns}}.",
      "anndata_invalid_value_error",
      call = call
    )
  }
  parts <- csv_builtin_tables(adata, skip_data)
  uns <- .subset2(adata, "uns")
  for (key in names(uns)) {
    parts[key] <- list(uns[[key]])
  }
  builtin <- names(csv_builtin_tables(adata, TRUE))
  warned_sparse <- FALSE
  for (key in names(parts)) {
    value <- parts[[key]]
    if (!inherits(value, "csv_table")) {
      if (is_sparse(value)) {
        if (!warned_sparse) {
          anndata_warn(
            "Omitting to write sparse annotation.",
            "anndata_write_warning",
            call = call
          )
          warned_sparse <- TRUE
        }
        next
      }
      value <- uns_csv_table(value, key, call)
      if (is.null(value)) {
        next
      }
      # Python decides the header and names by the key, whatever its source
      if (key %in% c("obs", "var", "obsm", "varm")) {
        value$header <- character()
      }
      if (key %in% c("obs", "var")) {
        value$index <- as.character(seq_len(nrow(value$cells)) - 1L)
      }
    }
    folder <- if (key %in% c(builtin, "X")) dirname else dir_uns
    write_csv_table(file.path(folder, paste0(key, ".csv")), value, sep)
  }
  invisible(NULL)
}

csv_table <- function(cells, header = NULL, index = NULL, index_name = "") {
  structure(
    list(
      cells = cells,
      header = header,
      index = index,
      index_name = index_name
    ),
    class = "csv_table"
  )
}

# The tables Python writes before `uns`, in its order (X only without
# `skip_data`)
csv_builtin_tables <- function(adata, skip_data) {
  tables <- list(
    obs = frame_csv_table(.subset2(adata, "obs"), .subset2(adata, "obs_names")),
    var = frame_csv_table(.subset2(adata, "var"), .subset2(adata, "var_names")),
    obsm = mapping_csv_table(
      .subset2(adata, "obsm"),
      nrow(.subset2(adata, "obs"))
    ),
    varm = mapping_csv_table(
      .subset2(adata, "varm"),
      nrow(.subset2(adata, "var"))
    )
  )
  if (!skip_data) {
    x <- adata$X
    tables$X <- if (is.null(x)) {
      csv_table(matrix(character(), 0L, 0L))
    } else {
      csv_table(matrix_csv_cells(x))
    }
  }
  tables
}

frame_csv_table <- function(df, names) {
  csv_table(
    frame_csv_cells(df),
    header = colnames(df),
    index = ifelse(is.na(names), "", names),
    index_name = frame_index_name(df) %||% ""
  )
}

frame_csv_cells <- function(df) {
  columns <- lapply(seq_len(ncol(df)), function(j) csv_cells(df[[j]]))
  matrix(
    unlist(columns, use.names = FALSE) %||% character(),
    nrow = nrow(df),
    ncol = length(columns)
  )
}

# Python's `to_df()` of an aligned mapping: one column per column of each
# value, named by the key and the 1-based column number
mapping_csv_table <- function(mapping, n) {
  cells <- list()
  header <- character()
  for (key in .subset2(mapping, "keys")()) {
    value <- mapping[[key]]
    block <- if (is_frame(value)) {
      frame_csv_cells(value)
    } else {
      matrix_csv_cells(value)
    }
    cells <- c(cells, list(block))
    header <- c(header, paste0(key, seq_len(ncol(block))))
  }
  csv_table(
    matrix(
      unlist(cells, use.names = FALSE) %||% character(),
      nrow = n,
      ncol = length(header)
    ),
    header = header
  )
}

matrix_csv_cells <- function(x) {
  dtype <- array_dtype(x)
  if (is_sparse(x) || !is.matrix(x)) {
    x <- as.matrix(x)
  }
  out <- csv_cells(drop_dtype(x), dtype)
  dim(out) <- dim(x)
  out
}

# The cells (strings) of a uns value as pandas would write it, `NULL` after a
# warning when pandas cannot make a data frame of it
uns_csv_table <- function(value, key, call) {
  if (is.null(value)) {
    return(csv_table(matrix("", 1L, 1L)))
  }
  if (is_frame(value)) {
    return(csv_table(frame_csv_cells(value)))
  }
  if (is.list(value)) {
    if (is.null(names(value))) {
      return(omit_uns(key, "ValueError", call))
    }
    return(csv_table(matrix(py_repr(value), 1L, 1L)))
  }
  if (length(dim(value)) > 2L) {
    return(omit_uns(key, "ValueError", call))
  }
  if (length(dim(value)) == 2L) {
    return(csv_table(matrix_csv_cells(value)))
  }
  cells <- csv_cells(drop_dtype(value), array_dtype(value))
  csv_table(matrix(cells, ncol = 1L))
}

omit_uns <- function(key, error, call) {
  anndata_warn(
    paste0(
      "Omitting to write ",
      gsub("([{}])", "\\1\\1", py_str_repr(key)),
      " of type <class '",
      error,
      "'>."
    ),
    "anndata_write_warning",
    call = call
  )
  NULL
}

# Strings as pandas writes a column: numbers by their dtype, bools as `True`
# and `False` and missing values as empty
csv_cells <- function(x, dtype = NULL) {
  if (is.factor(x)) {
    x <- as.character(x)
  }
  if (is.character(x)) {
    x[is.na(x)] <- ""
    return(x)
  }
  if (is.logical(x)) {
    out <- c("False", "True")[as.integer(x) + 1L]
    out[is.na(out)] <- ""
    return(out)
  }
  dtype <- dtype %||% get_dtype(x)[[1L]] %||% native_dtype(x)
  if (dtype == "bool") {
    return(csv_cells(as.logical(x)))
  }
  if (grepl("^u?int", dtype)) {
    out <- sprintf("%.0f", as.double(x))
    out[is.na(x)] <- ""
    return(out)
  }
  format_float(as.double(x), float32 = identical(dtype, "float32"))
}

# Python's `repr` of a float, empty for a missing value
format_float <- function(x, float32 = FALSE) {
  out <- character(length(x))
  out[is.na(x)] <- ""
  out[!is.na(x) & x == Inf] <- "inf"
  out[!is.na(x) & x == -Inf] <- "-inf"
  at <- which(is.finite(x))
  if (!length(at)) {
    return(out)
  }
  values <- x[at]
  sci <- character(length(values))
  rounded <- if (float32) to_float32(values) else values
  for (digits in seq_len(if (float32) 9L else 17L)) {
    pending <- which(sci == "")
    if (!length(pending)) {
      break
    }
    text <- sprintf(paste0("%.", digits - 1L, "e"), values[pending])
    back <- as.double(text)
    if (float32) {
      back <- to_float32(back)
    }
    done <- back == rounded[pending]
    sci[pending[done]] <- text[done]
  }
  zero <- values == 0
  out[at] <- vapply(
    seq_along(values),
    function(i) {
      if (zero[[i]]) {
        if (1 / values[[i]] < 0) "-0.0" else "0.0"
      } else {
        sci_to_repr(sci[[i]])
      }
    },
    character(1)
  )
  out
}

to_float32 <- function(x) {
  readBin(
    writeBin(x, raw(), size = 4L),
    "numeric",
    n = length(x),
    size = 4L
  )
}

# Python uses positional notation for exponents from -4 to 15
sci_to_repr <- function(text) {
  sign <- if (startsWith(text, "-")) "-" else ""
  parts <- strsplit(sub("^-", "", text), "e", fixed = TRUE)[[1L]]
  digits <- sub("0+$", "", gsub(".", "", parts[[1L]], fixed = TRUE))
  digits <- if (nzchar(digits)) digits else "0"
  exponent <- as.integer(parts[[2L]])
  count <- nchar(digits)
  if (exponent >= -4L && exponent < 16L) {
    if (exponent < 0L) {
      whole <- "0"
      fraction <- paste0(strrep("0", -exponent - 1L), digits)
    } else if (count <= exponent + 1L) {
      whole <- paste0(digits, strrep("0", exponent + 1L - count))
      fraction <- "0"
    } else {
      whole <- substr(digits, 1L, exponent + 1L)
      fraction <- substr(digits, exponent + 2L, count)
    }
    return(paste0(sign, whole, ".", fraction))
  }
  mantissa <- if (count == 1L) {
    digits
  } else {
    paste0(substr(digits, 1L, 1L), ".", substring(digits, 2L))
  }
  paste0(
    sign,
    mantissa,
    "e",
    if (exponent < 0L) "-" else "+",
    formatC(abs(exponent), width = 2L, flag = "0")
  )
}

# Python's `repr` of a string
py_str_repr <- function(x) {
  quote <- if (grepl("'", x, fixed = TRUE) && !grepl('"', x, fixed = TRUE)) {
    '"'
  } else {
    "'"
  }
  x <- gsub("\\", "\\\\", x, fixed = TRUE)
  x <- gsub("\n", "\\n", x, fixed = TRUE)
  x <- gsub("\r", "\\r", x, fixed = TRUE)
  x <- gsub("\t", "\\t", x, fixed = TRUE)
  if (quote == "'") {
    x <- gsub("'", "\\'", x, fixed = TRUE)
  }
  paste0(quote, x, quote)
}

# Python's `repr` of a dict of strings, scalars and dicts
py_repr <- function(x) {
  if (is.null(x)) {
    return("None")
  }
  if (is.list(x)) {
    if (!length(x)) {
      return("{}")
    }
    if (is.null(names(x))) {
      abort_not_supported(
        "Writing a dict holding an unnamed list as a csv file is not supported."
      )
    }
    items <- paste0(
      vapply(names(x), py_str_repr, ""),
      ": ",
      vapply(x, py_repr, "")
    )
    return(paste0("{", paste(items, collapse = ", "), "}"))
  }
  if (is.complex(x)) {
    abort_not_supported(
      "Writing a dict holding complex numbers as a csv file is not supported."
    )
  }
  if (length(x) != 1L || length(dim(x)) > 0L) {
    return(py_array_repr(x))
  }
  if (is.character(x) || is.factor(x)) {
    return(py_str_repr(as.character(x)))
  }
  if (is.na(x)) {
    return(if (is.logical(x)) "None" else "nan")
  }
  if (is.logical(x)) {
    return(if (x) "True" else "False")
  }
  csv_cells(drop_dtype(x), get_dtype(x)[[1L]] %||% native_dtype(x))
}

# numpy's `repr` of a 1-d array of numbers, strings or bools that fits on one
# line, the only case that does not need numpy's line wrapping and summaries
py_array_repr <- function(x) {
  unsupported <- function() {
    abort_not_supported(
      "Writing a dict holding this array as a csv file is not supported, only
       1-d arrays of at most 75 characters are."
    )
  }
  if (length(dim(x)) > 1L || !length(x)) {
    unsupported()
  }
  dtype <- NULL
  if (is.character(x) || is.factor(x)) {
    x <- as.character(x)
    items <- vapply(x, py_str_repr, "", USE.NAMES = FALSE)
    dtype <- paste0(", dtype='<U", max(nchar(x)), "'")
  } else if (is.logical(x)) {
    items <- formatC(
      c("False", "True")[as.integer(x) + 1L],
      width = if (all(x)) 4L else 5L
    )
  } else {
    kind <- get_dtype(x)[[1L]] %||% native_dtype(x)
    cells <- csv_cells(drop_dtype(x), kind)
    if (grepl("^u?int", kind)) {
      items <- formatC(cells, width = max(nchar(cells)))
      if (kind != "int64") {
        dtype <- paste0(", dtype=", kind)
      }
    } else {
      if (!all(is.finite(x)) || any(grepl("e", cells, fixed = TRUE))) {
        unsupported()
      }
      whole <- sub("\\..*$", "", cells)
      fraction <- sub("^[^.]*\\.", "", cells)
      fraction[fraction == "0"] <- ""
      items <- paste0(
        formatC(whole, width = max(nchar(whole))),
        ".",
        formatC(fraction, width = -max(nchar(fraction)))
      )
      if (!identical(kind, "float64")) {
        dtype <- paste0(", dtype=", kind)
      }
    }
  }
  out <- paste0("array([", paste(items, collapse = ", "), "]", dtype, ")")
  if (nchar(out) > 75L) {
    unsupported()
  }
  out
}

write_csv_table <- function(path, table, sep) {
  quote_cells <- function(x) {
    needs <- grepl(sep, x, fixed = TRUE) |
      grepl('"', x, fixed = TRUE) |
      grepl("[\r\n]", x)
    x[needs] <- paste0('"', gsub('"', '""', x[needs], fixed = TRUE), '"')
    x
  }
  to_lines <- function(m) {
    if (ncol(m) == 0L) {
      return(rep("", nrow(m)))
    }
    columns <- lapply(seq_len(ncol(m)), function(j) quote_cells(m[, j]))
    lines <- do.call(paste, c(columns, sep = sep))
    # A row of one empty field is quoted so that it is not a blank line
    if (ncol(m) == 1L) {
      lines[columns[[1L]] == ""] <- '""'
    }
    lines
  }
  cells <- table$cells
  header <- table$header
  if (!is.null(table$index)) {
    cells <- cbind(table$index, cells)
    header <- c(table$index_name, header)
  }
  lines <- to_lines(cells)
  if (!is.null(header)) {
    lines <- c(
      to_lines(matrix(header, nrow = 1L, ncol = length(header))),
      lines
    )
  }
  con <- file(path, "wb")
  on.exit(close(con))
  writeLines(enc2utf8(lines), con, useBytes = TRUE)
  invisible(path)
}
