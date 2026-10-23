#' Dicts
#'
#' Reads and writes the Element `dict`, version 0.1.0.
#' A `dict` is a group whose members are Elements, and its R value is a named
#' list.
#'
#' Nested lists, empty lists and `NULL` values (written as the `null` Element)
#' are supported.
#' A list that is not fully named, or that has duplicated names, cannot be
#' written and raises `anndata_io_registry_error`, as does any list with a
#' class.
#' An empty list is written as an empty `dict`, and an empty `dict` is read as
#' a named list of length 0.
#' Members are read in the order the file lists them, which is alphabetical for
#' files written by h5py.
#'
#' @param store An open rhdf5 file or group handle.
#' @param key Name of the Element within `store`.
#' @param value A named list.
#' @param dataset_kwargs A list of dataset creation options.
#' @param path Path of the Element.
#'
#' @name io-mapping
#' @keywords internal
NULL

#' @rdname io-mapping
write_mapping <- function(store, key, value, dataset_kwargs, path) {
  call <- rlang::caller_env()
  r_class <- class(value)
  # nocov start: defensive, only an S4 or setOldClass list subclass reaches here
  if (is.object(value)) {
    abort_io_registry(
      "No method registered for writing {.cls {r_class}} to {.path {path}}.",
      path = path,
      r_class = r_class,
      call = call
    )
  }
  # nocov end
  keys <- names(value)
  if (length(value) > 0L) {
    invalid <- is.null(keys) || anyNA(keys) || any(keys == "")
    if (invalid) {
      abort_unwritable(path, "all the members of a list must be named", call)
    }
    if (anyDuplicated(keys) > 0L) {
      abort_unwritable(path, "the names of a list must be unique", call)
    }
  }

  group <- if (identical(key, "/")) {
    group_root(store)
  } else {
    group_create(store, key)
  }
  on.exit(node_close(group), add = TRUE)
  set_elem_attr(group, "encoding-type", "dict")
  set_elem_attr(group, "encoding-version", "0.1.0")
  for (i in seq_along(value)) {
    # `value[[i]]` so that a `NULL` member is written as a `null` Element
    write_elem(group, keys[[i]], value[[i]], dataset_kwargs, call = call)
  }
  invisible(NULL)
}

read_mapping_elem <- function(elem, path, store) {
  keys <- group_members(elem)
  prefix <- if (identical(path, "/")) "/" else paste0(path, "/")
  result <- vector("list", length(keys))
  for (i in seq_along(keys)) {
    # Assigning a list keeps `NULL` members, which `[[<-` would drop
    result[i] <- list(read_elem(store, paste0(prefix, keys[[i]])))
  }
  names(result) <- keys
  result
}

register_writer("list", "dict", "0.1.0", write_mapping)
register_reader("dict", "0.1.0", read_mapping_elem)
