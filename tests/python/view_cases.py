"""Write Python's behaviour for operations on Views as JSON.

Usage: view_cases.py OUTPUT.json

Each operation runs on a fresh parent and View (rows 0 and 2 of 4, columns 0 and
2 of 3, unless the operation builds its own), and records the warnings raised,
any error, `is_view` afterwards, a summary of the View, and whether the parent
changed.
Every public name of `AnnData` must be covered or listed in `NOT_OPERATIONS`,
so a new method in a later Python version fails here.
The R equivalents are in tests/testthat/test-views.R.
"""

import json
import sys
import tempfile
import warnings
from pathlib import Path

import anndata as ad
import numpy as np
import pandas as pd
import scipy.sparse as sp


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
    if isinstance(x, (np.integer,)):
        return int(x)
    if isinstance(x, (np.floating, float)):
        return None if np.isnan(x) else float(x)
    if isinstance(x, (np.bool_,)):
        return bool(x)
    if x is None or isinstance(x, (bool, int, str)):
        return x
    return repr(x)


def mapping(m):
    return {str(k): plain(m[k]) for k in m.keys()}


def summary(adata):
    """Everything observable about an AnnData, for comparing before and after."""
    out = {
        "is_view": bool(adata.is_view),
        "shape": [int(adata.n_obs), int(adata.n_vars)],
        "obs_names": plain(adata.obs_names),
        "var_names": plain(adata.var_names),
        "X": plain(adata.X),
        "obs": plain(adata.obs),
        "var": plain(adata.var),
        "layers": mapping(adata.layers),
        "obsm": mapping(adata.obsm),
        "varm": mapping(adata.varm),
        "obsp": mapping(adata.obsp),
        "varp": mapping(adata.varp),
        "uns": plain(dict(adata.uns)),
    }
    if adata.raw is None:
        out["raw"] = None
    else:
        out["raw"] = {
            "X": plain(adata.raw.X),
            "var": plain(adata.raw.var),
            "var_names": plain(adata.raw.var_names),
            "shape": [int(s) for s in adata.raw.shape],
        }
    return out


def make_parent():
    """A parent with every Slot filled, and categories that a View leaves unused."""
    obs = pd.DataFrame(
        {
            "num": [1.0, 2.0, 3.0, 4.0],
            "cat": pd.Categorical(["a", "b", "c", "a"], categories=["a", "b", "c"]),
        },
        index=["o0", "o1", "o2", "o3"],
    )
    var = pd.DataFrame({"gene": [10.0, 20.0, 30.0]}, index=["v0", "v1", "v2"])
    adata = ad.AnnData(
        np.arange(12, dtype="float64").reshape(4, 3),
        obs=obs,
        var=var,
        layers={
            "counts": np.arange(12, dtype="float64").reshape(4, 3) * 10,
            "sparse": sp.csr_matrix(np.arange(12, dtype="float64").reshape(4, 3) + 1),
        },
        obsm={"pca": np.arange(8, dtype="float64").reshape(4, 2)},
        varm={"pcs": np.arange(6, dtype="float64").reshape(3, 2)},
        obsp={"conn": np.arange(16, dtype="float64").reshape(4, 4)},
        varp={"corr": np.arange(9, dtype="float64").reshape(3, 3)},
        uns={
            "u": 1,
            "nested": {"k": [1, 2, 3]},
            "cat_colors": ["red", "green", "blue"],
        },
    )
    adata.raw = adata
    return adata


def make_view(parent):
    return parent[[0, 2], [0, 2]]


def make_view_of_view(parent):
    return make_view(parent)[[1], :]


# Operations: each takes (view, parent) and returns an optional value to record.


def _set_attr(name, value):
    def op(view, parent):
        setattr(view, name, value() if callable(value) else value)

    return op


def _del_attr(name):
    def op(view, parent):
        delattr(view, name)

    return op


def _x_item(view, parent):
    view.X[0, 0] = -1.0


