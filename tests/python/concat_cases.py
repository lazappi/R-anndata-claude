"""Write Python's concat results for a table of input combinations as JSON.

Usage: concat_cases.py OUTPUT.json

The output has `inputs` (every input object, described in full so R can rebuild
it) and `cases` (rows of `inputs` names, `concat()` arguments and the result:
values, On-disk dtypes, sparse format, names, categories, warnings and errors).
All cases are built in one run, because each Python start is slow.
The R equivalents are in tests/testthat/test-concat.R (from ticket concat/02).
Some errors recorded here are accidents of Python's internals (for example the
pandas error of `keys_wrong_length` and the `AttributeError` of `not_anndata`),
so the R port decides deliberately what to raise for them.
"""

import json
import sys
import warnings
from importlib.metadata import version

import anndata as ad
import numpy as np
import pandas as pd
import scipy.sparse as sp


def plain(x):
    """Convert a value to something `json` can write."""
    if isinstance(x, pd.DataFrame):
        return frame(x)
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
    if x is pd.NA or x is None:
        return None
    if isinstance(x, (bool, int, str)):
        return x
    return repr(x)


def array(x):
    """Describe a matrix: class, sparse format, dtype, shape and dense values."""
    if x is None:
        return None
    if sp.issparse(x):
        return {
            "kind": "sparse",
            "format": x.format,
            "class": type(x).__name__,
            "dtype": str(x.dtype),
            "shape": list(x.shape),
            "nnz": int(x.nnz),
            "values": plain(x.toarray()),
        }
    if isinstance(x, pd.DataFrame):
        return frame(x)
    x = np.asarray(x)
    return {
        "kind": "dense",
        "class": "ndarray",
        "dtype": str(x.dtype),
        "shape": list(x.shape),
        "values": plain(x),
    }


def column(s):
    out = {"dtype": str(s.dtype)}
    if isinstance(s.dtype, pd.CategoricalDtype):
        out["categories"] = [plain(c) for c in s.cat.categories]
        out["ordered"] = bool(s.cat.ordered)
    out["values"] = [None if pd.isna(v) else plain(v) for v in s.astype(object)]
    return out


def frame(df):
    return {
        "kind": "dataframe",
        "index": [str(i) for i in df.index],
        "columns": {str(c): column(df[c]) for c in df.columns},
    }


def mapping(m):
    return {str(k): array(v) if not isinstance(v, dict) else plain(v) for k, v in m.items()}


def summary(adata):
    """Describe an AnnData: X, layers, annotations, aligned mappings, uns, raw."""
    return {
        "shape": [adata.n_obs, adata.n_vars],
        "obs_names": [str(i) for i in adata.obs_names],
        "var_names": [str(i) for i in adata.var_names],
        "X": array(adata.X),
        "layers": mapping(adata.layers),
        "obs": frame(adata.obs),
        "var": frame(adata.var),
        "obsm": mapping(adata.obsm),
        "varm": mapping(adata.varm),
        "obsp": mapping(adata.obsp),
        "varp": mapping(adata.varp),
        "uns": plain(adata.uns),
        "raw": None
        if adata.raw is None
        else {
            "X": array(adata.raw.X),
            "var": frame(adata.raw.var),
            "varm": mapping(adata.raw.varm),
        },
    }


# ---------------------------------------------------------------- inputs


def to_format(values, fmt, dtype):
    values = np.asarray(values).astype(dtype)
    if fmt == "csr":
        return sp.csr_matrix(values)
    if fmt == "csc":
        return sp.csc_matrix(values)
    return values


