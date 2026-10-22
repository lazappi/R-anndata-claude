"""Write legacy fixtures with real old anndata releases.

Usage: legacy_fixtures.py <fixtures dir>

Runs in any Python (standard library only) and drives
`uv run --no-project --isolated --python <v> --with anndata==<release> ...`
once per release, because the old releases do not install in the pinned
environment (tests/python). The pins below are the environment definition of
each release (see .scratch/legacy-formats/releases-spike.md).

Writes `<fixtures dir>/legacy/<tag>-<case>.h5ad` and packs the zarr stores into
`<fixtures dir>/legacy-zarr-fixtures.tar.gz` (R CMD check notes zarr directory
trees, see pack_zarr_fixtures.py).

The same file is the writer that runs inside each old environment:
`legacy_fixtures.py --write <outdir> <mode> <case:format,...>`.
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent

# `cases` are `<case>:<format>`, and `mode` is "full" or "neighbors"
RELEASES = [
    {
        # h5ad and one zarr store, which 0.13.4 cannot read (kept as the
        # evidence of the unsupported layout)
        "tag": "0.6.22",
        "release": "0.6.22.post1",
        "python": "3.8",
        "pins": ["zarr", "pandas<1.4", "numpy<1.24"],
        "mode": "full",
        "cases": ["dense:h5ad", "sparse:h5ad", "dense:zarr"],
    },
    {
        # the last 0.7.x, which writes the same layout as 0.7.0
        "tag": "0.7.8",
        "release": "0.7.8",
        "python": "3.8",
        "pins": ["zarr", "pandas<2", "numpy<1.24"],
        "mode": "full",
        "cases": ["dense:h5ad", "sparse:h5ad", "dense:zarr", "sparse:zarr"],
    },
    {
        # only the `uns["neighbors"]` move (current layout otherwise)
        "tag": "0.10.9",
        "release": "0.10.9",
        "python": "3.11",
        "pins": ["zarr<3", "pandas<3", "numpy<2"],
        "mode": "neighbors",
        "cases": ["neighbors:h5ad", "neighbors:zarr"],
    },
]


def write_files(out, mode, cases):
    """Runs inside the old environment, so the imports are local."""
    import warnings

    import anndata as ad
    import numpy as np
    import pandas as pd
    from scipy import sparse

    warnings.simplefilter("ignore")
    version = ad.__version__
    print("anndata", version)

    def neighbors():
        return {
            "params": {"n": 3},
            "connectivities": sparse.csr_matrix(np.eye(6, dtype="float32")),
            "distances": sparse.csr_matrix(np.eye(6, dtype="float32")),
        }

    def make(dense):
        n, m = 6, 4
        rng = np.random.RandomState(0)
        X = rng.poisson(1.0, (n, m)).astype("float32")
        if not dense:
            X = sparse.csr_matrix(X)
        obs = pd.DataFrame(
            {
                "cat": pd.Categorical(["a", "b", "a", "c", "b", "a"]),
                "num": np.arange(n, dtype="float64"),
                "str": ["x", "y", "z", "x", "y", "z"],
            },
            index=["o%d" % i for i in range(n)],
        )
        var = pd.DataFrame(
            {"vnum": np.arange(m, dtype="int64")},
            index=["v%d" % i for i in range(m)],
        )
        a = ad.AnnData(X, obs=obs, var=var)
        a.obsm["X_pca"] = rng.rand(n, 2)
        # varm gives raw.varm something to hold (the raw copy takes it)
        a.varm["PCs"] = rng.rand(m, 2)
        a.layers["counts"] = X.copy()
        a.uns["scalar"] = 3
        a.uns["str"] = "hello"
        a.uns["arr"] = np.arange(3)
        a.uns["neighbors"] = neighbors()
        a.raw = a
        return a

    def make_neighbors():
        a = ad.AnnData(np.arange(24, dtype="float32").reshape(6, 4))
        a.uns["neighbors"] = neighbors()
        return a

    for spec in cases.split(","):
        case, fmt = spec.split(":")
        a = make_neighbors() if mode == "neighbors" else make(case == "dense")
        path = "%s/%s.%s" % (out, case, fmt)
        if fmt == "h5ad":
            a.write_h5ad(path)
        elif version.startswith("0.6"):
            a.write_zarr(path, chunks=(3, 4))
        else:
            a.write_zarr(path)
        print("wrote", path)


def drive(fixtures):
    fixtures = Path(fixtures)
    dest = fixtures / "legacy"
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    with tempfile.TemporaryDirectory() as tmp:
        zarr_stage = Path(tmp) / "zarr"
        zarr_stage.mkdir()
        for entry in RELEASES:
            out = Path(tmp) / entry["tag"]
            out.mkdir()
            command = ["uv", "run", "--no-project", "--isolated"]
            command += ["--python", entry["python"]]
            command += ["--with", "anndata==" + entry["release"]]
            for pin in entry["pins"]:
                command += ["--with", pin]
            command += ["python", "-I", str(Path(__file__).resolve())]
            command += ["--write", str(out), entry["mode"], ",".join(entry["cases"])]
            subprocess.run(command, check=True)
            for path in sorted(out.iterdir()):
                name = "%s-%s" % (entry["tag"], path.name)
                if path.suffix == ".h5ad":
                    shutil.copy(path, dest / name)
                else:
                    shutil.copytree(path, zarr_stage / name)
        subprocess.run(
            [
                sys.executable,
                "-I",
                str(HERE / "pack_zarr_fixtures.py"),
                str(zarr_stage),
                str(fixtures / "legacy-zarr-fixtures.tar.gz"),
            ],
            check=True,
        )


if __name__ == "__main__":
    if sys.argv[1] == "--write":
        write_files(*sys.argv[2:5])
    else:
        drive(sys.argv[1])
