#' Unencoded Elements
#'
#' Reads Elements written without `encoding-type` and `encoding-version`
#' attributes (`read_basic`), as old anndata releases did.
#' Each one raises `anndata_old_format_warning`, as Python's `OldFormatWarning`.
#' A group is read as a dict and a dataset as an array or scalar, and a group
#' with the h5sparse attributes `h5sparse_format` and `h5sparse_shape` is read
#' as a CSR or CSC matrix.
#' A compound dataset with array-valued fields (old `obsm` and `varm`) is read
#' as a list of matrices, one per field.
#' The member types of a compound dataset come from the compiled helper (ADR
#' 0008), so numeric fields keep their on-disk dtype records (such as float32).
#' Writing always uses the current encodings.
#'
#' Legacy files also read with `read_h5ad(backed = )` (an unencoded dense `X`
#' or h5sparse `X` stays on disk) and rewrite to the current encodings.
#' `read_lazy()` follows Python and only reads the current encodings, so it
#' raises for the legacy layouts, and it does not move `uns$neighbors` matrices
#' to `obsp`.
#'
#' @param elem An open group or dataset handle.
#' @param path Path of the Element.
#' @param store The store `elem` was opened from.
#' @param call The call reported by conditions.
#'
#' @name io-legacy
#' @keywords internal
NULL

# Whether a group is a matrix in the h5sparse layout
has_h5sparse_attrs <- function(elem) {
  attr_exists(elem, "h5sparse_format")
}

# The CSR or CSC encoding type of an h5sparse group
h5sparse_encoding <- function(elem) {
  paste0(read_elem_attr(elem, "h5sparse_format"), "_matrix")
}

# Python's `shape` property prefers `shape` and falls back to `h5sparse_shape`
read_h5sparse_shape <- function(elem, path, call) {
  if (attr_exists(elem, "shape")) {
    return(read_shape_attr(elem, path, call))
  }
  if (!attr_exists(elem, "h5sparse_shape")) {
    abort_io_registry(
      "Cannot read {.path {path}}, it has no {.field h5sparse_shape}
       attribute.",
      path = path,
      call = call
    )
  }
  as.vector(attr_read(elem, "h5sparse_shape"))
}

# Python's `read_dataframe_legacy`: a dataframe stored as a compound dataset
# whose first field is the index
read_dataframe_legacy <- function(store, path, call) {
  anndata_warn(
    "{.path {path}} was written with a very old version of AnnData.
     Consider rewriting it.",
    "anndata_old_format_warning",
    path = path,
    call = call
  )
  # The records give every numeric field its on-disk dtype (int64 and float32
  # included), string records are not kept in dataframe columns
  fields <- lapply(
    table_read(store, path, call, records = TRUE),
    function(field) {
      field <- rec_array_read_field(field)
      if (is.character(field)) drop_dtype(field) else field
    }
  )
  frame_from_parts(
    fields[-1L],
    plain_string(fields[[1L]]),
    names(fields)[[1L]]
  )
}

# Whether `path` is the legacy compound layout (a dataset) and not a dataframe
# Element (a group), as in Python's `read_dataframe`
is_legacy_frame <- function(store, path) {
  node <- node_open(store, path)
  on.exit(node_close(node), add = TRUE)
  !is_group(node)
}

# Python's `_clean_uns`: categories kept in `uns[["<col>_categories"]]` become
# the levels of the `obs` and `var` column of that name, and the key is removed
clean_legacy_uns <- function(obs, var, uns, call) {
  drop <- character()
  for (key in names(uns) %||% character()) {
    if (!endsWith(key, "_categories")) {
      next
    }
    name <- gsub("_categories", "", key, fixed = TRUE)
    categories <- as.vector(drop_dtype(uns[[key]]))
    for (frame in c("obs", "var")) {
      ann <- if (frame == "obs") obs else var
      if (!name %in% names(ann)) {
        next
      }
      codes <- drop_dtype(ann[[name]])
      # Python's hack to find the axis the categories were stored for
      if (!is.numeric(codes) || !isTRUE(all(codes < length(categories)))) {
        next
      }
      ann[[name]] <- categorical_from_parts(
        codes,
        categories,
        FALSE,
        paste0("/", frame, "/", name),
        call
      )
      if (frame == "obs") {
        obs <- ann
      } else {
        var <- ann
      }
      drop <- c(drop, key)
    }
  }
  uns[unique(drop)] <- NULL
  list(obs = obs, var = var, uns = uns)
}