def make(
    obs,
    var,
    fmt="dense",
    dtype="float64",
    seed=0,
    layer=True,
    obsm=True,
    varm=False,
    pair=False,
    cats=True,
    extra_obs=False,
    uns=None,
    raw=False,
    no_x=False,
):
    """Build an input with deterministic non-zero values (zeros stay in sparse)."""
    rng = np.random.default_rng(seed)
    n, m = len(obs), len(var)
    if dtype == "bool":
        values = rng.random((n, m)) > 0.4
    else:
        values = rng.integers(0, 5, (n, m))
    obs_df = pd.DataFrame(index=pd.Index(obs, dtype=object))
    var_df = pd.DataFrame(index=pd.Index(var, dtype=object))
    if cats:
        obs_df["cat"] = pd.Categorical(
            [["u", "v", "w"][(i + seed) % 3] for i in range(n)]
        )
        obs_df["num"] = np.arange(n, dtype="float64") + seed
        obs_df["name"] = [f"s{(i + seed) % 2}" for i in range(n)]
        var_df["gene"] = [f"g{i + seed}" for i in range(m)]
    if extra_obs:
        obs_df["extra"] = np.arange(n, dtype="int64")
    adata = ad.AnnData(
        None if no_x else to_format(values, fmt, dtype),
        obs=obs_df,
        var=var_df,
        shape=(n, m) if no_x else None,
    )
    if layer:
        adata.layers["l"] = to_format(values * 2, fmt, "float64")
    if obsm:
        adata.obsm["emb"] = rng.random((n, 2))
    if varm:
        adata.varm["load"] = rng.random((m, 2))
    if pair:
        adata.obsp["g"] = sp.csr_matrix(np.eye(n))
        adata.varp["h"] = np.ones((m, m))
    adata.uns.update(uns or {})
    if raw and not no_x:
        adata.raw = adata
    return adata


O = ["o0", "o1", "o2"]
O2 = ["o3", "o4", "o5"]
V = ["v0", "v1", "v2"]
V2 = ["v1", "v2", "v3"]
V3 = ["w0", "w1", "w2"]

INPUTS = {
    # obs-disjoint, var partly overlapping (axis obs: outer join adds v0 and v3)
    "dense_a": make(O, V, seed=0, uns={"shared": 1, "a_only": "x", "nested": {"k": 1, "j": 2}}),
    "dense_b": make(O2, V2, seed=1, uns={"shared": 1, "b_only": "y", "nested": {"k": 1, "j": 3}}),
    "dense_c": make(["o6", "o7"], ["v2", "v4"], seed=2, uns={"shared": 2}),
    "csr_a": make(O, V, "csr", seed=0),
    "csr_b": make(O2, V2, "csr", seed=1),
    "csc_a": make(O, V, "csc", seed=0),
    "csc_b": make(O2, V2, "csc", seed=1),
    # the same var names, for axis obs without the join mattering
    "same_var_a": make(O, V, seed=0),
    "same_var_b": make(O2, V, seed=1),
    "csr_same_a": make(O, V, "csr", seed=0),
    "csr_same_b": make(O2, V, "csr", seed=1),
    # shared obs names, for index_unique and axis var
    "dup_a": make(O, V, seed=0),
    "dup_b": make(O, V2, seed=1),
    # same obs, different var, for axis var
    "var_a": make(O, V, seed=0, varm=True),
    "var_b": make(O, V3, seed=1, varm=True),
    "var_csr_a": make(O, V, "csr", seed=0),
    "var_csr_b": make(O, V3, "csr", seed=1),
    # dtypes
    "int32_a": make(O, V, dtype="int32", seed=0, layer=False),
    "int32_b": make(O2, V, dtype="int32", seed=1, layer=False),
    "float32_b": make(O2, V, dtype="float32", seed=1, layer=False),
    "int8_a": make(O, V, dtype="int8", seed=0, layer=False),
    "int8_csr_b": make(O2, V, "csr", dtype="int8", seed=1, layer=False),
    "bool_a": make(O, V, dtype="bool", seed=0, layer=False),
    "bool_b": make(O2, V, dtype="bool", seed=1, layer=False),
    "bool_csr_b": make(O2, V, "csr", dtype="bool", seed=1, layer=False),
    # missing and differing slots
    "bare_a": make(O, V, seed=0, layer=False, obsm=False, cats=False),
    "bare_b": make(O2, V, seed=1, layer=False, obsm=False, cats=False),
    "extra_obs_b": make(O2, V, seed=1, extra_obs=True),
    "no_layer_b": make(O2, V, seed=1, layer=False),
    "no_obsm_b": make(O2, V, seed=1, obsm=False),
    # no X
    "no_x_a": make(O, V, seed=0, layer=False, no_x=True),
    "no_x_b": make(O2, V, seed=1, layer=False, no_x=True),
    # pairwise
    "pair_a": make(O, V, seed=0, pair=True),
    "pair_b": make(O2, V, seed=1, pair=True),
    "pair_b_missing": make(O2, V, seed=1, pair=False),
    # raw
    "raw_a": make(O, V, seed=0, raw=True),
    "raw_b": make(O2, V, seed=1, raw=True),
    "raw_b_outer": make(O2, V2, seed=1, raw=True),
}

