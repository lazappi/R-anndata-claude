#' Dense lazy seeds
#'
#' A `StoreDenseSeed` is a DelayedArray seed for a dense Element on disk, in
#' h5ad or zarr (v3 and v2).
#' It holds an open store handle and the path of the array and reads blocks
#' with the store layer's selection reads (`array_read()`), so one code path
#' serves every format.
#' The seed has the shape of the array in Python's order, which is the order of
#' the R array, so no transposing is needed.
#'
#' Its `type()` is fixed from the On-disk dtype and not from a read, because a
#' small h5ad selection of int64, uint32 or uint64 comes back as `integer` where
#' a whole read gives `double`.
#' The types are those of `read_h5ad()`: `integer` for int8, int16, int32,
#' uint8 and uint16, `logical` for bool and `double` otherwise.
#' Blocks are plain arrays, so use `store_dense_values()` to get the values
#' with the On-disk dtype record that `read_h5ad()` gives.
#' Reading int64 or uint64 values of magnitude 2^53 or more raises the error of
#' `read_h5ad()` when the block holding them is realised.
#'
#' Deviation from eager reads: an int32 array holding -2^31 (the bit pattern of
#' `NA_integer_`) is read as `double` by `read_h5ad()`, but a seed's type is
#' fixed before any read.
#' Realising a block that holds -2^31 therefore raises
#' `anndata_dtype_overflow_error`, suggesting an eager read.
#'
#' `chunkdim()` is the chunk grid of Python's `read_elem_lazy()`: the
#' `chunks` argument if given (`NA` or `-1` for the whole axis), otherwise the
#' on-disk chunk shape (the inner chunk shape of sharded zarr), and for a
#' contiguous HDF5 dataset 1000 or the axis length when that is smaller.
#' The handle must stay open while the seed is used.
#'
#' @param store An open store handle, see [io-store].
#' @param path Absolute path of the dense array.
#' @param chunks Optional chunk shape, one entry per dimension.
#' @param x A `StoreDenseSeed`.
#' @param index A list with one entry per dimension, `NULL` (every index) or a
#'   vector of positions.
#' @param call The call reported by errors.
#'
#' @name lazy-dense
#' @keywords internal
NULL

# The chunk size Python uses for an unchunked h5ad array
lazy_default_stride <- 1000L

#' @importClassesFrom S4Arrays Array
#' @noRd
setClass(
  "StoreDenseSeed",
  contains = "Array",
  slots = c(
    store = "ANY",
    path = "character",
    dim = "integer",
    type = "character",
    dtype = "character",
    chunks = "integer"
  )
)

# The R type of values read from an array of On-disk dtype `dtype`
lazy_r_type <- function(dtype) {
  if (dtype == "bool") {
    "logical"
  } else if (dtype %in% c("int8", "int16", "int32", "uint8", "uint16")) {
    "integer"
  } else {
    "double"
  }
}

# The dtype name of an array from its `array_info()` row, `NA` when it is not a
# bool, integer or float
info_dtype <- function(info) {
  if (identical(info$dclass, "ENUM")) {
    return("bool")
  }
  h5 <- names(h5_numeric_types)[match(
    sub("BE$", "LE", info$dtype),
    h5_numeric_types
  )]
  if (!is.na(h5)) {
    return(h5)
  }
  if (info$dtype %in% numeric_dtypes) info$dtype else NA_character_
}

# The chunk shape of `read_elem_lazy()` for an array of shape `shape` whose
# on-disk chunks are `disk` (`NULL` when contiguous)
resolve_lazy_chunks <- function(chunks, shape, disk, call) {
  if (!is.null(chunks)) {
    if (length(chunks) != length(shape)) {
      anndata_abort(
        "{.arg chunks} must have one entry per dimension, not
         {length(chunks)} for {length(shape)} dimension{?s}.",
        "anndata_invalid_value_error",
        call = call
      )
    }
    chunks <- as.numeric(chunks)
    whole <- is.na(chunks) | chunks == -1
    chunks[whole] <- shape[whole]
  } else if (is.null(disk)) {
    chunks <- pmin(lazy_default_stride, shape)
  } else {
    chunks <- disk
  }
  # An empty axis has a chunk of 0 (Python's layout), never above the axis
  as.integer(pmin(pmax(chunks, 1), shape))
}

