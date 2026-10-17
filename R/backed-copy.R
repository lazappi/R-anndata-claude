# Copying a backed dense X to a new h5ad file in blocks, as Python's
# `write_chunked_dense_array_to_group` does, so that X is never read whole

# The chunk shape of the dataset behind a `backed_dense`, `NULL` when it is not
# chunked (HDF5 order, which is numpy's)
backed_source_chunks <- function(x) {
  dset <- rhdf5::H5Dopen(.subset2(x, "manager")$handle(), .subset2(x, "path"))
  on.exit(rhdf5::H5Dclose(dset), add = TRUE)
  plist <- rhdf5::H5Dget_create_plist(dset)
  on.exit(rhdf5::H5Pclose(plist), add = TRUE, after = FALSE)
  if (identical(rhdf5::H5Pget_layout(plist), "H5D_CHUNKED")) {
    as.integer(rhdf5::H5Pget_chunk(plist))
  }
}

# Python's `_iter_chunks_for_copy`: the chunks of the destination when it has
# some (given as `dest_chunks`), otherwise runs of rows that are the larger of
# the setting and the source's chunk length. Each block is a list of `rows` and
# `cols` positions, with `cols` of `NULL` for every column.
backed_copy_blocks <- function(shape, source_chunks, dest_chunks, min_rows) {
  starts <- function(n, step) {
    if (n == 0L) integer() else seq(1L, n, by = step)
  }
  if (!is.null(dest_chunks)) {
    row_starts <- starts(shape[[1L]], dest_chunks[[1L]])
    col_starts <- starts(shape[[2L]], dest_chunks[[2L]])
    blocks <- list()
    for (row in row_starts) {
      for (col in col_starts) {
        blocks[[length(blocks) + 1L]] <- list(
          rows = row:min(row + dest_chunks[[1L]] - 1L, shape[[1L]]),
          cols = col:min(col + dest_chunks[[2L]] - 1L, shape[[2L]])
        )
      }
    }
    return(blocks)
  }
  n_rows <- max(min_rows, source_chunks[[1L]] %||% 1L)
  lapply(starts(shape[[1L]], n_rows), function(row) {
    list(rows = row:min(row + n_rows - 1L, shape[[1L]]), cols = NULL)
  })
}

# Writes the `backed_dense` `x` as the dense array Element `X` of `group`, one
# block at a time. Compression chunks the new dataset, which the blocks follow.
write_backed_dense <- function(group, x, dataset_kwargs, call) {
  shape <- .subset2(x, "shape")
  dtype <- .subset2(x, "dtype")
  type <- if (identical(dtype, "bool")) {
    bool_type()
  } else {
    h5_numeric_types[[dtype]]
  }
  space <- h5_space(shape, FALSE)
  on.exit(rhdf5::H5Sclose(space), add = TRUE)
  dcpl <- make_dcpl(dataset_kwargs, rev(shape), type)
  on.exit(close_dcpl(dcpl), add = TRUE)
  dset <- rhdf5::H5Dcreate(group, "X", type, space, dcpl = dcpl)
  on.exit(rhdf5::H5Dclose(dset), add = TRUE, after = FALSE)
  blocks <- backed_copy_blocks(
    shape,
    backed_source_chunks(x),
    if (!is.null(dcpl)) as.integer(rhdf5::H5Pget_chunk(dcpl)),
    anndata_settings$min_rows_for_chunked_h5_copy
  )
  for (block in blocks) {
    values <- backed_dense_block(x, block$rows, block$cols, call)
    h5_write_block(
      dset,
      block$rows,
      block$cols %||% seq_len(shape[[2L]]),
      values,
      dtype
    )
  }
  elem <- node_open(group, "X")
  on.exit(node_close(elem), add = TRUE, after = FALSE)
  set_elem_attr(elem, "encoding-type", "array")
  set_elem_attr(elem, "encoding-version", "0.2.0")
  invisible(NULL)
}
