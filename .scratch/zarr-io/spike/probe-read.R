# Probe how each candidate reads the Python-written fixtures.
# Usage: Rscript probe-read.R <candidate> <fixture dir (out/)>
args <- commandArgs(TRUE)
cand <- args[[1]]
out <- args[[2]]

`%||%` <- function(a, b) if (is.null(a)) b else a

try_read <- function(label, expr) {
  res <- tryCatch(
    {
      v <- force(expr)
      paste0(
        "OK class=",
        paste(class(v), collapse = "/"),
        " typeof=",
        typeof(v),
        " dim=",
        paste(dim(v) %||% length(v), collapse = "x"),
        " head=",
        paste(utils::head(as.vector(v), 6), collapse = ",")
      )
    },
    error = function(e) paste("ERROR", conditionMessage(e)),
    warning = function(w) paste("WARN", conditionMessage(w))
  )
  cat(sprintf("%-28s %s\n", label, res))
}

arrays <- c(
  "int8",
  "int16",
  "int32",
  "int64",
  "uint8",
  "uint16",
  "uint32",
  "uint64",
  "float32",
  "float64",
  "bool",
  "string",
  "scalar_int",
  "scalar_float",
  "scalar_bool",
  "scalar_string"
)
layouts <- c(
  "chunked",
  "c_order",
  "zstd",
  "blosc",
  "gzip",
  "uncompressed",
  "missing",
  "fill_nan",
  "sharded"
)

if (cand == "Rarr") {
  suppressMessages(library(Rarr))
  for (v in c("v2", "v3")) {
    for (a in arrays) {
      p <- file.path(out, v, "types.zarr", a)
      try_read(paste(v, a), read_zarr_array(p))
    }
    for (a in layouts) {
      p <- file.path(out, v, "layout.zarr", a)
      try_read(paste(v, a), read_zarr_array(p))
    }
  }
} else if (cand == "zarr") {
  suppressMessages(library(zarr))
  for (v in c("v2", "v3")) {
    root <- tryCatch(
      open_zarr(file.path(out, v, "types.zarr")),
      error = function(e) e
    )
    if (inherits(root, "error")) {
      cat(v, "open ERROR", conditionMessage(root), "\n")
      next
    }
    for (a in arrays) {
      try_read(paste(v, a), root[[paste0("/", a)]]$read())
    }
    lay <- tryCatch(
      open_zarr(file.path(out, v, "layout.zarr")),
      error = function(e) e
    )
    for (a in layouts) {
      try_read(paste(v, a), lay[[paste0("/", a)]]$read())
    }
  }
} else if (cand == "pizzarr") {
  suppressMessages(library(pizzarr))
  for (v in c("v2", "v3")) {
    for (a in arrays) {
      try_read(paste(v, a), {
        z <- zarr_open(file.path(out, v, "types.zarr", a))
        z$get_item("...")$data
      })
    }
    for (a in layouts) {
      try_read(paste(v, a), {
        z <- zarr_open(file.path(out, v, "layout.zarr", a))
        z$get_item("...")$data
      })
    }
  }
}
