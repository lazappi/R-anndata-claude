"""Write Python's behaviour for backed mode as JSON.

Usage: backed_cases.py OUTPUT.json

Every operation runs on a fresh h5ad file (4 x 3 float32 X, obs column `g`, a layer
`l`) opened with `read_h5ad(backed=mode)`, for dense, csr and csc X and for the
modes "r" and "r+".
Each case records the result, the warnings raised, any error, the state of the
object afterwards (`isbacked`, `filename`, whether the file is open), and the
backing file: whether it still exists, whether its bytes changed and what
`read_h5ad()` makes of it.
Operations in `RAW_OPERATIONS` run a second time on a file with `raw`, because
Python rewrites `raw` in the file it is reading when it writes to the backing file.
Further sections cover in-memory objects, `read_h5ad(backed=)` arguments, the
file manager, `read_elem_partial()`, `sparse_dataset()` and the setting
`min_rows_for_chunked_h5_copy`.
String columns are written as plain `string-array` (`allow_write_nullable_strings`
is off), because `read_elem_partial()` cannot read `nullable-string-array`.
Paths in messages are replaced by `<dir>`.
The R equivalents are in tests/testthat/test-backed.R.
"""

import hashlib
import json
import shutil
import sys
import tempfile
import warnings
from pathlib import Path

import anndata as ad
import h5py
import numpy as np
import pandas as pd
import scipy.sparse as sp
from anndata._core.file_backing import AnnDataFileManager
from anndata._core.sparse_dataset import BaseCompressedSparseDataset
from anndata._io.specs.registry import read_elem_partial
from anndata.io import sparse_dataset

ad.settings.allow_write_nullable_strings = False

KINDS = ["dense", "csr", "csc"]
MODES = ["r", "r+"]
ROOT = Path(tempfile.mkdtemp(prefix="backed_cases_"))
COUNTER = [0]
TEMPLATES = {}


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
    return repr(x)


def result(x):
    """A value with its Python type, handles are described and not read."""
    if isinstance(x, h5py.Dataset):
        return {"type": "Dataset", "shape": list(x.shape), "dtype": str(x.dtype)}
    if isinstance(x, BaseCompressedSparseDataset):
        return {"type": type(x).__name__, "repr": repr(x), "shape": list(x.shape)}
    if isinstance(x, ad.AnnData):
        return {"type": "AnnData", "summary": state(x)}
    return {"type": type(x).__name__, "value": plain(x)}


def make_file(kind, path, raw=False):
    X = np.arange(1, 13, dtype="float32").reshape(4, 3)
    if kind == "csr":
        X = sp.csr_matrix(X)
    elif kind == "csc":
        X = sp.csc_matrix(X)
    adata = ad.AnnData(
        X,
        obs=pd.DataFrame({"g": ["a", "b", "a", "b"]}, index=["w", "x", "y", "z"]),
        var=pd.DataFrame(index=["p", "q", "r"]),
    )
    adata.layers["l"] = adata.X.copy()
    if raw:
        adata.raw = adata
    adata.write_h5ad(path)


def digest(path):
    p = Path(path)
    return hashlib.md5(p.read_bytes()).hexdigest() if p.exists() else None


def state(adata):
    """What can be seen of an object without reading X (which would reopen the file)."""
    out = {
        "shape": [int(adata.n_obs), int(adata.n_vars)],
        "is_view": bool(adata.is_view),
        "isbacked": bool(adata.isbacked),
        "filename": None if adata.filename is None else Path(adata.filename).name,
        "file_is_open": bool(adata.file.is_open),
        "file_mode": adata.file._filemode,
        "obs_columns": [str(c) for c in adata.obs.columns],
    }
    return out


def disk(path):
    """What read_h5ad() makes of a file."""
    if not Path(path).exists():
        return None
    try:
        r = ad.read_h5ad(path)
    except Exception as e:  # noqa: BLE001 - the error is the observation
        return {"error": {"type": type(e).__name__, "message": str(e)}}
    out = {
        "shape": [int(r.n_obs), int(r.n_vars)],
        "obs_columns": [str(c) for c in r.obs.columns],
        "obs_names": plain(r.obs_names),
        "layers": [str(k) for k in r.layers.keys()],
        "X": None if r.X is None else {"type": type(r.X).__name__, "value": plain(r.X)},
        "has_raw": r.raw is not None,
    }
    r.file.close()
    return out


class Case:
    """One backed object on a fresh file."""

    def __init__(self, kind, mode, raw=False):
        COUNTER[0] += 1
        self.dir = ROOT / f"c{COUNTER[0]}"
        self.dir.mkdir()
        self.kind, self.mode, self.raw = kind, mode, raw
        self.path = self.dir / "orig.h5ad"
        key = (kind, raw)
        if key not in TEMPLATES:
            TEMPLATES[key] = ROOT / f"template-{kind}-{raw}.h5ad"
            make_file(kind, TEMPLATES[key], raw)
        shutil.copy(TEMPLATES[key], self.path)
        self.b = ad.read_h5ad(self.path, backed=mode)

    def norm(self, obj):
        text = json.dumps(obj)
        for d in {str(self.dir), str(self.dir.resolve())}:
            text = text.replace(d, "<dir>")
        return json.loads(text)


