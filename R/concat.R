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
#' @section Not yet supported:
#' The annotations of the result (`obs`, `var`, `obsm`, `varm`, `obsp`, `varp`,
#' `uns` and `raw`) are not combined yet, so the result only has names.
#'
#' @param adatas A list of `AnnData` objects.
#' @param axis Which axis to concatenate along, `"obs"` or `"var"`.
#' @param join How to align the other axis, `"inner"` (the default) or
#'   `"outer"`.
#' @param fill_value The value for entries an outer join introduces, see the
#'   Arrays section.
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
  fill_value = NULL
) {
  join_given <- !missing(join)
  axis <- check_concat_choice(axis, c("obs", "var"), "axis")
  join <- check_concat_choice(join, c("inner", "outer"), "join")
  adatas <- as_concat_inputs(adatas)
  check_fill_value(fill_value)

  axis_index <- match(axis, c("obs", "var"))
  alt_index <- 3L - axis_index
  names_of <- function(adata, i) {
    if (i == 1L) adata$obs_names else adata$var_names
  }
  concat_names <- unlist(lapply(adatas, names_of, i = axis_index))
  old_alt <- lapply(adatas, names_of, i = alt_index)
  alt_names <- merge_names(old_alt, join)

  keys <- layer_keys(adatas, join)
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

  ns <- vapply(adatas, function(a) a$shape[[axis_index]], integer(1))
  arrays <- lapply(keys, function(key) {
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
  names(arrays) <- ifelse(is.na(keys), NA_character_, keys)
  x_position <- which(is.na(keys))
  x <- if (length(x_position)) arrays[[x_position]] else NULL
  arrays <- arrays[!is.na(keys)]

  frames <- list(
    obs = names_frame(if (axis_index == 1L) concat_names else alt_names),
    var = names_frame(if (axis_index == 2L) concat_names else alt_names)
  )
  shape <- if (is.null(x)) {
    c(nrow(frames$obs), nrow(frames$var))
  }
  AnnData(
    X = x,
    obs = frames$obs,
    var = frames$var,
    layers = if (length(arrays)) arrays,
    shape = shape
  )
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

names_frame <- function(names) {
  S4Vectors::DataFrame(row.names = names)
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
  if (is.na(position)) NULL else layers[[position]]
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
  data <- if (dtype == "bool") as.logical(triplets$x) else triplets$x
  matrix <- Matrix::sparseMatrix(
    i = as.integer(triplets$i %||% integer()),
    j = as.integer(triplets$j %||% integer()),
    x = data %||% (if (dtype == "bool") logical() else double()),
    dims = dims,
    index1 = FALSE,
    repr = "R"
  )
  if (dtype %in% c("bool", "float64")) {
    matrix
  } else {
    set_dtype(matrix, c(data = dtype))
  }
}
