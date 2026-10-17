#' Backed mode
#'
#' Internal pieces of backed mode (`file_backing.py`, `read_h5ad_backed`).
#' `read_h5ad(backed = )` keeps X and `raw$X` on disk while every other Slot is
#' read into memory, and the backing file is held by an `AnnDataFileManager`
#' (`adata$file`).
#'
#' The manager remembers the file name and mode, and opens read-only for
#' `"r"` and read-write for `"r+"`.
#' `close()` closes the handle but keeps the file name, so the object stays
#' backed, and reading X (or `raw$X`) opens the file again.
#' A finalizer closes the handle when the manager is garbage collected.
#' Unlike Python only the modes `"r"` and `"r+"` open, because `"w"` would
#' truncate the backing file.
#'
#' A `backed_x` stands for X or `raw$X` on disk.
#' It records where the array is and finds the open file through the manager,
#' so it survives a close.
#' A dense array is also a `backed_dense` (`R/backed-dense.R`) and a sparse
#' matrix a `backed_sparse` (`R/backed-sparse.R`).
#'
#' @param filename Path of the backing file.
#' @param filemode `"r"` or `"r+"`.
#' @param key Name of a member of the file, such as `"X"` or `"raw/X"`.
#' @param value A value to write.
#' @param manager An `AnnDataFileManager`.
#' @param path Path of the array within the file.
#' @param shape The shape of the array, rows then columns.
#' @param encoding The Encoding type, `"array"`, `"csr_matrix"` or
#'   `"csc_matrix"`.
#' @param dtype The dtype of the stored values.
#' @param store An open rhdf5 file handle.
#' @param call The call reported by errors.
#'
#' @name anndata-backed
#' @keywords internal
NULL

backed_modes <- c("r", "r+")

# The mode of `backed` in `read_h5ad()`: `NULL` for in-memory, otherwise "r" or
# "r+". Python reads `TRUE` as "r+" and treats `0` as `FALSE`.
check_backed <- function(backed, call) {
  if (is.null(backed) || isFALSE(backed) || identical(backed, 0)) {
    return(NULL)
  }
  if (isTRUE(backed)) {
    return("r+")
  }
  valid <- is.character(backed) &&
    length(backed) == 1L &&
    !is.na(backed) &&
    backed %in% backed_modes
  if (!valid) {
    abort_invalid_argument(
      "{.arg backed} must be {.code NULL}, a boolean, {.val r} or {.val r+}.",
      call
    )
  }
  backed
}

#' @noRd
file_manager_class <- R6Class(
  "AnnDataFileManager",
  cloneable = FALSE,
  public = list(
    #' @description Create a manager, which opens `filename` when it is given.
    initialize = function(
      filename = NULL,
      filemode = NULL,
      call = rlang::caller_env()
    ) {
      private$.filename <- filename
      private$.filemode <- filemode
      if (!is.null(filename)) {
        self$open(call = call)
      }
    },
    #' @description Opens the file, with a new name and mode when given.
    open = function(
      filename = NULL,
      filemode = NULL,
      call = rlang::caller_env()
    ) {
      if (!is.null(filename)) {
        private$.filename <- check_filename(filename, call)
      }
      if (!is.null(filemode)) {
        private$.filemode <- filemode
      }
      path <- private$.filename
      mode <- private$.filemode
      if (is.null(path)) {
        abort_invalid_argument(
          "Cannot open the backing file, no file is set.",
          call
        )
      }
      valid <- is.character(mode) &&
        length(mode) == 1L &&
        mode %in% backed_modes
      if (!valid) {
        abort_invalid_argument(
          "Invalid mode, it must be {.val r} or {.val r+}.",
          call
        )
      }
      if (!file.exists(path)) {
        anndata_abort(
          "Cannot open {.path {path}}, the file does not exist.",
          "anndata_file_not_found_error",
          call = call
        )
      }
      self$close()
      flags <- if (mode == "r") "H5F_ACC_RDONLY" else "H5F_ACC_RDWR"
      private$.file <- rhdf5::H5Fopen(path, flags = flags)
      invisible(self)
    },
    #' @description Closes the file and keeps its name, so the object stays
    #'   backed.
    close = function() {
      if (self$is_open) {
        rhdf5::H5Fclose(private$.file)
      }
      private$.file <- NULL
      invisible(self)
    },
    #' @description The open file, which is opened again after a `close()`.
    handle = function() {
      if (!self$is_open) {
        self$open()
      }
      private$.file
    },
    #' @description Whether the file has a member `key`.
    has = function(key) {
      isTRUE(member_exists(self$handle(), key))
    },
    #' @description The names of the members of the file.
    keys = function() {
      group_members(self$handle())
    },
    #' @description An open handle to the member `key`, which the caller closes.
    get = function(key, call = rlang::caller_env()) {
      if (!self$has(key)) {
        anndata_abort(
          "The backing file has no member {.val {key}}.",
          "anndata_key_error",
          call = call
        )
      }
      node_open(self$handle(), key)
    },
    #' @description Writes `value` as the member `key` (mode `"r+"` only).
    set = function(key, value, call = rlang::caller_env()) {
      private$check_writable("Cannot write to the backing file", call)
      write_elem(self$handle(), key, value, call = call)
      invisible(self)
    },
    #' @description Deletes the member `key` (mode `"r+"` only).
    remove = function(key, call = rlang::caller_env()) {
      private$check_writable("Cannot delete from the backing file", call)
      if (!self$has(key)) {
        anndata_abort(
          "The backing file has no member {.val {key}}.",
          "anndata_key_error",
          call = call
        )
      }
      member_delete(self$handle(), key)
      invisible(self)
    },
    #' @description The text Python's `repr` shows.
    format = function() {
      if (is.null(private$.filename)) {
        "Backing file manager: no file is set."
      } else {
        paste0("Backing file manager of file ", private$.filename, ".")
      }
    },
    #' @description Prints the manager.
    #' @param ... Ignored.
    print = function(...) {
      cat(self$format(), "\n", sep = "")
      invisible(self)
    }
  ),
  active = list(
    #' @field is_open Whether the file is open.
    is_open = function(value) {
      if (!missing(value)) {
        abort_read_only("is_open")
      }
      !is.null(private$.file) && isTRUE(rhdf5::H5Iis_valid(private$.file))
    },
    #' @field filename Path of the backing file, or `NULL`.
    filename = function(value) {
      if (!missing(value)) {
        abort_read_only("filename")
      }
      private$.filename
    },
    #' @field filemode `"r"`, `"r+"` or `NULL`.
    filemode = function(value) {
      if (!missing(value)) {
        abort_read_only("filemode")
      }
      private$.filemode
    }
  ),
  private = list(
    .filename = NULL,
    .filemode = NULL,
    .file = NULL,
    # Closes the file when the manager is garbage collected
    finalize = function() {
      self$close()
    },
    check_writable = function(what, call) {
      if (!identical(private$.filemode, "r+")) {
        anndata_abort(
          "{what}, it was opened read-only.",
          "anndata_read_only_error",
          call = call
        )
      }
    }
  )
)

