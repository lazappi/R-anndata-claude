"""Write Python's behaviour for lazy reading as JSON.

Usage: lazy_cases.py OUTPUT.json

The same AnnData (4 x 3, dense X, dense/CSR/CSC layers of several dtypes, obs and
var with categorical, nullable and plain columns, obsm, uns and raw) is written to
h5ad, zarr v3 and zarr v2, and so is a tall one (2500 x 4, CSR and CSC layers) for
the default chunks.
Sections of the table, each row keyed by name and then by format
(`h5ad`, `zarr_v3`, `zarr_v2`):

- `read_lazy`: `read_lazy()` with both values of `load_annotation_index`, plus the
  errors for missing and unconsolidated stores
- `read_elem_lazy`: every encoding with default and explicit `chunks`
- `operations`: subsetting, Views, `to_memory()`, printing, column access and writing
  on a lazily read AnnData
- `dask_chunks`: the default chunks of dense and sparse arrays

Each case records the result, the warnings raised and any error.
Types are Python class names, dask arrays are described by their `chunks`, and are
realised with `compute()` into `values`.
Paths in messages are replaced by `<dir>`.
The R equivalents are in tests/testthat/test-lazy.R.
"""

import json
import sys
import tempfile
import warnings
from pathlib import Path

import anndata as ad
import h5py
import numpy as np
import pandas as pd
import scipy.sparse as sp
import zarr
from anndata.experimental import read_elem_lazy, read_lazy

ad.settings.allow_write_nullable_strings = True

FORMATS = ["h5ad", "zarr_v3", "zarr_v2"]
ROOT = Path(tempfile.mkdtemp(prefix="lazy_cases_"))
FILES = {}


def plain(x):
    """Convert a value to something `json` can write, sparse matrices become dense."""
    if sp.issparse(x):
        return plain(x.toarray())
    if isinstance(x, pd.DataFrame):
        return {
            "index": [str(i) for i in x.index],
            "columns": {
                str(c): {
                    "dtype": str(x[c].dtype),
                    "values": plain(x[c].astype(object).where(x[c].notna(), None).tolist()),
                }
                for c in x.columns
            },
        }
    if isinstance(x, pd.Index):
        return [str(i) for i in x]
    if isinstance(x, np.ndarray):
        return plain(x.tolist())
    if isinstance(x, dict):
        return {str(k): plain(v) for k, v in x.items()}
    if isinstance(x, (list, tuple)):
        return [plain(v) for v in x]
    if isinstance(x, np.integer):
        return int(x)
    if isinstance(x, (np.floating, float)):
        return None if np.isnan(x) else float(x)
    if isinstance(x, np.bool_):
        return bool(x)
    if x is None or isinstance(x, (bool, int, str)):
        return x
    if x is pd.NA:
        return None
    return repr(x)


def describe(x):
    """A value with its Python type, lazy arrays are described and then computed."""
    if hasattr(x, "compute") and hasattr(x, "chunks"):
        values = x.compute()
        if values.size > 100:
            # a big array is recorded by its sum and corner, not in full
            dense = values.toarray() if sp.issparse(values) else values
            return {
                "type": type(x).__module__ + "." + type(x).__name__,
                "shape": [int(s) for s in x.shape],
                "dtype": str(x.dtype),
                "chunks": [[int(c) for c in axis] for axis in x.chunks],
                "meta_type": type(x._meta).__name__,
                "values_type": type(values).__name__,
                "values_sum": float(dense.sum()),
                "values_head": plain(dense[:3]),
            }
        return {
            "type": type(x).__module__ + "." + type(x).__name__,
            "shape": [int(s) for s in x.shape],
            "dtype": str(x.dtype),
            "chunks": [[int(c) for c in axis] for axis in x.chunks],
            "meta_type": type(x._meta).__name__,
            "values_type": type(values).__name__,
            "values": plain(values),
        }
    if isinstance(x, ad.AnnData):
        return {"type": "AnnData", "summary": summary(x)}
    if isinstance(x, pd.Series):
        return {
            "type": "Series",
            "dtype": str(x.dtype),
            "values": plain(x.astype(object).where(x.notna(), None).tolist()),
        }
    return {"type": type(x).__name__, "value": plain(x)}


