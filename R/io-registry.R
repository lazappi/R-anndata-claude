#' Element registry
#'
#' Internal dispatch for reading and writing Elements in an open rhdf5 file or
#' group (`registry.py`).
#' Reading dispatches on the Encoding type and Encoding version stored in the
#' `encoding-type` and `encoding-version` attributes.
#' Writing dispatches on the R class of the value, and records the Encoding type
#' and Encoding version on the written Element unless the writer already set
#' them.
#'
#' Encoding tickets add to the registry with `register_reader()` and
#' `register_writer()`.
#' Readers are called as `fn(elem, path, store)` with an open group or dataset
#' handle, its absolute path and the store it was opened from (rhdf5 cannot
#' open a sibling dataset from a dataset handle).
#' Writers are called as `fn(store, key, value, dataset_kwargs, path)` with an
#' open group handle.
#' Nested Elements go through `read_elem()` and `write_elem()` so that every
#' level is dispatched and checked.
#'
#' @param store An open rhdf5 file or group handle.
#' @param path Path of the Element within `store`.
#' @param key Name of the Element within `store`, `"/"` writes into the root.
#' @param value The R value to write.
#' @param dataset_kwargs A list of dataset creation options.
#' @param type,version Encoding type and Encoding version.
#' @param class R class the writer handles, matched with [methods::is()].
#' @param fn Reader or writer function.
#' @param call The call reported by errors.
#'
#' @name io-registry
#' @keywords internal
NULL

io_registry <- new.env(parent = emptyenv())
io_registry$read <- list()
io_registry$write <- list()

spec_key <- function(type, version) paste0(type, "\r", version)

# Looks a named package function up at call time, so replacing it (as covr does
# to instrument it) takes effect. Anonymous functions are kept as they are.
late_bound <- function(fn_expr, fn) {
  if (!is.symbol(fn_expr)) {
    return(fn)
  }
  name <- as.character(fn_expr)
  ns <- environment(fn)
  if (
    !is.environment(ns) ||
      !identical(ns, topenv(ns)) ||
      !exists(name, envir = ns, inherits = FALSE)
  ) {
    return(fn)
  }
  function(...) get(name, envir = ns, inherits = FALSE)(...)
}

#' @rdname io-registry
register_reader <- function(type, version, fn) {
  io_registry$read[[spec_key(type, version)]] <- late_bound(substitute(fn), fn)
  invisible(NULL)
}

#' @rdname io-registry
register_writer <- function(class, type, version, fn) {
  fn <- late_bound(substitute(fn), fn)
  current <- io_registry$write[[class]]
  changed <- !is.null(current) &&
    (current$type != type || current$version != version)
  if (changed) {
    abort_io_registry(c(
      "Cannot overwrite the encoding of {.cls {class}}.",
      i = "It is {.val {paste(current$type, current$version)}},
           not {.val {paste(type, version)}}."
    ))
  }
  io_registry$write[[class]] <- list(
    type = type,
    version = version,
    fn = fn
  )
  invisible(NULL)
}

abort_legacy <- function(path, what, call = rlang::caller_env()) {
  abort_not_supported(
    c(
      "Cannot read {.path {path}}, it is {what}.",
      i = "Legacy file formats are not yet supported."
    ),
    class = "anndata_legacy_format_error",
    path = path,
    call = call
  )
}

# Used by the dataframe reader (ticket 09) when a column is stored the old way
abort_legacy_categorical <- function(path, call = rlang::caller_env()) {
  abort_legacy(path, "an old-style categorical", call = call)
}

abort_awkward <- function(path, call = rlang::caller_env()) {
  abort_not_supported(
    c(
      "Cannot read {.path {path}}, it is an {.val awkward-array}.",
      i = "Awkward arrays are not yet supported."
    ),
    class = "anndata_awkward_array_error",
    path = path,
    call = call
  )
}

#' @rdname io-registry
read_elem <- function(store, path) {
  elem <- node_open(store, path)
  on.exit(node_close(elem), add = TRUE)
  read_elem_object(elem, store)
}

