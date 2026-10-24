"""Time Python anndata on one real h5ad file, and compare written files.

Usage:
  benchmark_real_files.py time <current.h5ad> <out_dir> <repeats>
  benchmark_real_files.py [--sorted <path> ...] compare <a> <b> [<a> <b> ...]

`time` prints JSON with the best of `repeats` wall-clock seconds for each
operation (or an `error` string), and leaves the files it wrote in <out_dir>
(`py.h5ad` and `py.zarr`). `compare` checks pairs of h5ad files or zarr stores
for Structural equivalence (the h5_tree.py and zarr_tree.py descriptions,
ignoring chunks) and prints the differences as JSON, one list per pair.
`--sorted` paths (sparse `data` and `indices` stored unsorted in the source,
ADR 0006) skip the digest check.

Driven by scripts/benchmark-real-files.R, which is run by hand (not a test).
"""

import json
import os
import shutil
import sys
import time
import traceback
import warnings
from pathlib import Path

# `-I` removes the script directory from the path
sys.path.insert(0, str(Path(__file__).resolve().parent))

import anndata  # noqa: E402
import h5_tree  # noqa: E402
import zarr_tree  # noqa: E402
from anndata.experimental import read_lazy  # noqa: E402

N_ROWS = 100


def best(fn, repeats, cleanup=None):
    times = []
    for _ in range(repeats):
        if cleanup is not None:
            cleanup()
        start = time.perf_counter()
        fn()
        times.append(time.perf_counter() - start)
    return min(times)


def remove(path):
    if os.path.isdir(path):
        shutil.rmtree(path)
    elif os.path.exists(path):
        os.remove(path)


def timings(src, out_dir, repeats):
    out_h5ad = os.path.join(out_dir, "py.h5ad")
    out_zarr = os.path.join(out_dir, "py.zarr")
    result = {}

    def run(name, fn, cleanup=None):
        try:
            result[name] = {"seconds": best(fn, repeats, cleanup)}
        except Exception:
            result[name] = {"error": traceback.format_exc(limit=-3)}

    adata = anndata.read_h5ad(src)

    run("read_h5ad", lambda: anndata.read_h5ad(src))
    run("write_h5ad", lambda: adata.write_h5ad(out_h5ad), lambda: remove(out_h5ad))
    run("write_zarr", lambda: adata.write_zarr(out_zarr), lambda: remove(out_zarr))
    run("read_zarr", lambda: anndata.read_zarr(out_zarr))

    def backed_slice():
        backed = anndata.read_h5ad(src, backed="r")
        try:
            backed.X[:N_ROWS, :]
        finally:
            backed.file.close()

    run("backed_slice", backed_slice)

    def lazy_subset():
        lazy = read_lazy(src)
        try:
            lazy[:N_ROWS].to_memory()
        finally:
            if hasattr(lazy, "file") and lazy.file.is_open:
                lazy.file.close()

    run("lazy_subset", lazy_subset)
    return result


def compare(pairs, sorted_paths=()):
    def describe(path):
        return (zarr_tree if os.path.isdir(path) else h5_tree).tree(path)

    out = []
    for a_path, b_path in pairs:
        a = {n["path"]: n for n in describe(a_path)}
        b = {n["path"]: n for n in describe(b_path)}
        diffs = []
        for path in sorted(set(a) - set(b)):
            diffs.append(f"{path}: only in the first")
        for path in sorted(set(b) - set(a)):
            diffs.append(f"{path}: only in the second")
        same_kind = os.path.isdir(a_path) == os.path.isdir(b_path)
        for path in sorted(set(a) & set(b)):
            x, y = a[path], b[path]
            for prop in ("kind", "dtype", "shape", "digest"):
                # ADR 0006: R stores unsorted sparse indices sorted, so the
                # digest of those datasets is expected to differ
                if prop == "digest" and path in sorted_paths:
                    continue
                if x.get(prop) != y.get(prop):
                    diffs.append(f"{path}: {prop} differs ({x.get(prop)!r} vs {y.get(prop)!r})")
            for attr in sorted(set(x["attrs"]) ^ set(y["attrs"])):
                diffs.append(f"{path}: attribute {attr} on one side only")
            for attr in sorted(set(x["attrs"]) & set(y["attrs"])):
                for prop in ("value", "type") if same_kind else ("value",):
                    if x["attrs"][attr][prop] != y["attrs"][attr][prop]:
                        diffs.append(f"{path}: attribute {attr} {prop} differs")
        out.append(diffs)
    return out


def main(args):
    warnings.simplefilter("ignore")
    if args[:1] == ["time"] and len(args) == 4:
        print(json.dumps(timings(args[1], args[2], int(args[3]))))
        return 0
    sorted_paths = []
    while args[:1] == ["--sorted"] and len(args) >= 2:
        sorted_paths.append(args[1])
        args = args[2:]
    if args[:1] == ["compare"] and len(args) >= 3 and len(args) % 2 == 1:
        print(json.dumps(compare(list(zip(args[1::2], args[2::2])), sorted_paths)))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