def run(operation, kind, mode, raw=False, backed=True):
    np.random.seed(0)
    case = Case(kind, mode, raw)
    if not backed:
        case.b.file.close()
        case.b = ad.read_h5ad(case.path)
    before = digest(case.path)
    res = None
    error = None
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        try:
            res = operation(case)
        except Exception as e:  # noqa: BLE001 - the error is the observation
            error = {"type": type(e).__name__, "message": str(e)}
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        after_state = state(case.b)
        current = case.b.filename
        try:
            case.b.file.close()
        except Exception:  # noqa: BLE001
            pass
        changed = digest(case.path) != before
        out = {
            "warnings": [
                {"category": w.category.__name__, "message": str(w.message)} for w in caught
            ],
            "error": error,
            "result": res,
            "state_after": after_state,
            "original_exists": case.path.exists(),
            "original_changed": changed,
            # what read_h5ad() makes of the original, only kept when its bytes changed
            "original_after": disk(case.path) if changed else None,
            "current_after": (
                disk(current)
                if current is not None and Path(current) != case.path
                else None
            ),
        }
    return case.norm(out)


# Operations: each takes a Case and returns an optional value to record


def tup(*items):
    return items


def getx(index):
    return lambda c: result(c.b.X[index])


def new_x(kind):
    X = np.arange(12, dtype="float32").reshape(4, 3) * 5
    return {"dense": X, "csr": sp.csr_matrix(X), "csc": sp.csc_matrix(X)}[kind]


def assign_x(value):
    def op(c):
        c.b.X = value() if callable(value) else value
        return {"isbacked": bool(c.b.isbacked), "X": result(c.b.X)}

    return op


def write_to(method, **kwargs):
    def op(c):
        getattr(c.b, method)(c.dir / "new.h5ad", **kwargs)
        return {"new": disk(c.dir / "new.h5ad")}

    return op


def view(c):
    return c.b[[0, 2], [0, 2]]


def view_op(fn):
    def op(c):
        v = view(c)
        return fn(v, c)

    return op


def closed(fn):
    def op(c):
        c.b.file.close()
        return fn(c)

    return op


def chunked(size):
    def op(c):
        return [
            {"start": s, "end": e, "chunk": result(chunk)}
            for chunk, s, e in c.b.chunked_X(size)
        ]

    return op


def chunk_x(*args, **kwargs):
    def op(c):
        return result(c.b.chunk_X(*args, **kwargs))

    return op


def file_op(fn):
    return lambda c: fn(c.b.file, c)


def set_filename(value):
    def op(c):
        c.b.filename = value(c) if callable(value) else value
        return None

    return op


def _x_item(c):
    c.b.X[0, 0] = 99.0
    return None


def _repr_after_close(c):
    c.b.file.close()
    return {"repr": repr(c.b), "file_is_open": bool(c.b.file.is_open)}


def _close_then(attr):
    def op(c):
        c.b.file.close()
        value = attr(c)
        return {"value": result(value), "file_is_open": bool(c.b.file.is_open)}

    return op


def _close_twice(c):
    c.b.file.close()
    c.b.file.close()
    return {"file_is_open": bool(c.b.file.is_open)}


def _file_open(c):
    c.b.file.open()
    return {"file_is_open": bool(c.b.file.is_open)}


def _file_open_other(c):
    c.b.file.close()
    c.b.file.open(c.path, "r+")
    return {"file_is_open": bool(c.b.file.is_open), "mode": c.b.file._filemode}


def _file_open_bad_mode(c):
    c.b.file.open(c.path, "q")


def _file_open_missing(c):
    c.b.file.open(c.dir / "missing.h5ad", "r")


def _file_setitem(c):
    c.b.file["extra"] = np.arange(3)
    return sorted(c.b.file.keys()) if hasattr(c.b.file, "keys") else None


def _file_delitem(c):
    del c.b.file["layers"]


def _file_contains(c):
    return {"X": "X" in c.b.file, "nope": "nope" in c.b.file}


def _file_iter(c):
    return sorted(list(c.b.file))


def _file_getitem(c):
    return result(c.b.file["X"])


def _file_getitem_missing(c):
    return result(c.b.file["nope"])


def _stale_handle(c):
    handle = c.b.X
    c.b.file.close()
    c.b.X  # reopens
    return result(handle[0])


def _copy_twice(c):
    first = c.b.copy(c.dir / "copy.h5ad")
    second = c.b.copy(c.dir / "copy.h5ad")
    return {"first": state(first), "second": state(second)}


def _copy_filename(c):
    copy = c.b.copy(c.dir / "copy.h5ad")
    return {
        "copy": state(copy),
        "same_object": copy is c.b,
        "X": result(copy.X),
        "file": disk(c.dir / "copy.h5ad"),
    }


def _to_memory(copy):
    def op(c):
        m = c.b.to_memory(copy=copy)
        out = {"memory": state(m), "X": result(m.X), "layers": plain(dict(m.layers)),
               "raw_X": None if m.raw is None else result(m.raw.X)}
        out["original_still_backed"] = bool(c.b.isbacked)
        return out

    return op


def _to_memory_view(copy):
    def op(c):
        m = view(c).to_memory(copy=copy)
        return {"memory": state(m), "X": result(m.X)}

    return op


def _write_view(path):
    def op(c):
        v = view(c)
        target = c.dir / "view.h5ad" if path == "new" else c.path
        v.write(target)
        return {"view": state(v), "written": disk(target)}

    return op


def _view_state(c):
    v = view(c)
    return {"view": state(v), "X": result(v.X), "layers": plain(dict(v.layers)),
            "repr": repr(v), "parent": state(c.b)}


def _view_of_view(c):
    v = view(c)[[1], :]
    return {"view": state(v), "X": result(v.X), "parent": state(c.b)}


def _view_raw(c):
    v = view(c)
    return result(v.raw.X) if v.raw is not None else None


def _view_modify(fn):
    def op(c):
        v = view(c)
        fn(v)
        return {"view": state(v), "parent": state(c.b)}

    return op


def _set_item(obj_fn, key, value):
    def fn(v):
        obj_fn(v)[key] = value

    return fn


def _view_x_assign(v):
    v.X = np.zeros((2, 2), dtype="float32")


def _view_obs(v):
    v.obs["n"] = [1.0, 2.0]


