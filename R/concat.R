#' Concatenate AnnData objects
#'
#' `concat()` combines `AnnData` objects along `axis`, following Python
#' anndata 0.13.4 `concat()`.
#' X and every layer present in the inputs are stacked along `axis` and aligned
#' on the other axis by name, either on the names every object has
#' (`join = "inner"`) or on all names (`join = "outer"`).
#'
#' @section Arrays:
#' With an inner join the names keep the order of the first object.
#' With an outer join the names are sorted, unless every object has the same
#' names.
#' An outer join fills the entries it introduces with `fill_value`.
#' The default is `0` when any of the arrays being combined is sparse and `NA`
#' otherwise, so dense arrays become floating point.
#' `fill_value` is an On-disk dtype in Python's terms: an R `integer` is int64,
#' a `double` is float64 and a `logical` is bool.
#'
#' Arrays are combined like numpy does.
#' The result has the promoted On-disk dtype of the inputs, so int32 with
#' float32 gives float64.
#' A result is sparse (CSR, even for CSC inputs) when any input is sparse and
#' dense otherwise.
#' An array that only some objects have is kept on an outer join, with the
#' other objects contributing `fill_value`, and dropped on an inner join.
#' The same applies to X, and objects without X give a result without X.
#'
#' @section Annotations:
#' The annotation of the concatenated axis (`obs` for `axis = "obs"`) has the
#' columns every object has on an inner join and all of them on an outer join,
#' with `NA` where an object lacks a column.
#' Categorical columns take the union of the categories in natural order
#' unless some are ordered, and `bool` columns become nullable boolean when
#' missing values are introduced.
#' The annotation of the other axis keeps the columns `merge` selects, from the
#' annotations reindexed to the result's names.
#' Columns of types that pandas would combine into an `object` column of mixed
#' values (such as numbers with strings) raise
#' `anndata_unsupported_value_error`.
#' Keys are character, so numeric `keys` are converted to strings.
#'
#' @section Merge strategies:
#' `merge` and `uns_merge` are `NULL` (nothing is kept), `"same"` (values that
#' are the same in every object), `"unique"` (values with one possible value),
#' `"first"` (the first value) or `"only"` (values in only one object).
#' `uns_merge` applies them recursively to lists.
#' A function takes its place: it is called with the list of reindexed
#' annotation data frames (or of `uns` lists) and returns a data frame or named
#' list (or a list).
#'
#' @section Aligned mappings:
#' The mapping of the concatenated axis (`obsm` for `axis = "obs"`) is
#' concatenated for the keys every object has (inner join) or all keys (outer
#' join).
#' Arrays of different widths are cut to the narrowest on an inner join and
#' padded to the widest with `fill_value` on an outer join, and data frames are
#' combined on their columns.
#' The mapping of the other axis (`varm`) is reindexed to the result's names and
#' selected with `merge`, so it is empty by default.
#' With `pairwise = TRUE` the pairwise mapping of the concatenated axis (`obsp`)
#' is combined as a block diagonal CSR matrix, and otherwise it is empty.
#' The pairwise mapping of the other axis (`varp`) follows `merge`.
#'
#' @section Raw:
#' When every object has `raw` its `X`, `var` and `varm` are concatenated with
#' the same `axis`, `join` and other arguments, and the `var` columns and `varm`
#' entries follow the rules for the other axis above.
#' When only some objects have `raw` it is dropped with a warning of class
#' `anndata_missing_raw_warning`.
#'
#' @section Lazy inputs:
#' When every object is read with [read_lazy()], `X`, `layers` and the `obsm`
#' arrays stay lazy (`DelayedArray`) and their realised values equal the
#' in-memory result.
#' When some objects are lazy and others are not, the lazy ones are read into
#' memory, as Python does.
#'
#' @section Deviations from Python:
#' `obs` and `var` of lazy objects are always read into memory (Python keeps
#' them lazy, loses their categorical columns and fails on an outer join with
#' string columns), and a lazy result has DelayedArray's R types, not the
#' promoted On-disk dtype.
#' Annotation columns Python would turn into a mixed `object` column raise
#' `anndata_unsupported_value_error`.
#' See `vignette("deviations")` for the full list.
#'
#' @param adatas A list of `AnnData` objects.
#'   A named list uses its names as `keys`.
#' @param axis Which axis to concatenate along, `"obs"` or `"var"`.
#' @param join How to align the other axis, `"inner"` (the default) or
#'   `"outer"`.
#' @param merge How the annotation of the other axis is selected, see the
#'   Merge strategies section.
#' @param uns_merge How `uns` is selected, with the same strategies as `merge`.
#' @param label A column of the concatenated axis annotation that gets the
#'   `keys` of the objects as a factor, or `NULL` for none.
#' @param keys A name for each object (unique), by default `"0"`, `"1"`, ...
#' @param index_unique A delimiter to make the concatenated names unique, as
#'   `"{name}{index_unique}{key}"`, or `NULL` to keep the names.
#' @param fill_value The value for entries an outer join introduces, see the
#'   Arrays section.
#' @param pairwise Whether to combine the pairwise mapping of the concatenated
#'   axis, see the Aligned mappings section.
#'
#' @return An `AnnData`.
#'
#' @examples
#' a <- AnnData(data.frame(x = c(1, 1), y = c(1, 1), row.names = c("a", "b")))
#' b <- AnnData(data.frame(y = c(2, 2), z = c(2, 2), row.names = c("c", "d")))
#' concat(list(a, b))$var_names
#' concat(list(a, b), join = "outer")$X
#'
#' @export
concat <- function(
  adatas,
  axis = c("obs", "var"),
  join = c("inner", "outer"),
  merge = NULL,
  uns_merge = NULL,
  label = NULL,
  keys = NULL,
  index_unique = NULL,
  fill_value = NULL,
  pairwise = FALSE
) {
  join_given <- !missing(join)
  axis <- check_concat_choice(axis, c("obs", "var"), "axis")
  join <- check_concat_choice(join, c("inner", "outer"), "join")
  if (!rlang::is_bool(pairwise)) {
    anndata_abort(
      "{.arg pairwise} must be {.code TRUE} or {.code FALSE}.",
      "anndata_invalid_argument_error"
    )
  }
  merge_fn <- resolve_merge_strategy(merge, "merge", same_type = TRUE)
  # Arrays are equal whatever their dtype, only data frame columns compare it
  mapping_merge_fn <- resolve_merge_strategy(merge, "merge")
  uns_merge_fn <- resolve_merge_strategy(uns_merge, "uns_merge")
  list_names <- concat_list_names(adatas)
  adatas <- as_concat_inputs(adatas)
  check_fill_value(fill_value)
  check_concat_string(label, "label")
  check_concat_string(index_unique, "index_unique")
  keys <- resolve_concat_keys(
    keys,
    list_names,
    length(adatas),
    rlang::caller_env()
  )

  axis_index <- match(axis, c("obs", "var"))
  alt_index <- 3L - axis_index
  names_of <- function(adata, i) {
    if (i == 1L) adata$obs_names else adata$var_names
  }
  ns <- vapply(adatas, function(a) a$shape[[axis_index]], integer(1))
  concat_names <- as.character(unlist(lapply(adatas, names_of, i = axis_index)))
  if (!is.null(index_unique)) {
    concat_names <- paste0(concat_names, index_unique, rep(keys, times = ns))
  }
  old_alt <- lapply(adatas, names_of, i = alt_index)
  alt_names <- merge_names(old_alt, join)

  array_keys <- layer_keys(adatas, join)
  # Python warns when only some objects have an X and `join` is not explicit
  has_x <- vapply(adatas, function(a) !is.null(a$X), logical(1))
  if (!join_given && any(has_x) && !all(has_x)) {
    anndata_warn(
      "Some {.field X} are {.code NULL} and {.arg join} is not explicit.
       {.field X} will be dropped, as {.field layers} are. Pass an explicit
       {.arg join} to silence this.",
      "anndata_missing_x_warning"
    )
  }

  arrays <- lapply(array_keys, function(key) {
    els <- lapply(adatas, function(a) layer_array(a, key))
    concat_arrays(
      els,
      ns,
      old_alt,
      alt_names,
      axis_index,
      fill_value
    )
  })
  names(arrays) <- ifelse(is.na(array_keys), NA_character_, array_keys)
  x_position <- which(is.na(array_keys))
  x <- if (length(x_position)) arrays[[x_position]] else NULL
  arrays <- arrays[!is.na(array_keys)]

  call <- rlang::caller_env()
  annotation_of <- function(i) {
    # Lazy frames are read into memory (Python keeps them lazy, see `concat()`)
    lapply(adatas, function(a) {
      realise_lazy_value(if (i == 1L) a$obs else a$var)
    })
  }
  axis_frame <- concat_axis_annotation(
    annotation_of(axis_index),
    ns,
    join,
    concat_names,
    label,
    keys,
    call
  )
  alt_frame <- concat_alt_annotation(
    annotation_of(alt_index),
    old_alt,
    alt_names,
    merge_fn,
    is.function(merge)
  )
  frames <- if (axis_index == 1L) {
    list(obs = axis_frame, var = alt_frame)
  } else {
    list(obs = alt_frame, var = axis_frame)
  }
  shape <- if (is.null(x)) {
    c(nrow(frames$obs), nrow(frames$var))
  }

  axis_slots <- paste0(c("obs", "var")[c(axis_index, alt_index)], c("m", "m"))
  pair_slots <- paste0(c("obs", "var")[c(axis_index, alt_index)], c("p", "p"))
  axis_mapping <- concat_axis_mapping(
    lapply(adatas, mapping_entries, slot = axis_slots[[1L]], lazy = TRUE),
    ns,
    join,
    concat_names,
    fill_value,
    call
  )
  axis_pairwise <- if (pairwise) {
    concat_pairwise_mapping(
      lapply(adatas, mapping_entries, slot = pair_slots[[1L]]),
      ns,
      join
    )
  }
  alt_mapping <- merge_alt_mapping(
    adatas,
    axis_slots[[2L]],
    old_alt,
    alt_names,
    mapping_merge_fn,
    FALSE
  )
  alt_pairwise <- merge_alt_mapping(
    adatas,
    pair_slots[[2L]],
    old_alt,
    alt_names,
    mapping_merge_fn,
    TRUE
  )
  uns <- uns_merge_fn(lapply(adatas, function(a) a$uns))
  raw <- concat_raw(adatas, axis, join, label, keys, index_unique, fill_value)

  slots <- list(
    obsm = axis_mapping,
    varm = alt_mapping,
    obsp = axis_pairwise,
    varp = alt_pairwise
  )
  if (axis_index == 2L) {
    names(slots) <- c("varm", "obsm", "varp", "obsp")
  }
  AnnData(
    X = x,
    obs = frames$obs,
    var = frames$var,
    uns = uns,
    obsm = slots$obsm,
    varm = slots$varm,
    obsp = slots$obsp,
    varp = slots$varp,
    layers = if (length(arrays)) arrays,
    raw = raw,
    shape = shape
  )
}

