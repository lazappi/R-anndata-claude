"""Write the input files and Python's results for the other-formats readers.

Usage: other_formats_cases.py OUTPUT.json

The input files are written to an `other_formats/` directory next to OUTPUT.json
and the JSON has `readers` (rows of reader, file or lines, arguments and the
result: X values, dtype and sparse format, names, warnings or the error) and
`write_csvs` (`adatas` described in full so R can rebuild them, and `cases`
with the files written and their contents as pandas reads them).
Everything is built in one run, because each Python start is slow.
The R equivalents are in tests/testthat/test-other-formats-table.R (the table)
and the test file of each reader.
"""

import bz2
import gzip
import json
import shutil
import sys
import tempfile
import warnings
import zipfile
from importlib.metadata import version
from pathlib import Path

import anndata as ad
import h5py
import numpy as np
import pandas as pd
import scipy.sparse as sp

TEXT_FILES = {
    # header row of names, row names in the first column
    "header_rownames.csv": "cell,g1,g2,g3\nc1,1,2,3\nc2,4,5,6\n",
    # header row with an empty corner cell
    "header_empty_corner.csv": ",g1,g2\nc1,1.5,2\nc2,3,4.5\n",
    # header row, no row names
    "header_only.csv": "g1,g2,g3\n1,2,3\n4,5,6\n",
    # no header, row names
    "rownames_only.csv": "c1,1,2\nc2,3,4\nc3,5,6\n",
    # numbers only
    "numbers.csv": "1,2,3\n4,5,6\n",
    # quoted names (R and pandas style)
    "quoted.csv": '"","g1","g2"\n"c1",1,2\n"c2",3,4\n',
    # last comment line stores the variable names
    "comments.txt": "# a comment\n# g1 g2 g3\n1 2 3\n4 5 6\n",
    # comment lines and a header
    "comments_header.txt": "# only a comment\n g1 g2\nc1 1 2\nc2 3 4\n",
    # whitespace runs, blank lines and carriage returns
    "whitespace.txt": "  g1   g2\r\n\r\nc1   1  2\r\n\nc2  3    4\r\n",
    # tab delimited
    "tabs.tab": "g1\tg2\nc1\t1\t2\nc2\t3\t4\n",
    # semicolon delimited
    "semicolon.data": "g1;g2\nc1;1;2\nc2;3;4\n",
    # header with one name fewer than values: integer row names
    "integer_names.txt": "1 2 3\n1 0.5 0.25 0.125\n2 4 5 6\n",
    # a numeric first column that is not row names
    "numeric_first_column.csv": "g1,g2,g3\n1,2,3\n4,5,6\n",
    # a single data row
    "single_row.csv": "g1,g2\nc1,1,2\n",
    # non-numeric value in the data
    "bad_value.csv": "g1,g2\nc1,1,x\n",
    # delimiter missing from the first line
    "no_delimiter.csv": "g1 g2\nc1 1 2\n",
    # last row shorter than the first
    "ragged.csv": "g1,g2,g3\nc1,1,2,3\nc2,4,5\n",
    # no data lines
    "header_no_data.csv": "g1,g2\n",
    "empty.csv": "",
}

UMI_TOOLS = (
    "gene\tcell\tcount\n"
    "g2\tc2\t3\n"
    "g1\tc1\t1\n"
    "g3\tc1\t2\n"
    "g1\tc3\t5\n"
    "g2\tc1\t4\n"
)

MTX_FILES = {
    "coordinate_integer.mtx": (
        "%%MatrixMarket matrix coordinate integer general\n%comment\n"
        "3 4 4\n1 1 5\n2 3 7\n3 4 9\n3 1 2\n"
    ),
    "coordinate_real.mtx": (
        "%%MatrixMarket matrix coordinate real general\n"
        "2 3 3\n1 1 1.5\n2 2 -2.25\n2 3 3\n"
    ),
    "coordinate_pattern.mtx": (
        "%%MatrixMarket matrix coordinate pattern general\n2 3 3\n1 1\n2 2\n1 3\n"
    ),
    "coordinate_symmetric.mtx": (
        "%%MatrixMarket matrix coordinate real symmetric\n3 3 3\n1 1 1\n2 1 2\n3 2 4\n"
    ),
    "array_real.mtx": (
        "%%MatrixMarket matrix array real general\n2 3\n1\n0\n2.5\n3\n0\n4\n"
    ),
    "coordinate_empty.mtx": ("%%MatrixMarket matrix coordinate real general\n2 3 0\n"),
    "coordinate_large_integer.mtx": (
        "%%MatrixMarket matrix coordinate integer general\n1 2 2\n1 1 16777217\n1 2 3\n"
    ),
}