# The array X (or `raw$X`) on disk, found again through the manager
new_backed_x <- function(
  manager,
  path,
  shape,
  encoding,
  dtype,
  cache_indptr = TRUE
) {
  dense <- identical(encoding, "array")
  structure(
    list(
      manager = manager,
      path = path,
      shape = as.integer(shape),
      encoding = encoding,
      dtype = dtype,
      # Sparse only: the environment that holds `indptr` once it was read
      cache = if (!dense && cache_indptr) new.env(parent = emptyenv()),
      # The shape lives here so that `append()` can grow it in place
      state = list2env(list(shape = as.integer(shape)), parent = emptyenv())
    ),
    class = c(
      if (dense) "backed_dense" else "backed_sparse",
      "backed_x"
    )
  )
}

# A handle is read-only, as Python's `shape` and `group` have no setter
#' @export
#' @noRd
`$<-.backed_x` <- function(x, name, value) {
  abort_read_only(name)
}

#' @export
#' @noRd
`[[<-.backed_x` <- function(x, i, value) {
  abort_read_only(i)
}

#' @export
#' @noRd
dim.backed_x <- function(x) {
  backed_shape(x)
}

# The current shape, which `sparse_dataset()$append()` changes
backed_shape <- function(x) .subset2(x, "state")$shape

#' @export
#' @noRd
format.backed_x <- function(x, ...) {
  shape <- backed_shape(x)
  encoding <- .subset2(x, "encoding")
  dtype <- .subset2(x, "dtype")
  if (identical(encoding, "array")) {
    return(paste0(
      "Backed dense array, shape (",
      paste(shape, collapse = ", "),
      "), dtype ",
      dtype
    ))
  }
  paste0(
    if (identical(encoding, "csr_matrix")) "CSRDataset" else "CSCDataset",
    ": backend hdf5, shape (",
    paste(shape, collapse = ", "),
    "), data_dtype ",
    dtype
  )
}

#' @export
#' @noRd
print.backed_x <- function(x, ...) {
  cat(format(x), "\n", sep = "")
  invisible(x)
}

# The dtype name of an array on disk, with `bool` for an enum
backed_dtype <- function(store, path) {
  if (identical(array_info(store, path)$dclass, "ENUM")) {
    return("bool")
  }
  h5_dtype(store, path)
}

# A `backed_x` for the Element at `path`, or `NULL` when it is not a numeric
# array or sparse matrix with a shape, which then is read into memory
backed_x_elem <- function(manager, path, store, call) {
  elem <- node_open(store, path)
  on.exit(node_close(elem), add = TRUE)
  encoding <- read_elem_attr(elem, "encoding-type")
  if (identical(encoding, "array")) {
    space <- rhdf5::H5Dget_space(elem)
    on.exit(rhdf5::H5Sclose(space), add = TRUE, after = FALSE)
    shape <- rev(rhdf5::H5Sget_simple_extent_dims(space)$size)
    data_path <- path
  } else if (encoding %in% c("csr_matrix", "csc_matrix")) {
    shape <- read_shape_attr(elem, path, call)
    data_path <- paste0(path, "/data")
  } else {
    return(NULL)
  }
  dtype <- backed_dtype(store, data_path)
  # Only 2-D arrays stay on disk, higher dimensions are read into memory
  if (length(shape) != 2L || is.na(dtype)) {
    return(NULL)
  }
  new_backed_x(manager, path, shape, encoding, dtype)
}

# Opens the file again when X is read after a `close()`, as Python does
reopen_backed <- function(x) {
  if (inherits(x, "backed_x")) {
    .subset2(x, "manager")$handle()
  }
  x
}
