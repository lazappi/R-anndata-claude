#' Dataset compression
#'
#' `dataset_kwargs` holds the dataset creation options that [write_elem()]
#' passes down to every dataset, as h5py's keywords do.
#' `compression` is `"gzip"` or `"lzf"`, and `compression_opts` is the gzip
#' level from 0 to 9 (4 when `NULL`), which `"lzf"` does not accept.
#' A compressed dataset is chunked with the shape h5py guesses, and scalars and
#' the `null` Element are never compressed, as in Python.
#' The internal key `as_dense` lists the Elements to write dense, see
#' [write_h5ad()].
#'
#' @param dataset_kwargs A list of dataset creation options.
#' @param compression,compression_opts As in [write_h5ad()].
#' @param dims Dimensions of the dataset as HDF5 sees them (row-major).
#' @param type An HDF5 type name or handle.
#' @param typesize Size of one element in bytes.
#' @param call The call reported by errors.
#'
#' @name io-compression
#' @keywords internal
NULL

#' @rdname io-compression
check_compression <- function(
  compression,
  compression_opts,
  call = rlang::caller_env()
) {
  if (is.null(compression)) {
    if (!is.null(compression_opts)) {
      abort_invalid_argument(
        "{.arg compression_opts} needs {.arg compression} to be set.",
        call
      )
    }
    return(invisible(NULL))
  }
  valid <- is.character(compression) &&
    length(compression) == 1L &&
    compression %in% c("gzip", "lzf")
  if (!valid) {
    abort_invalid_argument(
      "{.arg compression} must be {.val gzip}, {.val lzf} or {.code NULL}.",
      call
    )
  }
  if (identical(compression, "lzf")) {
    if (!is.null(compression_opts)) {
      abort_invalid_argument(
        "The {.val lzf} compression filter accepts no
         {.arg compression_opts}.",
        call
      )
    }
  } else if (!is.null(compression_opts)) {
    valid <- is.numeric(compression_opts) &&
      length(compression_opts) == 1L &&
      !is.na(compression_opts) &&
      compression_opts == round(compression_opts) &&
      compression_opts >= 0 &&
      compression_opts <= 9
    if (!valid) {
      abort_invalid_argument(
        "{.arg compression_opts} must be a gzip level, an integer from 0 to 9.",
        call
      )
    }
  }
  invisible(NULL)
}

# h5py's `guess_chunk` (`h5py/_hl/filters.py`)
#' @rdname io-compression
guess_chunk <- function(dims, typesize) {
  chunk_min <- 8 * 1024
  chunk_max <- 1024 * 1024
  chunks <- as.double(dims)
  chunks[chunks == 0] <- 1024
  target <- 16 * 1024 * 2^log10(prod(chunks) * typesize / (1024 * 1024))
  target <- min(max(target, chunk_min), chunk_max)
  i <- 0L
  repeat {
    bytes <- prod(chunks) * typesize
    near <- bytes < target || abs(bytes - target) / target < 0.5
    if ((near && bytes < chunk_max) || prod(chunks) == 1) {
      break
    }
    j <- i %% length(chunks) + 1L
    chunks[[j]] <- ceiling(chunks[[j]] / 2)
    i <- i + 1L
  }
  as.integer(chunks)
}

#' @rdname io-compression
make_dcpl <- function(dataset_kwargs, dims, type) {
  compression <- dataset_kwargs$compression
  if (is.null(compression) || length(dims) == 0L) {
    return(NULL)
  }
  # A handle is a string of digits, a predefined type is named like `H5T_*`
  tid <- if (startsWith(type, "H5T_")) rhdf5::H5Tcopy(type) else type
  dcpl <- rhdf5::H5Pcreate("H5P_DATASET_CREATE")
  # rhdf5 gives no size for variable-length strings, which h5py takes as 16
  typesize <- rhdf5::H5Tget_size(tid)
  rhdf5::H5Pset_chunk(dcpl, guess_chunk(dims, typesize %||% 16L))
  if (identical(compression, "gzip")) {
    rhdf5::H5Pset_deflate(dcpl, dataset_kwargs$compression_opts %||% 4L)
  } else {
    if (utils::packageVersion("rhdf5") >= "2.57.12") {
      # `h5tid` is deprecated (and ignored) from this version
      rhdf5::H5Pset_lzf(dcpl)
    } else {
      # `H5Pset_lzf()` crashes on a type with no size, and only reads the size,
      # so a 16-byte type stands in for variable-length strings
      rhdf5::H5Pset_lzf(
        dcpl,
        h5tid = if (is.null(typesize)) complex_type() else tid
      )
    }
  }
  dcpl
}

# Closes the property list of `make_dcpl()`, which is `NULL` without compression
close_dcpl <- function(dcpl) {
  if (!is.null(dcpl)) {
    rhdf5::H5Pclose(dcpl)
  }
}