def lazy_kind(x):
    """The class a lazy column or array has, without reading it."""
    return type(x).__module__ + "." + type(x).__name__


def column(ds, name):
    """What a column of a lazy obs/var is, and what it gives when realised."""
    var = ds[name]
    data = var.variable._data
    out = {
        "variable_type": lazy_kind(var.variable._data),
        "dtype": str(var.dtype),
    }
    values = ds[name].to_numpy() if hasattr(ds[name], "to_numpy") else var.values
    out["values_type"] = type(values).__name__
    out["values_dtype"] = str(getattr(values, "dtype", None))
    out["values"] = plain(pd.Series(values).astype(object).where(pd.Series(values).notna(), None).tolist())
    return out


def lazy_frame(ds):
    return {
        "type": type(ds).__name__,
        "shape": [int(s) for s in ds.shape],
        # the column order of a lazy frame varies between runs, so it is sorted
        "columns": sorted(str(c) for c in ds.columns),
        "index_name": ds.index.name,
        "index": plain(ds.index),
        "is_backed": bool(ds.is_backed),
        "true_index_dim": getattr(ds, "true_index_dim", None),
        "columns_detail": {str(c): column(ds, c) for c in sorted(ds.columns)},
    }


def mapping(m):
    return {str(k): describe(m[k]) for k in m.keys()}


def summary(adata):
    """What can be seen of a lazily read AnnData, without realising arrays."""
    out = {
        "is_view": bool(adata.is_view),
        "shape": [int(adata.n_obs), int(adata.n_vars)],
        "obs_names": plain(adata.obs_names),
        "var_names": plain(adata.var_names),
        "X_type": None if adata.X is None else lazy_kind(adata.X),
        "obs_type": type(adata.obs).__name__,
        "var_type": type(adata.var).__name__,
        "obs_columns": sorted(str(c) for c in adata.obs.columns),
        "var_columns": sorted(str(c) for c in adata.var.columns),
        "layers": {str(k): lazy_kind(adata.layers[k]) for k in adata.layers.keys()},
        "obsm": {str(k): lazy_kind(adata.obsm[k]) for k in adata.obsm.keys()},
        "varm": {str(k): lazy_kind(adata.varm[k]) for k in adata.varm.keys()},
        "uns": plain(dict(adata.uns)),
        "has_raw": adata.raw is not None,
        "file_attached": adata.file.is_open if adata.isbacked else None,
    }
    return out


def make_adata(n_obs=4):
    rng = np.random.default_rng(0)
    n_var = 3 if n_obs == 4 else 4
    base = np.arange(n_obs * n_var, dtype="float64").reshape(n_obs, n_var)
    if n_obs == 4:
        obs = pd.DataFrame(
            {
                "num": [1.0, 2.0, 3.0, 4.0],
                "plain_str": pd.array(["p", "q", "p", "r"], dtype="object"),
                "cat": pd.Categorical(["a", "b", "a", None], categories=["a", "b", "c"]),
                "ni": pd.array([1, None, 3, 4], dtype="Int64"),
                "nb": pd.array([True, None, False, True], dtype="boolean"),
                "ns": pd.array(["x", None, "z", "w"], dtype="string"),
            },
            index=["o0", "o1", "o2", "o3"],
        )
        var = pd.DataFrame(
            {
                "g": [1.0, 2.0, 3.0],
                "vcat": pd.Categorical(["u", "v", "u"]),
            },
            index=["v0", "v1", "v2"],
        )
    else:
        obs = pd.DataFrame({"num": rng.random(n_obs)}, index=[f"o{i}" for i in range(n_obs)])
        var = pd.DataFrame({"g": rng.random(n_var)}, index=[f"v{i}" for i in range(n_var)])
    mask = (base % 3) == 0
    layers = {
        "dense_i8": base.astype("int8"),
        "dense_u8": base.astype("uint8"),
        "dense_i64": base.astype("int64"),
        "dense_bool": mask,
        "csr_f32": sp.csr_matrix(base.astype("float32") * mask),
        "csr_i64": sp.csr_matrix(base.astype("int64") * mask),
        "csr_bool": sp.csr_matrix(mask),
        "csc_f64": sp.csc_matrix(base * mask),
        "csc_u8": sp.csc_matrix(base.astype("uint8") * mask),
    }
    adata = ad.AnnData(
        base.astype("float32"),
        obs=obs,
        var=var,
        layers=layers,
        obsm={"pca": base[:, :2].copy()},
        uns={"u": 1, "nested": {"k": [1, 2, 3]}},
    )
    if n_obs == 4:
        adata.raw = adata
    return adata


