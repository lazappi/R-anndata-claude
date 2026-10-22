# Roadmap: anndata.claude

Status: ready-for-human

## Goal

`anndata.claude` is an R package that ports Python anndata to R.
Its first priority is full compatibility with the anndata on-disk formats (h5ad and later zarr): an object read from a file must be equal whichever language wrote it, and files written by R must be structurally equivalent to files written by Python.
The in-memory `AnnData` object supports that goal, with full feature parity as the long-term aim and an MVP first.

Read `CONTEXT.md` for vocabulary and `docs/adr/` for settled decisions before working on any sub-project.

## Reference implementation

- Python anndata release **0.13.4** (commit `a487b81d38d4bfe7c7d76f01eed72a8622665c65`) is the only source of truth for behaviour (ADR 0001)
- Run `scripts/fetch-reference.sh` to get a git-ignored clone at `.reference/anndata/`
- All Python references in specs are `path:line` relative to `.reference/anndata/` at that commit
- The on-disk format is documented in `.reference/anndata/docs/fileformat-prose.md`
- Existing R implementations of anndata must not be used as a reference for API, code or behaviour

## Principles

- **Match behaviour, not implementation.**
  Observable behaviour (values, errors, warnings, printed output, files written) matches Python.
  Implementation is idiomatic R and should not translate Python code line by line.
- **On disk is non-negotiable.**
  Every Round trip preserves Encoding type, Encoding version, On-disk dtype, shape and values.
  Deviations from Python are allowed in memory only, and each must be documented.
- **R where Python idioms don't translate.**
  Indexing is 1-based with negative exclusion (core-object spec), and R6 reference semantics replace Python mutability (ADR 0002).
- **Only encodable values.**
  Only values with an anndata encoding are supported, and anything else raises an error naming the Element path.
- **Same warnings and errors.**
  Python's warnings and errors are raised under the same conditions as classed R conditions.
- **Modern R package practice.**
  The package passes `R CMD check` with no errors, warnings or notes, and every change is test-first.

## Sub-projects

Each sub-project has its own `.scratch/<slug>/spec.md`.
A stub spec must be grilled into a full spec before tickets are written for it.

| Order | Slug | Spec state | Summary | Depends on |
| ----- | ---- | ---------- | ------- | ---------- |
| 1 | `foundations` | done | Package skeleton, tooling, settings, conditions, Python round-trip harness | none |
| 2 | `core-object` | done (MVP) | `AnnData` R6 class and in-memory behaviour | foundations |
| 3 | `h5ad-io` | done (MVP) | Element registry and h5ad read/write for all current encodings except awkward-array | foundations, core-object |
| 4 | `views` | done (0.0.2) | Lazy views with copy-on-write | core-object |
| 5 | `concat` | done | `concat()` | core-object, views |
| 6 | `zarr-io` | done (0.0.2) | `read_zarr()` / `write_zarr()` for zarr v2 and v3 | h5ad-io |
| 7 | `backed` | done | Backed mode for h5ad | h5ad-io, views |
| 8 | `lazy` | done | Lazy arrays and lazy reading | h5ad-io, backed |
| 9 | `legacy-formats` | full | Reading files from before the current encodings | h5ad-io |
| 10 | `other-formats` | stub | csv, mtx, text, excel, loom, umi_tools, hdf readers and writers | core-object |
| 11 | `experimental` | stub, low priority (experimental in Python, little effort) | `concat_on_disk`, `AnnCollection`, awkward arrays, `acc` accessors, extension namespaces | most of the above |

The MVP is sub-projects 1 to 3, released as 0.0.1.
Next: `zarr-io`, then `views`, `backed` and `lazy`, then the rest (h5ad-io/15, full rec-array fidelity, after `lazy`).
`h5ad-io` may begin as soon as `core-object` can construct objects with every Slot, and the two can then progress in parallel.

## Non-goals

- `AnnLoader` and other pytorch integration (deprecated upstream, Python-specific)
- dask, cupy, jax and array-API backends for `X` (R-native lazy arrays are covered by `lazy`)
- Byte-identical files (Structural equivalence is the target)
- Custom R-only encodings that Python cannot read
- Converters to SingleCellExperiment, Seurat or other R classes (out of scope for now)
- Publication to CRAN or Bioconductor (dependencies are chosen for effectiveness)

## Development workflow

- Specs define behaviour, acceptance criteria and required tests, never R implementation details
- Each spec is broken into tickets at `.scratch/<slug>/issues/NN-<slug>.md` (see `docs/agents/issue-tracker.md`)
- Agents take one `ready-for-agent` ticket at a time and work test-first
- A ticket is done only when `scripts/check.sh` passes (see `foundations`)
- Each ticket is one atomic gitmoji commit
- New domain terms go in `CONTEXT.md`, and hard-to-reverse, surprising decisions get an ADR
- Development is local for now, and GitHub Actions CI is added when the repository is pushed to GitHub
- The human maintainer may add further instructions at development time, and those take precedence
