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
# quote and no double quote
quote_key <- function(keys) {
  vapply(
    keys,
    function(key) {
      key <- gsub("\\", "\\\\", key, fixed = TRUE)
      if (grepl("'", key, fixed = TRUE) && !grepl("\"", key, fixed = TRUE)) {
        paste0("\"", key, "\"")
      } else {
        paste0("'", gsub("'", "\\'", key, fixed = TRUE), "'")
      }
    },
    character(1),
    USE.NAMES = FALSE
  )
}
