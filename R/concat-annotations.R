# Annotation, merge strategy and key handling for `concat()` (merge.py in
# Python anndata)

# Python's `MissingVal`: a merge strategy gives it when an element has no
# value, and the element is left out of the result
concat_missing <- structure(list(), class = "anndata_concat_missing")

is_concat_missing <- function(x) {
  inherits(x, "anndata_concat_missing")
}

# Python's `Mapping`: a named list (a dict). Frames are S4 and not mappings.
concat_is_mapping <- function(x) {
  is.list(x) &&
    !is.object(x) &&
    (!is.null(names(x)) || length(x) == 0L)
}

# The keys of a list of mappings, in the order of `OrderedSet` operations:
# a union is in order of appearance, and an intersection follows the last
# mapping (`a & b` iterates `b`)
union_keys <- function(ds) {
  unique(unlist(lapply(ds, names), use.names = FALSE))
}

intersect_keys <- function(ds) {
  Reduce(
    function(a, b) b[b %in% a],
    lapply(ds, function(d) unique(names(d) %||% character()))
  )
}

# The pandas-style dtype name of an annotation column
column_dtype <- function(x) {
  nullable <- !is.null(get_nullable(x))
  if (is.factor(x)) {
    "category"
  } else if (is.character(x)) {
    if (nullable) "str" else "object"
  } else if (is.logical(x)) {
    if (nullable) "boolean" else "bool"
  } else {
    paste0(if (nullable) "nullable-", array_dtype(x))
  }
}

# Python's `equal()`, which treats missing values as equal to each other.
# `same_type` also asks for the same column dtype, as `Series.equals` does.
concat_equal <- function(a, b, same_type = FALSE) {
  if (is.null(a) || is.null(b)) {
    return(is.null(a) && is.null(b))
  }
  if (is.factor(a) || is.factor(b)) {
    same <- is.factor(a) &&
      is.factor(b) &&
      setequal(levels(a), levels(b)) &&
      is.ordered(a) == is.ordered(b)
    if (!same) {
      return(FALSE)
    }
    a <- as.character(a)
    b <- as.character(b)
  }
  if (is.list(a) || is.list(b)) {
    if (
      !(is.list(a) && is.list(b)) ||
        length(a) != length(b) ||
        !identical(names(a), names(b))
    ) {
      return(FALSE)
    }
    return(all(vapply(
      seq_along(a),
      function(i) concat_equal(a[[i]], b[[i]]),
      logical(1)
    )))
  }
  if (is_sparse(a) || is_sparse(b)) {
    a <- as.matrix(a)
    b <- as.matrix(b)
  }
  if (!is.atomic(a) || !is.atomic(b)) {
    return(identical(a, b))
  }
  if (same_type && !identical(column_dtype(a), column_dtype(b))) {
    return(FALSE)
  }
  if (is.character(a) != is.character(b)) {
    return(FALSE)
  }
  a <- drop_dtype(a)
  b <- drop_dtype(b)
  if (!identical(dim(a), dim(b)) || length(a) != length(b)) {
    return(FALSE)
  }
  missing_a <- is.na(a)
  if (!identical(as.vector(missing_a), as.vector(is.na(b)))) {
    return(FALSE)
  }
  all(a[!missing_a] == b[!missing_a])
}

# The per-element logic, each giving `concat_missing` when there is no value
unique_value <- function(same_type) {
  function(vals) {
    first <- vals[[1L]]
    for (i in seq_along(vals)[-1L]) {
      if (!concat_equal(vals[[i]], first, same_type)) {
        return(concat_missing)
      }
    }
    first
  }
}

first_value <- function(vals) {
  vals[[1L]]
}

only_value <- function(vals) {
  if (length(vals) == 1L) vals[[1L]] else concat_missing
}

merge_nested <- function(ds, keys_join, value_join) {
  out <- list()
  for (key in keys_join(ds)) {
    has_key <- vapply(ds, function(d) key %in% names(d), logical(1))
    vals <- lapply(ds[has_key], function(d) d[[key]])
    value <- if (length(vals) == 0L) {
      concat_missing
    } else if (all(vapply(vals, concat_is_mapping, logical(1)))) {
      nested <- merge_nested(vals, keys_join, value_join)
      if (length(nested) == 0L) concat_missing else nested
    } else {
      value_join(vals)
    }
    if (!is_concat_missing(value)) {
      out[key] <- list(value)
    }
  }
  out
}