# Annotation values that differ per object, for the merge strategies, which
# apply to the alternate axis (var for axis obs)
for key, genes in [("dense_a", ["a0", "a1", "a2"]), ("dense_b", ["a1", "b2", "b3"])]:
    INPUTS[key].var["gene"] = genes
    INPUTS[key].var["same_col"] = "k"
    INPUTS[key].var["only_col"] = [None, "q", "r"] if key == "dense_b" else [None, None, None]
INPUTS["dense_a"].var["only_col"] = INPUTS["dense_a"].var["only_col"].astype("object")
INPUTS["dense_b"].var["only_col"] = INPUTS["dense_b"].var["only_col"].astype("object")


# Bool annotation columns, which Python 0.13.3 promotes to nullable boolean when
# reindexing introduces missing values (an outer join with a union merge)
for key, flags in [("flag_a", [True, False, True]), ("flag_b", [False, False, True])]:
    obj = make(O if key == "flag_a" else O2, V if key == "flag_a" else V2, seed=0)
    obj.var["flag"] = flags
    obj.obs["flag"] = flags
    INPUTS[key] = obj
INPUTS["bool_outer_b"] = make(O2, V2, dtype="bool", seed=1, layer=False)
INPUTS["bool_outer_csr_b"] = make(O2, V2, "csr", dtype="bool", seed=1, layer=False)
INPUTS["bool_layer_a"] = make(O, V, dtype="bool", seed=0)
INPUTS["bool_layer_b"] = make(O2, V2, dtype="bool", seed=1)


def first_fn(values, axis=None):
    """Custom merge function: returns the first element (R: function(values))."""
    return values[0]


CUSTOM = {"first_fn": first_fn}

# ---------------------------------------------------------------- cases

CASES = []


def add(case_name, names, **kwargs):
    CASES.append({"name": case_name, "inputs": names, "args": kwargs})


AXES = ["obs", "var"]
JOINS = ["inner", "outer"]

# --- arrays: dense and sparse mixing on both axes and joins
for join in JOINS:
    add(f"dense_obs_{join}", ["dense_a", "dense_b"], axis="obs", join=join)
    add(f"dense_var_{join}", ["var_a", "var_b"], axis="var", join=join)
    add(f"csr_obs_{join}", ["csr_a", "csr_b"], axis="obs", join=join)
    add(f"csc_obs_{join}", ["csc_a", "csc_b"], axis="obs", join=join)
    add(f"csr_var_{join}", ["var_csr_a", "var_csr_b"], axis="var", join=join)
    add(f"csr_csc_obs_{join}", ["csr_a", "csc_b"], axis="obs", join=join)
    add(f"csc_csr_obs_{join}", ["csc_a", "csr_b"], axis="obs", join=join)
    add(f"dense_csr_obs_{join}", ["dense_a", "csr_b"], axis="obs", join=join)
    add(f"csr_dense_obs_{join}", ["csr_a", "dense_b"], axis="obs", join=join)
    add(f"csc_dense_obs_{join}", ["csc_a", "dense_b"], axis="obs", join=join)
    add(f"dense_csc_var_{join}", ["var_a", "var_csr_b"], axis="var", join=join)
    add(f"three_obs_{join}", ["dense_a", "dense_b", "dense_c"], axis="obs", join=join)
    add(f"three_csr_obs_{join}", ["csr_a", "csr_b", "csr_same_a"], axis="obs", join=join)
    add(f"same_var_obs_{join}", ["same_var_a", "same_var_b"], axis="obs", join=join)
    add(f"single_{join}", ["dense_a"], axis="obs", join=join)