# The names of a list of objects, which are the keys (as a Python mapping's
# keys are), or `NULL` when the list is unnamed
concat_list_names <- function(adatas) {
  nms <- names(adatas)
  if (is.null(nms) || !is.list(adatas) || all(!nzchar(nms))) {
    return(NULL)
  }
  nms
}

check_concat_string <- function(value, arg, call = rlang::caller_env(2L)) {
  if (!is.null(value) && !(is.character(value) && length(value) == 1L)) {
    anndata_abort(
      "{.arg {arg}} must be {.code NULL} or a single string.",
      "anndata_invalid_argument_error",
      call = call
    )
  }
}

check_concat_choice <- function(
  value,
  choices,
  arg,
  call = rlang::caller_env(2L)
) {
  if (identical(value, choices)) {
    return(choices[[1L]])
  }
  if (!is.character(value) || length(value) != 1L || !value %in% choices) {
    anndata_abort(
      "{.arg {arg}} must be one of {.or {.val {choices}}}.",
      "anndata_invalid_argument_error",
      call = call
    )
  }
  value
}

as_concat_inputs <- function(adatas, call = rlang::caller_env(2L)) {
  if (inherits(adatas, "AnnData")) {
    adatas <- list(adatas)
  }
  if (!is.list(adatas) || length(adatas) == 0L) {
    anndata_abort(
      "{.arg adatas} must be a list of one or more {.cls AnnData} objects.",
      "anndata_invalid_argument_error",
      call = call
    )
  }
  is_anndata <- vapply(adatas, inherits, logical(1), what = "AnnData")
  if (!all(is_anndata)) {
    anndata_abort(
      "{.arg adatas} must contain only {.cls AnnData} objects.",
      "anndata_invalid_argument_error",
      call = call
    )
  }
  unname(adatas)
}