def path_for(name, fmt):
    suffix = ".h5ad" if fmt == "h5ad" else ".zarr"
    return ROOT / f"{name}-{fmt}{suffix}"


def write(adata, path, fmt):
    # string columns stay strings, so plain and nullable string arrays are covered
    keep = {"convert_strings_to_categoricals": False}
    if fmt == "h5ad":
        adata.write_h5ad(path, **keep)
    elif fmt == "zarr_v3":
        with ad.settings.override(zarr_write_format=3):
            adata.write_zarr(path, **keep)
    else:
        with ad.settings.override(zarr_write_format=2):
            warnings.simplefilter("ignore")
            adata.write_zarr(path, **keep)


def setup():
    # the deprecation of zarr v2 writes is not an observation of this table
    warnings.filterwarnings("ignore", message="This setting will be removed")
    for name, n_obs in [("small", 4), ("tall", 2500)]:
        adata = make_adata(n_obs)
        for fmt in FORMATS:
            FILES[(name, fmt)] = path_for(name, fmt)
            write(adata, FILES[(name, fmt)], fmt)


def norm(obj):
    text = json.dumps(obj)
    for d in {str(ROOT), str(ROOT.resolve())}:
        text = text.replace(d, "<dir>")
    return json.loads(text)


def record(fn):
    """Run a function and record its result, warnings and error."""
    res = error = None
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        try:
            res = fn()
        except Exception as e:  # noqa: BLE001 - the error is the observation
            error = {"type": type(e).__name__, "message": str(e)}
    return norm(
        {
            "result": res,
            "error": error,
            "warnings": [
                {"category": w.category.__name__, "message": str(w.message)}
                for w in caught
                if not issubclass(w.category, (ResourceWarning, DeprecationWarning))
                or "anndata" in str(w.message)
            ],
        }
    )


def for_formats(fn, name="small"):
    """Run `fn(path, fmt)` for each format."""
    return {fmt: record(lambda fmt=fmt: fn(FILES[(name, fmt)], fmt)) for fmt in FORMATS}


def open_store(path, fmt):
    if fmt == "h5ad":
        return h5py.File(path, "r")
    return zarr.open_group(str(path), mode="r")


def elem_case(key, chunks="default", name="small"):
    def fn(path, fmt):
        store = open_store(path, fmt)
        elem = store[key]
        out = read_elem_lazy(elem) if chunks == "default" else read_elem_lazy(elem, chunks=chunks)
        if hasattr(out, "base_path_or_zarr_group"):
            # lazy categorical and masked arrays: they are read through an integer key
            info = {
                "type": lazy_kind(out),
                "shape": [int(s) for s in out.shape],
                "dtype": str(out.dtype),
            }
            try:
                # indexing the array directly fails, so realise it as read_lazy() does
                import xarray as xr

                values = xr.Variable(["d"], xr.core.indexing.LazilyIndexedArray(out)).values
                info["values_type"] = type(values).__name__
                info["values"] = plain(pd.Series(values).astype(object).where(pd.Series(values).notna(), None).tolist())
            except Exception as e:  # noqa: BLE001 - the error is the observation
                info["read_error"] = {"type": type(e).__name__, "message": str(e)}
            return info
        if hasattr(out, "ds") or type(out).__name__ == "Dataset2D":
            return lazy_frame(out)
        return describe(out)

    return lambda: for_formats(fn, name)