def _layer_item(view, parent):
    view.layers["counts"][0, 0] = -1.0


def _layer_set(view, parent):
    view.layers["new"] = np.ones(view.shape)


def _layer_del(view, parent):
    del view.layers["counts"]


def _obs_col_set(view, parent):
    view.obs["new"] = [1.0, 2.0]


def _obs_col_item(view, parent):
    view.obs["num"].iloc[0] = -1.0


def _obs_col_del(view, parent):
    del view.obs["num"]


def _var_col_set(view, parent):
    view.var["new"] = [1.0, 2.0]


def _var_col_del(view, parent):
    del view.var["gene"]


def _obs_assign(view, parent):
    view.obs = pd.DataFrame({"z": [1.0, 2.0]}, index=view.obs_names)


def _var_assign(view, parent):
    view.var = pd.DataFrame({"z": [1.0, 2.0]}, index=view.var_names)


def _obsm_set(view, parent):
    view.obsm["new"] = np.ones((2, 2))


def _obsm_item(view, parent):
    view.obsm["pca"][0, 0] = -1.0


def _obsm_del(view, parent):
    del view.obsm["pca"]


def _varm_set(view, parent):
    view.varm["new"] = np.ones((2, 2))


def _varm_del(view, parent):
    del view.varm["pcs"]


def _obsp_set(view, parent):
    view.obsp["new"] = np.ones((2, 2))


def _obsp_del(view, parent):
    del view.obsp["conn"]


def _varp_set(view, parent):
    view.varp["new"] = np.ones((2, 2))


def _varp_del(view, parent):
    del view.varp["corr"]


def _uns_set(view, parent):
    view.uns["new"] = 5


def _uns_modify(view, parent):
    view.uns["u"] = 2


def _uns_nested(view, parent):
    view.uns["nested"]["k"] = [9]


def _uns_del(view, parent):
    del view.uns["u"]


def _uns_assign(view, parent):
    view.uns = {"only": 1}


def _raw_assign(view, parent):
    view.raw = view


def _obs_names_set(view, parent):
    view.obs_names = ["p", "q"]


def _var_names_set(view, parent):
    view.var_names = ["p", "q"]


def _obs_names_make_unique(view, parent):
    view.obs_names = ["p", "p"]
    view.obs_names_make_unique()


def _var_names_make_unique(view, parent):
    view.var_names = ["p", "p"]
    view.var_names_make_unique()


def _strings_to_categoricals(view, parent):
    view.obs["s"] = ["x", "y"]
    view.strings_to_categoricals()


def _strings_to_categoricals_nothing(view, parent):
    view.strings_to_categoricals()


def _rename_categories(view, parent):
    view.rename_categories("cat", ["A", "B"])


def _write(fmt):
    def op(view, parent):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / f"view.{fmt}"
            if fmt == "h5ad":
                view.write_h5ad(path)
                back = ad.read_h5ad(path)
            else:
                view.write_zarr(path)
                back = ad.read_zarr(path)
            return {"written": summary(back)}

    return op


def _write_csvs(view, parent):
    with tempfile.TemporaryDirectory() as tmp:
        view.write_csvs(Path(tmp) / "csvs")
        return {"files": sorted(p.name for p in (Path(tmp) / "csvs").iterdir())}


def _write_loom(view, parent):
    # write_obsm_varm stops write_loom printing notes about the fields it drops
    with tempfile.TemporaryDirectory() as tmp:
        view.write_loom(Path(tmp) / "view.loom", write_obsm_varm=True)


def _write_alias(view, parent):
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "view.h5ad"
        view.write(path)
        return {"written": summary(ad.read_h5ad(path))}


def _chunked(view, parent):
    return [plain(c) for c in view.chunked_X(1)]


def _chunk_x(view, parent):
    return plain(view.chunk_X(select=[0]))


def _rows_view(view, parent):
    return {"view_of_view": summary(view[[1], :])}