EXCEL_SHEETS = {
    "counts": pd.DataFrame(
        {
            "cell": ["c1", "c2", "c3"],
            "g1": [1.0, 2.5, 3.0],
            "g2": [4.0, 5.0, 6.5],
        }
    ),
    "integer_labels": pd.DataFrame(
        {"id": [10, 20], "a": [1.0, 2.0], "b": [3.0, 4.0]}
    ),
    "numeric_headers": pd.DataFrame({"cell": ["x", "y"], 1: [1.0, 2.0], 2: [3.0, 4.0]}),
    "integer_values": pd.DataFrame({"cell": ["x", "y"], "a": [1, 2], "b": [3, 4]}),
}


# set in main, so messages naming an input file do not depend on where it lives
INPUT_PREFIX = ""


def plain(x):
    """Convert a value to something `json` can write."""
    if isinstance(x, pd.DataFrame):
        return {
            "columns": [str(c) for c in x.columns],
            "index": plain(x.index),
            "values": plain(x.to_numpy(dtype=object)),
            "dtypes": [str(t) for t in x.dtypes],
        }
    if isinstance(x, pd.Index):
        return [plain(i) for i in x]
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
    if isinstance(x, bytes):
        return x.decode()
    if x is pd.NA or x is None:
        return None
    if isinstance(x, (bool, int, str)):
        return x
    return repr(x)


def array(x):
    """Describe a matrix: sparse format, dtype, shape and dense values."""
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
    x = np.asarray(x)
    return {
        "kind": "dense",
        "dtype": str(x.dtype),
        "shape": list(x.shape),
        "values": plain(x),
    }


def describe(adata):
    """Describe a read result: X, names, index names and annotation columns."""
    return {
        "X": array(adata.X),
        "obs_names": plain(adata.obs_names),
        "var_names": plain(adata.var_names),
        "obs_names_dtype": str(adata.obs_names.dtype),
        "var_names_dtype": str(adata.var_names.dtype),
        "obs_index_name": adata.obs_names.name,
        "var_index_name": adata.var_names.name,
        "obs_columns": [str(c) for c in adata.obs.columns],
        "var_columns": [str(c) for c in adata.var.columns],
    }


def record(fn, *args, **kwargs):
    """Call `fn` and record the result, the warnings or the error."""
    out = {"warnings": []}
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        try:
            out["result"] = describe(fn(*args, **kwargs))
        except Exception as e:  # noqa: BLE001
            message = str(e).replace(INPUT_PREFIX, "")
            out["error"] = {"class": type(e).__name__, "message": message}
    out["warnings"] = [
        {"class": type(w.message).__name__, "message": str(w.message)}
        for w in caught
        if not issubclass(w.category, (DeprecationWarning, ResourceWarning))
    ]
    return out


def write_text(path, text):
    path.write_text(text, newline="")


