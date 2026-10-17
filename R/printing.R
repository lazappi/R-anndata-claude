#' Format and print an AnnData object
#'
#' Reproduces Python's `repr`: the shape followed by the keys of each non-empty
#' Slot. X is listed in `layers` as `None (.X)`.
#'
#' @param x An [AnnData()] object.
#' @param ... Ignored.
#' @return `format()` returns a single string, `print()` returns `x` invisibly.
#' @examples
#' adata <- AnnData(matrix(0, 2, 3))
#' print(adata)
#' @export
format.AnnData <- function(x, ...) {
  shape <- .subset2(x, "shape")
  slots <- c("obs", "var", "uns", "obsm", "varm", "obsp", "varp", "layers")
  lines <- character()
  # Written as a code point to keep the source ASCII
  times <- intToUtf8(0xD7)
  for (slot in slots) {
    keys <- slot_keys(x, slot)
    if (length(keys)) {
      lines <- c(
        lines,
        paste0("    ", slot, ": ", paste(keys, collapse = ", "))
      )
    }
  }
  paste(
    c(
      paste0(
        if (.subset2(x, "is_view")) "View of ",
        "AnnData object with n_obs ",
        times,
        " n_vars = ",
        shape[[1]],
        " ",
        times,
        " ",
        shape[[2]]
      ),
      lines
    ),
    collapse = "\n"
  )
}

#' @rdname format.AnnData
#' @export
print.AnnData <- function(x, ...) {
  cat(format(x), "\n", sep = "")
  invisible(x)
}

# The quoted keys of one Slot, as Python lists them
slot_keys <- function(x, slot) {
  if (slot %in% c("obs", "var")) {
    keys <- colnames(.subset2(x, slot))
  } else if (slot == "uns") {
    keys <- names(.subset2(x, "uns"))
  } else {
    keys <- .subset2(x, slot)$keys()
  }
  keys <- as.character(keys)
  # X is listed after the named layers, as Python does
  is_x <- is.na(keys)
  keys <- c(quote_key(keys[!is_x]), if (any(is_x)) "None (.X)")
  keys
}

# Python's `repr` of a string: single quotes unless the string has a single
# quote and no double quote, with backslash, control and non-printable
# characters escaped
quote_key <- function(keys) {
  vapply(
    keys,
    function(key) {
      use_double <- grepl("'", key, fixed = TRUE) &&
        !grepl("\"", key, fixed = TRUE)
      quote <- if (use_double) "\"" else "'"
      chars <- vapply(
        intToUtf8(utf8ToInt(key), multiple = TRUE),
        escape_char,
        character(1),
        quote = quote,
        USE.NAMES = FALSE
      )
      paste0(quote, paste(chars, collapse = ""), quote)
    },
    character(1),
    USE.NAMES = FALSE
  )
}

# One character as it appears inside Python's `repr` of a string
escape_char <- function(char, quote) {
  code <- utf8ToInt(char)
  if (char == quote || char == "\\") {
    paste0("\\", char)
  } else if (char == "\n") {
    "\\n"
  } else if (char == "\r") {
    "\\r"
  } else if (char == "\t") {
    "\\t"
  } else if (char != " " && grepl("^[\\p{C}\\p{Z}]$", char, perl = TRUE)) {
    if (code < 0x100) {
      sprintf("\\x%02x", code)
    } else if (code < 0x10000) {
      sprintf("\\u%04x", code)
    } else {
      sprintf("\\U%08x", code)
    }
  } else {
    char
  }
}