def _view_layer(v):
    v.layers["n"] = np.zeros((2, 2), dtype="float32")


def _view_names(v):
    v.obs_names = ["p", "q"]


def _view_x_item(v):
    v.X[0, 0] = 5.0


def _repr(c):
    return {"repr": repr(c.b), "str": str(c.b), "file_repr": repr(c.b.file)}


def _meta(c):
    return {
        "isbacked": bool(c.b.isbacked),
        "isview": bool(c.b.isview),
        "filename": plain(None if c.b.filename is None else Path(c.b.filename).name),
        "filename_type": type(c.b.filename).__name__,
        "file_is_open": bool(c.b.file.is_open),
        "file_filename": Path(c.b.file.filename).name,
        "layers_keys": [str(k) for k in c.b.layers.keys()],
        "none_in_layers": None in c.b.layers,
        "shape": list(c.b.shape),
    }


def _layers(key):
    return lambda c: result(c.b.layers[key])


def _raw_x(c):
    return result(c.b.raw.X) if c.b.raw is not None else None


def _raw_x_assign(c):
    c.b.raw.X = np.zeros((4, 3))


def _raw_assign(c):
    c.b.raw = c.b


def _layers_none_assign(c):
    c.b.layers[None] = new_x(c.kind)
    return {"isbacked": bool(c.b.isbacked)}


def _x_none(c):
    c.b.X = None
    return {"isbacked": bool(c.b.isbacked)}


def _x_del(c):
    del c.b.X
    return {"isbacked": bool(c.b.isbacked)}


def _after_assign_then(fn):
    def op(c):
        c.b.X = new_x(c.kind)
        return fn(c)

    return op


def _slot_assign(slot, value):
    def op(c):
        setattr(c.b, slot, value)
        return {"isbacked": bool(c.b.isbacked)}

    return op


def _layer_set(c):
    c.b.layers["new"] = np.ones((4, 3), dtype="float32")
    return {"isbacked": bool(c.b.isbacked)}


def _obs_edit_write(c):
    c.b.obs["n"] = [1.0, 2.0, 3.0, 4.0]
    c.b.write()
    return {"written": disk(c.path)}


def _filename_new_open(c):
    c.b.filename = c.dir / "moved.h5ad"
    c_state = state(c.b)
    return {"state": c_state, "X": result(c.b.X)}


def _filename_none(c):
    c.b.filename = None
    return {"state": state(c.b), "X": result(c.b.X),
            "raw_X": None if c.b.raw is None else result(c.b.raw.X)}


def _filename_twice_none(c):
    c.b.filename = None
    c.b.filename = None
    return state(c.b)


def _filename_same(c):
    c.b.filename = c.path
    return state(c.b)


def _filename_missing_dir(c):
    c.b.filename = c.dir / "nodir" / "x.h5ad"


def _copy_missing_dir(c):
    c.b.copy(c.dir / "nodir" / "x.h5ad")


def _write_no_arg(c):
    c.b.write()
    return {"state": state(c.b), "written": disk(c.path)}


def _write_same(c):
    c.b.write(c.path)
    return {"state": state(c.b), "written": disk(c.path)}


def _write_new(method):
    def op(c):
        getattr(c.b, method)(c.dir / "new.h5ad")
        return {"state": state(c.b), "new": disk(c.dir / "new.h5ad")}

    return op


def _write_missing_dir(c):
    c.b.write_h5ad(c.dir / "nodir" / "x.h5ad")


def _write_compressed(compression):
    def op(c):
        c.b.write_h5ad(c.dir / "new.h5ad", compression=compression, compression_opts=4 if compression == "gzip" else None)
        with h5py.File(c.dir / "new.h5ad") as f:
            node = f["X"] if isinstance(f["X"], h5py.Dataset) else f["X/data"]
            return {"compression": node.compression, "chunks": plain(node.chunks)}

    return op


def _write_as_dense(c):
    c.b.write_h5ad(c.dir / "new.h5ad", as_dense=["X"])
    with h5py.File(c.dir / "new.h5ad") as f:
        return {"X_is_dataset": isinstance(f["X"], h5py.Dataset)}


def _write_zarr(c):
    c.b.write_zarr(c.dir / "new.zarr")
    r = ad.read_zarr(c.dir / "new.zarr")
    return {"X": result(r.X)}


def _write_csvs(c):
    c.b.write_csvs(c.dir / "csvs")
    return sorted(p.name for p in (c.dir / "csvs").iterdir())


def _write_loom(c):
    c.b.write_loom(c.dir / "x.loom", write_obsm_varm=True)


def _transpose(c):
    return result(c.b.T)


def _copy_python(c):
    import copy

    return state(copy.copy(c.b))


def _deepcopy(c):
    import copy

    copy.deepcopy(c.b)