def write_inputs(d):
    """Write every input file into `d`."""
    for name, text in TEXT_FILES.items():
        write_text(d / name, text)
    csv = TEXT_FILES["header_rownames.csv"]
    # compressed copies (a fixed gzip timestamp keeps the bytes stable)
    with open(d / "header_rownames.csv.gz", "wb") as f:
        with gzip.GzipFile(fileobj=f, mode="wb", mtime=0) as g:
            g.write(csv.encode())
    (d / "header_rownames.csv.bz2").write_bytes(bz2.compress(csv.encode()))
    ws = TEXT_FILES["whitespace.txt"]
    with open(d / "whitespace.txt.gz", "wb") as f:
        with gzip.GzipFile(fileobj=f, mode="wb", mtime=0) as g:
            g.write(ws.encode())
    (d / "whitespace.txt.bz2").write_bytes(bz2.compress(ws.encode()))
    write_text(d / "umi_tools.tsv", UMI_TOOLS)
    with open(d / "umi_tools.tsv.gz", "wb") as f:
        with gzip.GzipFile(fileobj=f, mode="wb", mtime=0) as g:
            g.write(UMI_TOOLS.encode())
    write_text(
        d / "umi_tools_extra_column.tsv", "gene\tcell\tcount\tx\ng1\tc1\t2\ta\n"
    )
    for name, text in MTX_FILES.items():
        write_text(d / name, text)

    X = np.arange(6, dtype="float64").reshape(2, 3) + 0.5
    with h5py.File(d / "hdf_names.h5", "w") as f:
        f.create_dataset("data", data=X, track_times=False)
        f.create_dataset(
            "row_names", data=np.array([b"r1", b"r2"]), track_times=False
        )
        f.create_dataset(
            "col_names", data=np.array([b"a", b"b", b"c"]), track_times=False
        )
    with h5py.File(d / "hdf_plain.h5", "w") as f:
        f.create_dataset("data", data=X.astype("float32"), track_times=False)
    with h5py.File(d / "hdf_two_keys.h5", "w") as f:
        f.create_dataset("a", data=X, track_times=False)
        f.create_dataset("b", data=np.arange(4, dtype="int32").reshape(2, 2))
        f.create_dataset(
            "row_names", data=np.array([b"r1", b"r2"]), track_times=False
        )
    with h5py.File(d / "hdf_integer.h5", "w") as f:
        f.create_dataset(
            "data", data=np.arange(6, dtype="int64").reshape(3, 2), track_times=False
        )

    xlsx = d / "sheets.xlsx"
    with pd.ExcelWriter(xlsx, engine="openpyxl") as writer:
        for sheet, frame in EXCEL_SHEETS.items():
            frame.to_excel(writer, sheet_name=sheet, index=False)
        writer.book.properties.created = pd.Timestamp("2020-01-01").to_pydatetime()
        writer.book.properties.modified = pd.Timestamp("2020-01-01").to_pydatetime()
    # fix the zip entry timestamps so regenerating gives the same bytes
    tmp = d / "sheets.tmp"
    with zipfile.ZipFile(xlsx) as src, zipfile.ZipFile(
        tmp, "w", zipfile.ZIP_DEFLATED
    ) as dst:
        for info in src.infolist():
            new = zipfile.ZipInfo(info.filename, (2020, 1, 1, 0, 0, 0))
            new.compress_type = zipfile.ZIP_DEFLATED
            dst.writestr(new, src.read(info.filename))
    tmp.replace(xlsx)


def text_cases(d):
    """Rows for read_text and read_csv."""
    rows = []

    def add(name, reader, source, **args):
        fn = getattr(ad.io, reader)
        if source["kind"] == "file":
            target = str(d / source["file"])
        else:
            target = iter(source["lines"])
        rows.append(
            {
                "name": name,
                "reader": reader,
                "source": source,
                "args": args,
                **record(fn, target, **args),
            }
        )

    def file(name):
        return {"kind": "file", "file": name}

    add("csv_header_rownames","read_csv", file("header_rownames.csv"))
    add("csv_header_rownames_dtype", "read_csv", file("header_rownames.csv"), dtype="float64")
    add("csv_header_rownames_int", "read_csv", file("header_rownames.csv"), dtype="int32")
    add("csv_header_empty_corner", "read_csv", file("header_empty_corner.csv"))
    add("csv_header_only", "read_csv", file("header_only.csv"))
    add("csv_rownames_only", "read_csv", file("rownames_only.csv"))
    add("csv_numbers", "read_csv", file("numbers.csv"))
    add("csv_quoted", "read_csv", file("quoted.csv"))
    add("csv_gz", "read_csv", file("header_rownames.csv.gz"))
    add("csv_bz2", "read_csv", file("header_rownames.csv.bz2"))
    add(
        "csv_first_column_names",
        "read_csv",
        file("numeric_first_column.csv"),
        first_column_names=True,
    )
    add("csv_numeric_first_column", "read_csv", file("numeric_first_column.csv"))
    add("csv_single_row", "read_csv", file("single_row.csv"))
    add("csv_bad_value", "read_csv", file("bad_value.csv"))
    add("csv_no_delimiter", "read_csv", file("no_delimiter.csv"))
    add("csv_ragged", "read_csv", file("ragged.csv"))
    add("csv_header_no_data", "read_csv", file("header_no_data.csv"))
    add("csv_empty", "read_csv", file("empty.csv"))
    add("csv_semicolon_delimiter", "read_csv", file("semicolon.data"), delimiter=";")
    add("csv_whitespace_delimiter_none", "read_csv", file("whitespace.txt"), delimiter=None)
    add("text_comments", "read_text", file("comments.txt"))
    add("text_comments_header", "read_text", file("comments_header.txt"))
    add("text_whitespace", "read_text", file("whitespace.txt"))
    add("text_whitespace_gz", "read_text", file("whitespace.txt.gz"))
    add("text_whitespace_bz2", "read_text", file("whitespace.txt.bz2"))
    add("text_tabs", "read_text", file("tabs.tab"), delimiter="\t")
    add("text_tabs_default_delimiter", "read_text", file("tabs.tab"))
    add("text_semicolon", "read_text", file("semicolon.data"), delimiter=";")
    add("text_semicolon_wrong_delimiter", "read_text", file("semicolon.data"), delimiter=",")
    add("text_integer_names", "read_text", file("integer_names.txt"))
    add("text_space_delimiter", "read_text", file("whitespace.txt"), delimiter=" ")
    add("text_first_column_names_false", "read_text", file("rownames_only.csv"), delimiter=",", first_column_names=False)
    add("text_first_column_names_true", "read_text", file("numbers.csv"), delimiter=",", first_column_names=True)
    # a stream of lines is R's character vector of lines
    add(
        "text_lines",
        "read_text",
        {"kind": "lines", "lines": ["  g1  g2", "c1 1 2", "", "c2 3 4"]},
    )
    add(
        "csv_lines",
        "read_csv",
        {"kind": "lines", "lines": ["g1,g2", "1,2", "3,4\r\n"]},
    )
    add("csv_lines_empty", "read_csv", {"kind": "lines", "lines": []})
    return rows


