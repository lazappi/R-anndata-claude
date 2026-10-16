"""Write Python's `AnnData.unwriteable()` results for fixed cases as JSON.

Usage: unwriteable_cases.py OUTPUT.json

Each case has an R equivalent in tests/testthat/test-io-h5ad.R.
"""

import datetime
import json
import sys
import warnings

import anndata
import numpy as np
import pandas as pd


def _base(**kwargs):
    return anndata.AnnData(np.zeros((2, 3), dtype="float64"), **kwargs)


def _raw_adata():
    adata = _base()
    adata.raw = adata
    return adata


CASES = {
    "plain": lambda: _base(),
    "no_x": lambda: anndata.AnnData(
        obs=pd.DataFrame(index=["a", "b"]), var=pd.DataFrame(index=["x", "y", "z"])
    ),
    "x_3d": lambda: anndata.AnnData(np.zeros((2, 3, 4))),
    "layer_3d": lambda: _base(layers={"l": np.zeros((2, 3, 4))}),
    "uns_nested": lambda: _base(uns={"a": {"b": np.arange(3)}, "s": "text"}),
    "uns_none": lambda: _base(uns={"n": None}),
    "uns_date": lambda: _base(uns={"d": datetime.date(2020, 1, 1)}),
    "uns_function": lambda: _base(uns={"f": len}),
    "uns_object": lambda: _base(uns={"o": object()}),
    "obs_datetime": lambda: _base(
        obs=pd.DataFrame({"t": pd.date_range("2020-01-01", periods=2)}, index=["a", "b"])
    ),
    "obsm_ok": lambda: _base(obsm={"pca": np.zeros((2, 2))}),
    "raw": _raw_adata,
}


def run(factory):
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        adata = factory()
    return bool(adata.unwriteable())


if __name__ == "__main__":
    out = {name: run(factory) for name, factory in CASES.items()}
    with open(sys.argv[1], "w") as f:
        json.dump(out, f, indent=2, sort_keys=True)
        f.write("\n")