def read_lazy_case(**kwargs):
    def fn(path, fmt):
        adata = read_lazy(path, **kwargs)
        out = summary(adata)
        out["obs"] = lazy_frame(adata.obs)
        out["var"] = lazy_frame(adata.var)
        out["X"] = describe(adata.X)
        out["layers_described"] = {str(k): describe(adata.layers[k]) for k in adata.layers.keys()}
        out["raw_var_type"] = type(adata.raw.var).__name__ if adata.raw is not None else None
        out["to_memory"] = {
            "obs": plain(adata.to_memory().obs),
            "X": plain(adata.to_memory().X),
        }
        if hasattr(adata, "file") and adata.file.is_open:
            adata.file.close()
        return out

    return lambda: for_formats(fn)


def op_case(operation):
    def fn(path, fmt):
        adata = read_lazy(path)
        try:
            return operation(adata)
        finally:
            if adata.isbacked and adata.file.is_open:
                adata.file.close()

    return lambda: for_formats(fn)


def view_info(v):
    return {"is_view": bool(v.is_view), "summary": summary(v), "X": describe(v.X)}


def write_roundtrip(kind):
    def op(adata):
        out = ROOT / f"out-{kind}-{id(adata)}"
        if kind == "h5ad":
            adata.write_h5ad(str(out) + ".h5ad")
            back = ad.read_h5ad(str(out) + ".h5ad")
        else:
            adata.write_zarr(str(out) + ".zarr")
            back = ad.read_zarr(str(out) + ".zarr")
        return {
            "X": plain(back.X),
            "obs": plain(back.obs),
            "var": plain(back.var),
            "layers": {k: plain(back.layers[k]) for k in back.layers.keys()},
            "layer_types": {k: type(back.layers[k]).__name__ for k in back.layers.keys()},
            "has_raw": back.raw is not None,
            "uns": plain(dict(back.uns)),
        }

    return op


def assign_obs(adata):
    adata.obs["new"] = [1, 2, 3, 4]
    return {"obs_columns": sorted(str(c) for c in adata.obs.columns)}


def assign_X(adata):
    adata.X = np.zeros((4, 3), dtype="float32")
    return describe(adata.X)


def obs_col_subset(adata):
    return {"obs": lazy_frame(adata.obs[["num", "cat"]])}


def obs_row_subset(adata):
    sub = adata.obs.iloc[[0, 2]]
    return lazy_frame(sub)


def obs_loc(adata):
    return lazy_frame(adata.obs.loc[["o3", "o1"]])


def single_col(adata):
    return {
        n: column(adata.obs, n) for n in ["num", "plain_str", "cat", "ni", "nb", "ns"]
    }


def copy_op(adata):
    c = adata.copy()
    return {"type": type(c.X).__name__, "summary": summary(c)}


def transpose_op(adata):
    t = adata.T
    return {"summary": summary(t)}


def subset_names(adata):
    return view_info(adata[["o3", "o1"], ["v2", "v0"]])


def subset_bool(adata):
    return view_info(adata[np.array([True, False, True, False]), :])


def view_of_view(adata):
    return view_info(adata[[0, 2], :][[1], :])


def view_assign(adata):
    v = adata[[0, 2], :]
    v.obs["z"] = [1, 2]
    return {"is_view": bool(v.is_view), "obs_columns": sorted(str(c) for c in v.obs.columns)}


def repr_op(adata):
    return {"repr": repr(adata), "str": str(adata), "obs_repr_is_default": repr(adata.obs).startswith("<anndata._core.xarray.Dataset2D object at")}