def other_cases(d):
    rows = []

    def add(name, reader, file, **args):
        fn = getattr(ad.io, reader)
        rows.append(
            {
                "name": name,
                "reader": reader,
                "source": {"kind": "file", "file": file},
                "args": args,
                **record(fn, str(d / file), **args),
            }
        )

    add("mtx_integer", "read_mtx", "coordinate_integer.mtx")
    add("mtx_integer_dtype_int64", "read_mtx", "coordinate_integer.mtx", dtype="int64")
    add("mtx_real", "read_mtx", "coordinate_real.mtx")
    add("mtx_real_float64", "read_mtx", "coordinate_real.mtx", dtype="float64")
    add("mtx_pattern", "read_mtx", "coordinate_pattern.mtx")
    add("mtx_symmetric", "read_mtx", "coordinate_symmetric.mtx")
    add("mtx_array", "read_mtx", "array_real.mtx")
    add("mtx_empty", "read_mtx", "coordinate_empty.mtx")
    add("mtx_large_integer", "read_mtx", "coordinate_large_integer.mtx")
    add("mtx_large_integer_float64", "read_mtx", "coordinate_large_integer.mtx", dtype="float64")
    add("mtx_missing", "read_mtx", "does_not_exist.mtx")
    add("umi_tools", "read_umi_tools", "umi_tools.tsv")
    add("umi_tools_gz", "read_umi_tools", "umi_tools.tsv.gz")
    add("umi_tools_float", "read_umi_tools", "umi_tools.tsv", dtype="float32")
    add("umi_tools_extra_column", "read_umi_tools", "umi_tools_extra_column.tsv")
    add("hdf_names", "read_hdf", "hdf_names.h5", key="data")
    add("hdf_plain", "read_hdf", "hdf_plain.h5", key="data")
    add("hdf_integer", "read_hdf", "hdf_integer.h5", key="data")
    add("hdf_row_names_only", "read_hdf", "hdf_two_keys.h5", key="a")
    add("hdf_row_names_mismatch", "read_hdf", "hdf_two_keys.h5", key="b")
    add("hdf_empty_key", "read_hdf", "hdf_names.h5", key="")
    add("hdf_missing_key", "read_hdf", "hdf_names.h5", key="nope")
    add("excel_counts", "read_excel", "sheets.xlsx", sheet="counts")
    add("excel_counts_by_index", "read_excel", "sheets.xlsx", sheet=0)
    add("excel_integer_labels", "read_excel", "sheets.xlsx", sheet="integer_labels")
    add("excel_numeric_headers", "read_excel", "sheets.xlsx", sheet="numeric_headers")
    add("excel_integer_values", "read_excel", "sheets.xlsx", sheet="integer_values")
    add("excel_dtype_ignored", "read_excel", "sheets.xlsx", sheet="counts", dtype="int32")
    add("excel_missing_sheet", "read_excel", "sheets.xlsx", sheet="nope")
    # restrict_index_types = False keeps the labels' own types (integers here)
    with ad.settings.override(restrict_index_types=False):
        add("excel_integer_labels_unrestricted", "read_excel", "sheets.xlsx", sheet="integer_labels")
    return rows


