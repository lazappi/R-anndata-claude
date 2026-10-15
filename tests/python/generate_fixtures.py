"""Write the committed test fixtures and a manifest describing them.

Usage: generate_fixtures.py <outdir>

Cases are registered with the `case` decorator. Each case function takes the
output path and writes one file. Output must be deterministic (fixed seeds, no
timestamps in the content that tests compare). The manifest lists each case,
its file and the reference versions used.
"""

import json
import sys
from importlib.metadata import version
from pathlib import Path

import anndata
import h5py
import numpy as np

CASES = {}


def case(filename):
    """Register a function that writes the fixture `filename` under its name."""

    def register(fn):
        CASES[fn.__name__] = {"file": filename, "write": fn}
        return fn

    return register


@case("trivial.h5ad")
def trivial(path):
    """A tiny dense float32 matrix with default names."""
    anndata.AnnData(np.arange(6, dtype=np.float32).reshape(2, 3)).write_h5ad(path)


@case("spike_types.h5")
def spike_types(path):
    """Low-level HDF5 types the h5ad-io spike checks rhdf5 against."""
    import h5py

    str_dt = h5py.string_dtype()
    with h5py.File(path, "w") as f:
        f.create_dataset(
            "vlen_utf8",
            data=np.array(["a", "bé", "", "日本"], dtype=object),
            dtype=str_dt,
        )
        f.create_dataset(
            "vlen_utf8_2d",
            data=np.array([["a", "b", "c"], ["d", "e", "f"]], dtype=object),
            dtype=str_dt,
        )
        f.create_dataset("bool", data=np.array([True, False, True]))
        f.create_dataset(
            "bool_2d", data=np.array([[True, False, True], [False, False, True]])
        )
        for name in (
            "int8",
            "int16",
            "int32",
            "int64",
            "uint8",
            "uint16",
            "uint32",
            "uint64",
        ):
            info = np.iinfo(name)
            # 64-bit extremes are not representable as doubles, so the exact
            # R-readable boundary (2^53) is used and the hazards are separate
            lo, hi = max(info.min, -(2**53)), min(info.max, 2**53)
            f.create_dataset(name, data=np.array([lo, 0, 1, hi], dtype=name))
        f.create_dataset(
            "int64_big", data=np.array([2**53 + 1, -(2**62)], dtype="int64")
        )
        f.create_dataset(
            "uint64_big", data=np.array([2**63 + 5, 2**64 - 1], dtype="uint64")
        )
        special = [1.5, -2.25, np.nan, np.inf]
        f.create_dataset("float32", data=np.array(special, dtype="float32"))
        f.create_dataset("float64", data=np.array(special, dtype="float64"))
        z = [1 + 2j, -3.5 + 0.25j]
        f.create_dataset("complex64", data=np.array(z, dtype="complex64"))
        f.create_dataset("complex128", data=np.array(z, dtype="complex128"))
        f.create_dataset("matrix_2x3", data=np.arange(6, dtype="int32").reshape(2, 3))
        f.create_dataset(
            "array_2x3x4", data=np.arange(24, dtype="float64").reshape(2, 3, 4)
        )
        f.create_dataset("scalar_int", data=np.int32(7))
        f.create_dataset("scalar_float", data=np.float64(2.5))
        f.create_dataset("scalar_str", data="héllo", dtype=str_dt)
        f.create_dataset("scalar_bool", data=np.bool_(True))
        rec = np.array(
            [(1, 1.5, b"ab", "x"), (2, 2.5, b"c", "yé")],
            dtype=[("i", "<i4"), ("f", "<f8"), ("fixed", "S3"), ("v", str_dt)],
        )
        f.create_dataset("rec", data=rec)
        widths = np.array(
            [(1, -2, 3, 4, 0.5, True), (255, 7, 4000000000, -9, 1.5, False)],
            dtype=[
                ("u1", "u1"),
                ("i2", "<i2"),
                ("u4", "<u4"),
                ("i8", "<i8"),
                ("f4", "<f4"),
                ("b", "?"),
            ],
        )
        f.create_dataset("rec_widths", data=widths)
        big = np.arange(1000, dtype="float64").reshape(10, 100)
        f.create_dataset(
            "gzip", data=big, compression="gzip", compression_opts=4, chunks=(5, 50)
        )
        f.create_dataset("lzf", data=big, compression="lzf", chunks=(5, 50))
        g = f.create_group("attrs")
        g.attrs["str"] = "héllo"
        g.attrs["str_array"] = np.array(["a", "b", "c"], dtype=object)
        g.attrs["int"] = np.int64(5)
        g.attrs["float"] = np.float64(0.5)
        g.attrs["int_array"] = np.array([1, 2, 3], dtype="int32")
        g.attrs["bool"] = np.bool_(True)
        g.attrs["shape"] = np.array([2, 3], dtype="int64")


