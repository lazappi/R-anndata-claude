#!/usr/bin/env Rscript
# Times R and Python anndata on a real h5ad file and checks that the files R
# writes are Structurally equivalent to Python's. Run by hand (not a test) from
# the repository root, one file per command:
#
#   Rscript scripts/benchmark-real-files.R run pbmc3k 3
#   Rscript scripts/benchmark-real-files.R run cellxgene-vascular 1
#   Rscript scripts/benchmark-real-files.R report
#
# `run <name> <repeats>` reads `.ralph/oracle/dl/<name>.h5ad`, rewrites it with
# Python first (the downloads are legacy format), times both packages on the
# rewritten file (best of `repeats`) and stores the result in
# `.ralph/oracle/bench/<name>.json`. `report` writes
# `.scratch/hardening/benchmarks.md` from those results.

args <- commandArgs(trailingOnly = TRUE)
dl_dir <- ".ralph/oracle/dl"
bench_dir <- ".ralph/oracle/bench"
py_project <- "tests/python"
n_rows <- 100L

uv <- function(script, ...) {
  out <- suppressWarnings(system2(
    "uv",
    c(
      "run",
      "--project",
      py_project,
      "python",
      "-I",
      file.path(py_project, script),
      as.character(c(...))
    ),
    stdout = TRUE
  ))
  status <- attr(out, "status")
  if (!is.null(status) && status != 0L) {
    stop("Python script ", script, " failed with status ", status)
  }
  out
}

best_of <- function(fn, repeats, cleanup = function() NULL) {
  times <- vapply(
    seq_len(repeats),
    function(i) {
      cleanup()
      gc(verbose = FALSE)
      start <- proc.time()[["elapsed"]]
      fn()
      proc.time()[["elapsed"]] - start
    },
    numeric(1)
  )
  min(times)
}

r_timings <- function(src, out_dir, repeats) {
  out_h5ad <- file.path(out_dir, "r.h5ad")
  out_zarr <- file.path(out_dir, "r.zarr")
  result <- list()
  run <- function(name, fn, cleanup = function() NULL) {
    result[[name]] <<- tryCatch(
      list(seconds = best_of(fn, repeats, cleanup)),
      error = function(e) list(error = conditionMessage(e))
    )
  }

  adata <- read_h5ad(src)
  run("read_h5ad", function() read_h5ad(src))
  run(
    "write_h5ad",
    function() write_h5ad(adata, out_h5ad),
    function() unlink(out_h5ad)
  )
  run(
    "write_zarr",
    function() write_zarr(adata, out_zarr),
    function() unlink(out_zarr, recursive = TRUE)
  )
  # Free the object first, holding it made read_zarr() of the 4 GB store hit
  # the vector memory limit
  rm(adata)
  invisible(gc())
  run("read_zarr", function() read_zarr(out_zarr))
  run("backed_slice", function() {
    backed <- read_h5ad(src, backed = "r")
    on.exit(backed$file$close())
    backed$X[seq_len(n_rows), ]
  })
  run("lazy_subset", function() {
    lazy <- read_lazy(src)
    on.exit(try(lazy$file$close(), silent = TRUE))
    lazy[seq_len(n_rows), ]$to_memory()
  })
  result
}

run_file <- function(name, repeats) {
  src <- file.path(dl_dir, paste0(name, ".h5ad"))
  if (!file.exists(src)) {
    stop("Missing ", src, ", downloads are not allowed so stop here")
  }
  out_dir <- file.path(bench_dir, name)
  unlink(out_dir, recursive = TRUE)
  dir.create(file.path(out_dir, "py"), recursive = TRUE)
  dir.create(file.path(out_dir, "r"))

  current <- file.path(out_dir, "current.h5ad")
  message("Rewriting ", src, " with Python")
  uv("rewrite_h5ad.py", src, current)

  message("Timing Python")
  py <- jsonlite::fromJSON(
    paste(
      uv(
        "benchmark_real_files.py",
        "time",
        current,
        file.path(out_dir, "py"),
        repeats
      ),
      collapse = ""
    ),
    simplifyVector = FALSE
  )

  message("Timing R")
  pkgload::load_all(quiet = TRUE)
  r <- r_timings(current, file.path(out_dir, "r"), repeats)

  message("Comparing written files")
  r_files <- file.path(out_dir, "r", c("r.h5ad", "r.zarr"))
  py_files <- file.path(out_dir, "py", c("py.h5ad", "py.zarr"))
  # pbmc3k's raw/X has unsorted indices that R stores sorted (ADR 0006)
  sorted_args <- if (name == "pbmc3k") {
    c("--sorted", "/raw/X/data", "--sorted", "/raw/X/indices")
  }
  diffs <- if (all(file.exists(c(r_files, py_files)))) {
    jsonlite::fromJSON(
      paste(
        uv(
          "benchmark_real_files.py",
          sorted_args,
          "compare",
          r_files[1],
          py_files[1],
          r_files[2],
          py_files[2]
        ),
        collapse = ""
      ),
      simplifyVector = FALSE
    )
  } else {
    list("a file was not written", "a file was not written")
  }
  names(diffs) <- c("h5ad", "zarr")

  info <- list(
    name = name,
    size_mb = round(file.size(current) / 1e6, 1),
    n_obs = NA_integer_,
    repeats = repeats,
    r = r,
    python = py,
    differences = diffs
  )
  info$n_obs <- tryCatch(
    read_h5ad(src, backed = "r")$n_obs,
    error = function(e) NA_integer_
  )
  jsonlite::write_json(
    info,
    file.path(bench_dir, paste0(name, ".json")),
    auto_unbox = TRUE,
    pretty = TRUE
  )
  invisible(info)
}