# Python's `_read_legacy_raw`: `raw.X`, `raw.var` and `raw.varm` as members of
# the root, returned as the list `AnnData()` takes for `raw`
read_legacy_raw <- function(store, members, slots, call) {
  if (!is.null(slots$raw)) {
    abort_io_registry(
      "The store has both legacy and current raw formats.",
      path = "/raw.X",
      call = call
    )
  }
  # Python only reads the legacy members when `raw.X` exists
  if (!"raw.X" %in% members) {
    return(NULL)
  }
  raw <- list()
  for (name in c("X", "var", "varm")) {
    key <- paste0("raw.", name)
    if (!key %in% members) {
      next
    }
    path <- paste0("/", key)
    raw[name] <- list(
      if (name == "var" && is_legacy_frame(store, path)) {
        read_dataframe_legacy(store, path, call)
      } else {
        read_elem(store, path)
      }
    )
  }
  raw
}

# Python's `_move_adj_mtx`: 2-D `distances` and `connectivities` in
# `uns[["neighbors"]]` move to `obsp` with a `FutureWarning`
move_adjacency_matrices <- function(slots, call) {
  if (!is.list(slots$uns$neighbors)) {
    return(slots)
  }
  for (key in c("distances", "connectivities")) {
    value <- slots$uns$neighbors[[key]]
    if (length(dim(value)) != 2L) {
      next
    }
    warn_future(
      "Moving element from .uns['neighbors']['{key}'] to .obsp['{key}'].

       This is where adjacency matrices should go now.",
      call = call
    )
    slots$obsp[key] <- list(value)
    slots$uns$neighbors[key] <- NULL
  }
  slots
}

anndata_warn_unencoded <- function(path, call) {
  anndata_warn(
    "Element {.path {path}} was written without encoding metadata.",
    "anndata_old_format_warning",
    path = path,
    call = call
  )
}

# Python's `read_dataset` for a compound dataset without encoding metadata:
# a structured array. Fields with array values (the layout of old `obsm` and
# `varm`) come out as matrices and the others as a rec-array
read_unencoded_compound <- function(store, path, call) {
  dset <- rhdf5::H5Dopen(store, path)
  on.exit(rhdf5::H5Dclose(dset), add = TRUE)
  fields <- withCallingHandlers(
    suppressMessages(rhdf5::H5Dread(
      dset,
      bit64conversion = "double",
      compoundAsDataFrame = FALSE
    )),
    warning = function(w) abort_dtype_precision(path, "int64", call)
  )
  # h5py's complex numbers are the compound of `r` and `i`, which rhdf5 reads
  # as complex values
  if (!is.list(fields)) {
    return(NULL)
  }
  if (!any(vapply(fields, function(x) length(dim(x)) == 2L, logical(1)))) {
    return(read_rec_array_elem(NULL, path, store))
  }
  where <- h5_table_location(store, path)
  rhdf5::H5Fflush(store)
  members <- compound_members(where$file, where$dataset)
  for (i in seq_along(fields)) {
    if (length(dim(fields[[i]])) == 2L) {
      fields[[i]] <- t(fields[[i]])
    }
    if (members$class[[i]] %in% c("integer", "float")) {
      fields[[i]] <- record_dtype(
        fields[[i]],
        h5_member_dtype(
          members$class[[i]],
          members$size[[i]],
          members$sign[[i]]
        )
      )
    }
  }
  fields
}

# Whether `path` is a 1-d dataset of a single fixed-length string (the
# variable-length ones stay arrays in Python)
is_fixed_string_singleton <- function(store, path) {
  info <- array_info(store, path)
  if (!identical(info$dclass, "STRING") || as.integer(info$rank) != 1L) {
    return(FALSE)
  }
  if (!identical(as.numeric(info$shape[[1L]]), 1)) {
    return(FALSE)
  }
  dset <- rhdf5::H5Dopen(store, path)
  on.exit(rhdf5::H5Dclose(dset), add = TRUE)
  !rhdf5::H5Tis_variable_str(rhdf5::H5Dget_type(dset))
}

#' @rdname io-legacy
read_unencoded_elem <- function(elem, path, store, call) {
  anndata_warn_unencoded(path, call)
  if (!is_group(elem)) {
    if (
      !inherits(store, "zarr_node") &&
        identical(array_info(store, path)$dclass, "COMPOUND")
    ) {
      fields <- read_unencoded_compound(store, path, call)
      if (!is.null(fields)) {
        return(fields)
      }
    }
    # Backwards compat: old datasets have fixed-length strings as one element
    # 1-d arrays, which Python reads as a scalar (higher ranks are not strings
    # written by old versions, and Python would give their first row)
    scalar <- !inherits(store, "zarr_node") &&
      is_fixed_string_singleton(store, path)
    return(read_values_with_shape(store, path, scalar = scalar))
  }
  if (has_h5sparse_attrs(elem)) {
    csr <- identical(h5sparse_encoding(elem), "csr_matrix")
    shape <- read_h5sparse_shape(elem, path, call)
    return(read_sparse_parts(csr, shape, path, store, call))
  }
  read_mapping_elem(elem, path, store)
}