def uns_value(spec):
    kind = spec["kind"]
    if kind == "sparse":
        return sp.csr_matrix(np.array(spec["value"]))
    if kind in ("matrix", "array3", "vector"):
        return np.array(spec["value"])
    return spec["value"]


ADATAS = {
    "dense": {
        "X": {"kind": "dense", "values": [[1.0, 2.0, 3.0], [4.0, 5.0, 6.5]]},
        "obs_names": ["c1", "c2"],
        "var_names": ["g1", "g2", "g3"],
        "obs": {"group": ["a", "b"], "n": [1, 2]},
        "var": {"score": [0.5, 1.5, 2.5]},
        "obsm": {"X_pca": [[1.0, 2.0], [3.0, 4.0]]},
        "varm": {"loadings": [[0.1], [0.2], [0.3]]},
        "uns": {},
    },
    "sparse": {
        "X": {"kind": "sparse", "values": [[0.0, 2.0, 0.0], [4.0, 0.0, 6.5]]},
        "obs_names": ["c1", "c2"],
        "var_names": ["g1", "g2", "g3"],
        "obs": {"group": ["a", "b"]},
        "var": {},
        "obsm": {},
        "varm": {},
        "uns": {},
    },
    "no_x": {
        "X": None,
        "obs_names": ["c1", "c2"],
        "var_names": ["g1", "g2"],
        "obs": {"n": [1, 2]},
        "var": {},
        "obsm": {},
        "varm": {},
        "uns": {},
    },
    "uns_values": {
        "X": {"kind": "dense", "values": [[1.0, 2.0], [3.0, 4.0]]},
        "obs_names": ["c1", "c2"],
        "var_names": ["g1", "g2"],
        "obs": {},
        "var": {},
        "obsm": {},
        "varm": {},
        "uns": {
            "scalar_int": {"kind": "scalar", "value": 3},
            "scalar_float": {"kind": "scalar", "value": 2.5},
            "scalar_string": {"kind": "scalar", "value": "hello"},
            "vector": {"kind": "vector", "value": [1, 2, 3]},
            "string_vector": {"kind": "vector", "value": ["a", "b"]},
            "matrix": {"kind": "matrix", "value": [[1.0, 2.0], [3.0, 4.0]]},
        },
    },
    "uns_sparse": {
        "X": {"kind": "dense", "values": [[1.0, 2.0], [3.0, 4.0]]},
        "obs_names": ["c1", "c2"],
        "var_names": ["g1", "g2"],
        "obs": {},
        "var": {},
        "obsm": {},
        "varm": {},
        "uns": {
            "first_sparse": {"kind": "sparse", "value": [[0, 1], [2, 0]]},
            "second_sparse": {"kind": "sparse", "value": [[1, 0], [0, 1]]},
            "kept": {"kind": "scalar", "value": 1},
        },
    },
    "uns_unwritable": {
        "X": {"kind": "dense", "values": [[1.0, 2.0], [3.0, 4.0]]},
        "obs_names": ["c1", "c2"],
        "var_names": ["g1", "g2"],
        "obs": {},
        "var": {},
        "obsm": {},
        "varm": {},
        "uns": {
            "cube": {"kind": "array3", "value": [[[1, 2], [3, 4]], [[5, 6], [7, 8]]]},
            "kept": {"kind": "scalar", "value": 1},
        },
    },
    "uns_nested": {
        "X": {"kind": "dense", "values": [[1.0, 2.0], [3.0, 4.0]]},
        "obs_names": ["c1", "c2"],
        "var_names": ["g1", "g2"],
        "obs": {},
        "var": {},
        "obsm": {},
        "varm": {},
        "uns": {
            "params": {"kind": "dict", "value": {"a": 1, "b": 2.5}},
            "deep": {"kind": "dict", "value": {"a": {"b": 1}}},
        },
    },
}