check_fill_value <- function(fill_value, call = rlang::caller_env(2L)) {
  is_scalar <- (is.numeric(fill_value) || is.logical(fill_value)) &&
    length(fill_value) == 1L &&
    !is.object(fill_value)
  if (!is.null(fill_value) && !is_scalar) {
    anndata_abort(
      "{.arg fill_value} must be {.code NULL} or a single number or logical.",
      "anndata_invalid_argument_error",
      call = call
    )
  }
}

# pandas `Index.intersection` keeps the order of the first index and drops
# repeats
intersect_names <- function(a, b) {
  unique(a[a %in% b])
}

# pandas `Index.union` returns the first index when they are equal, and
# otherwise a sorted union (code point order, as the byte order of UTF-8 is)
union_names <- function(a, b) {
  if (identical(a, b) || length(b) == 0L) {
    return(a)
  }
  if (length(a) == 0L) {
    return(b)
  }
  sort(unique(c(a, b)), method = "radix")
}

merge_names <- function(names, join) {
  Reduce(if (join == "inner") intersect_names else union_names, names)
}

# The keys of the arrays to combine in Python's order: `NA` is X.
# An inner join keeps the keys every object has, an outer join all of them.
layer_keys <- function(adatas, join) {
  per_object <- lapply(adatas, function(a) names(a$layers))
  combine <- if (join == "inner") intersect else union
  Reduce(combine, per_object)
}