fmt_seconds <- function(x) {
  if (is.null(x$seconds)) "failed" else sprintf("%.2f", x$seconds)
}

report <- function() {
  files <- list.files(bench_dir, "\\.json$", full.names = TRUE)
  if (length(files) == 0L) {
    stop("No results in ", bench_dir)
  }
  versions <- jsonlite::fromJSON(paste(uv("versions.py"), collapse = ""))
  lines <- c(
    "# Real-file benchmarks",
    "",
    paste0("Date: ", format(Sys.Date())),
    paste0(
      "Machine: ",
      Sys.info()[["sysname"]],
      " ",
      Sys.info()[["release"]],
      " (",
      Sys.info()[["machine"]],
      ")"
    ),
    paste0(
      "Versions: R ",
      getRversion(),
      ", anndata.claude ",
      read.dcf("DESCRIPTION", "Version")[1L],
      ", rhdf5 ",
      as.character(utils::packageVersion("rhdf5")),
      ", Python anndata ",
      versions$anndata
    ),
    "",
    "Made by `scripts/benchmark-real-files.R`.",
    "Times are the best wall-clock seconds of the repeats, on the file after a Python rewrite (the downloads are legacy format).",
    "`backed_slice` reads the first 100 rows of a backed X, `lazy_subset` is `read_lazy()` then the first 100 observations realised.",
    "Ratio is R time over Python time, and more than 3 is queued under Discovered in `fix_plan.md`.",
    ""
  )
  for (file in files) {
    info <- jsonlite::fromJSON(file, simplifyVector = FALSE)
    lines <- c(
      lines,
      paste0("## ", info$name),
      "",
      paste0(
        info$size_mb,
        " MB rewritten, ",
        info$n_obs,
        " observations, best of ",
        info$repeats
      ),
      "",
      "| Operation | R (s) | Python (s) | Ratio |",
      "|---|---|---|---|"
    )
    for (op in names(info$python)) {
      r <- info$r[[op]]
      py <- info$python[[op]]
      ratio <- if (!is.null(r$seconds) && !is.null(py$seconds)) {
        sprintf("%.1f", r$seconds / py$seconds)
      } else {
        "-"
      }
      lines <- c(
        lines,
        paste0(
          "| `",
          op,
          "` | ",
          fmt_seconds(r),
          " | ",
          fmt_seconds(py),
          " | ",
          ratio,
          " |"
        )
      )
    }
    lines <- c(
      lines,
      "",
      "Structural equivalence of R's file with Python's:",
      ""
    )
    for (format in names(info$differences)) {
      d <- unlist(info$differences[[format]])
      lines <- c(
        lines,
        if (length(d) == 0L) {
          paste0("- ", format, ": equivalent")
        } else {
          c(
            paste0("- ", format, ": ", length(d), " differences"),
            paste0("  - ", utils::head(d, 10L))
          )
        }
      )
    }
    errors <- c(
      Filter(Negate(is.null), lapply(info$r, `[[`, "error")),
      Filter(Negate(is.null), lapply(info$python, `[[`, "error"))
    )
    if (length(errors) > 0L) {
      lines <- c(
        lines,
        "",
        "Errors:",
        "",
        paste0("- ", names(errors), ": ", gsub("\n", " ", unlist(errors)))
      )
    }
    lines <- c(lines, "")
  }
  writeLines(lines, ".scratch/hardening/benchmarks.md")
}

if (identical(args[1L], "run") && length(args) == 3L) {
  run_file(args[2L], as.integer(args[3L]))
} else if (identical(args[1L], "report")) {
  report()
} else {
  stop("usage: benchmark-real-files.R run <name> <repeats> | report")
}
