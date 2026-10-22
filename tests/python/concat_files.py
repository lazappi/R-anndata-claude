"""Concatenate h5ad files with anndata.concat and write the results.

Usage: concat_files.py <jobs.json>

The JSON file is a list of jobs, each `{"inputs": [paths], "out": path,
"kwargs": {...}}`, run in one process because importing anndata is slow. Every
job is attempted, failures are reported on stderr and make the exit status
non-zero.
"""

import json
import sys
import traceback

import anndata


def run(job):
    adatas = [anndata.read_h5ad(path) for path in job["inputs"]]
    anndata.concat(adatas, **job.get("kwargs", {})).write_h5ad(job["out"])


def main(args):
    if len(args) != 1:
        print("usage: concat_files.py <jobs.json>", file=sys.stderr)
        return 2
    with open(args[0]) as handle:
        jobs = json.load(handle)
    status = 0
    for job in jobs:
        try:
            run(job)
        except Exception:
            print(f"Concatenating {job['inputs']} failed:\n{traceback.format_exc()}", file=sys.stderr)
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