#' @rdname lazy-dense
store_dense_seed <- function(
  store,
  path,
  chunks = NULL,
  call = rlang::caller_env()
) {
  info <- array_info(store, path)
  dtype <- info_dtype(info)
  if (is.na(dtype)) {
    abort_dataset_type(path, "it is not a dense numeric or bool array", call)
  }
  shape <- info$shape[[1L]]
  if (length(shape) == 0L) {
    abort_dataset_type(path, "it is a scalar and not an array", call)
  }
  methods::new(
    "StoreDenseSeed",
    store = store,
    path = path,
    dim = as.integer(shape),
    type = lazy_r_type(dtype),
    dtype = dtype,
    chunks = resolve_lazy_chunks(chunks, shape, info$chunks[[1L]], call)
  )
}

#' @importFrom DelayedArray extract_array type chunkdim
#' @rdname lazy-dense
setMethod("dim", "StoreDenseSeed", function(x) x@dim)

#' @rdname lazy-dense
setMethod("dimnames", "StoreDenseSeed", function(x) {
  vector("list", length(x@dim))
})

setMethod("type", "StoreDenseSeed", function(x) x@type)

setMethod("chunkdim", "StoreDenseSeed", function(x) x@chunks)

# Reads the block of `index` (a list as `extract_array()` gets, with repeated
# and unsorted positions allowed) from the array on disk. Only the sorted unique
# positions are read, then rearranged in memory.
lazy_dense_block <- function(x, index, call = rlang::caller_env()) {
  shape <- x@dim
  positions <- Map(
    function(i, n) if (is.null(i)) seq_len(n) else as.integer(i),
    index,
    shape
  )
  out_dim <- lengths(positions)
  if (any(out_dim == 0L)) {
    return(array(vector(x@type), dim = out_dim))
  }
  # `+ 0L` makes the vectors plain, as Rarr takes sorted ALTREP for a range
  unique_pos <- lapply(positions, function(i) sort(unique(i)) + 0L)
  # A dimension read in full needs no selection
  whole <- Map(identical, unique_pos, lapply(shape, seq_len))
  if (all(unlist(whole))) {
    selection <- NULL
  } else {
    selection <- Map(function(i, w) if (w) NULL else i, unique_pos, whole)
  }
  block <- array_read(x@store, x@path, selection, call)
  block <- array(
    unclass(drop_dtype(block)),
    dim = lengths(unique_pos)
  )
  # -2^31 is the bit pattern of NA_integer_, which read_h5ad() keeps by
  # returning a double, but a seed's type is fixed
  if (x@type == "integer" && any(block == -2^31, na.rm = TRUE)) {
    anndata_abort(
      c(
        "Cannot represent the values of {.path {x@path}} as {.val {x@dtype}}.",
        "x" = "A lazy integer array cannot hold the value of {.code NA_integer_}
               ({.val {-2^31}}).",
        "i" = "Read the array eagerly with {.fn read_h5ad} or {.fn read_zarr}."
      ),
      "anndata_dtype_overflow_error",
      path = x@path,
      dtype = x@dtype,
      call = call
    )
  }
  storage.mode(block) <- x@type
  if (identical(unname(unique_pos), unname(positions))) {
    return(block)
  }
  rows <- Map(match, positions, unique_pos)
  do.call(`[`, c(list(block), rows, list(drop = FALSE)))
}

#' @rdname lazy-dense
setMethod("extract_array", "StoreDenseSeed", function(x, index) {
  lazy_dense_block(x, index)
})

#' @rdname lazy-dense
store_dense_values <- function(x) {
  values <- lazy_dense_block(x, vector("list", length(x@dim)))
  # read_elem() gives a plain vector for a 1-d array, except a 1-element one
  if (length(x@dim) == 1L && x@dim != 1L) {
    values <- as.vector(values)
  }
  if (x@dtype == "bool") {
    return(values)
  }
  record_dtype(values, x@dtype)
}