# A `merge` or `uns_merge` argument as a function of a list of mappings.
# `same_type` is for annotation columns, which must also have the same dtype.
resolve_merge_strategy <- function(
  strategy,
  arg,
  same_type = FALSE,
  call = rlang::caller_env(2L)
) {
  if (is.function(strategy)) {
    return(strategy)
  }
  if (is.null(strategy)) {
    return(function(ds) list())
  }
  if (!is.character(strategy) || length(strategy) != 1L) {
    strategy <- NA_character_
  }
  switch(
    strategy,
    same = function(ds) {
      merge_nested(ds, intersect_keys, unique_value(same_type))
    },
    unique = function(ds) {
      merge_nested(ds, union_keys, unique_value(same_type))
    },
    first = function(ds) merge_nested(ds, union_keys, first_value),
    only = function(ds) merge_nested(ds, union_keys, only_value),
    anndata_abort(
      "{.arg {arg}} must be {.code NULL}, a function or one of
       {.or {.val {c('same', 'unique', 'first', 'only')}}}.",
      "anndata_invalid_argument_error",
      call = call
    )
  )
}

# The `keys` for the objects, from the argument or the names of the list
resolve_concat_keys <- function(keys, list_names, n, call) {
  if (!is.null(list_names)) {
    if (!is.null(keys)) {
      anndata_abort(
        "Cannot specify categories in both list names and {.arg keys}.
         Only specify this once.",
        "anndata_invalid_argument_error",
        call = call
      )
    }
    keys <- list_names
  }
  if (is.null(keys)) {
    return(as.character(seq_len(n) - 1L))
  }
  if (length(keys) != n || anyNA(keys) || anyDuplicated(keys) > 0L) {
    anndata_abort(
      "{.arg keys} must have one unique value for each of the {n} objects.",
      "anndata_invalid_argument_error",
      call = call
    )
  }
  as.character(keys)
}

# Python's `check_combinable_cols()`
check_combinable_cols <- function(cols, join, call) {
  repeated <- unique(unlist(lapply(cols, function(x) x[duplicated(x)])))
  problem <- if (join == "inner") {
    intersect(repeated, Reduce(intersect, cols))
  } else {
    repeated
  }
  if (length(problem) > 0L) {
    anndata_abort(
      c(
        "Cannot combine data frames as some contained duplicated column
         names, causing ambiguity.",
        "i" = "The problem columns are {.val {problem}}."
      ),
      "anndata_invalid_argument_error",
      call = call
    )
  }
}

# Copies the dtype and nullable records of `from` to `to`
copy_records <- function(to, from) {
  dtype <- get_dtype(from)
  nullable <- get_nullable(from)
  if (!is.null(dtype)) {
    to <- set_dtype(to, dtype)
  }
  if (!is.null(nullable)) {
    to <- set_nullable(to, nullable)
  }
  to
}

# Rows `positions` of a column, `NA` where a position is `NA`, with the dtype
# pandas gives the reindexed column: bool becomes nullable boolean and the
# integers float64 (the numpy `NaN` has no integer form)
take_column <- function(x, positions) {
  taken <- drop_dtype(x)[positions]
  if (!anyNA(positions)) {
    return(copy_records(taken, x))
  }
  dtype <- column_dtype(x)
  if (dtype == "bool") {
    return(set_nullable(taken, TRUE))
  }
  if (
    is.numeric(taken) &&
      is.null(get_nullable(x)) &&
      !array_dtype(x) %in% c("float32", "float64")
  ) {
    storage.mode(taken) <- "double"
    return(taken)
  }
  copy_records(taken, x)
}