OPERATIONS = {
    # reading X
    "read_X": lambda c: result(c.b.X),
    "X_handle": lambda c: {
        "type": type(c.b.X).__name__,
        "dtype": str(c.b.X.dtype),
        "shape": list(c.b.X.shape),
        "format": getattr(c.b.X, "format", None),
    },
    "X_len": lambda c: len(c.b.X),
    "X_ndim": lambda c: c.b.X.ndim,
    "X_asarray": lambda c: result(np.asarray(c.b.X)),
    "X_empty_tuple": getx(()),
    "X_colon": getx(slice(None)),
    "X_ellipsis": getx(Ellipsis),
    "X_row": getx(1),
    "X_row_colon": getx(tup(1, slice(None))),
    "X_col": getx(tup(slice(None), 1)),
    "X_scalar": getx(tup(1, 2)),
    "X_slice_rows": getx(slice(1, 3)),
    "X_slices": getx(tup(slice(1, 3), slice(0, 2))),
    "X_rows_list": getx([0, 2]),
    "X_rows_list_cols_slice": getx(tup([0, 2], slice(None))),
    "X_cols_list": getx(tup(slice(None), [0, 2])),
    "X_rows_bool": getx(np.array([True, False, True, False])),
    "X_rows_cols_lists": getx(tup([0, 2], [0, 1])),
    "X_rows_cols_lists_outer": getx(tup([3, 0], [0, 2])),
    "X_empty_list": getx([]),
    "X_unsorted_rows": getx([2, 0]),
    "X_duplicate_rows": getx([0, 0]),
    "X_negative_list": getx([-1, 0]),
    "X_negative_int": getx(-1),
    "X_negative_slice": getx(slice(-3, None)),
    "X_stop_negative_slice": getx(slice(None, -1)),
    "X_negative_cols_slice": getx(tup(slice(None), slice(-2, None))),
    "X_step_slice": getx(slice(None, None, 2)),
    "X_reverse_slice": getx(slice(None, None, -1)),
    "X_out_of_range_row": getx(10),
    "X_out_of_range_col": getx(tup(0, 10)),
    "X_out_of_range_slice": getx(slice(10, 20)),
    "X_three_indices": getx(tup(slice(None), slice(None), slice(None))),
    "X_none_index": getx(None),
    "X_string_index": getx("w"),
    "read_raw_X": _raw_x,
    "layers_none": _layers(None),
    "layers_other": _layers("l"),
    "metadata": _meta,
    # views
    "view": _view_state,
    "view_of_view": _view_of_view,
    "view_raw_X": _view_raw,
    "view_copy": view_op(lambda v, c: result(v.copy())),
    "view_copy_filename": view_op(
        lambda v, c: {"copy": state(v.copy(c.dir / "viewcopy.h5ad")),
                      "file": disk(c.dir / "viewcopy.h5ad")}
    ),
    "view_to_memory": _to_memory_view(False),
    "view_to_memory_copy": _to_memory_view(True),
    "view_write_new": _write_view("new"),
    "view_write_same": _write_view("same"),
    "view_filename_set": view_op(
        lambda v, c: setattr(v, "filename", c.dir / "v.h5ad")
    ),
    "view_X_assign": _view_modify(_view_x_assign),
    "view_obs_assign": _view_modify(_view_obs),
    "view_layers_set": _view_modify(_view_layer),
    "view_obs_names_set": _view_modify(_view_names),
    "view_X_item": _view_modify(_view_x_item),
    "view_chunk_X": view_op(lambda v, c: result(v.chunk_X([1]))),
    "view_chunked_X": view_op(
        lambda v, c: [{"start": s, "end": e, "chunk": result(x)} for x, s, e in v.chunked_X(1)]
    ),
    # assignment
    "X_assign_none": _x_none,
    "X_del": _x_del,
    "X_assign_csr": assign_x(lambda: sp.csr_matrix(new_x("dense"))),
    "X_assign_csc": assign_x(lambda: sp.csc_matrix(new_x("dense"))),
    "X_assign_small": assign_x(lambda: np.zeros((2, 2), dtype="float32")),
    "X_assign_reshape": assign_x(lambda: np.zeros((3, 4), dtype="float32")),
    "X_assign_flat": assign_x(lambda: np.arange(12, dtype="float32")),
    "X_assign_3d": assign_x(lambda: np.zeros((4, 3, 2), dtype="float32")),
    "X_assign_scalar": assign_x(1.0),
    "X_item": _x_item,
    "layers_none_assign": _layers_none_assign,
    "obs_assign": _slot_assign("obs", pd.DataFrame({"z": [1.0, 2.0, 3.0, 4.0]}, index=["w", "x", "y", "z"])),
    "uns_assign": _slot_assign("uns", {"a": 1}),
    "obsm_assign": _slot_assign("obsm", {"m": np.zeros((4, 2))}),
    "layers_set": _layer_set,
    "raw_X_assign": _raw_x_assign,
    "raw_assign": _raw_assign,
    "write_after_X_assign": _after_assign_then(_write_no_arg),
    "filename_after_X_assign": _after_assign_then(
        lambda c: setattr(c.b, "filename", c.dir / "x.h5ad")
    ),
    # to_memory and copy
    "to_memory": _to_memory(False),
    "to_memory_copy": _to_memory(True),
    "to_memory_closed": closed(_to_memory(False)),
    "copy": lambda c: result(c.b.copy()),
    "copy_filename": _copy_filename,
    "copy_filename_closed": closed(_copy_filename),
    "copy_same_path": lambda c: result(c.b.copy(c.path)),
    "copy_twice": _copy_twice,
    "copy_missing_dir": _copy_missing_dir,
    "copy_stdlib": _copy_python,
    "deepcopy": _deepcopy,
    "transpose": _transpose,
    # writing
    "write_no_arg": _write_no_arg,
    "write_same": _write_same,
    "write_new": _write_new("write"),
    "write_h5ad_new": _write_new("write_h5ad"),
    "write_h5ad_new_closed": closed(_write_new("write_h5ad")),
    "write_h5ad_missing_dir": _write_missing_dir,
    "write_obs_edit": _obs_edit_write,
    "write_gzip": _write_compressed("gzip"),
    "write_lzf": _write_compressed("lzf"),
    "write_as_dense": _write_as_dense,
    "write_zarr": _write_zarr,
    "write_csvs": _write_csvs,
    "write_loom": _write_loom,
    # filename
    "filename_same": _filename_same,
    "filename_none": _filename_none,
    "filename_none_twice": _filename_twice_none,
    "filename_new": _filename_new_open,
    "filename_new_closed": closed(_filename_new_open),
    "filename_missing_dir": _filename_missing_dir,
    # chunked_X and chunk_X
    "chunked_X_1": chunked(1),
    "chunked_X_3": chunked(3),
    "chunked_X_default": chunked(None),
    "chunked_X_large": chunked(100),
    "chunked_X_zero": chunked(0),
    "chunked_X_negative": chunked(-1),
    "chunked_X_float": chunked(1.5),
    "chunked_X_closed": closed(chunked(2)),
    "chunk_X_list": chunk_x([0, 2]),
    "chunk_X_tuple": chunk_x((1, 2)),
    "chunk_X_range": chunk_x(range(2)),
    "chunk_X_array": chunk_x(np.array([3, 1])),
    "chunk_X_unsorted_duplicates": chunk_x([2, 0, 2]),
    "chunk_X_negative": chunk_x([-1]),
    "chunk_X_int": chunk_x(2),
    "chunk_X_int_replace": chunk_x(3, replace=True),
    "chunk_X_int_large": chunk_x(10),
    "chunk_X_int_large_no_replace": chunk_x(10, replace=False),
    "chunk_X_zero": chunk_x(0),
    "chunk_X_empty": chunk_x([]),
    "chunk_X_default": chunk_x(),
    "chunk_X_none": chunk_x(None),
    "chunk_X_float": chunk_x(1.0),
    "chunk_X_numpy_int": chunk_x(np.int64(2)),
    "chunk_X_true": chunk_x(True),
    "chunk_X_negative_int": chunk_x(-1),
    "chunk_X_out_of_range": chunk_x([10]),
    "chunk_X_string": chunk_x("a"),
    "chunk_X_bool": chunk_x(np.array([True, False, True, False])),
    "chunk_X_closed": closed(chunk_x([0, 2])),
    # the file manager
    "close_then_X": _close_then(lambda c: c.b.X),
    "close_then_raw_X": _close_then(lambda c: None if c.b.raw is None else c.b.raw.X),
    "close_then_layers_none": _close_then(lambda c: c.b.layers[None]),
    "close_then_layers_other": _close_then(lambda c: c.b.layers["l"]),
    "close_then_view_X": _close_then(lambda c: view(c).X),
    "close_then_shape": _close_then(lambda c: list(c.b.shape)),
    "close_then_obs": _close_then(lambda c: c.b.obs),
    "close_then_repr": _repr_after_close,
    "close_twice": _close_twice,
    "stale_handle": _stale_handle,
    "file_open": _file_open,
    "file_open_other": _file_open_other,
    "file_open_bad_mode": _file_open_bad_mode,
    "file_open_missing": _file_open_missing,
    "file_setitem": _file_setitem,
    "file_delitem": _file_delitem,
    "file_contains": _file_contains,
    "file_iter": _file_iter,
    "file_getitem": _file_getitem,
    "file_getitem_missing": _file_getitem_missing,
    "repr": _repr,
}
OPERATIONS["X_assign_dense"] = lambda c: assign_x(new_x("dense"))(c)

