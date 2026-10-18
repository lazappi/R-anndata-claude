#' Sparse lazy seeds
#'
#' A `StoreSparseSeed` is a DelayedArray seed for a CSR or CSC Element on disk,
#' in h5ad or zarr (v3 and v2).
#' It wraps a `backed_sparse` over the store, so it reads `indptr` once and
#' then only the slices of `data` and `indices` that a block needs, and the
#' same code serves every format.
#' Blocks stay sparse: `extract_sparse_array()` gives an `SVT_SparseMatrix`
#' (SparseArray) and `is_sparse()` is `TRUE`.
#'
#' As for [lazy-dense], `type()` is fixed from the On-disk dtype of `data`
#' (`logical` for bool, `integer` for int8, int16, int32, uint8 and uint16 and
#' `double` otherwise), and `store_sparse_values()` gives the matrix with the
#' On-disk dtype record that `read_h5ad()` gives.
#'
#' `chunkdim()` follows Python's `read_elem_lazy()` for sparse groups: the
#' major axis (rows for CSR, columns for CSC) is cut every 1000 positions or
#' every `chunks` entry (`NA` or `-1` for the whole axis), and the minor axis is
#' never cut, so `chunks` may only be the axis length, `-1` or `NA` there.
#' An axis of length 0 has a chunk of 0, as in Python.
#'
#' @param store An open store handle, see [io-store].
#' @param path Absolute path of the sparse matrix Element.
#' @param chunks Optional chunk shape, two entries.
#' @param x A `StoreSparseSeed`.
#' @param index A list with one entry per dimension, `NULL` (every index) or a
#'   vector of positions.
#' @param call The call reported by errors.
#'
#' @name lazy-sparse
#' @keywords internal
NULL

#' @noRd
setClass(
  "StoreSparseSeed",
  contains = "Array",
  slots = c(
    backed = "ANY",
    dim = "integer",
    type = "character",
    dtype = "character",
    chunks = "integer"
  )
)

# The chunk shape of a sparse group: only the major axis is cut
resolve_sparse_chunks <- function(chunks, shape, csr, call) {
  major <- if (csr) 1L else 2L
  minor <- 3L - major
  stride <- lazy_default_stride
  if (!is.null(chunks)) {
    if (length(chunks) != 2L) {
      anndata_abort(
        "{.arg chunks} must be a tuple of two integers.",
        "anndata_invalid_value_error",
        call = call
      )
    }
    chunks <- as.numeric(chunks)
    if (
      !(is.na(chunks[[minor]]) || chunks[[minor]] %in% c(-1, shape[[minor]]))
    ) {
      anndata_abort(
        c(
          "Only the major axis can be chunked.",
          "i" = "Try setting {.arg chunks} to
                 {.code {if (csr) '(1000, -1)' else '(-1, 1000)'}}."
        ),
        "anndata_invalid_value_error",
        call = call
      )
    }
    stride <- chunks[[major]]
    if (is.na(stride) || stride == -1) {
      stride <- shape[[major]]
    }
  }
  out <- integer(2L)
  out[[major]] <- as.integer(min(stride, shape[[major]]))
  out[[minor]] <- as.integer(shape[[minor]])
  out
}

#' @rdname lazy-sparse
store_sparse_seed <- function(
  store,
  path,
  chunks = NULL,
  call = rlang::caller_env()
) {
  elem <- node_open(store, path)
  on.exit(node_close(elem), add = TRUE)
  encoding <- read_elem_attr(elem, "encoding-type")
  if (!encoding %in% c("csr_matrix", "csc_matrix")) {
    abort_dataset_type(path, "it is not a sparse matrix", call)
  }
  shape <- as.integer(read_shape_attr(elem, path, call))
  dtype <- info_dtype(array_info(store, part_path(path, "data")))
  if (is.na(dtype)) {
    abort_dataset_type(path, "its data is not numeric or bool", call)
  }
  csr <- identical(encoding, "csr_matrix")
  chunks <- resolve_sparse_chunks(chunks, shape, csr, call)
  methods::new(
    "StoreSparseSeed",
    backed = new_backed_x(
      list(handle = function() store),
      path,
      shape,
      encoding,
      dtype
    ),
    dim = shape,
    type = lazy_r_type(dtype),
    dtype = dtype,
    chunks = chunks
  )
}

#' @importFrom DelayedArray is_sparse extract_sparse_array
#' @rdname lazy-sparse
setMethod("dim", "StoreSparseSeed", function(x) x@dim)

#' @rdname lazy-sparse
setMethod("dimnames", "StoreSparseSeed", function(x) vector("list", 2L))

setMethod("type", "StoreSparseSeed", function(x) x@type)

setMethod("chunkdim", "StoreSparseSeed", function(x) x@chunks)

setMethod("is_sparse", "StoreSparseSeed", function(x) TRUE)

# The sparse block of `index` (a list as `extract_array()` gets) with the
# On-disk dtype record, rows and columns arranged as the positions are given
lazy_sparse_block <- function(x, index, call = rlang::caller_env()) {
  positions <- Map(
    function(i, n) if (is.null(i)) NULL else as.integer(i),
    index,
    x@dim
  )
  backed_sparse_read(x@backed, positions[[1L]], positions[[2L]], call)
}

# A block as an SVT_SparseMatrix of the seed's type
lazy_sparse_svt <- function(block, type) {
  SparseArray::SVT_SparseArray(drop_dtype(block), type = type)
}

#' @rdname lazy-sparse
setMethod("extract_sparse_array", "StoreSparseSeed", function(x, index) {
  lazy_sparse_svt(lazy_sparse_block(x, index), x@type)
})

#' @rdname lazy-sparse
setMethod("extract_array", "StoreSparseSeed", function(x, index) {
  as.array(extract_sparse_array(x, index))
})

#' @rdname lazy-sparse
store_sparse_values <- function(x) {
  lazy_sparse_block(x, vector("list", 2L))
}
