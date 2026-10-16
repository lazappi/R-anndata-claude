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