layer_array <- function(adata, key) {
  layers <- as.list(adata$layers)
  position <- match(key, names(layers))
  # Python reads a backed X into memory to concatenate it
  if (is.na(position)) NULL else backed_in_memory(layers[[position]])
}

# numpy's result type for two dtypes
promote_dtype <- function(a, b) {
  if (identical(a, b) || b == "bool") {
    return(a)
  }
  if (a == "bool") {
    return(b)
  }
  kind <- function(d) {
    if (startsWith(d, "float")) {
      "f"
    } else if (startsWith(d, "uint")) {
      "u"
    } else {
      "i"
    }
  }
  bits <- function(d) as.integer(sub("^[a-z]+", "", d))
  name <- function(k, n) paste0(c(f = "float", u = "uint", i = "int")[[k]], n)
  ka <- kind(a)
  kb <- kind(b)
  if (ka == kb) {
    return(name(ka, max(bits(a), bits(b))))
  }
  if (ka == "f" || kb == "f") {
    float <- if (ka == "f") a else b
    int <- if (ka == "f") b else a
    # float32 holds the 8 and 16 bit integers exactly
    return(name("f", max(bits(float), if (bits(int) <= 16L) 32L else 64L)))
  }
  signed <- if (ka == "i") a else b
  unsigned <- if (ka == "u") a else b
  if (bits(signed) > bits(unsigned)) {
    return(signed)
  }
  if (bits(unsigned) == 64L) "float64" else name("i", 2L * bits(unsigned))
}

# The dtype of a matrix: its data dtype when sparse
array_dtype <- function(x) {
  record <- get_dtype(x)
  if (is_sparse(x)) {
    data <- record[["data"]]
    if (!is.null(data)) {
      return(data)
    }
    return(if (methods::is(x, "lMatrix")) "bool" else "float64")
  }
  if (!is.null(record)) {
    return(record[[1L]])
  }
  if (is.logical(x)) "bool" else native_dtype(x)
}

# The dtype of a fill value as numpy would see it
fill_dtype <- function(fill_value) {
  if (is.logical(fill_value)) {
    "bool"
  } else if (is.integer(fill_value)) {
    "int64"
  } else {
    "float64"
  }
}

# A numeric matrix as the R type that holds `dtype`, with its record
typed_dense <- function(values, dtype) {
  if (dtype == "bool") {
    storage.mode(values) <- "logical"
    return(values)
  }
  if (dtype %in% c("int8", "int16", "int32", "uint8", "uint16")) {
    storage.mode(values) <- "integer"
  } else {
    storage.mode(values) <- "double"
  }
  record_dtype(values, dtype)
}

# Entries of a sparse matrix as zero-based triplets
sparse_triplets <- function(x) {
  tri <- methods::as(x, "TsparseMatrix")
  list(i = tri@i, j = tri@j, x = as.double(tri@x))
}

# Entries of a dense matrix that a sparse matrix would store: pandas and scipy
# keep `NA` and `NaN`
dense_triplets <- function(x) {
  keep <- which(x != 0 | is.na(x))
  nr <- nrow(x)
  list(
    i = (keep - 1L) %% nr,
    j = (keep - 1L) %/% nr,
    x = as.double(x[keep])
  )
}