def to_memory_op(adata):
    m = adata.to_memory()
    return {
        "X": plain(m.X),
        "X_type": type(m.X).__name__,
        "obs": plain(m.obs),
        "var": plain(m.var),
        "layer_types": {k: type(m.layers[k]).__name__ for k in m.layers.keys()},
        "layers": {k: plain(m.layers[k]) for k in m.layers.keys()},
        "raw": None if m.raw is None else plain(m.raw.X),
        "is_view": bool(m.is_view),
    }


def to_memory_copy_false(adata):
    return {"X": plain(adata.to_memory(copy=False).X)}


def to_memory_view(adata):
    m = adata[[0, 2], :].to_memory()
    return {"X": plain(m.X), "obs": plain(m.obs), "is_view": bool(m.is_view)}


def sparse_chunk_case(layer, chunks):
    def fn(path, fmt):
        store = open_store(path, fmt)
        return describe(read_elem_lazy(store[f"layers/{layer}"], chunks=chunks))

    return lambda: for_formats(fn, "tall")


def default_chunk_case(layer):
    def fn(path, fmt):
        store = open_store(path, fmt)
        return describe(read_elem_lazy(store[f"layers/{layer}"]))

    return lambda: for_formats(fn, "tall")


def tall_read_lazy(adata_fn):
    def fn(path, fmt):
        adata = read_lazy(path)
        try:
            return adata_fn(adata)
        finally:
            if adata.isbacked and adata.file.is_open:
                adata.file.close()

    return lambda: for_formats(fn, "tall")


def missing_store():
    return {
        fmt: record(lambda fmt=fmt: summary(read_lazy(ROOT / f"missing-{fmt}{'.h5ad' if fmt == 'h5ad' else '.zarr'}")))
        for fmt in FORMATS
    }


def unconsolidated():
    # a v2 store without its consolidated metadata (v3 keeps it inside zarr.json)
    path = ROOT / "unconsolidated.zarr"
    write(make_adata(), path, "zarr_v2")
    (path / ".zmetadata").unlink()
    return {"zarr_v2": record(lambda: summary(read_lazy(path)))}


LAYER_ELEMS = {
    "dense_int8": "layers/dense_i8",
    "dense_uint8": "layers/dense_u8",
    "dense_int64": "layers/dense_i64",
    "dense_bool": "layers/dense_bool",
    "dense_float32": "X",
    "csr_float32": "layers/csr_f32",
    "csr_int64": "layers/csr_i64",
    "csr_bool": "layers/csr_bool",
    "csc_float64": "layers/csc_f64",
    "csc_uint8": "layers/csc_u8",
    "categorical": "obs/cat",
    "nullable_integer": "obs/ni",
    "nullable_boolean": "obs/nb",
    "nullable_string": "obs/ns",
    "string_array": "obs/plain_str",
    "dataframe_obs": "obs",
    "dataframe_var": "var",
    "obsm_array": "obsm/pca",
    "uns_dict": "uns",
    "uns_scalar": "uns/u",
    "raw_X": "raw/X",
    "raw_var": "raw/var",
}