WRITE_CASES = [
    # name, adata, args
    ("dense_default", "dense", {}),
    ("dense_skip_data", "dense", {"skip_data": True}),
    ("dense_with_data", "dense", {"skip_data": False}),
    ("dense_with_data_tab", "dense", {"skip_data": False, "sep": "\t"}),
    ("sparse_skip_data", "sparse", {}),
    ("sparse_with_data", "sparse", {"skip_data": False}),
    ("no_x_skip_data", "no_x", {}),
    ("no_x_with_data", "no_x", {"skip_data": False}),
    ("csv_dirname", "dense", {"dirname": "out.csv"}),
    ("nested_dirname", "dense", {"dirname": "a/b/out"}),
    ("uns_values", "uns_values", {}),
    ("uns_values_tab", "uns_values", {"sep": ";"}),
    ("uns_sparse", "uns_sparse", {}),
    ("uns_unwritable", "uns_unwritable", {}),
    ("uns_nested", "uns_nested", {}),
]


def build_adata(spec):
    X = spec["X"]
    if X is None:
        x = None
    else:
        x = np.array(X["values"], dtype="float32")
        if X["kind"] == "sparse":
            x = sp.csr_matrix(x)
    obs = pd.DataFrame(spec["obs"], index=pd.Index(spec["obs_names"]))
    var = pd.DataFrame(spec["var"], index=pd.Index(spec["var_names"]))
    adata = ad.AnnData(
        X=x,
        obs=obs,
        var=var,
        obsm={k: np.array(v) for k, v in spec["obsm"].items()} or None,
        varm={k: np.array(v) for k, v in spec["varm"].items()} or None,
        uns={k: uns_value(v) for k, v in spec["uns"].items()} or None,
    )
    if x is None:
        adata = ad.AnnData(obs=obs, var=var, uns=adata.uns or None)
    return adata


def read_back(root, sep):
    """Every file under `root` as pandas reads it, keyed by relative path."""
    files = {}
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        rel = path.relative_to(root).as_posix()
        stem = path.stem
        in_uns = rel.startswith("uns/")
        has_header = (not in_uns) and stem in {"obs", "var", "obsm", "varm"}
        has_index = (not in_uns) and stem in {"obs", "var"}
        try:
            frame = pd.read_csv(
                path,
                sep=sep,
                header=0 if has_header else None,
                index_col=0 if has_index else None,
            )
            content = plain(frame)
        except Exception as e:  # noqa: BLE001
            content = {"error": {"class": type(e).__name__, "message": str(e)}}
        files[rel] = {
            "header": has_header,
            "index": has_index,
            **content,
            "text": path.read_text(),
        }
    return files


def write_cases():
    cases = []
    for name, key, args in WRITE_CASES:
        adata = build_adata(ADATAS[key])
        args = dict(args)
        dirname = args.pop("dirname", "out")
        sep = args.get("sep", ",")
        root = Path(tempfile.mkdtemp())
        try:
            target = root / dirname
            out = {"warnings": []}
            with warnings.catch_warnings(record=True) as caught:
                warnings.simplefilter("always")
                try:
                    adata.write_csvs(target, **args)
                except Exception as e:  # noqa: BLE001
                    out["error"] = {"class": type(e).__name__, "message": str(e)}
            out["warnings"] = [
                {"class": type(w.message).__name__, "message": str(w.message)}
                for w in caught
                if not issubclass(w.category, (DeprecationWarning, ResourceWarning))
            ]
            out["files"] = read_back(root, sep)
        finally:
            shutil.rmtree(root)
        cases.append(
            {
                "name": name,
                "adata": key,
                "dirname": dirname,
                "args": args,
                **out,
            }
        )
    return cases


if __name__ == "__main__":
    out_json = Path(sys.argv[1])
    inputs = out_json.parent / "other_formats"
    if inputs.exists():
        shutil.rmtree(inputs)
    inputs.mkdir(parents=True)
    INPUT_PREFIX = str(inputs) + "/"
    write_inputs(inputs)
    table = {
        "version": version("anndata"),
        "readers": text_cases(inputs) + other_cases(inputs),
        "write_csvs": {"adatas": ADATAS, "cases": write_cases()},
    }
    with open(out_json, "w") as f:
        json.dump(table, f, indent=2)
        f.write("\n")