# Operations that also run on a file with `raw`, because they write to the backing file
RAW_OPERATIONS = [
    "read_raw_X",
    "view_raw_X",
    "view_X_assign",
    "view_obs_assign",
    "raw_X_assign",
    "raw_assign",
    "to_memory",
    "copy_filename",
    "copy_same_path",
    "write_no_arg",
    "write_same",
    "write_new",
    "write_h5ad_new",
    "filename_none",
    "filename_new",
    "filename_same",
    "close_then_raw_X",
    "chunk_X_list",
    "view_write_new",
]


# In-memory objects and handles stored in memory

MEMORY_OPERATIONS = {
    "repr": _repr,
    "metadata": _meta,
    "file_open": _file_open,
    "file_close": lambda c: {"closed": c.b.file.close(), "is_open": bool(c.b.file.is_open)},
    "file_repr": lambda c: repr(c.b.file),
    "file_getitem": _file_getitem,
    "file_contains": lambda c: "X" in c.b.file,
    "file_iter": lambda c: list(c.b.file),
    "chunked_X_1": chunked(1),
    "chunked_X_3": chunked(3),
    "chunked_X_default": chunked(None),
    "chunked_X_zero": chunked(0),
    "chunked_X_negative": chunked(-1),
    "chunked_X_float": chunked(1.5),
    "chunked_X_X_none": lambda c: (setattr(c.b, "X", None), chunked(2)(c))[1],
    "chunk_X_list": chunk_x([0, 2]),
    "chunk_X_unsorted_duplicates": chunk_x([2, 0, 2]),
    "chunk_X_negative": chunk_x([-1]),
    "chunk_X_int": chunk_x(2),
    "chunk_X_int_replace": chunk_x(3, replace=True),
    "chunk_X_int_large": chunk_x(10),
    "chunk_X_int_large_no_replace": chunk_x(10, replace=False),
    "chunk_X_zero": chunk_x(0),
    "chunk_X_empty": chunk_x([]),
    "chunk_X_default": chunk_x(),
    "chunk_X_none": chunk_x(None),
    "chunk_X_float": chunk_x(1.0),
    "chunk_X_numpy_int": chunk_x(np.int64(2)),
    "chunk_X_true": chunk_x(True),
    "chunk_X_negative_int": chunk_x(-1),
    "chunk_X_out_of_range": chunk_x([10]),
    "chunk_X_string": chunk_x("a"),
    "chunk_X_bool": chunk_x(np.array([True, False, True, False])),
    "to_memory": lambda c: {
        "same_object": c.b.to_memory() is c.b,
        "X_shared": c.b.to_memory().X is c.b.X,
    },
    "to_memory_copy": lambda c: {
        "same_object": c.b.to_memory(copy=True) is c.b,
        "X_shared": c.b.to_memory(copy=True).X is c.b.X,
    },
    "copy_filename": lambda c: state(c.b.copy(c.dir / "copy.h5ad")),
    "copy_filename_written": lambda c: (
        c.b.copy(c.dir / "copy.h5ad"),
        {"exists": (c.dir / "copy.h5ad").exists()},
    )[1],
    "filename_set_new": lambda c: (
        setattr(c.b, "filename", c.dir / "mem.h5ad"),
        {"state": state(c.b), "X": result(c.b.X), "layers": plain(dict(c.b.layers)),
         "file": disk(c.dir / "mem.h5ad"), "X_on_disk_is_dataset": _x_is_dataset(c.dir / "mem.h5ad")},
    )[1],
    "filename_set_none": lambda c: (setattr(c.b, "filename", None), state(c.b))[1],
    "filename_set_new_X_none": lambda c: (
        setattr(c.b, "X", None),
        setattr(c.b, "filename", c.dir / "mem.h5ad"),
    )[1],
    "filename_set_missing_dir": lambda c: setattr(c.b, "filename", c.dir / "nodir" / "x.h5ad"),
    "copy_with_handle": lambda c: _copy_with_handle(c),
    "to_memory_with_handle": lambda c: _to_memory_with_handle(c),
}


