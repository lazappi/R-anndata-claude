# Restores the element registry on exit so tests can register encodings freely
local_io_registry <- function(env = parent.frame()) {
  old <- as.list(io_registry)
  withr::defer(
    {
      io_registry$read <- old$read
      io_registry$write <- old$write
    },
    envir = env
  )
}

# A fresh, open, empty h5 file that is closed when the test ends
local_h5_store <- function(env = parent.frame()) {
  path <- withr::local_tempfile(fileext = ".h5", .local_envir = env)
  rhdf5::h5createFile(path)
  fid <- rhdf5::H5Fopen(path)
  withr::defer(rhdf5::h5closeAll(), envir = env)
  fid
}

read_fixture_elem <- function(name, env = parent.frame()) {
  store <- rhdf5::H5Fopen(
    fixture_path(file.path("h5ad", paste0(name, ".h5"))),
    flags = "H5F_ACC_RDONLY"
  )
  withr::defer(rhdf5::h5closeAll(), envir = env)
  read_elem(store, "x")
}

# Writes `value` as an Element at `x` of a new file and returns the path
write_fixture_like <- function(value, env = parent.frame()) {
  path <- withr::local_tempfile(fileext = ".h5", .local_envir = env)
  rhdf5::h5createFile(path)
  store <- rhdf5::H5Fopen(path)
  write_elem(store, "x", value)
  rhdf5::h5closeAll()
  path
}

read_written <- function(path) {
  store <- rhdf5::H5Fopen(path, flags = "H5F_ACC_RDONLY")
  on.exit(rhdf5::h5closeAll())
  read_elem(store, "x")
}

read_adata_fixture <- function(name) {
  read_h5ad(fixture_path(file.path("h5ad", paste0(name, ".h5ad"))))
}

# The contents of an AnnData as plain R values, to compare two objects (frames
# become lists because DataFrame metadata differs by how they were built)
adata_parts <- function(adata) {
  plain_frame <- function(df) {
    list(
      names = rownames(df),
      index_name = frame_index_name(df),
      columns = as.list(df)
    )
  }
  # An empty list is unnamed when built and named when read from a dict
  named <- function(x) {
    if (length(x)) x else stats::setNames(list(), character())
  }
  mapping <- function(m) {
    named(lapply(as.list(m), function(v) {
      if (is.data.frame(v) || methods::is(v, "DataFrame")) plain_frame(v) else v
    }))
  }
  raw <- adata$raw
  list(
    shape = adata$shape,
    X = adata$X,
    obs = plain_frame(adata$obs),
    var = plain_frame(adata$var),
    obsm = mapping(adata$obsm),
    varm = mapping(adata$varm),
    obsp = mapping(adata$obsp),
    varp = mapping(adata$varp),
    layers = mapping(adata$layers),
    uns = named(adata$uns),
    raw = if (is.null(raw)) {
      NULL
    } else {
      list(X = raw$X, var = plain_frame(raw$var), varm = mapping(raw$varm))
    }
  )
}

# A trivial encoding `test-elem` 0.1.0, a group holding the attribute `n`, used
# to test dispatch without any real encoding
register_test_encoding <- function() {
  register_writer(
    "test_elem",
    "test-elem",
    "0.1.0",
    function(store, key, value, dataset_kwargs, path) {
      group <- if (identical(key, "/")) {
        rhdf5::H5Gopen(store, "/")
      } else {
        rhdf5::H5Gcreate(store, key)
      }
      rhdf5::h5writeAttribute(value$n, group, "n", asScalar = TRUE)
    }
  )
  register_reader("test-elem", "0.1.0", function(elem, path, store) {
    attr <- rhdf5::H5Aopen(elem, "n")
    structure(list(n = rhdf5::H5Aread(attr)), class = "test_elem")
  })
}

test_elem <- function(n) structure(list(n = n), class = "test_elem")

# Creates a group with the given encoding attributes (use NULL to omit one)
make_encoded_group <- function(store, key, type = NULL, version = NULL) {
  group <- rhdf5::H5Gcreate(store, key)
  if (!is.null(type)) {
    set_elem_attr(group, "encoding-type", type)
  }
  if (!is.null(version)) {
    set_elem_attr(group, "encoding-version", version)
  }
  group
}

# The h5ad fixture of a case read with the HDF5 backend, `NULL` when the case
# has no h5ad fixture (both were written by Python from one case)
h5_case_elem <- function(case, env = parent.frame()) {
  file <- fixture_path(file.path("h5ad", paste0(case, ".h5")))
  if (!file.exists(file)) {
    return(NULL)
  }
  store <- rhdf5::H5Fopen(file, flags = "H5F_ACC_RDONLY")
  withr::defer(rhdf5::h5closeAll(), envir = env)
  read_elem(store, "x")
}

# The whole-AnnData fixture cases, shared by the h5ad and zarr tests
adata_fixture_names <- c(
  "anndata_full",
  "anndata_no_raw",
  "anndata_empty_slots",
  "anndata_sparse_x",
  "anndata_no_x",
  "anndata_0_obs",
  "anndata_0_vars",
  "anndata_raw_own_var",
  "anndata_raw_0_obs",
  "anndata_raw_0_vars",
  "realistic",
  "realistic_csc",
  "realistic_gzip",
  "realistic_lzf"
)

adata_fixture_files <- function() {
  fixture_path(file.path("h5ad", paste0(adata_fixture_names, ".h5ad")))
}

# AnnData objects built in R that cover the Slots, with alphabetical keys
# because h5py lists the members of a dict that way
r_built_adatas <- function() {
  obs <- data.frame(
    group = factor(c("a", "b", "a", "b")),
    n = c(1, 2, 3, 4),
    row.names = paste0("cell", 0:3)
  )
  var <- data.frame(
    score = c(0.5, 1.5, 2.5),
    row.names = paste0("gene", 0:2)
  )
  x <- matrix(as.numeric(1:12), 4)
  sparse <- methods::as(
    Matrix::sparseMatrix(
      i = c(1, 3, 4),
      j = c(1, 2, 3),
      x = c(1, 2, 3),
      dims = c(4, 3)
    ),
    "CsparseMatrix"
  )
  full <- AnnData(
    X = x,
    obs = obs,
    var = var,
    obsm = list(pca = matrix(as.numeric(1:8), 4)),
    varm = list(load = matrix(as.numeric(1:6), 3)),
    obsp = list(conn = matrix(as.numeric(1:16), 4)),
    varp = list(corr = matrix(as.numeric(1:9), 3)),
    layers = list(counts = sparse),
    uns = list(note = "text", sub = list(k = c(1, 2, 3)))
  )
  with_raw <- full$copy()
  with_raw$raw <- full
  # Raw has a variable and a varm key that the object lacks
  own_var <- AnnData(matrix(as.numeric(1:8), 4), obs = obs)
  own_var$raw <- full
  raw_zero_obs <- AnnData(matrix(0, 0, 3))
  raw_zero_obs$raw <- raw_zero_obs
  raw_zero_vars <- AnnData(matrix(0, 2, 0))
  raw_zero_vars$raw <- raw_zero_vars
  list(
    full = full,
    with_raw = with_raw,
    raw_own_var = own_var,
    raw_zero_obs = raw_zero_obs,
    raw_zero_vars = raw_zero_vars,
    sparse_x = AnnData(sparse),
    no_x = AnnData(shape = c(2L, 3L)),
    empty_slots = AnnData(matrix(0, 2, 3)),
    zero_obs = AnnData(matrix(0, 0, 3)),
    zero_vars = AnnData(matrix(0, 2, 0))
  )
}