# A column made from `pieces`, a list with one entry per object that is `NULL`
# where the object lacks the column (its `n` rows are then missing).
# Follows `unify_dtypes()` and `pd.concat`.
combine_columns <- function(pieces, ns, call) {
  present <- Filter(Negate(is.null), pieces)
  has_missing <- length(present) < length(pieces)
  dtypes <- vapply(present, column_dtype, character(1))
  fill <- function(convert) {
    unlist(
      lapply(seq_along(pieces), function(k) {
        if (is.null(pieces[[k]])) rep(NA, ns[[k]]) else convert(pieces[[k]])
      }),
      use.names = FALSE
    )
  }
  strings <- function(x) as.character(drop_dtype(x))

  if (all(dtypes == "category")) {
    return(combine_factors(present, fill))
  }
  if (any(dtypes == "category") || all(dtypes %in% c("str", "object"))) {
    # A categorical with another type is an object column of strings
    if (!all(dtypes %in% c("category", "str", "object"))) {
      abort_column_types(dtypes, call)
    }
    out <- as.character(fill(strings))
    # Only strings that are all `str` stay `str`, anything else is `object`
    if (all(dtypes == "str")) {
      out <- set_nullable(out, get_nullable(present[[1L]]))
    }
    return(out)
  }
  if (all(dtypes %in% c("bool", "boolean"))) {
    out <- as.logical(fill(drop_dtype))
    return(
      if (has_missing || any(dtypes == "boolean")) {
        set_nullable(out, TRUE)
      } else {
        out
      }
    )
  }
  numeric <- vapply(present, is.numeric, logical(1))
  if (!all(numeric)) {
    abort_column_types(dtypes, call)
  }
  nullable <- any(vapply(present, function(p) !is.null(get_nullable(p)), TRUE))
  dtype <- Reduce(promote_dtype, vapply(present, array_dtype, character(1)))
  if (has_missing && !nullable && !startsWith(dtype, "float")) {
    dtype <- "float64"
  }
  out <- typed_dense(as.double(fill(drop_dtype)), dtype)
  if (nullable) set_nullable(out, TRUE) else out
}

abort_column_types <- function(dtypes, call) {
  anndata_abort(
    "Cannot combine annotation columns of the types {.val {unique(dtypes)}}.",
    "anndata_unsupported_value_error",
    call = call
  )
}

# Categories of categorical columns: the natural-order union unless some are
# ordered, when the common order is kept if every column has it and otherwise
# the column becomes strings
combine_factors <- function(present, fill) {
  all_levels <- lapply(present, levels)
  union <- unique(unlist(all_levels, use.names = FALSE))
  union <- union[natural_order(union)]
  values <- as.character(fill(as.character))
  if (!any(vapply(present, is.ordered, logical(1)))) {
    return(factor(values, levels = union))
  }
  with_levels <- all_levels[lengths(all_levels) > 0L]
  shared <- if (length(unique(all_levels)) == 1L) {
    all_levels[[1L]]
  } else {
    sort(union, method = "radix")
  }
  same_order <- length(with_levels) > 0L &&
    all(vapply(
      present[lengths(all_levels) > 0L],
      function(p) is.ordered(p) && identical(levels(p), shared),
      logical(1)
    ))
  if (same_order) {
    factor(values, levels = shared, ordered = TRUE)
  } else {
    values
  }
}

# An annotation `DataFrame` from a list of columns
frame_from_columns <- function(columns, names) {
  methods::new(
    "DFrame",
    listData = if (length(columns)) {
      columns
    } else {
      structure(list(), names = character())
    },
    nrows = length(names),
    rownames = names
  )
}

# The annotation of the concatenation axis (`pd.concat` of the frames)
concat_axis_annotation <- function(
  frames,
  ns,
  join,
  index,
  label,
  keys,
  call
) {
  cols <- lapply(frames, colnames)
  check_combinable_cols(cols, join, call)
  column_names <- if (join == "inner") {
    Reduce(function(a, b) a[a %in% b], cols)
  } else {
    unique(unlist(cols))
  }
  columns <- lapply(column_names, function(name) {
    pieces <- lapply(frames, function(f) {
      if (name %in% colnames(f)) f[[name]] else NULL
    })
    combine_columns(pieces, ns, call)
  })
  names(columns) <- column_names
  if (!is.null(label)) {
    columns[[label]] <- factor(rep(keys, times = ns), levels = keys)
  }
  frame_from_columns(columns, index)
}

# The annotation of the other axis: each frame reindexed to `alt_names`, then
# merged with `strategy`
concat_alt_annotation <- function(
  frames,
  old_alt,
  alt_names,
  strategy,
  custom
) {
  reindexed <- lapply(seq_along(frames), function(k) {
    positions <- match(alt_names, old_alt[[k]])
    lapply(as.list(frames[[k]]), take_column, positions = positions)
  })
  # A custom function gets the reindexed frames and returns a frame or a list
  # of columns
  merged <- if (custom) {
    as.list(strategy(lapply(reindexed, frame_from_columns, names = alt_names)))
  } else {
    strategy(reindexed)
  }
  frame_from_columns(merged, alt_names)
}