def _x_is_dataset(path):
    with h5py.File(path) as f:
        return isinstance(f["X"], h5py.Dataset)


def _copy_with_handle(c):
    f = h5py.File(c.path, "r")
    try:
        a = ad.AnnData(np.zeros((4, 3), dtype="float32"))
        a.layers["h"] = f["X"]
        a.copy()
    finally:
        f.close()


def _to_memory_with_handle(c):
    f = h5py.File(c.path, "r")
    try:
        a = ad.AnnData(np.zeros((4, 3), dtype="float32"))
        a.layers["h"] = f["X"]
        return result(a.to_memory().layers["h"])
    finally:
        f.close()


def run_memory_cases():
    out = {}
    for kind in KINDS:
        out[kind] = {
            name: run(op, kind, "r", backed=False) for name, op in MEMORY_OPERATIONS.items()
        }
    return out


# read_h5ad(backed=)


def read_backed_cases():
    out = {}
    d = ROOT / "read"
    d.mkdir()
    path = d / "file.h5ad"
    make_file("csr", path)
    for label, value in {
        "true": True,
        "r": "r",
        "r+": "r+",
        "a": "a",
        "w": "w",
        "rb": "rb",
        "upper_R": "R",
        "empty": "",
        "one": 1,
        "false": False,
        "none": None,
        "zero": 0,
    }.items():
        with warnings.catch_warnings(record=True) as caught:
            warnings.simplefilter("always")
            try:
                a = ad.read_h5ad(path, backed=value)
                res = {"state": state(a), "X": result(a.X) if not a.isbacked else {"type": type(a.X).__name__}}
                a.file.close()
                error = None
            except BaseException as e:  # noqa: BLE001
                res, error = None, {"type": type(e).__name__, "message": str(e)}
        out[label] = {
            "error": error,
            "result": res,
            "warnings": [{"category": w.category.__name__, "message": str(w.message)} for w in caught],
        }
    try:
        ad.read_h5ad(d / "missing.h5ad", backed="r")
    except Exception as e:  # noqa: BLE001
        out["missing_file"] = {"error": {"type": type(e).__name__, "message": str(e)}}
    a = ad.read_h5ad(path, backed="r", as_sparse=("X",))
    out["as_sparse_ignored"] = {"state": state(a)}
    a.file.close()
    # constructor errors
    for label, kwargs in {
        "file_and_name": {"filename": h5py.File(d / "h5file.h5", "w"), "filemode": "r"},
        "filename_no_mode": {"filename": path},
    }.items():
        try:
            ad.AnnData(**kwargs)
        except Exception as e:  # noqa: BLE001
            out["constructor_" + label] = {"error": {"type": type(e).__name__, "message": str(e)}}
    out["repr"] = {"file_manager": "see operations"}
    return json.loads(json.dumps(out).replace(str(d.resolve()), "<dir>").replace(str(d), "<dir>"))


# read_elem_partial


