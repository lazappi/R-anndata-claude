"""Write Python's AnnData repr strings for fixed objects as JSON.

Usage: repr_cases.py OUTPUT.json
"""

import json
import sys

import anndata as ad
import numpy as np
import pandas as pd


def names(prefix, n):
    return [f"{prefix}{i}" for i in range(n)]


def base(n_obs=3, n_vars=2, **kwargs):
    return ad.AnnData(np.zeros((n_obs, n_vars)), **kwargs)


def frame(n, columns, prefix):
    return pd.DataFrame(
        {c: np.arange(n, dtype=float) for c in columns}, index=names(prefix, n)
    )


def cases():
    out = {}
    out["empty"] = base()
    out["obs_var"] = base(
        obs=frame(3, ["a", "b"], "o"), var=frame(2, ["gene"], "v")
    )
    out["uns"] = base(uns={"first": 1, "second": "x", "a": [1, 2]})
    out["obsm_varm"] = base(
        obsm={"X_pca": np.zeros((3, 2)), "X_umap": np.zeros((3, 2))},
        varm={"PCs": np.zeros((2, 2))},
    )
    out["obsp_varp"] = base(
        obsp={"connectivities": np.zeros((3, 3))},
        varp={"corr": np.zeros((2, 2))},
    )
    out["layers"] = base(
        layers={"counts": np.zeros((3, 2)), "logcounts": np.zeros((3, 2))}
    )
    out["layers_only_counts"] = base(layers={"counts": np.zeros((3, 2))})
    out["raw"] = base(obs=frame(3, ["a"], "o"))
    out["raw"].raw = out["raw"]
    out["all_slots"] = base(
        obs=frame(3, ["a", "b"], "o"),
        var=frame(2, ["gene"], "v"),
        uns={"u": 1},
        obsm={"X_pca": np.zeros((3, 2))},
        varm={"PCs": np.zeros((2, 2))},
        obsp={"c": np.zeros((3, 3))},
        varp={"d": np.zeros((2, 2))},
        layers={"counts": np.zeros((3, 2))},
    )
    out["all_slots"].raw = out["all_slots"]
    out["quotes"] = base(
        obs=frame(3, ["it's", 'say "hi"', "plain"], "o"),
        uns={"a'b": 1},
    )
    out["no_x"] = ad.AnnData(
        obs=frame(3, ["a"], "o"), var=frame(2, ["gene"], "v")
    )
    return out


if __name__ == "__main__":
    result = {}
    for label, adata in cases().items():
        result[label] = {
            "repr": repr(adata),
            "layer_keys": [None if k is None else k for k in adata.layers.keys()],
        }
    with open(sys.argv[1], "w") as f:
        json.dump(result, f, indent=2)
        f.write("\n")