def _by_name(view, parent):
    return {"by_name": summary(view[["o2"], ["v0"]])}


def _by_bool(view, parent):
    return {"by_bool": summary(view[np.array([True, False]), :])}


def _by_slice(view, parent):
    return {"by_slice": summary(view[1:, :])}


def _parent_ref(view, parent):
    return {"adata_ref_is_parent": view._adata_ref is parent}


def _vv_parent_ref(view, parent):
    sub = view[[1], :]
    return {"adata_ref_is_parent": sub._adata_ref is parent, "is_view": sub.is_view}


def _parent_x_new(view, parent):
    parent.X = np.zeros((4, 3))


def _parent_x_item(view, parent):
    parent.X[0, 0] = -99.0


def _parent_layer_item(view, parent):
    parent.layers["counts"][0, 0] = -99.0


def _parent_layer_set(view, parent):
    parent.layers["counts"] = np.zeros((4, 3))


def _parent_obs_col(view, parent):
    parent.obs["num"] = [-1.0, -2.0, -3.0, -4.0]


def _parent_obs_new_col(view, parent):
    parent.obs["new"] = [1, 2, 3, 4]


def _parent_var_col(view, parent):
    parent.var["gene"] = [-1.0, -2.0, -3.0]


def _parent_obsm_item(view, parent):
    parent.obsm["pca"][0, 0] = -99.0


def _parent_obsm_new(view, parent):
    parent.obsm["pca"] = np.zeros((4, 2))


def _parent_obsp_item(view, parent):
    parent.obsp["conn"][0, 0] = -99.0


def _parent_uns(view, parent):
    parent.uns["u"] = 99


def _parent_uns_nested(view, parent):
    parent.uns["nested"]["k"].append(99)


def _parent_raw(view, parent):
    parent.raw = None


def _parent_obs_names(view, parent):
    parent.obs_names = ["a", "b", "c", "d"]