add("default_args", ["dense_a", "dense_b"])
add("fill_value_dense", ["dense_a", "dense_b"], join="outer", fill_value=-1)
add("fill_value_csr", ["csr_a", "csr_b"], join="outer", fill_value=-1)
add("fill_value_csr_zero", ["csr_a", "csr_b"], join="outer", fill_value=0)
add("fill_value_var", ["var_a", "var_b"], axis="var", join="outer", fill_value=7)
add("fill_value_inner_ignored", ["dense_a", "dense_b"], join="inner", fill_value=-1)

# --- dtypes
for join in JOINS:
    add(f"int32_int32_{join}", ["int32_a", "int32_b"], join=join)
    add(f"int32_float32_{join}", ["int32_a", "float32_b"], join=join)
    add(f"int32_float64_{join}", ["int32_a", "same_var_b"], join=join)
    add(f"int8_csr_int8_{join}", ["int8_a", "int8_csr_b"], join=join)
    add(f"bool_bool_{join}", ["bool_a", "bool_b"], join=join)
    add(f"bool_csr_{join}", ["bool_a", "bool_csr_b"], join=join)
    add(f"bool_float_{join}", ["bool_a", "same_var_b"], join=join)
    add(f"bool_reindexed_{join}", ["bool_a", "bool_outer_b"], join=join)
    add(f"bool_reindexed_csr_{join}", ["bool_a", "bool_outer_csr_b"], join=join)
    add(f"bool_layers_{join}", ["bool_layer_a", "bool_layer_b"], join=join)
add("bool_reindexed_fill", ["bool_a", "bool_outer_b"], join="outer", fill_value=True)

# --- bool annotation columns promoted to nullable boolean (0.13.3)
for axis in AXES:
    for merge in ["unique", "first", "same", "only", None]:
        add(
            f"bool_column_{axis}_{merge}",
            ["flag_a", "flag_b"],
            axis=axis,
            join="outer",
            merge=merge,
        )
add("bool_column_inner", ["flag_a", "flag_b"], join="inner", merge="first")

# --- NULL X
for axis in AXES:
    for join in JOINS:
        add(f"no_x_{axis}_{join}", ["no_x_a", "no_x_b"], axis=axis, join=join)
add("no_x_mixed", ["no_x_a", "same_var_b"])
add("no_x_mixed_reverse", ["same_var_a", "no_x_b"])

# --- obs / var annotation, label, keys, index_unique
add("label", ["dense_a", "dense_b"], label="batch")
add("label_keys", ["dense_a", "dense_b"], label="batch", keys=["x", "y"])
add("label_named", ["dense_a", "dense_b"], label="batch", named=["x", "y"])
add("keys_only", ["dense_a", "dense_b"], keys=["x", "y"])
add("label_var", ["var_a", "var_b"], axis="var", label="batch", keys=["x", "y"])
add("label_existing_col", ["dense_a", "dense_b"], label="cat")
add("keys_wrong_length", ["dense_a", "dense_b"], keys=["x"])
add("index_unique", ["dup_a", "dup_b"], index_unique="-")
add("index_unique_keys", ["dup_a", "dup_b"], index_unique="-", keys=["x", "y"])
add("index_unique_named", ["dup_a", "dup_b"], index_unique="_", named=["x", "y"])
add("index_unique_label", ["dup_a", "dup_b"], index_unique="-", label="batch")
add("duplicate_index", ["dup_a", "dup_b"])
add("duplicate_index_var_axis", ["var_a", "dup_b"], axis="var")
add("extra_obs_column", ["dense_a", "extra_obs_b"], join="outer")
add("extra_obs_column_inner", ["dense_a", "extra_obs_b"], join="inner")
add("categoricals_union", ["dense_a", "dense_b"])
add("bare_obs_cols", ["bare_a", "bare_b"])
add("bare_vs_cats", ["bare_a", "same_var_b"], join="outer")