# Encoding table cases (.scratch/h5ad-io/encoding-table.md)
#
# Each case is the Python value equivalent to an R value class. Element cases
# are written with `write_elem` to the key "x" of an HDF5 file, so the root of
# the file only holds that Element. `settings` overrides anndata settings.

ENCODING_DIR = "h5ad"
INT_NAMES = ("int8", "int16", "int32", "int64", "uint8", "uint16", "uint32", "uint64")
FLOAT_NAMES = ("float32", "float64")
SPECIAL = [1.5, -2.25, np.nan, np.inf]


def _df(**columns):
    import pandas as pd

    n = len(next(iter(columns.values())))
    return pd.DataFrame(columns, index=pd.Index([f"r{i}" for i in range(n)]))


def _csr(dtype, fmt="csr", indices=None):
    import scipy.sparse as sp

    dense = np.array([[0, 1, 0, 2], [3, 0, 0, 0], [0, 0, 4, 5]])
    mat = sp.csr_matrix(dense.astype(dtype)) if fmt == "csr" else sp.csc_matrix(
        dense.astype(dtype)
    )
    if indices is not None:
        mat.indices = mat.indices.astype(indices)
        mat.indptr = mat.indptr.astype(indices)
    return mat


def _categorical(n_categories, ordered=False, numeric=False, missing=False):
    import pandas as pd

    cats = list(range(n_categories)) if numeric else [f"c{i}" for i in range(n_categories)]
    values = [cats[0], None if missing else cats[1], cats[-1]]
    return pd.Categorical(values, categories=cats, ordered=ordered)


def _rec_arrays():
    str_dt = np.dtype("O")
    basic = np.array(
        [(1, 1.5, b"ab", "x"), (2, 2.5, b"c", "yé")],
        dtype=[("i", "<i4"), ("f", "<f8"), ("fixed", "S3"), ("uni", "U3")],
    )
    widths = np.array(
        [(1, -2, 3, 4, 0.5, True), (255, 7, 4000000000, -9, 1.5, False)],
        dtype=[
            ("u1", "u1"),
            ("i2", "<i2"),
            ("u4", "<u4"),
            ("i8", "<i8"),
            ("f4", "<f4"),
            ("b", "?"),
        ],
    )
    # Shaped like scanpy's `rank_genes_groups` names, `U` fields named by group
    rank = np.rec.fromarrays(
        [np.array(["g1", "g2"], dtype="U2"), np.array(["g3", "g4"], dtype="U2")],
        dtype=[("0", "U2"), ("1", "U2")],
    )
    objects = np.array([("a", 1.0), ("bé", 2.0)], dtype=[("o", str_dt), ("f", "<f8")])
    return {
        "rec_array_basic": basic,
        "rec_array_widths": widths,
        "rec_array_rank_genes_groups": rank,
        "rec_array_object_field": objects,
    }


