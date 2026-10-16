"""Write Python's strings_to_categoricals and rename_categories results as JSON.

Usage: categorical_cases.py OUTPUT.json
"""

import json
import logging
import sys

import anndata as ad
import numpy as np
import pandas as pd
from anndata.logging import anndata_logger

STRINGS = {
    "plain": ["b", "a", "b", "a", "c10", "c2"],
    "all_unique": list("abcdef"),
    "with_na": ["x", None, "x", "y", np.nan, "y"],
    "unique_with_na": ["a", None, "b", "c", "d", "e"],
    "all_na": [None] * 6,
    "mixed": ["a", 1, "a", 1, "a", 1],
    "numbers": [1, 2, 1, 2, 1, 2],
    "natural": ["c10", "c2", "c1", "c10", "c2", "c1"],
    "case": ["B", "a", "b", "A", "a", "b"],
    "digits_first": ["10a", "2a", "a", "10a", "2a", "a"],
}


class Capture(logging.Handler):
    def __init__(self):
        super().__init__(logging.INFO)
        self.messages = []

    def emit(self, record):
        self.messages.append(record.getMessage())


def column_result(series):
    if isinstance(series.dtype, pd.CategoricalDtype):
        return {
            "categories": [str(c) for c in series.cat.categories],
            "values": [None if pd.isna(v) else str(v) for v in series],
        }
    return None


def convert_case():
    out = {}
    handler = Capture()
    anndata_logger.setLevel("INFO")
    anndata_logger.addHandler(handler)
    for label, values in STRINGS.items():
        obs = pd.DataFrame(
            {"col": values},
            index=[f"o{i}" for i in range(6)],
        )
        adata = ad.AnnData(np.zeros((6, 1)), obs=obs)
        handler.messages.clear()
        adata.strings_to_categoricals()
        out[label] = {
            "values": [None if v is None or v is np.nan else v for v in values],
            "result": column_result(adata.obs["col"]),
            "messages": list(handler.messages),
        }
    # The single-row frame is never converted
    adata = ad.AnnData(
        np.zeros((1, 1)), obs=pd.DataFrame({"col": ["a"]}, index=["o0"])
    )
    adata.strings_to_categoricals()
    out["single_row"] = {
        "values": ["a"],
        "result": column_result(adata.obs["col"]),
        "messages": [],
    }
    anndata_logger.removeHandler(handler)
    return out


def rename_case():
    out = {}
    obs = pd.DataFrame(
        {
            "s": pd.Categorical(["a", "b", "c", "a", "b", "c"]),
            "both": pd.Categorical(["u", "v", "u", "v", "u", "v"]),
            "plain": ["a", "b", "c", "a", "b", "c"],
        },
        index=[f"o{i}" for i in range(6)],
    )
    var = pd.DataFrame(
        {
            "g": pd.Categorical(["p", "q", "p"]),
            "both": pd.Categorical(["k", "l", "k"]),
        },
        index=list("xyz"),
    )

    def fresh():
        return ad.AnnData(np.zeros((6, 3)), obs=obs.copy(), var=var.copy())

    def run(key, categories):
        adata = fresh()
        try:
            adata.rename_categories(key, categories)
        except Exception as e:
            return {"error": type(e).__name__, "message": str(e)}
        return {
            "obs": {c: column_result(adata.obs[c]) for c in ["s", "both"]},
            "var": {c: column_result(adata.var[c]) for c in ["g", "both"]},
        }

    out["obs"] = run("s", ["W", "X", "Y"])
    out["var"] = run("g", ["P", "Q"])
    out["both_prefers_obs"] = run("both", ["A", "B"])
    out["swap_names"] = run("s", ["c", "a", "b"])
    out["missing_key"] = run("nope", ["a"])
    out["not_categorical"] = run("plain", ["a", "b", "c"])
    out["too_short"] = run("s", ["a", "b"])
    out["too_long"] = run("s", ["a", "b", "c", "d"])
    out["duplicates"] = run("s", ["a", "a", "b"])
    out["mapping"] = run("s", {"a": "A"})
    return out


def rename_uns_case():
    """Scanpy-style uns entries whose rec-array fields are named by category."""
    handler = Capture()
    handler.setLevel(logging.WARNING)
    anndata_logger.addHandler(handler)

    def rec(names):
        return np.rec.fromarrays(
            [np.array([i + 1.0, i + 2.0]) for i in range(len(names))],
            names=names,
        )

    obs = pd.DataFrame(
        {"s": pd.Categorical(["a", "b", "c", "a", "b", "c"])},
        index=[f"o{i}" for i in range(6)],
    )
    adata = ad.AnnData(np.zeros((6, 3)), obs=obs)
    adata.uns["match"] = {
        "params": {"groupby": "s"},
        "names": rec(["a", "b", "c"]),
        "scores": rec(["a", "b", "c"]),
        "stale": rec(["x", "y", "z"]),
        "plain": np.array([1.0, 2.0]),
    }
    adata.uns["other_group"] = {
        "params": {"groupby": "t"},
        "names": rec(["a", "b", "c"]),
    }
    adata.uns["bad_params"] = {"params": "x", "names": rec(["a", "b", "c"])}
    adata.uns["no_params"] = {"names": rec(["a", "b", "c"])}
    adata.uns["not_dict"] = rec(["a", "b", "c"])
    adata.rename_categories("s", ["X", "Y", "Z"])
    anndata_logger.removeHandler(handler)

    def names(v):
        return list(v.dtype.names)

    return {
        "match": {k: names(v) for k, v in adata.uns["match"].items() if k != "params" and v.dtype.names},
        "other_group": names(adata.uns["other_group"]["names"]),
        "no_params": names(adata.uns["no_params"]["names"]),
        "bad_params": names(adata.uns["bad_params"]["names"]),
        "not_dict": names(adata.uns["not_dict"]),
        "warnings": list(handler.messages),
    }


if __name__ == "__main__":
    result = {
        "convert": convert_case(),
        "rename": rename_case(),
        "rename_uns": rename_uns_case(),
    }
    with open(sys.argv[1], "w") as f:
        json.dump(result, f, indent=2)
        f.write("\n")