def partial_cases():
    d = ROOT / "partial"
    d.mkdir()
    out = {}
    for kind in KINDS:
        path = d / f"{kind}.h5ad"
        make_file(kind, path)
        with h5py.File(path, "r") as f:
            out[kind] = {}

            def p(label, **kwargs):
                elem = kwargs.pop("elem")
                try:
                    out[kind][label] = {"result": result(read_elem_partial(f[elem], **kwargs))}
                except Exception as e:  # noqa: BLE001
                    out[kind][label] = {"error": {"type": type(e).__name__, "message": str(e)}}

            p("X_default", elem="X")
            p("X_rows", elem="X", indices=(slice(1, 3), slice(None)))
            p("X_slices", elem="X", indices=(slice(1, 3), slice(0, 2)))
            p("X_list_rows", elem="X", indices=([0, 2], slice(None)))
            p("X_list_cols", elem="X", indices=(slice(None), [0, 2]))
            p("X_outer_lists", elem="X", indices=([2, 0], [1, 2]))
            p("X_unsorted", elem="X", indices=([2, 0], slice(None)))
            p("X_bool", elem="X", indices=(np.array([True, False, True, False]), slice(None)))
            p("X_int_row", elem="X", indices=(1, slice(None)))
            p("X_out_of_range_int", elem="X", indices=(10, slice(None)))
            p("X_out_of_range_slice", elem="X", indices=(slice(10, 20), slice(None)))
            p("X_three_indices", elem="X", indices=(slice(None),) * 3)
            p("X_bare_slice", elem="X", indices=slice(1, 3))
            p("layer_rows", elem="layers/l", indices=(slice(0, 2), slice(None)))
            p("obs_default", elem="obs")
            # dataframes take (rows, columns) and categoricals a 1-tuple
            p("obs_rows", elem="obs", indices=(slice(1, 3), slice(None)))
            p("obs_list", elem="obs", indices=([0, 2], slice(None)))
            p("obs_unsorted", elem="obs", indices=([2, 0], slice(None)))
            p("obs_items", elem="obs", items=["g"], indices=(slice(1, 3), slice(None)))
            p("obs_items_missing", elem="obs", items=["zz"], indices=(slice(1, 3), slice(None)))
            p("obs_items_empty", elem="obs", items=[], indices=(slice(1, 3), slice(None)))
            p("obs_bare_slice", elem="obs", indices=slice(1, 3))
            p("obs_index", elem="obs/_index", indices=(slice(1, 3),))
            p("obs_categorical", elem="obs/g", indices=(slice(1, 3),))
            p("obs_categorical_bare_slice", elem="obs/g", indices=slice(1, 3))
            p("obs_categorical_default", elem="obs/g")
            p("var_rows", elem="var", indices=(slice(0, 2), slice(None)))
            p("uns_dict", elem="uns")
            p("root", elem="/")
    # element types without a partial reader
    path = d / "other.h5ad"
    a = ad.AnnData(np.zeros((4, 3), dtype="float32"), uns={"s": "text", "n": 1, "d": {"a": 1}})
    a.write_h5ad(path)
    out["other"] = {}
    with h5py.File(path, "r") as f:
        for key in ["uns/s", "uns/n", "uns/d"]:
            try:
                out["other"][key] = {"result": result(read_elem_partial(f[key]))}
            except Exception as e:  # noqa: BLE001
                out["other"][key] = {"error": {"type": type(e).__name__, "message": str(e)}}
        try:
            read_elem_partial(np.zeros(3))
        except Exception as e:  # noqa: BLE001
            out["other"]["ndarray"] = {"error": {"type": type(e).__name__, "message": str(e)}}
    return json.loads(json.dumps(out).replace(str(d.resolve()), "<dir>").replace(str(d), "<dir>"))


# sparse_dataset


def sparse_dataset_cases():
    d = ROOT / "sparse"
    d.mkdir()
    out = {}
    for kind in ["csr", "csc"]:
        path = d / f"{kind}.h5ad"
        make_file(kind, path)
        out[kind] = {}

        def attempt(label, fn):
            with h5py.File(path, "r") as f:
                handle = sparse_dataset(f["X"])
                try:
                    out[kind][label] = {"result": result(fn(handle))}
                except Exception as e:  # noqa: BLE001
                    out[kind][label] = {"error": {"type": type(e).__name__, "message": str(e)}}

        attempt("repr", lambda h: repr(h))
        attempt("shape", lambda h: list(h.shape))
        attempt("format", lambda h: h.format)
        attempt("backend", lambda h: h.backend)
        attempt("dtype", lambda h: str(h.dtype))
        attempt("to_memory", lambda h: h.to_memory())
        attempt("to_memory_indices", lambda h: {"indices": h.to_memory().indices.dtype.name})
        attempt("all", lambda h: h[...])
        attempt("rows", lambda h: h[1:3])
        attempt("cell", lambda h: h[1, 2])
        attempt("empty_list", lambda h: h[[]])
        attempt("outer", lambda h: h[[3, 0], [0, 2]])
        attempt("set_shape", lambda h: setattr(h, "shape", (1, 1)))
        attempt("set_group", lambda h: setattr(h, "group", h._group))
        attempt("len", lambda h: len(h))
        attempt("no_cache", lambda h: type(sparse_dataset(h.group, should_cache_indptr=False)).__name__)
        attempt("positional", lambda h: sparse_dataset(h.group, True))
        # appending, each on a fresh copy so a failed append cannot affect the next
        for label, value in {
            "append_same": lambda: sp.csr_matrix(np.ones((2, 3), dtype="float32"))
            if kind == "csr"
            else sp.csc_matrix(np.ones((4, 2), dtype="float32")),
            "append_other_format": lambda: sp.csc_matrix(np.ones((2, 3), dtype="float32"))
            if kind == "csr"
            else sp.csr_matrix(np.ones((4, 2), dtype="float32")),
            "append_coo": lambda: sp.coo_matrix(np.ones((2, 3), dtype="float32")),
            "append_dense": lambda: np.ones((2, 3), dtype="float32"),
            "append_empty": lambda: sp.csr_matrix((0, 3), dtype="float32")
            if kind == "csr"
            else sp.csc_matrix((4, 0), dtype="float32"),
            "append_wrong_size": lambda: sp.csr_matrix(np.ones((2, 5), dtype="float32"))
            if kind == "csr"
            else sp.csc_matrix(np.ones((5, 2), dtype="float32")),
            "append_float64": lambda: (sp.csr_matrix if kind == "csr" else sp.csc_matrix)(
                np.ones((2, 3) if kind == "csr" else (4, 2), dtype="float64")
            ),
        }.items():
            target = d / f"{kind}-{label}.h5ad"
            shutil.copy(path, target)
            with h5py.File(target, "r+") as f:
                handle = sparse_dataset(f["X"])
                try:
                    handle.append(value())
                    out[kind][label] = {"shape": list(handle.shape),
                                        "attr_shape": [int(i) for i in f["X"].attrs["shape"]],
                                        "data_dtype": str(f["X/data"].dtype)}
                    out[kind][label]["after"] = plain(sparse_dataset(f["X"]).to_memory())
                except Exception as e:  # noqa: BLE001
                    out[kind][label] = {"error": {"type": type(e).__name__, "message": str(e)}}
        target = d / f"{kind}-append_closed_r.h5ad"
        shutil.copy(path, target)
        with h5py.File(target, "r") as f:
            handle = sparse_dataset(f["X"])
            try:
                handle.append(
                    sp.csr_matrix(np.ones((2, 3), dtype="float32"))
                    if kind == "csr"
                    else sp.csc_matrix(np.ones((4, 2), dtype="float32"))
                )
                out[kind]["append_read_only"] = {"shape": list(handle.shape)}
            except Exception as e:  # noqa: BLE001
                out[kind]["append_read_only"] = {"error": {"type": type(e).__name__, "message": str(e)}}
    # groups that are not sparse
    path = d / "other.h5ad"
    a = ad.AnnData(np.zeros((4, 3), dtype="float32"), uns={"d": {"a": 1}})
    a.write_h5ad(path)
    out["not_sparse"] = {}
    with h5py.File(path, "r") as f:
        for label, fn in {
            "dense_array": lambda: sparse_dataset(f["X"]),
            "dict_group": lambda: sparse_dataset(f["uns/d"]),
            "ndarray": lambda: sparse_dataset(np.zeros(3)),
            "dict": lambda: sparse_dataset({}),
        }.items():
            try:
                out["not_sparse"][label] = {"result": result(fn())}
            except Exception as e:  # noqa: BLE001
                out["not_sparse"][label] = {"error": {"type": type(e).__name__, "message": str(e)}}
    # a CSR matrix written as the h5sparse legacy format
    path = d / "legacy.h5"
    with h5py.File(path, "w") as f:
        g = f.create_group("X")
        m = sp.csr_matrix(np.arange(1, 13, dtype="float32").reshape(4, 3))
        g.create_dataset("data", data=m.data)
        g.create_dataset("indices", data=m.indices)
        g.create_dataset("indptr", data=m.indptr)
        g.attrs["h5sparse_format"] = "csr"
        g.attrs["h5sparse_shape"] = m.shape
        out["legacy_attributes"] = result(sparse_dataset(g)[...])
    return json.loads(json.dumps(out).replace(str(d.resolve()), "<dir>").replace(str(d), "<dir>"))