def _element_cases():
    import pandas as pd

    cases = {}
    for name in INT_NAMES + FLOAT_NAMES:
        values = np.array([1, 2, 3], dtype=name)
        cases[f"array_{name}"] = lambda v=values: v
        cases[f"scalar_{name}"] = lambda v=values: v[0]
    cases["array_bool"] = lambda: np.array([True, False, True])
    cases["array_bool_2d"] = lambda: np.array([[True, False, True], [False, False, True]])
    cases["scalar_bool"] = lambda: np.bool_(True)
    cases["array_complex128"] = lambda: np.array([1 + 2j, -3.5 + 0.25j])
    cases["array_complex64"] = lambda: np.array([1 + 2j, -3.5 + 0.25j], dtype="complex64")
    cases["scalar_complex128"] = lambda: np.complex128(1 + 2j)
    cases["array_float64_special"] = lambda: np.array(SPECIAL)
    cases["array_float64_2d"] = lambda: np.arange(6, dtype="float64").reshape(2, 3)
    cases["array_int32_2d"] = lambda: np.arange(6, dtype="int32").reshape(2, 3)
    # -2^31 shares its bit pattern with R's NA_integer_
    cases["array_int32_min"] = lambda: np.array([-(2**31), 0, 5], dtype="int32")
    cases["scalar_int32_min"] = lambda: np.int32(-(2**31))
    cases["array_float64_3d"] = lambda: np.arange(24, dtype="float64").reshape(2, 3, 4)
    cases["array_float64_empty"] = lambda: np.zeros(0)
    cases["array_float64_0x3"] = lambda: np.zeros((0, 3))
    cases["array_float64_1elem"] = lambda: np.array([2.5])
    cases["scalar_python_float"] = lambda: 2.5
    cases["scalar_python_int"] = lambda: 7
    cases["scalar_python_bool"] = lambda: True
    cases["scalar_python_str"] = lambda: "héllo"
    cases["scalar_str_empty"] = lambda: ""
    cases["string_array_1d"] = lambda: np.array(["a", "bé", "", "日本"])
    cases["string_array_object"] = lambda: np.array(["a", "bé", "", "日本"], dtype=object)
    cases["string_array_2d"] = lambda: np.array([["a", "b", "c"], ["d", "e", "f"]])
    cases["string_array_1elem"] = lambda: np.array(["a"])
    cases["string_array_empty"] = lambda: np.array([], dtype=object)
    cases["null"] = lambda: None
    cases["dict_nested"] = lambda: {
        "a": np.array([1.0, 2.0]),
        "s": "str",
        "n": 3,
        "sub": {"flag": True, "names": np.array(["x", "y"])},
    }
    cases["dict_empty"] = lambda: {}
    cases["dict_with_null"] = lambda: {"nothing": None, "x": 1.0}
    for name, value in _rec_arrays().items():
        cases[name] = lambda v=value: v
    for name in ("float64", "float32", "int64", "int32", "int8", "bool"):
        cases[f"csr_{name}"] = lambda n=name: _csr(n)
        cases[f"csc_{name}"] = lambda n=name: _csr(n, "csc")
    cases["csr_array_float64"] = lambda: __import__("scipy.sparse").sparse.csr_array(
        _csr("float64")
    )
    cases["csr_indices_int64"] = lambda: _csr("float64", indices="int64")
    cases["csr_empty"] = lambda: __import__("scipy.sparse").sparse.csr_matrix((3, 4))
    cases["csr_0_rows"] = lambda: __import__("scipy.sparse").sparse.csr_matrix((0, 4))
    for name in ("float64", "int64", "int32", "int8", "uint8", "float32", "bool"):
        cases[f"df_col_{name}"] = lambda n=name: _df(c=np.array([0, 1, 1], dtype=n))
    cases["df_col_float64_nan"] = lambda: _df(c=np.array([1.5, np.nan, np.inf]))
    cases["df_col_str"] = lambda: _df(c=pd.array(["a", "bé", ""], dtype="str"))
    cases["df_col_str_na"] = lambda: _df(c=pd.array(["a", None, ""], dtype="str"))
    cases["df_col_object_str"] = lambda: _df(c=np.array(["a", "b", "c"], dtype=object))
    cases["df_col_string_pdna"] = lambda: _df(
        c=pd.array(["a", None, "c"], dtype=pd.StringDtype(na_value=pd.NA))
    )
    cases["df_col_nullable_int"] = lambda: _df(c=pd.array([1, None, 3], dtype="Int64"))
    cases["df_col_nullable_int8"] = lambda: _df(c=pd.array([1, None, 3], dtype="Int8"))
    cases["df_col_nullable_uint16"] = lambda: _df(c=pd.array([1, None, 3], dtype="UInt16"))
    cases["df_col_nullable_int_nomissing"] = lambda: _df(c=pd.array([1, 2, 3], dtype="Int32"))
    cases["df_col_nullable_bool"] = lambda: _df(c=pd.array([True, None, False], dtype="boolean"))
    cases["df_col_nullable_float"] = lambda: _df(c=pd.array([1.5, None, 3], dtype="Float64"))
    cases["df_col_categorical"] = lambda: _df(c=_categorical(3))
    cases["df_col_categorical_numeric"] = lambda: _df(c=_categorical(3, numeric=True))
    cases["df_col_categorical_ordered"] = lambda: _df(c=_categorical(3, ordered=True))
    cases["df_col_categorical_missing"] = lambda: _df(c=_categorical(3, missing=True))
    cases["df_col_categorical_bool"] = lambda: _df(
        c=pd.Categorical([True, False, True], categories=[False, True])
    )
    # Pin the boundaries where pandas widens the code dtype
    cases["df_col_categorical_126"] = lambda: _df(c=_categorical(126))
    cases["df_col_categorical_127"] = lambda: _df(c=_categorical(127))
    cases["df_col_categorical_32767"] = lambda: _df(c=_categorical(32767))
    cases["df_col_categorical_128"] = lambda: _df(c=_categorical(128))
    cases["df_col_categorical_32768"] = lambda: _df(c=_categorical(32768))
    cases["df_col_categorical_empty"] = lambda: _df(
        c=pd.Categorical(["a", "b", "a"], categories=["a", "b", "unused"])
    )
    cases["df_two_columns"] = lambda: _df(b=np.array([1.0, 2.0, 3.0]), a=np.array([1, 2, 3]))
    cases["df_no_columns"] = lambda: pd.DataFrame(index=pd.Index(["a", "b"]))
    cases["df_no_rows"] = lambda: pd.DataFrame(
        {"c": np.zeros(0)}, index=pd.Index([], dtype=object)
    )
    cases["df_no_rows_str_index"] = lambda: pd.DataFrame(
        {"c": np.zeros(0), "s": pd.array([], dtype="str")},
        index=pd.Index([], dtype="str"),
    )
    cases["df_index_named"] = lambda: _df(c=np.array([1.0, 2.0, 3.0])).rename_axis("cell")
    cases["df_index_duplicates"] = lambda: pd.DataFrame(
        {"c": [1.0, 2.0, 3.0]}, index=pd.Index(["a", "a", "b"])
    )
    cases["df_index_nonascii"] = lambda: pd.DataFrame(
        {"c": [1.0, 2.0, 3.0]}, index=pd.Index(["é", "日本", "ß"])
    )
    cases["df_index_na"] = lambda: pd.DataFrame(
        {"c": [1.0, 2.0, 3.0]}, index=pd.Index(["a", None, "b"])
    )
    cases["df_index_range"] = lambda: pd.DataFrame({"c": [1.0, 2.0, 3.0]})
    cases["df_index_int"] = lambda: pd.DataFrame(
        {"c": [1.0, 2.0, 3.0]}, index=pd.Index([10, 20, 30])
    )
    cases["df_index_same_as_column"] = lambda: pd.DataFrame(
        {"id": ["a", "b", "c"]}, index=pd.Index(["a", "b", "c"], name="id")
    )
    cases["df_index_categorical"] = lambda: pd.DataFrame(
        {"c": [1.0, 2.0, 3.0]}, index=pd.CategoricalIndex(["a", "b", "a"])
    )
    cases["df_columns_order"] = lambda: _df(z=np.arange(3), a=np.arange(3), m=np.arange(3))
    cases["df_all_types"] = lambda: _df(
        f=np.array([1.5, 2.5, 3.5]),
        i=np.array([1, 2, 3], dtype="int32"),
        b=np.array([True, False, True]),
        s=pd.array(["a", "b", "c"], dtype="str"),
        cat=_categorical(3),
        ni=pd.array([1, None, 3], dtype="Int64"),
    )
    return cases


