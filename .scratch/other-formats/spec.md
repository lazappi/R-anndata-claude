# Other formats

Status: needs-triage

Stub spec, to be grilled into a full spec before tickets are written.
Sub-project 10 of the roadmap (`.scratch/roadmap/spec.md`).

## Goal

Readers and writers for formats that cannot represent a full `AnnData`, matching Python's results.

## Scope

- `read_csv()`, `read_excel()`, `read_umi_tools()`, `read_hdf()`, `read_loom()`, `read_mtx()`, `read_text()`
- `write_csvs()` and `write_loom()`

## Python references

- `src/anndata/_io/read.py` (`read_csv:30`, `read_excel:60`, `read_umi_tools:94`, `read_hdf:117`, `read_loom:190`, `read_mtx:336`, `read_text:366`)
- `src/anndata/_io/write.py`
- `src/anndata/_core/anndata.py:1747-1792`

## Open questions

- Which of these are worth doing, and in what order?
- Which R packages should handle Excel and loom?
