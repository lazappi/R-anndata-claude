#' Make names unique
#'
#' Appends `join` and a counter to repeated names, leaving the first occurrence
#' and any `NA` untouched, and skipping suffixed names that already exist.
#'
#' @param names Character vector of names.
#' @param join String between a name and its counter.
#' @param call Call reported by the collision warning.
#'
#' @return `names` with duplicates renamed.
#' @noRd
make_names_unique <- function(names, join = "-", call = rlang::caller_env()) {
  duplicate <- duplicated(names) & !is.na(names)
  if (!any(duplicate)) {
    return(names)
  }
  # Keys are prefixed because an environment cannot hold an empty name
  key <- function(x) paste0("k", x)
  taken <- new.env(parent = emptyenv())
  for (name in names[!is.na(names)]) {
    taken[[key(name)]] <- TRUE
  }
  counter <- new.env(parent = emptyenv())
  examples <- character()
  for (i in which(duplicate)) {
    name <- names[[i]]
    repeat {
      count <- (if (is.null(counter[[key(name)]])) 0L else counter[[key(name)]])
      count <- count + 1L
      counter[[key(name)]] <- count
      candidate <- paste0(name, join, count)
      if (is.null(taken[[key(candidate)]])) {
        taken[[key(candidate)]] <- TRUE
        names[[i]] <- candidate
        break
      }
      if (length(examples) < 5L) {
        examples <- c(examples, candidate)
      }
    }
  }
  if (length(examples)) {
    anndata_warn(
      "Suffix used ({join}[0-9]+) to deduplicate names may make them difficult
       to interpret.
       There are names with similar suffixes.
       Consider using a different delimiter by passing {.arg join}.
       Example collisions: {.val {examples}}",
      "anndata_names_collision_warning",
      join = join,
      examples = examples,
      call = call
    )
  }
  names
}

check_join <- function(join, call) {
  if (!rlang::is_string(join)) {
    abort_invalid_argument("{.arg join} must be a single string.", call)
  }
}