# Settings variants of cases whose encoding depends on a setting
SETTING_CASES = {
    "df_col_str_na_allow_nullable_true": (
        "df_col_str_na",
        {"allow_write_nullable_strings": True},
    ),
    "df_col_str_na_allow_nullable_false": (
        "df_col_str_na",
        {"allow_write_nullable_strings": False},
    ),
    "df_col_str_allow_nullable_false": (
        "df_col_str",
        {"allow_write_nullable_strings": False},
    ),
    "df_col_str_allow_nullable_true": (
        "df_col_str",
        {"allow_write_nullable_strings": True},
    ),
    "df_col_string_pdna_allow_nullable_true": (
        "df_col_string_pdna",
        {"allow_write_nullable_strings": True},
    ),
    "csr_indices_min_dtype": (
        "csr_float64",
        {"write_csr_csc_indices_with_min_possible_dtype": True},
    ),
    "csr_indices_int64_min_dtype": (
        "csr_indices_int64",
        {"write_csr_csc_indices_with_min_possible_dtype": True},
    ),
}


# Cases Python 0.13.4 refuses to write, recorded under "errors" in the manifest
ERROR_CASES = {"df_col_nullable_float", "df_col_str_na_allow_nullable_false"}


def _describe_value(value):
    """Short description of a Python value for the encoding table."""
    import pandas as pd

    if isinstance(value, np.ndarray):
        if value.dtype.names:
            fields = ", ".join(f"{n}:{value.dtype[n]}" for n in value.dtype.names)
            return f"structured ndarray [{fields}]"
        return f"ndarray {value.dtype} {value.shape}"
    if isinstance(value, np.generic):
        return f"np.{value.dtype} scalar"
    if isinstance(value, pd.DataFrame):
        cols = ", ".join(f"{c}:{value[c].dtype}" for c in value.columns)
        return f"DataFrame[{cols}] index {value.index.dtype}"
    if isinstance(value, pd.Categorical):
        return f"Categorical {value.categories.dtype}"
    if hasattr(value, "format") and hasattr(value, "indptr"):
        return f"{type(value).__name__} {value.dtype}, index {value.indices.dtype}"
    if isinstance(value, dict):
        return "dict"
    if value is None:
        return "None"
    return type(value).__name__


