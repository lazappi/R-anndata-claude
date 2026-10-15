# rhdf5 capability spike

Findings for `.scratch/h5ad-io/issues/01-rhdf5-spike.md`.
Tested with rhdf5 2.54.1, rhdf5filters 1.22.0 (Rhdf5lib 1.32.0) against h5py files from the reference environment.
Every verdict is backed by a test in `tests/testthat/test-rhdf5-spike.R`, which reads the Python-written `tests/testthat/fixtures/spike_types.h5` and writes a file that `tests/python/spike_describe.py` and `h5_tree.py` read back.

## Summary

| Item | Read | Write | Verdict |
| ---- | ---- | ----- | ------- |
| Variable-length UTF-8 strings (datasets) | pass | workaround | Write needs low-level `H5Tcopy("H5T_C_S1")` with `H5Tset_size(tid, -1L)` and `H5Tset_cset(tid, "UTF8")` |
| Variable-length UTF-8 strings (attributes) | pass | pass | `h5writeAttribute(..., encoding = "UTF-8", variableLengthString = TRUE, asScalar = TRUE)` |
| h5py boolean enum | workaround | workaround | Reads as a two-level factor, write needs an explicit enum type and `h5type = <enum>` |
| Integers int8 to int32, uint16 | pass | pass | uint8 reads as `raw` |
| uint32, int64, uint64 | workaround | workaround | Need `bit64conversion` on read (see int64 recommendation), write as doubles |
| float32, float64 | pass | pass | NaN and Inf are kept |
| complex128 | pass | pass | Written by rhdf5 as h5py's compound `r`/`i` |
| complex64 | gap | n/a | Reads garbage, detectable by type size 8, so raise a classed error. R has no single-precision complex, so always write complex128 |
| Structured datasets (`rec-array`) | partial | gap | See below, needs a human decision |
| 0-dimensional datasets | pass | workaround | Write needs `H5Screate("H5S_SCALAR")` |
| Array-valued attributes | pass | pass | Typed attributes need `H5Acreate` and `H5Awrite` |
| gzip | pass | pass | |
| lzf | pass | workaround | `H5Pset_lzf(plist, h5tid = <type id>)` needs a type id, not a constant name |

**Blocking finding:** `rec-array` cannot be written or fully read with rhdf5 alone, see "rec-array (gap)".
Every other gap has a workaround.

## Row-major shape and `dim()`

- HDF5 is row-major and R is column-major, and rhdf5 by default keeps the memory layout and reverses the dims, so an on-disk `(2, 3)` dataset reads as an R `3 x 2` array
- `h5read(file, name, native = TRUE)` returns an array whose `dim()` equals the on-disk shape and whose `[i, j]` is the on-disk `[i, j]`, with no further transposition. **Read with `native = TRUE`.**
- Low-level writes (`H5Dwrite`) do not transpose even with a native dataspace, so write with the reversed dims (`H5Screate_simple(rev(dim(x)))`) and the row-major buffer `aperm(x)` (`t(x)` for a matrix).
  This gives Python the shape `dim(x)` with the values `x[i, j]` at `[i, j]`.
- 1-d datasets read with a length-1 `dim` attribute (`[1:4(1d)]`), which `dim(x) <- NULL` removes
- `h5write(..., native = TRUE)` also writes correctly but is unusable for Elements, see "Extra attributes" below

## Extra attributes and default compression

The high-level `h5write()`, `h5createDataset()` and `h5writeDataset()` add things Python does not write:

- a `rhdf5-NA.OK` attribute on every dataset
- a `storage.mode = "logical"` attribute on logical datasets
- gzip level 6 compression and chunking by default (the `level` argument controls it)
- fixed-length ASCII strings (`size = nchar + 1`) for character data

The Element writers must therefore use the low-level API (`H5Dcreate`, `H5Dwrite`, `H5Acreate`, `H5Awrite`) or `h5writeAttribute()` for attributes.
This is what the tests do, and the resulting file is structurally equivalent to the h5py one for every non-gap item.

## Strings

- Variable-length UTF-8 datasets read correctly as `character`, in 1-d, 2-d and 0-d
- The high-level `h5createDataset(storage.mode = "character")` has no variable-length option, so use the low-level type shown in the summary
- Attribute strings are written as variable-length UTF-8 scalars when `variableLengthString = TRUE` and `asScalar = TRUE` is set, as h5py does for `encoding-type` and friends
- Without `variableLengthString` attributes are fixed-length ASCII, which Python reads but is not what it writes