# Positions of the new names in the old names, `NA` where an old name is
# absent
reindex_positions <- function(old_names, new_names) {
  match(new_names, old_names)
}

concat_arrays <- function(
  els,
  ns,
  old_alt,
  alt_names,
  axis_index,
  fill_value
) {
  # Python keeps the result lazy only when every input is lazy, otherwise it
  # reads the lazy ones into memory
  lazy <- vapply(els, is_delayed, logical(1))
  if (any(lazy)) {
    if (all(lazy | vapply(els, is.null, logical(1)))) {
      return(concat_arrays_lazy(
        els,
        ns,
        old_alt,
        alt_names,
        axis_index,
        fill_value
      ))
    }
    els <- lapply(els, realise_lazy_value)
  }
  sparse <- any(vapply(
    els,
    function(el) !is.null(el) && is_sparse(el),
    logical(1)
  ))
  default_fill <- if (sparse) 0 else NA_real_
  explicit_fill <- !is.null(fill_value)
  fill <- if (explicit_fill) fill_value else default_fill
  fill_type <- if (explicit_fill) fill_dtype(fill) else "float64"
  n_alt <- length(alt_names)

  pieces <- vector("list", length(els))
  for (k in seq_along(els)) {
    el <- els[[k]]
    old <- old_alt[[k]]
    if (is.null(el)) {
      pieces[[k]] <- missing_piece(ns[[k]], n_alt, fill, fill_type, sparse)
      next
    }
    oriented <- if (axis_index == 2L) {
      if (is_sparse(el)) Matrix::t(el) else t(el)
    } else {
      el
    }
    positions <- reindex_positions(old, alt_names)
    unchanged <- identical(old, alt_names)
    if (is_sparse(oriented) || sparse) {
      pieces[[k]] <- reindex_sparse_piece(
        oriented,
        positions,
        unchanged,
        fill,
        fill_type,
        n_alt
      )
    } else {
      pieces[[k]] <- reindex_dense_piece(
        oriented,
        positions,
        unchanged,
        fill,
        fill_type
      )
    }
  }
  dtype <- Reduce(promote_dtype, lapply(pieces, function(p) p$dtype))

  if (sparse) {
    stack_sparse(pieces, dtype, n_alt, axis_index)
  } else {
    stack_dense(pieces, dtype, axis_index)
  }
}

is_delayed <- function(x) {
  methods::is(x, "DelayedArray")
}

# `concat_arrays()` for lazily read inputs: the pieces are reindexed and
# stacked as DelayedArray operations, so nothing is read until the result is.
# The result type is DelayedArray's (R types, not the On-disk dtype), and
# a sparse result is whatever DelayedArray keeps sparse.
concat_arrays_lazy <- function(
  els,
  ns,
  old_alt,
  alt_names,
  axis_index,
  fill_value
) {
  sparse <- any(vapply(
    els,
    function(el) !is.null(el) && DelayedArray::is_sparse(el),
    logical(1)
  ))
  fill <- fill_value %||% if (sparse) 0 else NA_real_
  n_alt <- length(alt_names)
  constant <- function(n, m) {
    DelayedArray::ConstantArray(c(n, m), value = fill)
  }
  pieces <- lapply(seq_along(els), function(k) {
    el <- els[[k]]
    if (is.null(el)) {
      return(constant(ns[[k]], n_alt))
    }
    dimnames(el) <- NULL
    oriented <- if (axis_index == 2L) t(el) else el
    old <- old_alt[[k]]
    if (identical(old, alt_names)) {
      return(oriented)
    }
    positions <- reindex_positions(old, alt_names)
    present <- which(!is.na(positions))
    absent <- which(is.na(positions))
    if (length(present) == 0L) {
      return(constant(ns[[k]], n_alt))
    }
    taken <- oriented[, positions[present], drop = FALSE]
    if (length(absent) == 0L) {
      return(taken)
    }
    joined <- cbind(taken, constant(ns[[k]], length(absent)))
    joined[, order(c(present, absent)), drop = FALSE]
  })
  stacked <- do.call(S4Arrays::arbind, pieces)
  if (axis_index == 2L) t(stacked) else stacked
}