def _write_element(path, value, settings):
    from anndata.io import write_elem

    with h5py.File(path, "w") as f, anndata.settings.override(**settings):
        write_elem(f, "x", value)
    return _describe_value(value)


def _write_bytes(path):
    with h5py.File(path, "w") as f:
        ds = f.create_dataset("x", data=np.bytes_(b"raw bytes"))
        ds.attrs["encoding-type"] = "bytes"
        ds.attrs["encoding-version"] = "0.2.0"


def _full_adata(raw=True):
    import pandas as pd
    import scipy.sparse as sp

    rng = np.random.default_rng(0)
    adata = anndata.AnnData(
        rng.random((4, 3)).astype("float32"),
        obs=pd.DataFrame(
            {"group": pd.Categorical(["a", "b", "a", "b"]), "n": [1, 2, 3, 4]},
            index=[f"cell{i}" for i in range(4)],
        ),
        var=pd.DataFrame(
            {"gene": ["g1", "g2", "g3"]}, index=[f"gene{i}" for i in range(3)]
        ),
        obsm={"pca": rng.random((4, 2))},
        varm={"load": rng.random((3, 2))},
        obsp={"conn": sp.csr_matrix(np.eye(4))},
        varp={"corr": rng.random((3, 3))},
        layers={"counts": sp.csr_matrix(rng.integers(0, 3, (4, 3)).astype("int32"))},
        uns={"note": "text", "sub": {"k": np.arange(3)}},
    )
    if raw:
        adata.raw = adata
    return adata


def _adata_cases():
    import pandas as pd
    import scipy.sparse as sp

    return {
        "anndata_full": lambda: _full_adata(),
        "anndata_no_raw": lambda: _full_adata(raw=False),
        "anndata_empty_slots": lambda: anndata.AnnData(np.zeros((2, 3), dtype="float32")),
        "anndata_sparse_x": lambda: anndata.AnnData(sp.csr_matrix(np.eye(3, dtype="float32"))),
        "anndata_no_x": lambda: anndata.AnnData(
            obs=pd.DataFrame(index=["a", "b"]), var=pd.DataFrame(index=["x", "y", "z"])
        ),
        "anndata_0_obs": lambda: anndata.AnnData(np.zeros((0, 3), dtype="float32")),
        "anndata_0_vars": lambda: anndata.AnnData(np.zeros((2, 0), dtype="float32")),
    }


def _register_encoding_cases():
    elements = _element_cases()
    for name, factory in elements.items():
        filename = f"{ENCODING_DIR}/{name}.h5"

        def write(path, factory=factory):
            return _write_element(path, factory(), {})

        CASES[name] = {"file": filename, "write": write}
    for name, (base, settings) in SETTING_CASES.items():
        filename = f"{ENCODING_DIR}/{name}.h5"

        def write(path, base=base, settings=settings):
            return _write_element(path, elements[base](), settings)

        CASES[name] = {"file": filename, "write": write}
    CASES["bytes_scalar"] = {"file": f"{ENCODING_DIR}/bytes_scalar.h5", "write": _write_bytes}
    for name, factory in _adata_cases().items():
        CASES[name] = {
            "file": f"{ENCODING_DIR}/{name}.h5ad",
            "write": lambda path, factory=factory: factory().write_h5ad(path),
        }


_register_encoding_cases()


def main(outdir):
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    (outdir / ENCODING_DIR).mkdir(exist_ok=True)
    manifest = {
        "versions": {
            name: version(name) for name in ("anndata", "h5py", "numpy", "pandas")
        },
        "cases": {},
        "errors": {},
    }
    for name, entry in sorted(CASES.items()):
        path = outdir / entry["file"]
        if name in ERROR_CASES:
            # Python refuses these values, so the manifest records the error
            try:
                entry["write"](path)
            except Exception as err:
                manifest["errors"][name] = {
                    "type": type(err).__name__,
                    "message": str(err).splitlines()[0],
                }
                path.unlink(missing_ok=True)
                continue
            raise RuntimeError(f"{name} was expected to fail but wrote {path}")
        python = entry["write"](path)
        manifest["cases"][name] = {"file": entry["file"]}
        if python is not None:
            manifest["cases"][name]["python"] = python
    with open(outdir / "manifest.json", "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main(sys.argv[1])