## Booleans

- h5py writes an `int8` enum with members `FALSE = 0` and `TRUE = 1`
- rhdf5 reads it as a two-level `factor` with levels `"FALSE"` and `"TRUE"`, and keeps the shape.
  `as.logical(as.character(x))` converts it (restore `dim` for 2-d)
- Writing needs the enum type (`H5Tenum_create("H5T_STD_I8LE")` plus `H5Tenum_insert()` for `FALSE` and `TRUE`) and `H5Dwrite(did, <integer 0/1>, h5type = <the enum type>)`.
  Without `h5type` the write fails.
- An `h5writeAttribute()` of a logical gives h5py a boolean attribute (checked with `asScalar = TRUE`)
- The buffer must be `raw` (one byte per value) to match the int8 enum memory type, an integer buffer silently writes wrong values
- There is no way to write `NA`, which Python does not have either (`nullable-boolean` covers it)

## Integers and floats

- On-disk dtype (sign and width) of datasets is only visible through `h5ls(file, all = TRUE)$dtype` (for example `H5T_STD_U16LE`).
  The R binding has no `H5Tget_sign`.
  Reading the dtype of an attribute is not possible, but anndata's attributes have fixed types.
- Default reads: int8, int16, int32 and uint16 give `integer`, uint8 gives `raw`, uint32, int64 and uint64 overflow to `NA` with a warning
- `-2^31` in an int32 dataset reads as `NA_integer_` (the same bit pattern) with the message "converted to NA".
  This is unavoidable and should be documented as a deviation.
- Writing: a double buffer converts exactly to any integer width HDF5 knows, including `H5T_STD_I64LE` and `H5T_STD_U64LE`, up to 2^53.
  `raw` is the buffer for `H5T_STD_U8LE`.
- float32 widens exactly to double on read and narrows on write, NaN and Inf are kept

## int64 recommendation

- Read with `bit64conversion = "bit64"`, which is exact for every `int64`, then convert to `double` when every value has magnitude strictly below 2^53 (`as.double()` warns at exactly 2^53)
- Otherwise keep the `integer64` vector (requires `bit64` in Imports at that point), or raise a classed error if a later ticket prefers that.
  The h5ad-io spec allows either.
- `h5read(native = TRUE, bit64conversion = "bit64")` errors (`INTEGER() can only be applied to a 'integer'`), so read n-d `integer64` without `native` and `aperm()` the result
- `bit64conversion = "double"` is lossy above 2^53 and warns, so it must not be the first read
- `uint64` above 2^63 is unrepresentable (`integer64` reads it as `NA` with a warning), so a classed error that names the path is the only exact option.
  `uint32` is exact as `double`, so read it with `bit64conversion = "double"`.
- **Writing** an `integer64` is broken: `H5Dwrite` reinterprets the `integer64` bits as a double and writes the wrong values (the test shows `[0, -2]`).
  Convert to double first, which is exact up to 2^53, and raise a classed error above that.
  Python files with indices or values above 2^53 are not realistic, so this is acceptable.

## Complex numbers

- complex128 (two float64 members `r` and `i`) reads and writes correctly, and the written file is structurally equivalent to h5py's
- complex64 (two float32 members) reads garbage because rhdf5 reads the members as float64.
  The type size is 8 rather than 16 (`H5Tget_size()`), so it is detectable.
  R has no single-precision complex, so the recommendation is a classed error naming the path when the compound size is 8, and always writing complex128.

## rec-array (gap)

Reading:

- A compound dataset reads as a `data.frame` with the correct field names, order and values, for both fixed-length (`S3`) and variable-length string members
- Member dtypes cannot be recovered: rhdf5 exposes no `H5Tget_member_type`, `H5Tget_member_name` or `H5Tget_sign`, so an `i2`, `u4` or `i8` member reads as `integer` (or `integer64` with `bit64conversion`) and whether a string member was fixed or variable length is lost.
  The per-field On-disk dtype required by the spec cannot be recorded.

Writing:

- `h5writeDataset(<data.frame>, ...)` writes a compound with only `int32`, `float64` and fixed-length ASCII string members, with no way to choose a width, a variable-length string or UTF-8.
  The tests show Python reads the values correctly (`yé` in a 3-byte fixed string) and anndata's `read_recarray` accepts fixed strings, but the file is not structurally equivalent to what h5py writes (`string(variable, utf-8)` for `U`/`O` fields, per `methods.py:715-720`).
- There is no `H5Tinsert`, so a compound type cannot be built with the exported API
- Passing `level = 0L, chunk = <nrow>` avoids the default compression, and `h5writeDataset()` on an open file handle avoids the `rhdf5-NA.OK` attribute

No workaround exists inside rhdf5 for field dtype preservation or variable-length string members.
**Options for the human:**

1. **Recommended: a small compiled helper** (`src/`, `LinkingTo: Rhdf5lib`) that reads a compound type's members and creates a compound dataset from a field specification.
   Rhdf5lib ships the HDF5 headers, so this adds no new system dependency, but it adds C code and a build step to the package.
2. Add `hdf5r` for `rec-array` only.
   It has the whole API but needs a system libhdf5 and is not installed here, and the project principle is to keep the dependency set small.
3. Accept the degradation: write `rec-array` through `h5writeDataset()` (int32, float64, fixed-length strings), document it as a deviation and relax the spec's field dtype and structural equivalence requirement for `rec-array`.
   Python round trips values but not dtypes, which conflicts with "On disk is non-negotiable".

The rec-array and on-disk dtype records for rec-array fields (h5ad-io/08) depend on this decision.
Nothing else is blocked.

**Decision (human, 2026-10-15):** option 3, accept the degradation.
See ADR 0005, the "rec-array" section of the spec and follow-up ticket 15 for the later fidelity work.

## Scalars

- A 0-dimensional dataset reads as a length-1 vector with no `dim`
- `h5ls(file, all = TRUE)$stype` is `"SCALAR"` for 0-d and `"SIMPLE"` otherwise, so a scalar is distinguishable from a 1-element array
- Write with `H5Screate("H5S_SCALAR")`, which h5py reads with shape `()`.
  The high-level `h5createDataset(dims = NULL)` also works but adds extra attributes.

## Attributes

- Read with `h5readAttributes(file, name, native = TRUE)`
- Strings, ints, floats, bool and int32 arrays read as expected, scalar attributes as length-1 vectors
- 1-element arrays and scalars are indistinguishable once read, so the writer must track which Python wrote.
  Write with `asScalar = TRUE` or `H5Screate("H5S_SCALAR")` for scalars.
- A typed attribute (for example `shape` as `int64`) needs `H5Acreate(obj, name, "H5T_STD_I64LE", space)` and `H5Awrite()`, because `h5writeAttribute()` writes `int32`

## Compression

- Reading gzip and lzf is transparent, and lzf is available through `rhdf5filters` (`available_filters()` includes `"lzf"`)
- Write gzip with `H5Pset_chunk(plist, rev(chunk))` and `H5Pset_deflate(plist, level)`, and lzf with `H5Pset_lzf(plist, h5tid = H5Tcopy("H5T_IEEE_F64LE"))`.
  The type argument is used for its size, and a constant name fails with "Inappropriate type".
- Chunk dims are given in R order and so are reversed relative to the on-disk shape.
- h5py reads the result with `compression == "gzip"`, `compression_opts == 4` and `compression == "lzf"`
- rhdf5 does not add the shuffle filter on the low-level path, matching h5py when `shuffle` is not requested

## Dependencies

- `rhdf5` stays in Imports
- `rhdf5filters` is a dependency of rhdf5 and rhdf5 loads it, so it needs no direct use and goes in Suggests (the test checks lzf is available)
- `bit64` goes in Suggests until the Element reader needs `integer64`, then moves to Imports

## Other gaps found

- rhdf5 has no `H5Tclose`, so type handles are released by `h5closeAll()` or garbage collection
- `h5read()` prints the "converted to NA" notice and warns on overflow for 32/64-bit unsigned and 64-bit signed reads, so the reader must use `bit64conversion` and never rely on defaults
- Many `H5T` helpers (`H5Tget_sign`, `H5Tget_member_*`, `H5Tinsert`, `H5Tequal`) are missing, which limits type introspection to `h5ls(all = TRUE)`, `H5Tget_class`, `H5Tget_size` and `H5Tis_variable_str`