read_elem_object <- function(elem, store, call = rlang::caller_env()) {
  path <- node_path(elem)
  type <- read_elem_attr(elem, "encoding-type")
  version <- read_elem_attr(elem, "encoding-version")

  if (type == "" && version == "") {
    if (identical(path, "/")) {
      # An unencoded root is an AnnData without a warning, as in `read_h5ad()`,
      # but without `obs` there is nothing to read
      if (!"obs" %in% group_members(elem)) {
        abort_legacy(path, "an unencoded Element", call = call)
      }
      return(read_anndata_elem(elem, path, store))
    }
    return(read_unencoded_elem(elem, path, store, call))
  }
  if (type == "dataframe" && version == "0.1.0") {
    abort_legacy(path, "a dataframe of version 0.1.0", call = call)
  }
  if (type == "awkward-array") {
    abort_awkward(path, call = call)
  }

  fn <- io_registry$read[[spec_key(type, version)]]
  if (is.null(fn)) {
    abort_io_registry(
      c(
        "No read method registered for {.path {path}} with encoding type
         {.val {type}} version {.val {version}}.",
        i = "You may need to update your installation of anndata.claude."
      ),
      path = path,
      encoding_type = type,
      encoding_version = version,
      call = call
    )
  }
  fn(elem, path, store)
}

lookup_writer <- function(value) {
  # A dtype record adds an S3 class that hides the class the writer is under
  for (class in methods::is(drop_dtype(value))) {
    writer <- io_registry$write[[class]]
    if (!is.null(writer)) {
      return(writer)
    }
  }
  NULL
}

find_writer <- function(value, path, call) {
  writer <- lookup_writer(value)
  if (!is.null(writer)) {
    return(writer)
  }
  r_class <- class(value)
  abort_io_registry(
    "No method registered for writing {.cls {r_class}} to {.path {path}}.",
    path = path,
    r_class = r_class,
    call = call
  )
}

#' @rdname io-registry
write_elem <- function(
  store,
  key,
  value,
  dataset_kwargs = list(),
  call = rlang::caller_env()
) {
  if (is_store_file(store)) {
    store <- group_root(store)
    on.exit(node_close(store), add = TRUE)
  }
  store_name <- node_path(store)

  if (identical(key, "/")) {
    if (!identical(store_name, "/")) {
      anndata_abort(
        "{.val /} is not in the subpath of {.path {store_name}}.",
        "anndata_invalid_key_error"
      )
    }
    for (name in group_members(store)) {
      member_delete(store, name)
    }
  } else {
    # Stores may have a prefix like /uns, written to with keys like /uns/foo
    if (startsWith(key, "/")) {
      prefix <- if (identical(store_name, "/")) "/" else paste0(store_name, "/")
      if (!startsWith(key, prefix)) {
        anndata_abort(
          "{.path {key}} is not in the subpath of {.path {store_name}}.",
          "anndata_invalid_key_error"
        )
      }
      key <- substring(key, nchar(prefix) + 1L)
    }
    if (grepl("/", key, fixed = TRUE)) {
      # Python always refuses them in a zarr group, whatever the setting
      if (
        inherits(store, "zarr_node") ||
          anndata_settings$disallow_forward_slash_in_h5ad
      ) {
        anndata_abort(
          "Forward slashes are not allowed in keys, found {.val {key}} in
           {.path {store_name}}.",
          "anndata_forward_slash_key_error",
          key = key
        )
      }
      warn_future(
        "Forward slashes will be written differently in a future anndata
         version."
      )
    }
    if (member_exists(store, key)) {
      member_delete(store, key)
    }
  }

  path <- if (identical(key, "/")) store_name else elem_path(store, key)
  writer <- find_writer(value, path, call)
  writer$fn(store, key, value, dataset_kwargs, path)

  elem <- node_open(store, if (identical(key, "/")) "." else key)
  on.exit(node_close(elem), add = TRUE)
  if (!attr_exists(elem, "encoding-type")) {
    set_elem_attr(elem, "encoding-type", writer$type)
  }
  if (!attr_exists(elem, "encoding-version")) {
    set_elem_attr(elem, "encoding-version", writer$version)
  }
  invisible(NULL)
}