OPERATIONS = {
    # reading never warns or copies
    "read_X": lambda v, p: plain(v.X),
    "read_obs": lambda v, p: plain(v.obs),
    "read_var": lambda v, p: plain(v.var),
    "read_layers": lambda v, p: mapping(v.layers),
    "read_obsm": lambda v, p: mapping(v.obsm),
    "read_varm": lambda v, p: mapping(v.varm),
    "read_obsp": lambda v, p: mapping(v.obsp),
    "read_varp": lambda v, p: mapping(v.varp),
    "read_uns": lambda v, p: plain(dict(v.uns)),
    "read_raw": lambda v, p: plain(v.raw.X),
    "read_obs_names": lambda v, p: plain(v.obs_names),
    "read_var_names": lambda v, p: plain(v.var_names),
    "shape": lambda v, p: list(v.shape),
    "len": lambda v, p: len(v),
    "contains": lambda v, p: "v0" in v,
    "repr": lambda v, p: repr(v),
    "isview_alias": lambda v, p: bool(v.isview),
    "isbacked": lambda v, p: bool(v.isbacked),
    "filename": lambda v, p: plain(v.filename),
    "to_df": lambda v, p: plain(v.to_df()),
    "to_df_layer": lambda v, p: plain(v.to_df(layer="counts")),
    "obs_vector": lambda v, p: plain(v.obs_vector("num")),
    "var_vector": lambda v, p: plain(v.var_vector("o0")),
    "obs_keys": lambda v, p: plain(v.obs_keys()),
    "var_keys": lambda v, p: plain(v.var_keys()),
    "obsm_keys": lambda v, p: plain(v.obsm_keys()),
    "varm_keys": lambda v, p: plain(v.varm_keys()),
    "uns_keys": lambda v, p: plain(v.uns_keys()),
    "unwriteable": lambda v, p: plain(v.unwriteable()),
    "chunked_X": _chunked,
    "chunk_X": _chunk_x,
    # new Views
    "subset_rows": _rows_view,
    "subset_by_name": _by_name,
    "subset_by_bool": _by_bool,
    "subset_by_slice": _by_slice,
    "parent_ref": _parent_ref,
    "view_of_view_parent": _vv_parent_ref,
    # whole-object operations
    "copy": lambda v, p: {"copy": summary(v.copy())},
    "to_memory": lambda v, p: {"to_memory": summary(v.to_memory())},
    "transpose": lambda v, p: summary(v.transpose()),
    "T": lambda v, p: summary(v.T),
    "write_h5ad": _write("h5ad"),
    "write_zarr": _write("zarr"),
    "write": _write_alias,
    "write_csvs": _write_csvs,
    "write_loom": _write_loom,
    # assignment, X
    "X_assign": _set_attr("X", lambda: np.full((2, 2), 7.0)),
    "X_assign_none": _set_attr("X", None),
    "X_assign_wrong_shape": _set_attr("X", lambda: np.zeros((3, 3))),
    "X_item": _x_item,
    "X_del": _del_attr("X"),
    # layers
    "layers_set": _layer_set,
    "layers_item": _layer_item,
    "layers_del": _layer_del,
    "layers_assign": _set_attr("layers", lambda: {"only": np.ones((2, 2))}),
    # obs and var
    "obs_assign": _obs_assign,
    "obs_col_set": _obs_col_set,
    "obs_col_item": _obs_col_item,
    "obs_col_del": _obs_col_del,
    "var_assign": _var_assign,
    "var_col_set": _var_col_set,
    "var_col_del": _var_col_del,
    # aligned mappings
    "obsm_set": _obsm_set,
    "obsm_item": _obsm_item,
    "obsm_del": _obsm_del,
    "obsm_assign": _set_attr("obsm", lambda: {"only": np.ones((2, 2))}),
    "varm_set": _varm_set,
    "varm_del": _varm_del,
    "obsp_set": _obsp_set,
    "obsp_del": _obsp_del,
    "varp_set": _varp_set,
    "varp_del": _varp_del,
    # uns
    "uns_set": _uns_set,
    "uns_modify": _uns_modify,
    "uns_nested": _uns_nested,
    "uns_del": _uns_del,
    "uns_assign": _uns_assign,
    # raw
    "raw_assign": _raw_assign,
    "raw_del": _del_attr("raw"),
    "raw_assign_none": _set_attr("raw", None),
    # names
    "obs_names_set": _obs_names_set,
    "var_names_set": _var_names_set,
    "obs_names_make_unique": _obs_names_make_unique,
    "var_names_make_unique": _var_names_make_unique,
    # methods that modify
    "strings_to_categoricals": _strings_to_categoricals,
    "strings_to_categoricals_nothing": _strings_to_categoricals_nothing,
    "rename_categories": _rename_categories,
    # the parent changes after the View was created
    "parent_X_new": _parent_x_new,
    "parent_X_item": _parent_x_item,
    "parent_layer_item": _parent_layer_item,
    "parent_layer_set": _parent_layer_set,
    "parent_obs_col": _parent_obs_col,
    "parent_obs_new_col": _parent_obs_new_col,
    "parent_var_col": _parent_var_col,
    "parent_obsm_item": _parent_obsm_item,
    "parent_obsm_new": _parent_obsm_new,
    "parent_obsp_item": _parent_obsp_item,
    "parent_uns": _parent_uns,
    "parent_uns_nested": _parent_uns_nested,
    "parent_raw": _parent_raw,
    "parent_obs_names": _parent_obs_names,
}