def build():
    table = {"read_lazy": {}, "read_elem_lazy": {}, "operations": {}, "dask_chunks": {}}
    t = table["read_lazy"]
    t["default"] = read_lazy_case()()
    t["load_annotation_index_true"] = read_lazy_case(load_annotation_index=True)()
    t["load_annotation_index_false"] = read_lazy_case(load_annotation_index=False)()
    t["missing_store"] = missing_store()
    t["unconsolidated_zarr"] = unconsolidated()
    t["open_handle"] = for_formats(
        lambda path, fmt: summary(read_lazy(open_store(path, fmt)))
    )

    e = table["read_elem_lazy"]
    for name, key in LAYER_ELEMS.items():
        e[f"{name}_default"] = elem_case(key)()
    for name in ["dense_float32", "dense_int64", "dense_bool"]:
        e[f"{name}_chunks_2_2"] = elem_case(LAYER_ELEMS[name], chunks=(2, 2))()
        e[f"{name}_chunks_minus1_none"] = elem_case(LAYER_ELEMS[name], chunks=(-1, None))()
        e[f"{name}_chunks_bad_length"] = elem_case(LAYER_ELEMS[name], chunks=(2,))()
    e["string_array_chunks_2"] = elem_case("obs/plain_str", chunks=(2,))()
    for name in ["csr_float32", "csr_int64", "csr_bool"]:
        e[f"{name}_chunks_2_minus1"] = elem_case(LAYER_ELEMS[name], chunks=(2, -1))()
        e[f"{name}_chunks_minor_axis"] = elem_case(LAYER_ELEMS[name], chunks=(2, 2))()
        e[f"{name}_chunks_bad_length"] = elem_case(LAYER_ELEMS[name], chunks=(2,))()
    for name in ["csc_float64", "csc_uint8"]:
        e[f"{name}_chunks_minus1_2"] = elem_case(LAYER_ELEMS[name], chunks=(-1, 2))()
        e[f"{name}_chunks_minor_axis"] = elem_case(LAYER_ELEMS[name], chunks=(2, 2))()
    e["categorical_chunks_ignored"] = elem_case("obs/cat", chunks=(2,))()
    e["nullable_integer_chunks_ignored"] = elem_case("obs/ni", chunks=(2,))()

    o = table["operations"]
    ops = {
        "subset_names": subset_names,
        "subset_bool": subset_bool,
        "view_of_view": view_of_view,
        "view_assign_obs": view_assign,
        "obs_column_subset": obs_col_subset,
        "obs_row_subset": obs_row_subset,
        "obs_loc": obs_loc,
        "obs_columns_realised": single_col,
        "copy": copy_op,
        "transpose": transpose_op,
        "repr": repr_op,
        "to_memory": to_memory_op,
        "to_memory_copy_false": to_memory_copy_false,
        "to_memory_view": to_memory_view,
        "assign_obs_column": assign_obs,
        "assign_X": assign_X,
        "write_h5ad": write_roundtrip("h5ad"),
        "write_zarr": write_roundtrip("zarr"),
    }
    for name, fn in ops.items():
        o[name] = op_case(fn)()
    o["subset_slices"] = op_case(lambda a: view_info(a[1:3, :2]))()
    o["subset_obs_only"] = op_case(lambda a: view_info(a[[0, 3]]))()
    o["subset_var_only"] = op_case(lambda a: view_info(a[:, ["v1"]]))()
    o["subset_tall_csr"] = tall_read_lazy(
        lambda a: {"X_chunks": describe(a.layers["csr_f32"])["chunks"], "layer": describe(a[[5, 2400], :].layers["csr_f32"])}
    )()
    # writing a lazy object raises, so also write what `to_memory()` gives
    o["write_h5ad_after_to_memory"] = op_case(lambda a: write_roundtrip("h5ad")(a.to_memory()))()
    o["write_zarr_after_to_memory"] = op_case(lambda a: write_roundtrip("zarr")(a.to_memory()))()
    o["write_view_h5ad"] = op_case(lambda a: write_roundtrip("h5ad")(a[[0, 2], :]))()
    o["write_view_zarr"] = op_case(lambda a: write_roundtrip("zarr")(a[[0, 2], :]))()

    d = table["dask_chunks"]
    for layer in ["csr_f32", "csc_f64", "dense_i64"]:
        d[f"tall_{layer}"] = default_chunk_case(layer)()
    d["tall_csr_stride_100"] = sparse_chunk_case("csr_f32", (100, -1))()
    d["tall_csc_stride_2"] = sparse_chunk_case("csc_f64", (-1, 2))()
    return table


def main():
    out = Path(sys.argv[1])
    setup()
    np.random.seed(0)
    table = build()
    out.write_text(json.dumps(table, indent=1, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
