# Aligned mappings, pairwise mappings and raw for `concat()` (merge.py in
# Python anndata)

# The entries of an aligned mapping slot (`"obsm"`, ...) as a named list
mapping_entries <- function(adata, slot) {
  as.list(switch(
    slot,
    obsm = adata$obsm,
    varm = adata$varm,
    obsp = adata$obsp,
    varp = adata$varp
  ))
}

is_frame_element <- function(x) {
  methods::is(x, "DataFrame")
}

# The keys `join` keeps from a list of mappings
mapping_keys <- function(mappings, join) {
  if (join == "inner") intersect_keys(mappings) else union_keys(mappings)
}

# Concatenates the mapping of the concatenated axis (`obsm` for `axis = "obs"`)
# along its first dimension.
# Arrays of different widths are cut to the narrowest on an inner join and
# padded to the widest with `fill_value` on an outer join, as Python's range
# index reindexers do, and data frames are combined on their columns.
concat_axis_mapping <- function(
  mappings,
  ns,
  join,
  index,
  fill_value,
  call
) {
  keys <- mapping_keys(mappings, join)
  out <- lapply(keys, function(key) {
    els <- lapply(mappings, function(m) m[[key]])
    concat_mapping_element(els, ns, join, index, fill_value, call)
  })
  names(out) <- keys
  out
}

# `els` has an element per object, `NULL` where the object lacks the key
concat_mapping_element <- function(els, ns, join, index, fill_value, call) {
  present <- Filter(Negate(is.null), els)
  frames <- vapply(present, is_frame_element, logical(1))
  if (any(frames)) {
    if (!all(frames)) {
      anndata_abort(
        "Cannot concatenate a data frame with other array types.",
        "anndata_unsupported_value_error",
        call = call
      )
    }
    # An object without the key contributes rows with no columns
    filled <- lapply(seq_along(els), function(k) {
      els[[k]] %||% frame_from_columns(list(), as.character(seq_len(ns[[k]])))
    })
    return(concat_axis_annotation(filled, ns, join, index, NULL, NULL, call))
  }
  widths <- vapply(els, function(el) if (is.null(el)) 0L else ncol(el), 1L)
  width <- if (join == "inner") min(widths) else max(widths)
  old_alt <- lapply(widths, function(w) as.character(seq_len(w)))
  concat_arrays(
    els,
    ns,
    old_alt,
    as.character(seq_len(width)),
    1L,
    fill_value
  )
}

# Positions of `new` in `old`, with `NULL` for no change
alignment_positions <- function(old, new) {
  if (identical(old, new)) NULL else match(new, old)
}

# An array with its rows and columns picked by position (`NA` for a new one),
# as Python's `Reindexer` does, so new entries are `NaN` (dense) or empty
# (sparse, which has the default fill of 0)
reindex_array <- function(el, rows = NULL, cols = NULL) {
  if (is.null(rows) && is.null(cols)) {
    return(el)
  }
  rows <- rows %||% seq_len(nrow(el))
  cols <- cols %||% seq_len(ncol(el))
  if (is_sparse(el)) {
    return(reindex_sparse_array(el, rows, cols))
  }
  values <- drop_dtype(el)
  if (!anyNA(rows) && !anyNA(cols)) {
    return(copy_records(values[rows, cols, drop = FALSE], el))
  }
  storage.mode(values) <- "double"
  out <- matrix(NA_real_, length(rows), length(cols))
  keep_rows <- which(!is.na(rows))
  keep_cols <- which(!is.na(cols))
  out[keep_rows, keep_cols] <- values[
    rows[keep_rows],
    cols[keep_cols],
    drop = FALSE
  ]
  out
}

reindex_sparse_array <- function(el, rows, cols) {
  parts <- sparse_triplets(el)
  new_i <- match(seq_len(nrow(el)), rows)[parts$i + 1L] - 1L
  new_j <- match(seq_len(ncol(el)), cols)[parts$j + 1L] - 1L
  keep <- !is.na(new_i) & !is.na(new_j)
  sparse_from_triplets(
    new_i[keep],
    new_j[keep],
    parts$x[keep],
    c(length(rows), length(cols)),
    array_dtype(el),
    if (is_csr(el)) "R" else "C"
  )
}

