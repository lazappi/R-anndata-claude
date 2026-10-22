# Legacy releases spike

Findings of legacy-formats/01 (2026-10-23, uv 0.12.3, macOS x86_64).
Each release wrote a dense and a sparse (CSR) `AnnData` (categorical, float and string `obs` columns, `var`, `obsm`, `layers`, `raw`, scalar/string/array `uns`, and `uns["neighbors"]` with sparse `connectivities` and `distances`) to h5ad and zarr.
Files were read with Python 0.13.4 (`tests/python`), recording values and warnings.
Throwaway scripts: `.ralph/oracle/legacy_gen.py` (writer, run inside the old environment) and `.ralph/oracle/legacy_read.py` (0.13.4 reader and tree dump).

## Releases tried

| Release | Installs | Environment (`uv run --no-project --isolated`) |
| --- | --- | --- |
| 0.5.10 | No | Needs `scipy.sparse.sputils.IndexMixin` (scipy at most 1.2), which has no Python 3.8 wheel, and Python 3.7 is not available to uv here (source build of scipy 1.2.3 fails) |
| 0.6.22.post1 | Yes | `--python 3.8 --with zarr --with "pandas<1.4" --with "numpy<1.24"` |
| 0.7.0 | Yes | `--python 3.8 --with zarr --with "pandas<1.4" --with "numpy<1.24"` |
| 0.7.8 | Yes | `--python 3.8 --with zarr --with "pandas<2" --with "numpy<1.24"` (pandas 2 breaks `reorder_categories(inplace=)`) |
| 0.8.0 | Yes | `--python 3.9 --with zarr --with "pandas<2" --with "numpy<1.24"` |
| 0.10.9 | Yes | `--python 3.11 --with "zarr<3" --with "pandas<3" --with "numpy<2"` |

Only 0.6.22 needs a different call for zarr (`write_zarr(path, chunks=...)`).
Releases between these were not tried because the neighbours bracket every layout change seen.

## Layouts produced and the 0.13.4 read path each exercises

| Layout | Produced by | 0.13.4 path | Result in 0.13.4 |
| --- | --- | --- | --- |
| Root without `encoding-type`, every Element unencoded (`IOSpec("", "")`) | 0.6.22 h5ad | `read_basic` (`methods.py:202`) | One `OldFormatWarning` per Element ("was written without encoding metadata") for every Element except `obs`/`var`/`raw.var`, values read correctly |
| Unencoded dense and sparse X, layers, obsm, uns | 0.6.22 h5ad | `read_basic` | As above |
| h5sparse legacy attributes (`h5sparse_format`, `h5sparse_shape`) on a group (X, layers, raw.X, `uns/neighbors/*`) | 0.6.22 h5ad | `read_basic` Mapping branch, `sparse_dataset(elem).to_memory()` | Read as `csr_matrix` (values checked for `obsp`, X), one `OldFormatWarning` "Element '/X' was written without encoding metadata." per group (`/X`, `/layers/counts`, `/raw.X`, `/uns/neighbors/connectivities`, `/uns/neighbors/distances`) |
| `obs`/`var` as a compound dataset | 0.6.22 h5ad | `read_dataframe_legacy` (`h5ad.py:332`) | `OldFormatWarning` "very old version of AnnData", first field becomes the index |
| Categories as `uns["<col>_categories"]` | 0.6.22 h5ad | `_clean_up_old_format` / `_clean_uns` (obs is a Dataset) | Columns come back categorical (`cat`, and the string column `str`), the `*_categories` keys are removed from `uns` |
| `raw.X` and `raw.var` as root members | 0.6.22 h5ad | `_read_legacy_raw` (`h5ad.py:299`) | `raw` rebuilt, `OldFormatWarning` for `raw.X` and `raw.var` |
| `uns["neighbors"]` connectivities and distances | 0.6.22, 0.7.0, 0.7.8 (zarr too), 0.10.9 (h5ad and zarr) | `_move_adj_mtx` (`anndata.py:492`) | Moved to `obsp` with a `FutureWarning` ("Moving element from .uns['neighbors']..."), obsp order follows the file |
| `dataframe` 0.1.0: categories in `obs/__categories/<col>`, codes with a `categories` attribute (HDF5 object reference in h5ad, path string in zarr), `column-order`, `_index` | 0.7.0, 0.7.8 h5ad and zarr | `read_dataframe_01` (`methods.py:1133`) | Categoricals restored, columns in `column-order` |
| Root without `encoding-type`, but `obs`/`var`/`raw` encoded (dataframe 0.1.0, raw 0.1.0) and `X`, `layers`, `obsm`, `obsp`, `uns` unencoded | 0.7.0, 0.7.8 h5ad and zarr | `read_basic` for the unencoded ones, normal readers for the rest | `OldFormatWarning` for each unencoded Element and for each dataframe column and `__categories` member (h5ad), zarr warns `OldFormatWarning` "Element '<path>' was written without encoding metadata" for `/obsp`, `/obsm`, `/obsm/X_pca`, `/layers`, `/layers/counts`, `/var/vnum`, `/var/_index`, `/uns` and its members (the exact full list per file is recorded as expectations by the fixture ticket) |
| Sparse matrices already `csr_matrix` 0.1.0 | 0.7.0 onwards | normal sparse reader | No warning |
| 0.8.0 layout: every Element encoded (array 0.2.0, dataframe 0.2.0, categorical 0.2.0, `string-array`, `numeric-scalar`) | 0.8.0 h5ad and zarr | normal readers | No warnings, not legacy (current encodings) |
| 0.10.9 layout | 0.10.9 h5ad and zarr | normal readers | Not legacy, only the `uns["neighbors"]` move above |

