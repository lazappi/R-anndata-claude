# Order of strings as natsort's default does: digit runs compare as integers,
# everything else compares by code point (so uppercase sorts before lowercase)
natural_order <- function(x) {
  tokens <- lapply(x, function(s) {
    digits <- gregexpr("[0-9]+", s)[[1]]
    if (digits[[1]] == -1L) {
      return(list(s))
    }
    starts <- c(1L, as.integer(digits) + attr(digits, "match.length"))
    ends <- c(as.integer(digits) - 1L, nchar(s))
    runs <- substring(
      s,
      as.integer(digits),
      as.integer(digits) +
        attr(digits, "match.length") -
        1L
    )
    words <- substring(s, starts, ends)
    out <- vector("list", length(words) + length(runs))
    out[seq(1L, length(out), by = 2L)] <- words
    out[seq(2L, length(out), by = 2L)] <- as.list(as.numeric(runs))
    out
  })
  width <- max(lengths(tokens), 0L)
  columns <- lapply(seq_len(width), function(j) {
    values <- lapply(tokens, function(t) if (j <= length(t)) t[[j]] else NA)
    if (j %% 2L == 1L) {
      as.character(unlist(values))
    } else {
      as.numeric(unlist(values))
    }
  })
  do.call(order, c(columns, list(na.last = FALSE, method = "radix")))
}

# Mirrors one `strings_to_categoricals` pass: a character column with at least
# one value and fewer distinct values than rows becomes an unordered factor
categorise_frame <- function(df, call) {
  if (!inherits(df, c("data.frame", "DataFrame"))) {
    abort_invalid_argument(
      "{.arg df} must be a data frame, not {.obj_type_friendly {df}}.",
      call
    )
  }
  for (key in colnames(df)) {
    column <- df[[key]]
    if (!is.character(column) || all(is.na(column))) {
      next
    }
    levels <- unique(column[!is.na(column)])
    if (length(levels) >= length(column)) {
      next
    }
    df[[key]] <- factor(column, levels = levels[natural_order(levels)])
    rlang::signal(
      paste0("... storing ", encodeString(key, quote = "'"), " as categorical"),
      class = "anndata_info_message"
    )
  }
  df
}

# Mirrors `rename_categories`: obs is tried before var, and `categories` are
# matched to the old levels by position
rename_frame_categories <- function(obs, var, key, categories, call) {
  if (!rlang::is_string(key)) {
    abort_invalid_argument("{.arg key} must be a single string.", call)
  }
  if (!is.atomic(categories) || is.null(categories) || is.object(categories)) {
    abort_invalid_argument(
      "Only list-like {.arg categories} is supported.",
      call
    )
  }
  attr <- if (key %in% colnames(obs)) {
    "obs"
  } else if (key %in% colnames(var)) {
    "var"
  } else {
    abort_key(
      "{.val {key}} is neither in {.field obs} nor in {.field var}.",
      "anndata_key_error",
      call
    )
  }
  frame <- if (attr == "obs") obs else var
  column <- frame[[key]]
  if (!is.factor(column)) {
    abort_invalid_argument(
      "Column {.val {key}} of {.field {attr}} must be a factor.",
      call
    )
  }
  categories <- as.character(categories)
  if (length(categories) != nlevels(column)) {
    abort_invalid_argument(
      "New categories need to have the same number of items as the old
       categories.",
      call
    )
  }
  if (anyDuplicated(categories)) {
    abort_invalid_argument("Categories must be unique.", call)
  }
  old <- levels(column)
  levels(column) <- categories
  frame[[key]] <- column
  list(attr = attr, frame = frame, old = old, new = categories)
}

# Scanpy stores per-group results (e.g. `rank_genes_groups`) as rec-arrays named
# by category in a `uns` entry whose `params$groupby` is the renamed key. Like
# Python, a rec-array whose fields are not the old categories is left alone with
# a warning
rename_uns_rec_arrays <- function(uns, key, old, new, call) {
  for (k1 in names(uns)) {
    entry <- uns[[k1]]
    params <- if (is.list(entry) && !is.object(entry)) entry[["params"]]
    groupby <- if (is.list(params) && !is.object(params)) params[["groupby"]]
    if (!rlang::is_string(groupby) || groupby != key) {
      next
    }
    for (k2 in names(entry)) {
      value <- entry[[k2]]
      if (!inherits(value, rec_array_class)) {
        next
      }
      if (identical(names(value), old)) {
        names(value) <- new
        uns[[k1]][[k2]] <- value
      } else {
        anndata_warn(
          "Omitting {k1}/{k2} as old categories do not match.",
          "anndata_rec_array_categories_mismatch_warning",
          call = call
        )
      }
    }
  }
  uns
}