# A frame with its rows picked by position, as `take_column()` does per column
reindex_frame <- function(el, rows, names) {
  frame_from_columns(
    lapply(as.list(el), take_column, positions = rows),
    names
  )
}

# The entries of the other axis mapping (`varm` for `axis = "obs"`) of each
# object reindexed to `alt_names` (both dimensions for pairwise mappings),
# then selected with the merge strategy
merge_alt_mapping <- function(
  adatas,
  slot,
  old_alt,
  alt_names,
  strategy,
  pairwise
) {
  reindexed <- lapply(seq_along(adatas), function(k) {
    positions <- alignment_positions(old_alt[[k]], alt_names)
    lapply(mapping_entries(adatas[[k]], slot), function(el) {
      if (is_frame_element(el)) {
        if (is.null(positions)) el else reindex_frame(el, positions, alt_names)
      } else if (pairwise) {
        reindex_array(el, positions, positions)
      } else {
        reindex_array(el, positions)
      }
    })
  })
  strategy(reindexed)
}

# Pairwise mappings as a block diagonal CSR matrix per key.
# An object without the key adds an empty boolean block.
concat_pairwise_mapping <- function(mappings, ns, join) {
  keys <- mapping_keys(mappings, join)
  out <- lapply(keys, function(key) {
    pieces <- lapply(seq_along(mappings), function(k) {
      el <- mappings[[k]][[key]]
      if (is.null(el)) {
        return(list(
          dtype = "bool",
          dims = c(ns[[k]], ns[[k]]),
          i = integer(),
          j = integer(),
          x = double()
        ))
      }
      parts <- if (is_sparse(el)) {
        sparse_triplets(el)
      } else {
        dense_triplets(drop_dtype(el))
      }
      c(list(dtype = array_dtype(el), dims = dim(el)), parts)
    })
    block_diagonal(pieces)
  })
  names(out) <- keys
  out
}

block_diagonal <- function(pieces) {
  dims <- vapply(pieces, function(p) as.integer(p$dims), integer(2L))
  row_offsets <- cumsum(c(0L, dims[1L, ]))[seq_along(pieces)]
  col_offsets <- cumsum(c(0L, dims[2L, ]))[seq_along(pieces)]
  sparse_from_triplets(
    unlist(lapply(seq_along(pieces), function(k) {
      pieces[[k]]$i + row_offsets[[k]]
    })),
    unlist(lapply(seq_along(pieces), function(k) {
      pieces[[k]]$j + col_offsets[[k]]
    })),
    unlist(lapply(pieces, function(p) p$x)),
    c(sum(dims[1L, ]), sum(dims[2L, ])),
    Reduce(promote_dtype, lapply(pieces, function(p) p$dtype)),
    "R"
  )
}

# The concatenated raw: every object's raw (its X, var and varm over the
# observations of the object) is concatenated as an `AnnData`.
# Python drops raw, with a warning, when only some objects have one.
concat_raw <- function(
  adatas,
  axis,
  join,
  label,
  keys,
  index_unique,
  fill_value
) {
  has_raw <- vapply(adatas, function(a) !is.null(a$raw), logical(1))
  if (!any(has_raw)) {
    return(NULL)
  }
  if (!all(has_raw)) {
    anndata_warn(
      "Only some {.cls AnnData} objects have {.field raw}, not concatenating
       {.field raw}.",
      "anndata_missing_raw_warning"
    )
    return(NULL)
  }
  parts <- lapply(adatas, function(a) {
    AnnData(
      X = backed_in_memory(a$raw$X),
      obs = frame_from_columns(list(), a$obs_names),
      var = a$raw$var,
      varm = as.list(a$raw$varm)
    )
  })
  raw <- concat(
    parts,
    axis = axis,
    join = join,
    label = label,
    keys = keys,
    index_unique = index_unique,
    fill_value = fill_value
  )
  # Python's `AnnData(raw=)` drops an `AnnData` with no observations, because
  # its length is zero and so it is falsy
  if (raw$n_obs == 0L) NULL else raw
}