# The fill for an object without the array (numpy broadcasts the fill value,
# and a sparse group uses an all-zero CSR matrix of float64 for 0)
missing_piece <- function(n, n_alt, fill, fill_type, sparse) {
  if (sparse) {
    if (isTRUE(fill == 0)) {
      return(list(
        kind = "sparse",
        dtype = "float64",
        n = n,
        i = integer(),
        j = integer(),
        x = double()
      ))
    }
    full <- matrix(as.double(fill), n, n_alt)
    return(c(
      list(kind = "sparse", dtype = fill_type, n = n),
      dense_triplets(full)
    ))
  }
  list(
    kind = "dense",
    dtype = fill_type,
    n = n,
    x = matrix(as.double(fill), n, n_alt)
  )
}

reindex_dense_piece <- function(el, positions, unchanged, fill, fill_type) {
  dtype <- array_dtype(el)
  values <- drop_dtype(el)
  storage.mode(values) <- "double"
  if (unchanged) {
    return(list(kind = "dense", dtype = dtype, n = nrow(el), x = values))
  }
  absent <- is.na(positions)
  if (ncol(el) == 0L) {
    return(list(
      kind = "dense",
      dtype = fill_type,
      n = nrow(el),
      x = matrix(as.double(fill), nrow(el), length(positions))
    ))
  }
  taken <- values[, ifelse(absent, 1L, positions), drop = FALSE]
  if (any(absent)) {
    taken[, absent] <- as.double(fill)
    dtype <- promote_dtype(dtype, fill_type)
  }
  list(kind = "dense", dtype = dtype, n = nrow(el), x = taken)
}

reindex_sparse_piece <- function(
  el,
  positions,
  unchanged,
  fill,
  fill_type,
  n_alt
) {
  dtype <- array_dtype(el)
  parts <- if (is_sparse(el)) sparse_triplets(el) else dense_triplets(el)
  n <- nrow(el)
  if (unchanged) {
    return(c(list(kind = "sparse", dtype = dtype, n = n), parts))
  }
  if (ncol(el) == 0L) {
    return(missing_piece(n, n_alt, fill, fill_type, TRUE))
  }
  # Where each old column goes
  target <- match(seq_len(ncol(el)), positions)
  new_j <- target[parts$j + 1L] - 1L
  keep <- !is.na(new_j)
  parts <- list(i = parts$i[keep], j = new_j[keep], x = parts$x[keep])
  absent <- which(is.na(positions))
  if (length(absent) > 0L && !isTRUE(fill == 0)) {
    dtype <- promote_dtype(dtype, fill_type)
    parts <- list(
      i = c(parts$i, rep(seq_len(n) - 1L, times = length(absent))),
      j = c(parts$j, rep(absent - 1L, each = n)),
      x = c(parts$x, rep(as.double(fill), n * length(absent)))
    )
  }
  c(list(kind = "sparse", dtype = dtype, n = n), parts)
}

stack_dense <- function(pieces, dtype, axis_index) {
  values <- do.call(rbind, lapply(pieces, function(p) p$x))
  if (axis_index == 2L) {
    values <- t(values)
  }
  typed_dense(values, dtype)
}

stack_sparse <- function(pieces, dtype, n_alt, axis_index) {
  sizes <- vapply(pieces, function(p) as.integer(p$n), integer(1))
  offsets <- cumsum(c(0L, sizes))[seq_along(pieces)]
  triplets <- list(
    i = unlist(lapply(seq_along(pieces), function(k) {
      pieces[[k]]$i + offsets[[k]]
    })),
    j = unlist(lapply(pieces, function(p) p$j)),
    x = unlist(lapply(pieces, function(p) p$x))
  )
  dims <- c(sum(sizes), n_alt)
  if (axis_index == 2L) {
    triplets[c("i", "j")] <- triplets[c("j", "i")]
    dims <- rev(dims)
  }
  sparse_from_triplets(triplets$i, triplets$j, triplets$x, dims, dtype, "R")
}

# A sparse matrix (`repr` "R" is CSR) from zero-based triplets, with `dtype` as
# the dtype of its data
sparse_from_triplets <- function(i, j, x, dims, dtype, repr) {
  data <- if (dtype == "bool") as.logical(x) else x
  matrix <- Matrix::sparseMatrix(
    i = as.integer(i %||% integer()),
    j = as.integer(j %||% integer()),
    x = data %||% (if (dtype == "bool") logical() else double()),
    dims = dims,
    index1 = FALSE,
    repr = repr
  )
  if (dtype %in% c("bool", "float64")) {
    matrix
  } else {
    set_dtype(matrix, c(data = dtype))
  }
}