Notes:

- 0.7.x writes `uns` scalars as 0-d datasets and strings as 0-d object datasets (not `numeric-scalar`/`string`), so unencoded scalars and strings are read by `read_dataset`, in 0.6.22 they are 1-element arrays (`uns/scalar` int64 shape `(1,)`, `uns/str` object shape `(1,)`) and 0.13.4 reads them (h5ad, dense and sparse) as `uns["scalar"] = array([3])`, `uns["str"] = array(['hello'], dtype=object)` and `uns["neighbors"]["params"]["n"] = array([3])`, while 0.7.8 gives `np.int64(3)` and `'hello'`
- Values checked in 0.13.4 for 0.6.22 (dense and sparse h5ad) and 0.7.8: `obs` columns and index (`o0..o5`, the index name is `index` for 0.6.22 and unnamed for 0.7.x), categories `['a','b','c']` and `['x','y','z']` (the string column becomes categorical in 0.6.22 and 0.7.x), `var` and `raw.var` index, X type (ndarray or csr_matrix, float32), `obsp` types (csr_matrix), and `raw.varm` is empty
- `_clean_up_old_format` (`anndata.py:1921`) is only the `obs_keys_multicol`, `smp_keys_multicol`, `var_keys_multicol` handling (moving multicolumn obs/var fields into `obsm`/`varm`), and the `<col>_categories` clean-up is `_clean_uns` (`_io/utils.py`) run when `obs` is a Dataset
- 0.7.x raw is already the `raw/` group, never `raw.X`, so `raw.X` comes only from 0.6.x
- 0.6.22 zarr (`obs`, `var` and `raw.var` as arrays with the `json2` object codec) cannot be read by 0.13.4 in the pinned environment: `ValueError: No Zarr data type found that matches {'name': '|O', 'object_codec_id': 'json2'}` (zarr 3 has no object dtype)

## Legacy read paths no installable release exercises

- `read_dataframe_legacy` and the `raw.X`/`raw.var` backwards-compatible paths for **zarr** (`zarr.py:152-235`): 0.6.22 zarr stores install and write, but 0.13.4 itself cannot read them, so there is no Python expectation to compare against (unsupported and untested, record 0.13.4's error)
- Anything only written by releases before 0.6 (0.5.x and earlier): not installable
- `raw.varm` as a root member: an open gap, 0.6.22 wrote no `raw.varm` for this fixture (no `varm` set), so the ticket for `raw.*` must write a `varm` with 0.6.22 and check whether it exists
- `_clean_up_old_format` multicolumn keys (`obs_keys_multicol`, `smp_keys_multicol`, `var_keys_multicol`): none of the tried releases wrote them (0.6.22 stores multicolumn arrays in `obsm`), so unsupported and untested
- `_clean_uns` categories clean-up with `<col>_categories` is exercised (0.6.22 h5ad) and the zarr branch is not (0.6.22 zarr unreadable)
- Unencoded dict with `h5sparse_format` in zarr (`read_basic_zarr`): no release writes h5sparse attributes to zarr (0.6.22 zarr cannot be read at all)
- Categories in `uns["<col>_categories"]` for zarr (`_clean_uns` after `read_zarr`) is only reachable with a zarr `obs` Array, which is 0.6.22 zarr (unreadable)

## Recommendation for the fixture generator

- One `tests/python/legacy_fixtures.py` (not `generate_fixtures.py`, which runs in the pinned environment) driving the old releases through `uv run --no-project --isolated --python <v> --with anndata==<release> ...` with the pins above, one call per release: 0.6.22.post1 (h5ad only), 0.7.0 and 0.7.8 (h5ad and zarr) and 0.10.9 (h5ad and zarr, for the `uns["neighbors"]` move).
  0.7.0 and 0.7.8 write the same layout, so keep one of them (0.7.8, the last 0.7.x)
- No committed per-release environment directories: the pins are the environment definition, kept in the script, so a lockfile per release is not needed. Wheels are cached by uv so regeneration is cheap
- 0.8.0 adds nothing, skip it (it is a current layout already covered by the existing fixtures)
- Python expectations come from reading each fixture with 0.13.4 (values as JSON/h5ad rewrite, warning classes and messages), with the freshness test pattern used by the other `*_cases.py` scripts
- Record the 0.6.22 zarr error and the zarr-only paths above as unsupported in the spec, with 0.13.4's behaviour noted
- Ticket candidates: (1) fixture generator and expectation table, (2) unencoded Elements and h5sparse groups, (3) legacy dataframes (compound dataset, dataframe 0.1.0 `__categories`) and `uns` categories clean-up, (4) `raw.X`/`raw.var` and `uns["neighbors"]` move, (5) backed, lazy and real-world PBMC 3k through the legacy paths
