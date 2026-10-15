#' Base R generics for AnnData
#'
#' `dim()` is `c(n_obs, n_vars)`, `dimnames()` is `list(obs_names, var_names)`
#' and `length()` is `n_obs`, like Python's `len()`.
#' `nrow()` and `ncol()` follow from `dim()`.
#' Comparison operators (`==`, `!=`, `<` and so on) are not supported and raise
#' an `anndata_not_implemented_error`, as Python's `__eq__` raises
#' `NotImplementedError`, so compare the desired attributes instead.
#'
#' @param x An [AnnData()] object.
#' @param e1,e2 Operands of a comparison.
#'
#' @return `dim()` an integer vector of length 2, `dimnames()` a list of two
#'   character vectors and `length()` a single integer.
#' @name anndata-generics
#' @examples
#' adata <- AnnData(matrix(as.numeric(1:6), nrow = 3))
#' dim(adata)
#' dimnames(adata)
#' length(adata)
NULL

#' @rdname anndata-generics
#' @export
dim.AnnData <- function(x) {
  as.integer(x$shape)
}

#' @rdname anndata-generics
#' @export
dimnames.AnnData <- function(x) {
  list(x$obs_names, x$var_names)
}

#' @rdname anndata-generics
#' @export
length.AnnData <- function(x) {
  as.integer(x$n_obs)
}

#' @rdname anndata-generics
#' @export
Ops.AnnData <- function(e1, e2) {
  op <- get(".Generic", envir = environment())
  if (!op %in% c("==", "!=", "<", ">", "<=", ">=")) {
    return(NextMethod())
  }
  anndata_abort(
    "Equality comparisons are not supported for {.cls AnnData} objects,
     instead compare the desired attributes.",
    "anndata_not_implemented_error",
    call = rlang::caller_env()
  )
}