# --- merge strategies (the alternate axis annotation)
for merge in [None, "same", "unique", "first", "only"]:
    for join in JOINS:
        add(f"merge_{merge}_{join}", ["dense_a", "dense_b"], merge=merge, join=join)
add("merge_custom", ["dense_a", "dense_b"], merge="first_fn")
add("merge_bad", ["dense_a", "dense_b"], merge="nope")
add("merge_var_axis", ["var_a", "var_b"], axis="var", merge="same")
add("merge_same_obs_axis_var_names", ["same_var_a", "same_var_b"], merge="first")

# --- uns merge strategies
for uns_merge in [None, "same", "unique", "first", "only"]:
    add(f"uns_merge_{uns_merge}", ["dense_a", "dense_b"], uns_merge=uns_merge)
add("uns_merge_custom", ["dense_a", "dense_b"], uns_merge="first_fn")
add("uns_merge_three", ["dense_a", "dense_b", "dense_c"], uns_merge="same")
add("uns_merge_bad", ["dense_a", "dense_b"], uns_merge="nope")

# --- aligned mappings, layers and missing slots
for join in JOINS:
    add(f"no_layer_{join}", ["dense_a", "no_layer_b"], join=join)
    add(f"no_obsm_{join}", ["dense_a", "no_obsm_b"], join=join)
    add(f"bare_{join}", ["bare_a", "bare_b"], join=join)
    add(f"varm_var_{join}", ["var_a", "var_b"], axis="var", join=join)
    add(f"varm_obs_{join}", ["var_a", "var_b"], axis="obs", join=join)
add("layers_outer_fill", ["csr_a", "csr_b"], join="outer", fill_value=3)

# --- pairwise
for pairwise in [False, True]:
    for axis in AXES:
        add(f"pairwise_{pairwise}_{axis}", ["pair_a", "pair_b"], axis=axis, pairwise=pairwise)
    add(f"pairwise_{pairwise}_missing", ["pair_a", "pair_b_missing"], pairwise=pairwise)
    add(f"pairwise_{pairwise}_outer", ["pair_a", "pair_b"], join="outer", pairwise=pairwise)

# --- raw
for join in JOINS:
    add(f"raw_{join}", ["raw_a", "raw_b"], join=join)
    add(f"raw_{join}_var", ["raw_a", "raw_b"], axis="var", join=join)
add("raw_outer_vars", ["raw_a", "raw_b_outer"], join="outer")
add("raw_one_missing", ["raw_a", "same_var_b"])

# --- argument errors
add("bad_axis", ["dense_a", "dense_b"], axis="rows")
add("bad_join", ["dense_a", "dense_b"], join="left")
add("empty_input", [])
add("not_anndata", ["dense_a", "not_anndata"])


# ---------------------------------------------------------------- run


def run(case):
    out = {k: v for k, v in case.items()}
    args = dict(case["args"])
    named = args.pop("named", None)
    names = case["inputs"]
    for key in ("merge", "uns_merge"):
        if args.get(key) in CUSTOM:
            args[key] = CUSTOM[args[key]]
    if "not_anndata" in names:
        objs = [INPUTS[n] if n in INPUTS else "not_anndata" for n in names]
    else:
        objs = [INPUTS[n].copy() for n in names]
    if named is not None:
        objs = dict(zip(named, objs))
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        try:
            result = ad.concat(objs, **args)
        except Exception as e:  # noqa: BLE001
            out["error"] = {"class": type(e).__name__, "message": str(e)}
            out["warnings"] = warn_list(caught)
            return out
    out["warnings"] = warn_list(caught)
    out["result"] = summary(result)
    return out


def warn_list(caught):
    return [
        {"class": w.category.__name__, "message": str(w.message)}
        for w in caught
        if not issubclass(w.category, (DeprecationWarning, FutureWarning))
        or "anndata" in str(w.filename)
    ]


if __name__ == "__main__":
    result = {
        "version": version("anndata"),
        "inputs": {k: summary(v) for k, v in INPUTS.items()},
        "cases": [run(c) for c in CASES],
    }
    with open(sys.argv[1], "w") as f:
        json.dump(result, f, indent=1, allow_nan=False)
        f.write("\n")