# Public names of AnnData that are not operations, or are covered under another name
NOT_OPERATIONS = {
    "T": "transpose",
    "X": "read_X, X_assign",
    "filename": "filename",
    "is_view": "recorded for every operation",
    "isview": "isview_alias",
    "isbacked": "isbacked",
    "layers": "read_layers, layers_set",
    "n_obs": "shape",
    "n_vars": "shape",
    "obs": "read_obs, obs_assign",
    "obs_names": "read_obs_names, obs_names_set",
    "obsm": "read_obsm, obsm_set",
    "obsp": "read_obsp, obsp_set",
    "raw": "read_raw, raw_assign",
    "shape": "shape",
    "uns": "read_uns, uns_set",
    "var": "read_var, var_assign",
    "var_names": "read_var_names, var_names_set",
    "varm": "read_varm, varm_set",
    "varp": "read_varp, varp_set",
}
METHODS = {
    "chunk_X": "chunk_X",
    "chunked_X": "chunked_X",
    "copy": "copy",
    "obs_keys": "obs_keys",
    "obs_names_make_unique": "obs_names_make_unique",
    "obs_vector": "obs_vector",
    "obsm_keys": "obsm_keys",
    "rename_categories": "rename_categories",
    "strings_to_categoricals": "strings_to_categoricals",
    "to_df": "to_df",
    "to_memory": "to_memory",
    "transpose": "transpose",
    "uns_keys": "uns_keys",
    "unwriteable": "unwriteable",
    "var_keys": "var_keys",
    "var_names_make_unique": "var_names_make_unique",
    "var_vector": "var_vector",
    "varm_keys": "varm_keys",
    "write": "write",
    "write_csvs": "write_csvs",
    "write_h5ad": "write_h5ad",
    "write_loom": "write_loom",
    "write_zarr": "write_zarr",
}


def check_coverage():
    public = {n for n in dir(ad.AnnData) if not n.startswith("_")}
    known = set(NOT_OPERATIONS) | set(METHODS)
    missing = public - known
    if missing:
        raise SystemExit(f"AnnData names not covered by view_cases.py: {sorted(missing)}")
    for name in METHODS.values():
        if name not in OPERATIONS:
            raise SystemExit(f"No operation named {name}")


def run(name, operation, build):
    parent = make_parent()
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        view = build(parent)
        before_view = summary(view)
    before_parent = summary(parent)
    result = None
    error = None
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        try:
            result = operation(view, parent)
        except Exception as e:  # noqa: BLE001 - the error is the observation
            error = {"type": type(e).__name__, "message": str(e)}
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        after_view = summary(view)
        after_parent = summary(parent)
    # The summaries are only kept when they differ from the start, to keep the table small
    return {
        "warnings": [
            {"category": w.category.__name__, "message": str(w.message)} for w in caught
        ],
        "error": error,
        "result": plain(result),
        "is_view_after": after_view["is_view"],
        "view_after": after_view if before_view != after_view else None,
        "view_changed": before_view != after_view,
        "parent_changed": before_parent != after_parent,
        "parent_after": after_parent if before_parent != after_parent else None,
    }


def main(path):
    check_coverage()
    out = {
        "parent": summary(make_parent()),
        "view": summary(make_view(make_parent())),
        "view_of_view_start": summary(make_view_of_view(make_parent())),
        "operations": {},
        "view_of_view": {},
    }
    for name, operation in OPERATIONS.items():
        out["operations"][name] = run(name, operation, make_view)
    # The same operations on a View of a View (modifications and reads only)
    for name in OPERATIONS:
        if name.startswith("parent_") or name in ("subset_rows", "view_of_view_parent"):
            continue
        out["view_of_view"][name] = run(name, OPERATIONS[name], make_view_of_view)
    # Views of Views compose against the original parent
    parent = make_parent()
    chain = parent[[3, 2, 1, 0], :][[1, 3], :][[1], [2, 0]]
    out["composition"] = {
        "obs_names": plain(chain.obs_names),
        "var_names": plain(chain.var_names),
        "X": plain(chain.X),
        "is_view": bool(chain.is_view),
        "ref_is_parent": chain._adata_ref is parent,
    }
    with open(path, "w") as f:
        json.dump(out, f, indent=2, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main(sys.argv[1])