# the setting min_rows_for_chunked_h5_copy


def settings_cases():
    d = ROOT / "settings"
    d.mkdir()
    out = {"default": ad.settings.min_rows_for_chunked_h5_copy, "invalid": {}, "slices": {}}
    for label, value in {"zero": 0, "negative": -1, "float": 1.5, "string": "a", "none": None}.items():
        try:
            ad.settings.min_rows_for_chunked_h5_copy = value
            out["invalid"][label] = {"accepted": True}
        except Exception as e:  # noqa: BLE001
            out["invalid"][label] = {"error": {"type": type(e).__name__}}
        ad.settings.reset("min_rows_for_chunked_h5_copy")

    def rows_read(setting, chunks=None, compression=None):
        path = d / f"s{setting}-{chunks}-{compression}.h5ad"
        with h5py.File(path, "w") as f:
            pass
        adata = ad.AnnData(np.arange(75, dtype="float32").reshape(25, 3))
        adata.write_h5ad(path)
        if chunks:
            with h5py.File(path, "r+") as f:
                data = f["X"][()]
                del f["X"]
                f.create_dataset("X", data=data, chunks=chunks)
                f["X"].attrs["encoding-type"] = "array"
                f["X"].attrs["encoding-version"] = "0.2.0"
        b = ad.read_h5ad(path, backed="r")
        seen = []
        original = h5py.Dataset.__getitem__

        def spy(self, key):
            if self.name == "/X":
                seen.append(key)
            return original(self, key)

        h5py.Dataset.__getitem__ = spy
        try:
            with ad.settings.override(min_rows_for_chunked_h5_copy=setting):
                b.write_h5ad(d / "out.h5ad", compression=compression)
        finally:
            h5py.Dataset.__getitem__ = original
        b.file.close()
        return [plain(k) if not isinstance(k, tuple) else [repr(s) for s in k] for k in seen]

    for setting in [1, 7, 10, 25, 26, 1000]:
        out["slices"][f"setting_{setting}"] = rows_read(setting)
    out["slices"]["chunked_source_5_setting_3"] = rows_read(3, chunks=(5, 3))
    out["slices"]["chunked_source_10_setting_20"] = rows_read(20, chunks=(10, 3))
    out["slices"]["gzip_destination"] = rows_read(10, compression="gzip")
    return out


def check_coverage():
    """A new public name in a later Python version must be covered here."""
    manager = {n for n in dir(AnnDataFileManager) if not n.startswith("_")}
    assert manager == {"open", "close", "filename", "is_open"}, sorted(manager)
    sparse = {n for n in dir(BaseCompressedSparseDataset) if not n.startswith("_")}
    assert sparse == {"append", "backend", "dtype", "group", "shape", "to_memory"}, sorted(
        sparse
    )
    for name in ["isbacked", "filename", "to_memory", "chunked_X", "chunk_X", "copy", "write"]:
        assert hasattr(ad.AnnData, name), name


def main(path):
    check_coverage()
    out = {"operations": {}, "raw_operations": {}}
    for name, operation in OPERATIONS.items():
        out["operations"][name] = {
            kind: {mode: run(operation, kind, mode) for mode in MODES} for kind in KINDS
        }
    for name in RAW_OPERATIONS:
        out["raw_operations"][name] = {
            kind: {mode: run(OPERATIONS[name], kind, mode, raw=True) for mode in MODES}
            for kind in KINDS
        }
    out["in_memory"] = run_memory_cases()
    out["read_h5ad"] = read_backed_cases()
    out["read_elem_partial"] = partial_cases()
    out["sparse_dataset"] = sparse_dataset_cases()
    out["settings"] = settings_cases()
    shutil.rmtree(ROOT, ignore_errors=True)
    with open(path, "w") as f:
        json.dump(out, f, indent=1, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main(sys.argv[1])
