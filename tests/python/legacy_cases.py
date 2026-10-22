"""Write what Python 0.13.4 reads from the legacy fixtures as JSON.

Usage: legacy_cases.py <fixtures dir> OUTPUT.json

The fixtures come from legacy_fixtures.py (real old releases). Each row holds
the values read, or the error, and the warnings raised (sorted).
"""

import importlib.metadata
import json
import sys
import tarfile
import tempfile
import warnings
from pathlib import Path

import anndata as ad
import numpy as np
import pandas as pd
from scipy import sparse

# Layouts with no fixture or no 0.13.4 expectation to compare against (see
# .scratch/legacy-formats/releases-spike.md, "Legacy read paths no installable
# release exercises"). `behaviour` is filled for layouts with a fixture.
UNSUPPORTED = [
    {
        "layout": "0.6.x zarr store",
        "fixture": "0.6.22-dense.zarr",
        "reason": "obs, var and raw.var are zarr arrays with the json2 object codec, which zarr 3 cannot open",
    },
    {
        "layout": "read_dataframe_legacy and raw.X/raw.var for zarr (zarr.py:152-235)",
        "fixture": None,
        "reason": "only written by 0.6.x zarr stores, which 0.13.4 cannot read, so there is no expectation",
    },
    {
        "layout": "anything written by releases before 0.6 (0.5.x and earlier)",
        "fixture": None,
        "reason": "not installable (0.5.10 needs scipy 1.2)",
    },
    {
        "layout": "multicolumn keys obs_keys_multicol, smp_keys_multicol, var_keys_multicol",
        "fixture": None,
        "reason": "no tried release wrote them (0.6.22 stores multicolumn arrays in obsm)",
    },
    {
        "layout": "zarr groups with h5sparse_format attributes (read_basic_zarr)",
        "fixture": None,
        "reason": "no release writes h5sparse attributes to zarr",
    },
    {
        "layout": "uns categories <col>_categories in zarr (_clean_uns after read_zarr)",
        "fixture": None,
        "reason": "only reachable with a zarr obs Array, which is a 0.6.22 zarr store",
    },
]


def plain(x):
    """A JSON-ready copy of a value, with the Python type of arrays kept apart."""
    if isinstance(x, dict):
        # Sorted, because 0.13.4 reads members in a different order on each run
        return {str(k): plain(x[k]) for k in sorted(x, key=str)}
    if isinstance(x, (list, tuple)):
        return [plain(v) for v in x]
    if sparse.issparse(x):
        return {
            "type": type(x).__name__,
            "dtype": str(x.dtype),
            "shape": list(x.shape),
            "values": x.toarray().tolist(),
        }
    if isinstance(x, np.ndarray):
        return {
            "type": "ndarray",
            "dtype": str(x.dtype),
            "shape": list(x.shape),
            "values": x.tolist(),
        }
    if isinstance(x, np.generic):
        return {"type": type(x).__name__, "value": x.item()}
    if isinstance(x, (str, int, float, bool)) or x is None:
        return {"type": type(x).__name__, "value": x}
    return {"type": type(x).__name__, "value": str(x)}


def frame(df):
    columns = {}
    for name in df.columns:
        col = df[name]
        entry = {"dtype": str(col.dtype), "values": col.astype(object).tolist()}
        if isinstance(col.dtype, pd.CategoricalDtype):
            entry["categories"] = col.cat.categories.tolist()
            entry["ordered"] = bool(col.cat.ordered)
        columns[str(name)] = entry
    return {
        "index": df.index.tolist(),
        "index_name": df.index.name,
        "columns": columns,
    }


def mapping(m):
    return {str(key): plain(m[key]) for key in sorted(m.keys(), key=str)}


def describe(a):
    out = {
        "shape": list(a.shape),
        "obs": frame(a.obs),
        "var": frame(a.var),
        "X": None if a.X is None else plain(a.X),
        "layers": mapping(a.layers),
        "obsm": mapping(a.obsm),
        "varm": mapping(a.varm),
        "obsp": mapping(a.obsp),
        "varp": mapping(a.varp),
        "uns": plain(dict(a.uns)),
        "raw": None,
    }
    if a.raw is not None:
        out["raw"] = {
            "shape": list(a.raw.shape),
            "var": frame(a.raw.var),
            "X": plain(a.raw.X),
            "varm": mapping(a.raw.varm),
        }
    return out


def read_one(path):
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        try:
            reader = ad.read_h5ad if path.suffix == ".h5ad" else ad.read_zarr
            row = {"status": "ok", "values": describe(reader(path))}
        except Exception as e:
            row = {"status": "error", "error": type(e).__name__, "message": str(e)}
    # Python raises these in a different order on each run, so they are sorted,
    # and the warnings before an error depend on which members were read first
    # so an error row has none
    row["warnings"] = [] if row["status"] == "error" else sorted(
        (
            {"category": w.category.__name__, "message": str(w.message)}
            for w in caught
        ),
        key=lambda w: (w["category"], w["message"]),
    )
    return row


def main(fixtures, output):
    fixtures = Path(fixtures)
    with tempfile.TemporaryDirectory() as tmp:
        with tarfile.open(fixtures / "legacy-zarr-fixtures.tar.gz") as tar:
            tar.extractall(tmp, filter="data")
        paths = sorted(
            [*(fixtures / "legacy").glob("*.h5ad"), *Path(tmp).glob("*.zarr")],
            key=lambda p: p.name,
        )
        rows = {path.name: read_one(path) for path in paths}
    unsupported = []
    for entry in UNSUPPORTED:
        entry = dict(entry)
        if entry["fixture"] is not None:
            row = rows[entry["fixture"]]
            entry["behaviour"] = {k: row[k] for k in ("status", "error", "message") if k in row}
        else:
            entry["behaviour"] = None
        unsupported.append(entry)
    with open(output, "w") as f:
        json.dump(
            {"anndata": importlib.metadata.version("anndata"), "fixtures": rows, "unsupported": unsupported},
            f,
            indent=2,
        )
        f.write("\n")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
